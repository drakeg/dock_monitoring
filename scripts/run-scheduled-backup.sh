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
attempt_epoch="$(date -u +%s)"
# Metrics are published only when the operator opts in with the sentinel file.
METRICS_DIR="${BACKUP_METRICS_DIR:-./backup-metrics}"
publish_metrics() {
  [[ -f "$METRICS_DIR/backup-monitoring.enabled.prom" ]] || return 0
  local result="$1" last_success=0 tmp
  [[ -s "$STATUS_DIR/last-success-epoch.txt" ]] && read -r last_success < "$STATUS_DIR/last-success-epoch.txt"
  tmp="$(mktemp "$METRICS_DIR/.backup-status.XXXXXX")" || return 1
  {
    printf "# HELP dock_backup_last_attempt_timestamp_seconds Unix time of latest backup attempt.\n"
    printf "# TYPE dock_backup_last_attempt_timestamp_seconds gauge\n"
    printf "dock_backup_last_attempt_timestamp_seconds %s\n" "$attempt_epoch"
    printf "# HELP dock_backup_last_success_timestamp_seconds Unix time of latest successful backup.\n"
    printf "# TYPE dock_backup_last_success_timestamp_seconds gauge\n"
    printf "dock_backup_last_success_timestamp_seconds %s\n" "$last_success"
    printf "# HELP dock_backup_last_run_success Whether latest backup succeeded (1 yes, 0 no).\n"
    printf "# TYPE dock_backup_last_run_success gauge\n"
    printf "dock_backup_last_run_success %s\n" "$result"
  } > "$tmp"
  mv -f "$tmp" "$METRICS_DIR/backup-status.prom"
}

printf '%s\n' "$start" > "$STATUS_DIR/last-attempt.txt"
if bash scripts/restic-backup.sh; then
  printf '%s\n' "$start" > "$STATUS_DIR/last-success.txt"
  date -u +%s > "$STATUS_DIR/last-success-epoch.txt"
  rm -f "$STATUS_DIR/last-failure.txt"
  publish_metrics 1
  echo "Backup succeeded at $start"
else
  rc=$?
  printf '%s exit=%s\n' "$start" "$rc" > "$STATUS_DIR/last-failure.txt"
  publish_metrics 0 || echo "WARNING: failed to publish backup metrics" >&2
  echo "Backup FAILED (exit $rc). See backup job logs." >&2
  exit "$rc"
fi
