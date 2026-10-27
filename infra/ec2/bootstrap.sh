#!/usr/bin/env bash
set -euo pipefail

APP_DIR=/opt/excalidash
DATA_VOLUME_LABEL=excalidash-docker
SWAP_FILE=/swapfile
SWAP_SIZE=2G
# Pinned so first boot does not execute whatever the latest release happens to be.
COMPOSE_VERSION=v5.6.1

REPO_URL="${EXCALIDASH_REPO_URL:-https://github.com/prdai-archive/ExcaliDash.git}"
REPO_REF="${EXCALIDASH_REPO_REF:-main}"

: "${EXCALIDASH_HOSTNAME:?EXCALIDASH_HOSTNAME is required}"
: "${EXCALIDASH_BASIC_AUTH_USERNAME:?EXCALIDASH_BASIC_AUTH_USERNAME is required}"
: "${EXCALIDASH_BASIC_AUTH_PASSWORD_B64:?EXCALIDASH_BASIC_AUTH_PASSWORD_B64 is required}"

wait_for_data_device() {
  local label_device device
  label_device=$(blkid -L "$DATA_VOLUME_LABEL" || true)
  if [ -n "$label_device" ]; then
    printf '%s\n' "$label_device"
    return
  fi
  for _ in $(seq 1 60); do
    for device in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
      if [ -b "$device" ]; then
        printf '%s\n' "$device"
        return
      fi
    done
    sleep 2
  done
  echo "data volume did not attach within 120s" >&2
  exit 1
}

device=$(wait_for_data_device)
if ! blkid "$device" >/dev/null 2>&1; then
  mkfs.ext4 -L "$DATA_VOLUME_LABEL" "$device"
fi
mkdir -p /var/lib/docker
if ! mountpoint -q /var/lib/docker; then
  mount "$device" /var/lib/docker
fi
grep -q "LABEL=$DATA_VOLUME_LABEL" /etc/fstab ||
  printf 'LABEL=%s /var/lib/docker ext4 defaults,nofail 0 2\n' "$DATA_VOLUME_LABEL" >>/etc/fstab

if ! swapon --show=NAME --noheadings | grep -qx "$SWAP_FILE"; then
  fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE" >/dev/null
  swapon "$SWAP_FILE"
fi
grep -q "^$SWAP_FILE" /etc/fstab || printf '%s none swap sw 0 0\n' "$SWAP_FILE" >>/etc/fstab
printf 'vm.swappiness=10\n' >/etc/sysctl.d/99-excalidash.conf
sysctl -w vm.swappiness=10 >/dev/null

dnf install -y --setopt=install_weak_deps=False docker tar curl
systemctl enable --now docker

mkdir -p /usr/local/lib/docker/cli-plugins
if [ ! -x /usr/local/lib/docker/cli-plugins/docker-compose ]; then
  curl -fsSL "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-linux-aarch64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
fi

if [ ! -d "$APP_DIR/.git" ]; then
  dnf install -y --setopt=install_weak_deps=False git
  git clone --branch "$REPO_REF" "$REPO_URL" "$APP_DIR"
fi

if [ ! -f "$APP_DIR/.env" ]; then
  basic_auth_password=$(printf '%s' "$EXCALIDASH_BASIC_AUTH_PASSWORD_B64" | base64 -d)
  basic_auth_hash=$(docker run --rm caddy:2.11.7-alpine \
    caddy hash-password --plaintext "$basic_auth_password")

  cat >"$APP_DIR/.env" <<EOF
COMPOSE_PROJECT_NAME=excalidash
EXCALIDASH_TAG=latest
EXCALIDASH_HOSTNAME=$EXCALIDASH_HOSTNAME
FRONTEND_URL=https://$EXCALIDASH_HOSTNAME
TRUST_PROXY=3
FILE_UPLOAD_MAX_MB=100
EXCALIDASH_BASIC_AUTH_USER=$EXCALIDASH_BASIC_AUTH_USERNAME
EXCALIDASH_BASIC_AUTH_HASH='$basic_auth_hash'
JWT_SECRET=$(openssl rand -hex 32)
CSRF_SECRET=$(openssl rand -hex 32)
EOF
  chmod 600 "$APP_DIR/.env"
fi

install -m 0755 "$APP_DIR/infra/ec2/deploy.sh" /usr/local/bin/excalidash-deploy
install -m 0644 "$APP_DIR/infra/ec2/excalidash-deploy.service" /etc/systemd/system/excalidash-deploy.service
install -m 0644 "$APP_DIR/infra/ec2/excalidash-deploy.timer" /etc/systemd/system/excalidash-deploy.timer
systemctl daemon-reload
systemctl enable --now excalidash-deploy.timer

mkdir -p /etc/caddy/certs "$APP_DIR/backups"

if [ -s /etc/caddy/certs/origin.pem ] && [ -s /etc/caddy/certs/origin.key ]; then
  APP_DIR="$APP_DIR" DEPLOY_REF="$REPO_REF" bash /usr/local/bin/excalidash-deploy
else
  cat >&2 <<'EOF'
Cloudflare origin certificate missing.
Save the Origin Certificate as /etc/caddy/certs/origin.pem and its key as
/etc/caddy/certs/origin.key, then run: systemctl start excalidash-deploy
EOF
fi
