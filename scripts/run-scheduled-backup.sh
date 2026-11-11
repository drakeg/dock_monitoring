#!/usr/bin/env bash
# Opt-in scheduled backup entrypoint. Does not change containers or prune settings.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
[[ -f .env ]] || { echo "Missing .env" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source .env
set +a
STATUS_DIR="${BACKUP_STATUS_DIR:-./backup-status}"
mkdir -p "$STATUS_DIR"
STATUS_DIR="$(cd "$STATUS_DIR" && pwd)"
exec 9>"$STATUS_DIR/backup.lock"
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || { echo "Backup already running" >&2; exit 1; }
else
  echo "WARNING: flock unavailable; overlapping jobs are not prevented" >&2
fi
start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "$start" > "$STATUS_DIR/last-attempt.txt"
if bash scripts/restic-backup.sh; then
  printf '%s\n' "$start" > "$STATUS_DIR/last-success.txt"
  rm -f "$STATUS_DIR/last-failure.txt"
  echo "Backup succeeded at $start"
else
  rc=$?
  printf '%s exit=%s\n' "$start" "$rc" > "$STATUS_DIR/last-failure.txt"
  echo "Backup FAILED (exit $rc). See backup job logs." >&2
  exit "$rc"
fi
