#!/usr/bin/env bash
set -Eeuo pipefail

REPO_BASE="https://raw.githubusercontent.com/VRB95/my-network-lxc/main"
DEFAULT_HOSTNAME="mynetwork"
DEFAULT_STORAGE="local-lvm"
DEFAULT_DISK="10"
DEFAULT_CORES="2"
DEFAULT_MEMORY="2048"
DEFAULT_SWAP="512"
DEFAULT_BRIDGE="vmbr0"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this script as root on the Proxmox host."
command -v pct >/dev/null 2>&1 || die "pct not found. Run this on a Proxmox VE host."
command -v pveam >/dev/null 2>&1 || die "pveam not found. Run this on a Proxmox VE host."

log "myNetwork LXC setup"

NEXT_ID="$(pvesh get /cluster/nextid 2>/dev/null || true)"
[[ -n "$NEXT_ID" ]] || NEXT_ID="200"

read -rp "VMID [$NEXT_ID]: " VMID
VMID="${VMID:-$NEXT_ID}"

if pct status "$VMID" >/dev/null 2>&1; then
  die "VMID $VMID already exists."
fi

read -rp "Hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"

read -rp "Storage [$DEFAULT_STORAGE]: " STORAGE
STORAGE="${STORAGE:-$DEFAULT_STORAGE}"

if ! pvesm status | awk 'NR>1 {print $1}' | grep -qx "$STORAGE"; then
  die "Storage '$STORAGE' was not found."
fi

read -rp "Disk size in GB [$DEFAULT_DISK]: " DISK
DISK="${DISK:-$DEFAULT_DISK}"

read -rp "CPU cores [$DEFAULT_CORES]: " CORES
CORES="${CORES:-$DEFAULT_CORES}"

read -rp "RAM in MB [$DEFAULT_MEMORY]: " MEMORY
MEMORY="${MEMORY:-$DEFAULT_MEMORY}"

read -rp "Swap in MB [$DEFAULT_SWAP]: " SWAP
SWAP="${SWAP:-$DEFAULT_SWAP}"

read -rp "Network bridge [$DEFAULT_BRIDGE]: " BRIDGE
BRIDGE="${BRIDGE:-$DEFAULT_BRIDGE}"

log "Locating Debian 13 template"
TEMPLATE="$(pveam list local 2>/dev/null | awk '/debian-13-standard_.*_amd64\.tar\.(zst|gz)/ {print $1; exit}')"

if [[ -z "$TEMPLATE" ]]; then
  log "Downloading Debian 13 template"
  pveam update
  TEMPLATE_NAME="$(pveam available --section system | awk '/debian-13-standard_.*_amd64\.tar\.(zst|gz)/ {print $2}' | tail -n1)"
  [[ -n "$TEMPLATE_NAME" ]] || die "Could not find a Debian 13 template."
  pveam download local "$TEMPLATE_NAME"
  TEMPLATE="local:vztmpl/$TEMPLATE_NAME"
fi

ok "Using template: $TEMPLATE"

log "Creating LXC $VMID"
pct create "$VMID" "$TEMPLATE"   --hostname "$HOSTNAME"   --rootfs "${STORAGE}:${DISK}"   --cores "$CORES"   --memory "$MEMORY"   --swap "$SWAP"   --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp"   --unprivileged 1   --features nesting=1   --onboot 1   --start 1

log "Waiting for network"
for _ in {1..30}; do
  if pct exec "$VMID" -- bash -lc 'ip -4 addr show eth0 | grep -q "inet "' 2>/dev/null; then
    break
  fi
  sleep 2
done

if ! pct exec "$VMID" -- bash -lc 'ip -4 addr show eth0 | grep -q "inet "'; then
  die "LXC was created, but eth0 did not receive an IPv4 address."
fi

log "Installing myNetwork inside LXC"
TMP_INSTALL="/tmp/mynetwork-install-${VMID}.sh"
curl -fsSL "${REPO_BASE}/install.sh" -o "$TMP_INSTALL"
pct push "$VMID" "$TMP_INSTALL" /root/mynetwork-install.sh
rm -f "$TMP_INSTALL"

if ! pct exec "$VMID" -- bash /root/mynetwork-install.sh; then
  die "Installation failed. LXC $VMID was kept for troubleshooting."
fi

pct exec "$VMID" -- rm -f /root/mynetwork-install.sh

IP="$(pct exec "$VMID" -- hostname -I | awk '{print $1}')"

printf '\n\033[1;32m====================================================\033[0m\n'
printf '\033[1;32m myNetwork installed successfully\033[0m\n'
printf '\033[1;32m====================================================\033[0m\n'
printf 'CT ID : %s\n' "$VMID"
printf 'IP    : %s\n' "$IP"
printf 'Web UI: http://%s:8840\n' "$IP"
printf '\nSet the scan interface to: eth0\n'
printf 'Future updates inside the LXC: mynetwork-update\n'
