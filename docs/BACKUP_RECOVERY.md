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

## Opt-in scheduling and monitoring

**Do not enable unattended backups until a manual backup and isolated restore
drill have succeeded.** This repository does not install a scheduler or
modify the running Docker stack automatically.

For a Linux host with `flock`, an example daily cron entry is:

```cron
15 2 * * * cd /absolute/path/to/dock_monitoring && /usr/bin/bash scripts/run-scheduled-backup.sh >> /var/log/dock-monitoring-backup.log 2>&1
```

Use an absolute repository path and ensure the cron account can access Docker,
the Restic password file and the backup mount. Protect log permissions; Docker
and Restic error output may contain deployment details. On macOS, schedule the
same wrapper through launchd rather than relying on a Linux-only systemd timer;
the wrapper warns if `flock` is missing, so prevent overlapping jobs using
your scheduler. Do not use the Linux mountpoint enforcement option on macOS
without installing a compatible utility.

The wrapper records UTC timestamps in `BACKUP_STATUS_DIR` (default
`./backup-status`) and writes a failure marker if the backup exits nonzero.
It never changes `BACKUP_ENABLE_PRUNE`, which remains disabled by default.

Run `bash scripts/check-backup-health.sh` to get a monitoring-friendly exit
code and text. The default freshness threshold is 30 hours; configure
`BACKUP_MAX_AGE_HOURS` in `.env` if needed. Integrate this command into your
existing monitoring agent or scheduled alert mechanism and alert on any
nonzero result. A failed run is reported even if an older successful backup
is still fresh. **No SMTP integration or monitoring service is automatically
configured by this PR.**

Test both success and failure paths in a disposable environment before
installing a cron/launchd schedule. Backup freshness does not prove
restorability; continue periodic isolated restore drills and use
`restic check --read-data` for stronger data verification.

## Prometheus / Alertmanager backup alerts (opt-in)

The Node Exporter container now reads `./backup-metrics/*.prom` through
its textfile collector. This directory is **not** a backup destination.
Prometheus rules cover failed backups, last success older than 30 hours,
missing backup metrics and textfile parsing errors. Existing Alertmanager
routing determines whether notifications are emailed.

**No backup job or monitoring alert is activated automatically.** Only after
a manual backup and isolated restore test have passed:

1. Recreate Node Exporter to enable the collector:
   `docker compose up -d --no-deps node-exporter`.
2. Enable backup alert monitoring explicitly by creating a local sentinel
   file (never commit this file):
   ```bash
   mkdir -p backup-metrics
   printf '# HELP dock_backup_monitoring_enabled Whether backup monitoring is explicitly enabled.\n# TYPE dock_backup_monitoring_enabled gauge\ndock_backup_monitoring_enabled 1\n' > backup-metrics/backup-monitoring.enabled.prom
   ```
3. Run `bash scripts/run-scheduled-backup.sh` once. It writes
   `backup-metrics/backup-status.prom` atomically and reports whether the
   last run succeeded. The host account running the script must have write
   permission to `backup-metrics`; Node Exporter needs read permission.
4. Check Prometheus for `dock_backup_last_run_success`,
   `dock_backup_last_success_timestamp_seconds` and
   `dock_backup_monitoring_enabled`. Confirm the alerts appear in
   Prometheus and route through your configured Alertmanager receiver.
5. Test missing metrics by temporarily moving `backup-status.prom` out of
   the directory; restore it after observing the alert. Test stale/failure
   rules in an isolated test environment rather than deliberately failing
   a production backup.

The sentinel prevents alerts before operators opt into backup monitoring.
Once enabled, absence of backup status metrics triggers a warning. Remove
the sentinel to intentionally disable backup-specific alerts; doing so does
not disable other Prometheus monitoring. Backup status files and sentinel
files are gitignored. The threshold is currently fixed at 30 hours in
`prometheus/rules/backups.yml`.

**Host note:** Node Exporter runs in Docker and reads the bind-mounted
`backup-metrics` directory. The backup script writes to that directory on
the same host. On SELinux systems, ensure the bind mount has an appropriate
readable label; on macOS Docker Desktop, share the repository directory.
