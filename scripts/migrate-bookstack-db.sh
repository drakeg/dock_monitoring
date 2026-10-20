#!/usr/bin/env bash
# One-time migration from the original dedicated BookStack DB to shared uptime-db.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
: "${BOOKSTACK_DB_PASSWORD:?Set BOOKSTACK_DB_PASSWORD}"
old_db="$(docker compose -f compose.bookstack.yml ps -q bookstack-db)"
[[ -n "$old_db" ]] || { echo "Old BookStack DB is not running. Stop."; exit 1; }
existing="$(docker exec uptime-db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME=\x27bookstack\x27"' )"
[[ "$existing" == 0 ]] || { echo "Shared DB already contains BookStack; refusing overwrite."; exit 1; }
backup_dir="$(mktemp -d)"
chmod 700 "$backup_dir"
echo "Protected backup directory: $backup_dir"
docker compose -f compose.bookstack.yml stop bookstack
docker exec "$old_db" sh -c 'exec mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --events bookstack' > "$backup_dir/bookstack.sql"
[[ -s "$backup_dir/bookstack.sql" ]] || { echo "Dump failed; restart old BookStack before retrying."; exit 1; }
# Escape quotes/backslashes for SQL literal without printing the secret.
escaped="${BOOKSTACK_DB_PASSWORD//\\/\\\\}"
escaped="${escaped//\'/\'\'}"
printf "CREATE DATABASE bookstack CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\nCREATE USER IF NOT EXISTS 'bookstack'@'%%' IDENTIFIED BY '%s';\nGRANT ALL PRIVILEGES ON bookstack.* TO 'bookstack'@'%%';\n" "$escaped" | docker exec -i uptime-db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"'
docker exec -i uptime-db sh -c 'exec mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" bookstack' < "$backup_dir/bookstack.sql"
echo "Migration complete. Start the new BookStack service with docker compose up -d bookstack."
echo "Do not delete the old database volume until application verification and restore testing."
