#!/usr/bin/env bash
# Local k3d hub and spoke clusters on Docker bridge network hga.
#   k3d.sh preflight        check required CLIs, Docker memory, and hga network
#   k3d.sh hub              create hga-hub if missing, pin IPs, wait for /readyz
#   k3d.sh spoke <name>     create hga-<name> (name spoke-*), pin IPs, and store
#                           its admin connection in OpenBao on the hub at
#                           clusters/<name> (server, caData, token)
#   k3d.sh register         store every hga-spoke-* connection again (after a
#                           hub restart: dev-mode OpenBao starts empty)
#   k3d.sh pin [cluster...] fix container IPs on network hga
#   k3d.sh down [name...]   delete hga-<name> (default: all hga-* clusters)
set -euo pipefail

hub=k3d-hga-hub

wait_ready() {
  local ctx="k3d-$1"
  for _ in $(seq 1 60); do
    if kubectl --context "$ctx" get --raw='/readyz' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "$0: timed out waiting for $ctx /readyz" >&2
  return 1
}

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
    wait_ready "$c"
  done
}

k3d_clusters() {
  k3d cluster list -o json | jq -r --arg p "$1" '.[].name | select(startswith($p))'
}

check_network() {
  if ! docker network inspect hga >/dev/null 2>&1; then
    echo "$0: Docker network 'hga' does not exist. Create it first with an explicit subnet, e.g.:" >&2
    echo "  docker network create --driver bridge --subnet 172.30.80.0/24 hga" >&2
    exit 1
  fi
  local subnet
  subnet=$(docker network inspect hga --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
  if [ -z "$subnet" ]; then
    echo "$0: Docker network 'hga' has no explicit IPv4 subnet (required for IP pinning)." >&2
    exit 1
  fi
}

create_cluster() {
  check_network
  k3d cluster list "$1" >/dev/null 2>&1 ||
    k3d cluster create "$1" \
      --network hga \
      --api-port 127.0.0.1:random \
      --k3s-arg "--disable=traefik@server:0" \
      --kubeconfig-update-default=false \
      --kubeconfig-switch-context=false \
      --wait
  k3d kubeconfig merge "$1" --output "$HOME/.kube/config" \
    --kubeconfig-switch-context=false >/dev/null
}

# Writes the JSON on stdin into OpenBao on the hub at path $1. Stdin only: the
# values never reach a command line or the disk, and never leave the pod.
bao_put() {
  kubectl --context "$hub" -n openbao wait --for=condition=Ready pod/openbao-0 \
    --timeout=120s </dev/null >/dev/null
  kubectl --context "$hub" -n openbao exec -i openbao-0 -- \
    sh -c 'BAO_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" bao kv put -mount=secret "$1" - >/dev/null' \
    _ "$1"
}

# What `argocd cluster add` does on the spoke side, for spoke $1: a
# cluster-admin ServiceAccount argocd-manager and a long-lived token. The
# connection goes into OpenBao at clusters/<spoke>; the hub's admin
# registration (clusters/hga-hub-agent/<spoke>.yaml) turns it into a cluster
# Secret. Only the PE agent may read it (ClusterSecretStore hub-secret-store).
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

# A spoke name: a DNS label starting with spoke- (it names the k3d cluster,
# the OpenBao path and the registration file).
spoke_name() {
  local re='^spoke-[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
  [[ ${1:-} =~ $re ]] && [ ${#1} -le 63 ] ||
    { echo "$0: '${1:-}' is not spoke-<name> (a DNS label)" >&2; exit 2; }
}

case "${1:-}" in
  preflight)
    for bin in git tofu docker k3d kubectl helm jq; do
      command -v "$bin" >/dev/null 2>&1 || { echo "missing required tool: $bin" >&2; exit 1; }
    done
    mem_gb=$(docker info --format '{{.MemTotal}}' | awk '{printf "%.1f", $1/1024/1024/1024}')
    echo "Docker memory: ${mem_gb} GiB (recommended >= 8 GiB)"
    check_network
    echo "preflight OK (network hga ready)"
    ;;
  hub)
    create_cluster hga-hub
    pin hga-hub
    ;;
  spoke)
    spoke_name "${2:-}"
    create_cluster "hga-$2"
    pin "hga-$2"
    register_spoke "$2"
    ;;
  register)
    for c in $(k3d_clusters hga-spoke-); do
      register_spoke "${c#hga-}"
    done
    ;;
  pin)
    shift
    [ $# -gt 0 ] || set -- $(k3d_clusters hga-)
    pin "$@"
    ;;
  down)
    shift
    if [ $# -gt 0 ]; then set -- "${@/#/hga-}"; else set -- $(k3d_clusters hga-); fi
    [ $# -gt 0 ] || { echo "no hga-* clusters"; exit 0; }
    KUBECONFIG="$HOME/.kube/config" k3d cluster delete "$@"
    ;;
  *)
    echo "usage: $0 preflight|hub|spoke <name>|register|pin [cluster...]|down [name...]" >&2
    exit 2
    ;;
esac
