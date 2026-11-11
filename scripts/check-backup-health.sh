#!/usr/bin/env bash
# Monitoring-friendly backup freshness check. Exit nonzero on stale or failed backups.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Missing .env" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source .env
set +a
STATUS_DIR="${BACKUP_STATUS_DIR:-./backup-status}"
MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-30}"
[[ "$MAX_AGE_HOURS" =~ ^[0-9]+$ ]] && (( MAX_AGE_HOURS > 0 )) || { echo "Invalid BACKUP_MAX_AGE_HOURS" >&2; exit 2; }
[[ -s "$STATUS_DIR/last-success.txt" ]] || { echo "CRITICAL: no successful scheduled backup recorded"; exit 1; }
[[ ! -e "$STATUS_DIR/last-failure.txt" ]] || { echo "CRITICAL: latest backup failed"; exit 1; }
last="$(cat "$STATUS_DIR/last-success.txt")"
if date -u -d "$last" +%s >/dev/null 2>&1; then
  epoch="$(date -u -d "$last" +%s)"
else
  epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last" +%s 2>/dev/null)" || { echo "CRITICAL: invalid timestamp"; exit 1; }
fi
now="$(date -u +%s)"
age=$((now - epoch))
if (( age < 0 || age > MAX_AGE_HOURS * 3600 )); then
  echo "CRITICAL: last successful backup is stale or timestamp is in future ($last)"
  exit 1
fi
echo "OK: last successful backup started at $last"
