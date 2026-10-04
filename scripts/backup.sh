#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${BACKUP_DIR%/}/${STAMP}"

mkdir -p "$DEST"

if [[ ! -f .env ]]; then
  echo "ERROR: .env is required for the MariaDB logical backup." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${UPTIME_DB_ROOT_PASSWORD:?UPTIME_DB_ROOT_PASSWORD must be set in .env}"

echo "Creating MariaDB logical backup..."
docker exec uptime-db mariadb-dump \
  -uroot \
  -p"$UPTIME_DB_ROOT_PASSWORD" \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  --triggers \
  > "$DEST/mariadb-all-databases.sql"

backup_volume() {
  local volume="$1"
  local archive="$2"

  echo "Archiving Docker volume $volume..."
  docker run --rm \
    -v "$volume:/source:ro" \
    -v "$PWD/$DEST:/backup" \
    alpine:3.22 \
    tar -C /source -czf "/backup/$archive" .
}

echo "Stopping stateful non-database services for consistent volume snapshots..."
docker compose stop grafana prometheus alertmanager uptime-kuma dockge

cleanup() {
  echo "Restarting stopped services..."
  docker compose up -d grafana prometheus alertmanager uptime-kuma dockge
}
trap cleanup EXIT

backup_volume grafana-data grafana-data.tar.gz
backup_volume prometheus-data prometheus-data.tar.gz
backup_volume alertmanager-data alertmanager-data.tar.gz
backup_volume uptime-kuma-data uptime-kuma-data.tar.gz
backup_volume dockge-data dockge-data.tar.gz

printf '%s\n' \
  "Created: $STAMP" \
  "Repository commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  "MariaDB image: $(docker inspect --format '{{.Config.Image}}' uptime-db 2>/dev/null || echo unknown)" \
  "Grafana image: $(docker inspect --format '{{.Config.Image}}' grafana 2>/dev/null || echo unknown)" \
  "Prometheus image: $(docker inspect --format '{{.Config.Image}}' prometheus 2>/dev/null || echo unknown)" \
  "Alertmanager image: $(docker inspect --format '{{.Config.Image}}' alertmanager 2>/dev/null || echo unknown)" \
  > "$DEST/MANIFEST.txt"

echo "Backup complete: $DEST"
