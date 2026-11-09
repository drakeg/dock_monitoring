# Backup safety and verification

The supported encrypted backup entrypoint is `bash scripts/restic-backup.sh`.
The older `scripts/backup.sh` is a separate, disruptive tar snapshot workflow:
it stops services and is **not** the scheduled Restic job.

## Before running

1. Configure `BACKUP_MOUNT` and `RESTIC_PASSWORD_FILE` in a private `.env`.
2. Prefer an external disk or mounted NAS and set `BACKUP_REQUIRE_MOUNT=true`.
   On macOS, `mountpoint` may not be available; use a Linux host for strict
   mountpoint enforcement or configure an equivalent verified mount check.
3. Preserve the Restic password independently from the backup destination.
4. Confirm `docker compose ps` shows `uptime-db` and `rt-db` healthy.
5. Run `bash scripts/restic-backup.sh` from the repository directory.

The script creates logical dumps of the shared MariaDB instance (Uptime Kuma
and BookStack when present), and the RT PostgreSQL database. It also captures
the listed application volumes and deployment configuration, including the
secret-bearing `.env`, **inside the encrypted Restic repository**.

**Do not store the repository password alongside the only copy of the backup.**
A successful snapshot does not establish that an application can be restored.

## Retention

Pruning is disabled by default. Only after a verified restore drill, set
`BACKUP_ENABLE_PRUNE=true` in `.env`. The script then retains 7 daily,
4 weekly and 6 monthly snapshots tagged `dock-monitoring`, and checks
repository integrity before and after pruning. Pruning deletes old backup
snapshots, never Docker application volumes.

## Read-only verification

```bash
bash scripts/verify-restic-backup.sh
```

This checks repository metadata/integrity and lists recent tagged snapshots.
It does **not** decrypt and restore every file. For a stronger data-integrity
test, use Restic's `check --read-data` on a maintenance schedule.

## Restore drill (isolated environment only)

1. Provision a separate test host and an empty Docker environment.
2. Copy the encrypted Restic repository and supply its password securely.
3. Restore the desired snapshot into an **empty directory**, not a running
   application's volume. Example:
   ```bash
   docker run --rm -v "$PWD/restic-repository:/repository:ro" \
     -v "$PWD/restore-test:/restore" \
     -v "$RESTIC_PASSWORD_FILE:/password:ro" \
     -e RESTIC_REPOSITORY=/repository -e RESTIC_PASSWORD_FILE=/password \
     restic/restic:0.18.1 restore latest --target /restore
   ```
4. Inspect `restore-test/data/config-and-db/db/uptime.sql` and `rt.dump`.
   Restore SQL dumps to **fresh** test databases with matching application
   versions, not the production databases. Recreate app volumes from the
   restored `data/volumes` contents only while test applications are stopped.
5. Verify BookStack attachments/pages, RT tickets, Uptime Kuma monitors,
   Grafana dashboards and credentials, then record the recovery time.

The sample restore command assumes `restic-repository` is a local copy of the
`dock-monitoring` Restic repository and the restore target is empty.
Never use `docker compose down -v` to perform a restore.
