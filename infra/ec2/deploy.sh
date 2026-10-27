#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/excalidash}"
DEPLOY_REF="${DEPLOY_REF:-main}"
BACKUP_RETENTION="${BACKUP_RETENTION:-4}"
CERT_DIR="${CERT_DIR:-/etc/caddy/certs}"

cd "$APP_DIR"

if [ ! -s "$CERT_DIR/origin.pem" ] || [ ! -s "$CERT_DIR/origin.key" ]; then
  echo "missing Cloudflare origin certificate in $CERT_DIR" >&2
  exit 1
fi

PROJECT="${COMPOSE_PROJECT_NAME:-}"
if [ -z "$PROJECT" ] && [ -f .env ]; then
  PROJECT=$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' .env | tail -n 1)
fi
PROJECT="${PROJECT:-excalidash}"

compose=(docker compose -f docker-compose.prod.yml -f infra/ec2/compose.override.yml)

git fetch --prune origin
git reset --hard "origin/$DEPLOY_REF"

mkdir -p "$APP_DIR/backups"
stamp=$(date -u +%Y%m%dT%H%M%SZ)

"${compose[@]}" stop backend
if docker volume inspect "${PROJECT}_backend-data" >/dev/null 2>&1; then
  docker run --rm \
    -v "${PROJECT}_backend-data:/data:ro" \
    -v "$APP_DIR/backups:/backup" \
    alpine:3.24 sh -c "tar czf /backup/predeploy-${stamp}.tgz -C /data ."
fi

"${compose[@]}" pull
"${compose[@]}" up -d --remove-orphans
docker image prune -f >/dev/null

find "$APP_DIR/backups" -name 'predeploy-*.tgz' -printf '%T@ %p\n' |
  sort -rn |
  tail -n "+$((BACKUP_RETENTION + 1))" |
  cut -d' ' -f2- |
  xargs -r rm -f

for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:6767/api/health >/dev/null 2>&1; then
    echo "deployed $stamp"
    exit 0
  fi
  sleep 5
done

echo "health check did not pass after deploy" >&2
exit 1
