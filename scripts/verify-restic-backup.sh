#!/usr/bin/env bash
# Read-only integrity and restore-readiness verification for the Restic repository.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
[[ -f .env ]] || { echo "Missing .env" >&2; exit 1; }
set -a
# shellcheck disable=SC1091
source .env
set +a
BACKUP_MOUNT="${BACKUP_MOUNT:-./backups-local}"
BACKUP_REQUIRE_MOUNT="${BACKUP_REQUIRE_MOUNT:-false}"
[[ -d "$BACKUP_MOUNT" ]] || { echo "Backup destination missing: $BACKUP_MOUNT" >&2; exit 1; }
BACKUP_MOUNT="$(cd "$BACKUP_MOUNT" && pwd)"
if [[ "$BACKUP_REQUIRE_MOUNT" == true ]]; then
  command -v mountpoint >/dev/null 2>&1 || { echo "mountpoint is required" >&2; exit 1; }
  mountpoint -q "$BACKUP_MOUNT" || { echo "Backup destination not mounted" >&2; exit 1; }
fi
BACKUP_DIR="$BACKUP_MOUNT/dock-monitoring"
PASSFILE="${RESTIC_PASSWORD_FILE:-/etc/dock-monitoring/restic-password}"
[[ -s "$PASSFILE" ]] || { echo "Missing restic password file" >&2; exit 1; }
[[ -f "$BACKUP_DIR/config" ]] || { echo "Restic repository not initialized" >&2; exit 1; }
restic() {
  docker run --rm -v "$BACKUP_DIR:/repository:ro" -v "$PASSFILE:/password:ro" \
    -e RESTIC_REPOSITORY=/repository -e RESTIC_PASSWORD_FILE=/password \
    restic/restic:0.18.1 "$@"
}
echo "Checking Restic repository integrity..."
restic check
echo "Listing latest dock-monitoring snapshot..."
restic snapshots --tag dock-monitoring --latest 1
echo "Verification completed. This checks repository structure and file listings,"
echo "not a full data restore or every stored pack's content."
