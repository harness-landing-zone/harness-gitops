#!/usr/bin/env bash
# Local k3d hub cluster on Docker bridge network hga.
#   k3d.sh preflight        check required CLIs, Docker memory, and hga network
#   k3d.sh hub              create hga-hub if missing, pin IPs, wait for /readyz
#   k3d.sh pin [cluster...] fix container IPs on network hga
#   k3d.sh down [name...]   delete hga-<name> (default: all hga-* clusters)
set -euo pipefail

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
    echo "usage: $0 preflight|hub|pin [cluster...]|down [name...]" >&2
    exit 2
    ;;
esac
