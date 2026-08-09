#!/usr/bin/env bash
set -Eeuo pipefail

APP_REPO="https://github.com/VRB95/my-network.git"
INSTALLER_BASE="https://raw.githubusercontent.com/VRB95/my-network-lxc/main"
APP_DIR="/opt/mynetwork"
DATA_DIR="/data/myNetwork"
BIN="/usr/local/bin/mynetwork"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root inside the LXC."

log "Updating Debian"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get full-upgrade -y

log "Installing system dependencies"
apt-get install -y git curl ca-certificates build-essential arp-scan tzdata rsync xz-utils

log "Installing Node.js 22"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

log "Cloning myNetwork"
rm -rf "$APP_DIR"
git clone "$APP_REPO" "$APP_DIR"

GO_VERSION="$(awk '/^go / {print $2; exit}' "$APP_DIR/backend/go.mod")"
[[ -n "$GO_VERSION" ]] || die "Could not determine Go version from backend/go.mod."

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) GO_ARCH="amd64" ;;
  arm64) GO_ARCH="arm64" ;;
  *) die "Unsupported architecture: $ARCH" ;;
esac

log "Installing Go ${GO_VERSION}"
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o "/tmp/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
rm -f "/tmp/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
export PATH="/usr/local/go/bin:/usr/local/bin:$PATH"

log "Building frontend"
cd "$APP_DIR/frontend"
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi
npm run build

mkdir -p "$APP_DIR/backend/internal/web/public/assets"
rsync -a --delete "$APP_DIR/frontend/dist/assets/" "$APP_DIR/backend/internal/web/public/assets/"

log "Building backend"
cd "$APP_DIR/backend"
go mod download
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$BIN" ./cmd/myNetwork
chmod 0755 "$BIN"

log "Creating persistent data directory"
mkdir -p "$DATA_DIR"

log "Installing update command"
curl -fsSL "${INSTALLER_BASE}/update.sh" -o /usr/local/sbin/mynetwork-update
chmod 0755 /usr/local/sbin/mynetwork-update

log "Creating systemd service"
cat >/etc/systemd/system/mynetwork.service <<EOF
[Unit]
Description=myNetwork LAN Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=TZ=Europe/Bucharest
ExecStart=${BIN} -d ${DATA_DIR}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mynetwork

sleep 2
systemctl is-active --quiet mynetwork || {
  journalctl -u mynetwork -n 100 --no-pager
  die "myNetwork failed to start."
}

ok "myNetwork is running"
