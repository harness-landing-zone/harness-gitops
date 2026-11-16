#!/usr/bin/env bash
# Local test clusters: a hub and spokes on one Docker network, so the hub can
# reach a spoke's API at https://k3d-hga-<spoke>-server-0:6443. A spoke's name
# is its fleet-member name (spoke-<x>); its k3d cluster is hga-<spoke> and its
# context k3d-hga-<spoke>. Your current context is left alone. Normally run by
# OpenTofu in this folder (one workspace per cluster, see README.md); every
# command also works by hand.
#
#   k3d.sh hub               create hga-hub if missing, pin it
#   k3d.sh delegate <name>   install the Harness delegate <name> on the hub
#                            ($DELEGATE_TOKEN, $HARNESS_ACCOUNT_ID)
#   k3d.sh pin [cluster...]  fix each container's current address on network hga
#                            (no cluster: every hga-* cluster)
#   k3d.sh register          write every hga-spoke-* cluster's connection into
#                            OpenBao on the hub (clusters/spoke-<x>)
#   k3d.sh spoke <name>      create hga-<name> if missing, pin it, register it
#   k3d.sh store-key <name>  write $HARNESS_API_KEY into OpenBao on the hub
#                            (harness-api-keys/<name>, property api_key)
#   k3d.sh down [name...]    delete hga-<name> for each name; with none, every
#                            hga-* cluster, the hub included
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

# Prints the k3d clusters whose names start with $1.
k3d_clusters() {
  k3d cluster list -o json | jq -r --arg p "$1" '.[].name | select(startswith($p))'
}

# Creates k3d cluster $1 unless it exists, and merges its context.
create_cluster() {
  k3d cluster list "$1" >/dev/null 2>&1 ||
    k3d cluster create "$1" \
      --network hga \
      --k3s-arg "--disable=traefik@server:0" \
      --kubeconfig-update-default=false \
      --kubeconfig-switch-context=false \
      --wait
  # Merged explicitly: k3d cannot pick a file when KUBECONFIG lists several.
  k3d kubeconfig merge "$1" --output "$HOME/.kube/config" \
    --kubeconfig-switch-context=false >/dev/null
}

# Writes the JSON on stdin into OpenBao on the hub at path $1. Stdin only: the
# values never reach a command line or the disk, and never leave the pod.
bao_put() {
  # Wait for the store before writing to it.
  kubectl --context "$hub" -n openbao wait --for=condition=Ready pod/openbao-0 \
    --timeout=120s </dev/null >/dev/null
  kubectl --context "$hub" -n openbao exec -i openbao-0 -- \
    sh -c 'BAO_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" bao kv put -mount=secret "$1" - >/dev/null' \
    _ "$1"
}

# What `argocd cluster add` does on the spoke side, for spoke $1. The
# connection (server, caData, token) goes into OpenBao at clusters/<spoke>.
# ESO builds the Argo CD cluster Secret from it.
register_spoke() {
  local name=$1 spoke=k3d-hga-$1
  # The spoke's API as the hub's pods reach it on the shared Docker network.
  local server=https://k3d-hga-$name-server-0:6443
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
  kubectl --context "$spoke" -n kube-system get secret argocd-manager-token -o json |
    jq -c --arg server "$server" \
      '{server: $server, caData: .data["ca.crt"], token: (.data.token | @base64d)}' |
    bao_put "clusters/$name"
  echo "stored clusters/$name in OpenBao ($server)"
}

# A spoke name: a DNS label starting with spoke- (it names the k3d cluster and
# the OpenBao paths).
spoke_name() {
  local re='^spoke-[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
  [[ ${1:-} =~ $re ]] && [ ${#1} -le 63 ] ||
    { echo "$0: '${1:-}' is not spoke-<name> (a DNS label)" >&2; exit 2; }
}

hub=k3d-hga-hub

case "${1:-}" in
  hub)
    create_cluster hga-hub
    pin hga-hub
    ;;
  delegate)
    [ -n "${2:-}" ] || { echo "usage: $0 delegate <name>" >&2; exit 2; }
    [ -n "${DELEGATE_TOKEN:-}" ] && [ -n "${HARNESS_ACCOUNT_ID:-}" ] ||
      { echo "$0: DELEGATE_TOKEN and HARNESS_ACCOUNT_ID must be set" >&2; exit 1; }
    helm repo add harness-delegate \
      https://app.harness.io/storage/harness-download/delegate-helm-chart/ --force-update >/dev/null
    # The token only as values on stdin (-f -), never on a command line.
    jq -n '{delegateToken: env.DELEGATE_TOKEN}' |
      helm upgrade -i "$2" harness-delegate/harness-delegate-ng \
        --kube-context "$hub" -n harness-delegate-ng --create-namespace \
        --set delegateName="$2" \
        --set accountId="$HARNESS_ACCOUNT_ID" \
        --set managerEndpoint=https://app.harness.io \
        --set upgrader.enabled=true \
        -f - >/dev/null
    echo "installed delegate $2 on $hub"
    ;;
  pin)
    shift
    [ $# -gt 0 ] || set -- $(k3d_clusters hga-)
    pin "$@"
    ;;
  register)
    # Every hga-spoke-* cluster, also those OpenTofu made. Re-run after a hub
    # restart (dev mode empties the store) or a spoke rebuild. Controller keys
    # are not restored here: see README.md.
    for c in $(k3d_clusters hga-spoke-); do
      register_spoke "${c#hga-}"
    done
    ;;
  spoke)
    spoke_name "${2:-}"
    create_cluster "hga-$2"
    pin "hga-$2"
    register_spoke "$2"
    ;;
  store-key)
    spoke_name "${2:-}"
    [ -n "${HARNESS_API_KEY:-}" ] || { echo "$0: HARNESS_API_KEY is empty" >&2; exit 1; }
    # jq reads the key from its environment: never on a command line.
    jq -nc '{api_key: env.HARNESS_API_KEY}' | bao_put "harness-api-keys/$2"
    echo "stored harness-api-keys/$2 in OpenBao"
    ;;
  down)
    shift
    if [ $# -gt 0 ]; then set -- "${@/#/hga-}"; else set -- $(k3d_clusters hga-); fi
    [ $# -gt 0 ] || { echo "no hga-* clusters"; exit 0; }
    k3d cluster delete "$@"
    ;;
  *)
    echo "usage: $0 hub|delegate <name>|pin [cluster...]|register|spoke <name>|store-key <name>|down [name...]" >&2
    exit 2
    ;;
esac
