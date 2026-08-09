#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/mynetwork"
BRANCH="main"
BIN="/usr/local/bin/mynetwork"
NEW_BIN="/usr/local/bin/mynetwork.new"
BACKUP_BIN="/usr/local/bin/mynetwork.previous"
SERVICE="mynetwork"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root."
[[ -d "$APP_DIR/.git" ]] || die "Repository not found at $APP_DIR."

export PATH="/usr/local/go/bin:$PATH"

for cmd in git node npm go rsync systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing dependency: $cmd"
done

OLD_COMMIT="$(git -C "$APP_DIR" rev-parse HEAD)"

log "Checking for updates"
git -C "$APP_DIR" fetch origin "$BRANCH"
NEW_COMMIT="$(git -C "$APP_DIR" rev-parse "origin/${BRANCH}")"

if [[ "$OLD_COMMIT" == "$NEW_COMMIT" ]]; then
  ok "Already up to date (${OLD_COMMIT:0:8})"
  exit 0
fi

printf 'Updating %s -> %s\n' "${OLD_COMMIT:0:8}" "${NEW_COMMIT:0:8}"

log "Updating source"
git -C "$APP_DIR" reset --hard "origin/${BRANCH}"
git -C "$APP_DIR" clean -fd

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
CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$NEW_BIN" ./cmd/myNetwork
chmod 0755 "$NEW_BIN"

log "Deploying new version"
cp -a "$BIN" "$BACKUP_BIN"
systemctl stop "$SERVICE"
mv -f "$NEW_BIN" "$BIN"

if systemctl start "$SERVICE" && sleep 2 && systemctl is-active --quiet "$SERVICE"; then
  ok "Updated successfully to ${NEW_COMMIT:0:8}"
  exit 0
fi

printf '\nNew version failed to start. Rolling back...\n' >&2
systemctl stop "$SERVICE" || true
cp -a "$BACKUP_BIN" "$BIN"
systemctl start "$SERVICE"

if systemctl is-active --quiet "$SERVICE"; then
  die "Update failed. Previous binary was restored and the service is running."
fi

die "Update and rollback both failed. Check: journalctl -u mynetwork -n 100"
