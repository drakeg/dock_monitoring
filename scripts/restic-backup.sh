#!/usr/bin/env bash
# Encrypted, deduplicated off-system backup. Never deletes application volumes.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
[[ -f .env ]] || { echo "Missing .env" >&2; exit 1; }
set -a
source .env
set +a
BACKUP_MOUNT="${BACKUP_MOUNT:-./backups-local}"
BACKUP_REQUIRE_MOUNT="${BACKUP_REQUIRE_MOUNT:-false}"
if [[ "$BACKUP_REQUIRE_MOUNT" == true ]]; then
  [[ -d "$BACKUP_MOUNT" ]] || { echo "Backup mount missing: $BACKUP_MOUNT" >&2; exit 1; }
else
  mkdir -p "$BACKUP_MOUNT"
fi
BACKUP_MOUNT="$(cd "$BACKUP_MOUNT" && pwd)"
if [[ "$BACKUP_REQUIRE_MOUNT" == true ]]; then
  command -v mountpoint >/dev/null 2>&1 || { echo "mountpoint utility required for mount verification" >&2; exit 1; }
  mountpoint -q "$BACKUP_MOUNT" || { echo "Refusing to write: $BACKUP_MOUNT is not mounted" >&2; exit 1; }
fi
BACKUP_DIR="$BACKUP_MOUNT/dock-monitoring"
mkdir -p "$BACKUP_DIR"
PASSFILE="${RESTIC_PASSWORD_FILE:-/etc/dock-monitoring/restic-password}"
[[ -s "$PASSFILE" ]] || { echo "Missing restic password file: $PASSFILE" >&2; exit 1; }
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/db" "$staging/config"
docker exec uptime-db sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --quick --routines --events --all-databases' > "$staging/db/uptime.sql"
docker exec rt-db sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$staging/db/rt.dump"
[[ -s "$staging/db/uptime.sql" && -s "$staging/db/rt.dump" ]] || { echo "Database dump missing or empty; refusing backup" >&2; exit 1; }
# BookStack now uses uptime-db, included in the all-databases dump above.
cp compose.yml "$staging/config/"
[[ ! -f compose.bookstack.yml ]] || cp compose.bookstack.yml "$staging/config/"
cp .env "$staging/config/"
[[ ! -f alertmanager/alertmanager.yml ]] || cp alertmanager/alertmanager.yml "$staging/config/"
args=(-v "$BACKUP_DIR:/repository" -v "$PASSFILE:/password:ro" -v "$staging:/data/config-and-db:ro")
for vol in uptime-kuma-data grafana-data grafana-dashboard-data prometheus-data dockge-data alertmanager-data rt-data rt-caddy-data rt-caddy-config bookstack-data; do
  if docker volume inspect "$vol" >/dev/null 2>&1; then args+=(-v "$vol:/data/volumes/$vol:ro"); fi
done
restic() {
  docker run --rm "${args[@]}" -e RESTIC_REPOSITORY=/repository -e RESTIC_PASSWORD_FILE=/password restic/restic:0.18.1 "$@"
}
if [[ ! -f "$BACKUP_DIR/config" ]]; then restic init; fi
restic backup /data --tag dock-monitoring
# Check repository integrity before considering retention/prune operations.
restic check
if [[ "${BACKUP_ENABLE_PRUNE:-false}" == true ]]; then
  restic forget --tag dock-monitoring --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
  restic check
else
  echo "Retention/prune disabled (BACKUP_ENABLE_PRUNE=false)."
fi
echo "Backup completed successfully. Repository: $BACKUP_DIR"
