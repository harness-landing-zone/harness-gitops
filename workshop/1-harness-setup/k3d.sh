#!/usr/bin/env bash
# Local test clusters: a hub and one spoke per entry in envs (below) on one
# Docker network, so the hub can reach a spoke's API at
# https://k3d-hga-spoke-<env>-server-0:6443.
# Contexts are k3d-hga-hub and k3d-hga-spoke-<env>; your current context is
# left alone. To add a spoke, add its env to envs and run up, then register.
#
#   k3d.sh up        create whatever is missing (an existing cluster is untouched),
#                    then pin
#   k3d.sh pin [cluster...]  fix each container's current address on network hga
#   k3d.sh register  write each spoke's connection into OpenBao on the hub (clusters/spoke-<env>),
#                    plus self-managed spokes' controller keys (OpenTofu output spoke_api_keys)
#   k3d.sh down      delete them all
set -euo pipefail

# A Docker restart hands out addresses on hga in start order. k3s then finds its
# recorded node IP gone and crash-loops ("failed to find interface with
# specified node ip"), and a load balancer may keep proxying to an old address.
# Pinning the address each container has now, once, makes Docker reuse it. It
# stops and starts each unpinned container (server first, then its load
# balancer), keeping the same address, so k3s sees no change.
pin() {
  local c n ip
  for c in "$@"; do
    for n in "k3d-$c-server-0" "k3d-$c-serverlb"; do
      [ -n "$(docker inspect "$n" --format \
        '{{with (index .NetworkSettings.Networks "hga").IPAMConfig}}{{.IPv4Address}}{{end}}')" ] &&
        continue
      ip=$(docker inspect "$n" --format '{{(index .NetworkSettings.Networks "hga").IPAddress}}')
      [ -n "$ip" ] || { echo "$n is not running on hga" >&2; return 1; }
      docker stop "$n" >/dev/null
      docker network disconnect hga "$n"
      docker network connect --ip "$ip" hga "$n"
      docker start "$n" >/dev/null
      echo "pinned $n at $ip"
    done
  done
}

envs=(nonprod prod test)
clusters=(hga-hub "${envs[@]/#/hga-spoke-}")
hub=k3d-hga-hub

case "${1:-}" in
  up)
    for c in "${clusters[@]}"; do
      k3d cluster list "$c" >/dev/null 2>&1 ||
        k3d cluster create "$c" \
          --network hga \
          --k3s-arg "--disable=traefik@server:0" \
          --kubeconfig-update-default=false \
          --kubeconfig-switch-context=false \
          --wait
      # Merged explicitly: k3d cannot pick a file when KUBECONFIG lists several.
      k3d kubeconfig merge "$c" --output "$HOME/.kube/config" \
        --kubeconfig-switch-context=false >/dev/null
    done
    pin "${clusters[@]}"
    ;;
  pin)
    shift
    [ $# -gt 0 ] || set -- "${clusters[@]}"
    pin "$@"
    ;;
  register)
    # What `argocd cluster add` does on the spoke side. The connection (server,
    # caData, token) goes into OpenBao at clusters/spoke-<env> through a pipe
    # only: never printed, never on disk. ESO builds the Argo CD cluster Secret
    # from it. Re-run after a hub restart (dev mode empties the store) or a
    # spoke rebuild.
    # Wait for the store before writing to it.
    kubectl --context "$hub" -n openbao wait --for=condition=Ready pod/openbao-0 --timeout=120s >/dev/null
    for env in "${envs[@]}"; do
      spoke=k3d-hga-spoke-$env
      # The spoke's API as the hub's pods reach it on the shared Docker network.
      server=https://k3d-hga-spoke-$env-server-0:6443
      kubectl --context "$spoke" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: {name: argocd-manager, namespace: kube-system}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: argocd-manager}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin}
subjects:
  - {kind: ServiceAccount, name: argocd-manager, namespace: kube-system}
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations: {kubernetes.io/service-account.name: argocd-manager}
type: kubernetes.io/service-account-token
YAML
      # The token controller fills the Secret asynchronously.
      for _ in $(seq 1 30); do
        [ -n "$(kubectl --context "$spoke" -n kube-system get secret argocd-manager-token \
          -o jsonpath='{.data.token}' | head -c1)" ] && break
        sleep 1
      done
      # JSON on stdin only; the store's token never leaves the pod.
      kubectl --context "$spoke" -n kube-system get secret argocd-manager-token -o json |
        jq -c --arg server "$server" \
          '{server: $server, caData: .data["ca.crt"], token: (.data.token | @base64d)}' |
        kubectl --context "$hub" -n openbao exec -i openbao-0 -- \
          sh -c 'BAO_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" bao kv put -mount=secret "clusters/$1" - >/dev/null' \
          _ "spoke-$env"
      echo "stored clusters/spoke-$env in OpenBao ($server)"
    done
    # Each self-managed spoke's own controller key, made by OpenTofu (output
    # spoke_api_keys: cluster => {path, token}), goes into OpenBao at its path
    # the same way. The token only ever travels through pipes: tofu output is
    # read once per cluster and jq picks that cluster's token.
    tf="$(cd "$(dirname "$0")/.." && pwd)/harness-gitops/workshop/1-harness-setup"
    if ! keys=$(tofu -chdir="$tf" output -json spoke_api_keys </dev/null 2>/dev/null |
      jq -r 'to_entries[] | "\(.key) \(.value.path)"'); then
      echo "no spoke_api_keys output in $tf (OpenTofu not applied?): controller keys skipped"
    else
      while read -r cluster path; do
        [ -n "$cluster" ] || continue
        tofu -chdir="$tf" output -json spoke_api_keys </dev/null |
          jq -c --arg c "$cluster" '{api_key: .[$c].token}' |
          kubectl --context "$hub" -n openbao exec -i openbao-0 -- \
            sh -c 'BAO_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" bao kv put -mount=secret "$1" - >/dev/null' \
            _ "$path"
        echo "stored $path in OpenBao ($cluster controller key)"
      done <<<"$keys"
    fi
    ;;
  down)
    k3d cluster delete "${clusters[@]}"
    ;;
  *)
    echo "usage: $0 up|pin [cluster...]|register|down" >&2
    exit 2
    ;;
esac
