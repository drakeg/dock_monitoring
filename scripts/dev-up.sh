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

# Verify the same network authentication path RT actually uses.
# PostgreSQL's 127.0.0.1 pg_hba entry can be trust, so localhost is NOT a valid password check.
rt_db_connect() {
  docker compose run --rm --no-deps --entrypoint perl rt -MDBI -e '
    my $dbh = DBI->connect(
      "dbi:Pg:dbname=$ENV{RT_DB_NAME};host=rt-db;port=5432",
      $ENV{RT_DB_USER}, $ENV{RT_DB_PASSWORD},
      {RaiseError => 1, PrintError => 0}
    );
    $dbh->disconnect;
  ' >/dev/null 2>&1
}

if ! rt_db_connect; then
  table_count="$(docker compose exec -T rt-db psql -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" -Atqc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")"
  if [[ "$table_count" != 0 ]]; then
    echo "ERROR: RT database is populated but RT cannot authenticate. Preserving data; manual recovery required." >&2
    exit 1
  fi
  echo "Synchronizing password for empty RT development database..."
  printf "SELECT format('ALTER ROLE %%I PASSWORD %%L', current_user, :'new_password') \\gexec\n" |
    docker compose exec -T rt-db psql -v ON_ERROR_STOP=1 -v new_password="$RT_DB_PASSWORD" \
      -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" >/dev/null
  if ! rt_db_connect; then
    echo "ERROR: RT cannot authenticate after synchronizing development credentials." >&2
    exit 1
  fi
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
    printf "CREATE USER IF NOT EXISTS '\''%s'\''@'\''%%'\'' IDENTIFIED BY '\''%s'\'';\nALTER USER '\''%s'\''@'\''%%'\'' IDENTIFIED BY '\''%s'\'';\nGRANT PROCESS, REPLICATION CLIENT, SLAVE MONITOR, SELECT ON *.* TO '\''%s'\''@'\''%%'\'';\n" "$escaped_user" "$escaped_pass" "$escaped_user" "$escaped_pass" "$escaped_user" | mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"
  '

# Recreate RT after first-time schema initialization: an existing unhealthy process
# may have started before its database was ready and never retried initialization.
docker compose up -d --force-recreate rt mysqld-exporter
docker compose up -d
echo "Development bootstrap complete. Optional Jenkins: docker compose --profile jenkins up -d jenkins"
