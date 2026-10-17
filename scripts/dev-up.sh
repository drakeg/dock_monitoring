#!/usr/bin/env bash
# Opt-in local development bootstrap. Never deletes volumes.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env with documented development defaults."
fi

# The Docker exporter image runs unprivileged and needs the host socket's GID.
if [[ -S /var/run/docker.sock ]]; then
  socket_gid="$(stat -c %g /var/run/docker.sock)"
  sed -i -E "s/^DOCKER_SOCKET_GID=.*/DOCKER_SOCKET_GID=${socket_gid}/" .env
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

echo "Starting development databases..."
docker compose up -d rt-db uptime-db

echo "Waiting for PostgreSQL..."
for attempt in $(seq 1 60); do
  if docker compose exec -T rt-db pg_isready -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" >/dev/null 2>&1; then break; fi
  sleep 2
done

# Check credentials over TCP: local socket connections may use trust auth.
if ! docker compose exec -T -e PGPASSWORD="$RT_DB_PASSWORD" rt-db \
  psql -h 127.0.0.1 -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" -Atqc 'SELECT 1' >/dev/null 2>&1; then
  table_count="$(docker compose exec -T rt-db psql -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" -Atqc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")"
  if [[ "$table_count" != 0 ]]; then
    echo "ERROR: RT database contains tables but configured password differs. Preserving database; manual recovery required." >&2
    exit 1
  fi
  echo "Synchronizing password for empty RT development database..."
  # psql variable interpolation quotes the password safely as a SQL literal.
  docker compose exec -T rt-db psql -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" \
    -v new_password="$RT_DB_PASSWORD" -c "SELECT 1" >/dev/null
  docker compose exec -T rt-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER ROLE \"$POSTGRES_USER\" PASSWORD '\''$(printf "%s" "$POSTGRES_PASSWORD" | sed "s/'\''/'\'''\''/g")'\'';"' >/dev/null
fi

table_count="$(docker compose exec -T rt-db psql -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" -Atqc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")"
if [[ "$table_count" == 0 ]]; then
  echo "Initializing empty RT database..."
  docker compose run --rm --no-deps rt \
    bash -c 'cd /opt/rt && perl ./sbin/rt-setup-database --action init --skip-create'
else
  echo "RT database already initialized; leaving its data intact."
fi

echo "Waiting for MariaDB..."
for attempt in $(seq 1 60); do
  if docker compose exec -T uptime-db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -e "SELECT 1" >/dev/null 2>&1'; then break; fi
  sleep 2
done

# Create or reconcile the monitoring-only exporter user. Never change application users.
# Password is passed via environment, not printed in logs.
docker compose exec -T \
  -e EXPORTER_USER="${MYSQLD_EXPORTER_USER:-exporter}" \
  -e EXPORTER_PASSWORD="$MYSQLD_EXPORTER_PASSWORD" uptime-db sh -c '
    escaped_user=$(printf "%s" "$EXPORTER_USER" | sed "s/'\''/'\'''\''/g")
    escaped_pass=$(printf "%s" "$EXPORTER_PASSWORD" | sed "s/'\''/'\'''\''/g")
    printf "CREATE USER IF NOT EXISTS '\''%s'\''@'\''%%'\'' IDENTIFIED BY '\''%s'\'';\nALTER USER '\''%s'\''@'\''%%'\'' IDENTIFIED BY '\''%s'\'';\nGRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO '\''%s'\''@'\''%%'\'';\n" "$escaped_user" "$escaped_pass" "$escaped_user" "$escaped_pass" "$escaped_user" | mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"
  '

docker compose up -d
echo "Development bootstrap complete. Optional Jenkins: docker compose --profile jenkins up -d jenkins"
