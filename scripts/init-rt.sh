#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for the RT PostgreSQL database to become healthy..."
docker compose up -d rt-db

until docker compose exec -T rt-db pg_isready -U "${RT_DB_USER:-rt}" -d "${RT_DB_NAME:-rt}" >/dev/null 2>&1; do
  sleep 2
done

echo "Initializing the RT database..."
docker compose run --rm --no-deps rt \
  bash -c 'cd /opt/rt && perl ./sbin/rt-setup-database --action init --skip-create'

echo "Starting RT..."
docker compose up -d rt rt-web

echo "RT initialization complete."
