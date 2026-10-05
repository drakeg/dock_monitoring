#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f .env ]]; then
  echo "ERROR: .env is required." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

BACKUP_DIR="${BACKUP_DIR:-./backups}"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"
BACKUP_PATH="${1:-}"

if [[ -z "$BACKUP_PATH" ]]; then
  BACKUP_PATH="$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -print | sort | tail -n 1)"
fi

if [[ -z "$BACKUP_PATH" ]]; then
  echo "ERROR: no backup directory found under $BACKUP_DIR." >&2
  exit 1
fi

if [[ "$BACKUP_PATH" != /* ]]; then
  BACKUP_PATH="$(cd "$(dirname "$BACKUP_PATH")" && pwd)/$(basename "$BACKUP_PATH")"
fi

DUMP="$BACKUP_PATH/mariadb-uptime-kuma.sql"
test -s "$DUMP" || { echo "ERROR: missing or empty $DUMP" >&2; exit 1; }

CONTAINER="dock-monitoring-mariadb-restore-test"
VOLUME="dock-monitoring-mariadb-restore-test"
TEST_ROOT_PASSWORD="restore-test-only-$(date +%s)-$$"

cleanup() {
  echo "Cleaning up isolated restore-test resources..."
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup
docker volume create "$VOLUME" >/dev/null

echo "Starting isolated MariaDB 12.3 restore target..."
docker run -d \
  --name "$CONTAINER" \
  -e MARIADB_ROOT_PASSWORD="$TEST_ROOT_PASSWORD" \
  -v "$VOLUME:/var/lib/mysql" \
  mariadb:12.3 >/dev/null

echo "Waiting for MariaDB initialization..."
for _ in $(seq 1 120); do
  if docker exec "$CONTAINER" mariadb-admin ping -uroot -p"$TEST_ROOT_PASSWORD" --silent >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec "$CONTAINER" mariadb-admin ping -uroot -p"$TEST_ROOT_PASSWORD" --silent >/dev/null 2>&1 || {
  echo "ERROR: restore-test MariaDB did not become ready." >&2
  docker logs "$CONTAINER" >&2 || true
  exit 1
}

echo "Importing backup: $DUMP"
docker exec -i "$CONTAINER" mariadb -uroot -p"$TEST_ROOT_PASSWORD" < "$DUMP"

echo "Validating restored databases..."
DATABASES="$(docker exec "$CONTAINER" mariadb -N -uroot -p"$TEST_ROOT_PASSWORD" -e 'SHOW DATABASES;')"
printf '%s\n' "$DATABASES"

EXPECTED_DB="${UPTIME_DB_NAME:-uptime_kuma}"
printf '%s\n' "$DATABASES" | grep -Fx "$EXPECTED_DB" >/dev/null || {
  echo "ERROR: expected database '$EXPECTED_DB' was not restored." >&2
  exit 1
}

TABLE_COUNT="$(docker exec "$CONTAINER" mariadb -N -uroot -p"$TEST_ROOT_PASSWORD" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$EXPECTED_DB';")"
if [[ "$TABLE_COUNT" -le 0 ]]; then
  echo "ERROR: restored database '$EXPECTED_DB' contains no tables." >&2
  exit 1
fi

echo "Restore drill PASSED: '$EXPECTED_DB' restored with $TABLE_COUNT tables."
