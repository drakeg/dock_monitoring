# Backup and Restore

This stack is reproducible from Git, but several services also contain runtime state that must be backed up separately.

## What is backed up

| Component | Persistent state | Backup method |
| --- | --- | --- |
| MariaDB / Uptime Kuma database | `uptime-db-data` | Logical `mariadb-dump` (authoritative database backup) |
| Grafana | `grafana-data` | Stopped-service volume archive |
| Prometheus | `prometheus-data` | Stopped-service volume archive |
| Alertmanager | `alertmanager-data` | Stopped-service volume archive |
| Uptime Kuma application data | `uptime-kuma-data` | Stopped-service volume archive |
| Dockge | `dockge-data` | Stopped-service volume archive |
| Compose, Prometheus rules, provisioning, docs | Git repository | Restore from Git |
| Secrets and deployment-specific config | local `.env`, local Alertmanager config | Back up separately in a secure secret/password system |

Do not treat the repository as a backup of `.env`, SMTP credentials, or other excluded secrets.

## Create a backup

By default:

```bash
./scripts/backup.sh
```

To choose another destination:

```bash
BACKUP_DIR=/path/to/backup-storage ./scripts/backup.sh
```

The destination should ideally be on storage independent of the Docker host. A backup that exists only on the same disk as the monitored host does not protect against host/disk loss.

The script creates a timestamped directory containing the MariaDB SQL dump, volume archives, and `MANIFEST.txt`. It briefly stops Grafana, Prometheus, Alertmanager, Uptime Kuma, and Dockge while archiving their volumes, then restarts them automatically. MariaDB uses a transactional logical dump and is not archived live.

## Verify backups

After every backup:

1. Require a non-empty `mariadb-all-databases.sql`.
2. Run `gzip -t` against every `.tar.gz` archive.
3. Review `MANIFEST.txt`.
4. Confirm the stopped services returned to a healthy/running state.
5. Periodically perform a restore drill on a non-production/test Docker host. Archive existence alone is not proof of recoverability.

## Restore principles

Restore into compatible software versions. Use `MANIFEST.txt` and repository history to identify the configuration/image generation that produced the backup.

Never use `docker compose down -v` during an ordinary restore unless the explicit intent is to destroy all existing named-volume data.

### MariaDB

The SQL dump is the authoritative MariaDB backup. For a disaster restore, start with an empty compatible MariaDB data volume, wait for MariaDB to initialize, then import the dump:

```bash
cat /path/to/mariadb-all-databases.sql | \
  docker exec -i uptime-db mariadb -uroot -p"$UPTIME_DB_ROOT_PASSWORD"
```

After import, verify Uptime Kuma tables/data, run any version-appropriate MariaDB upgrade checks, start Uptime Kuma, and verify existing monitors and notification configuration.

### Named-volume archives

For Grafana, Prometheus, Alertmanager, Uptime Kuma application data, or Dockge:

1. Stop the service that owns the target volume.
2. Preserve/rename the current volume or create a separate test volume before destructive recovery.
3. Ensure the target named volume is empty.
4. Extract the corresponding archive into the volume with a temporary container.
5. Start the owning service.
6. Validate application state and logs before discarding the previous volume.

Example restore pattern:

```bash
docker run --rm \
  -v grafana-data:/restore \
  -v /path/to/backup:/backup:ro \
  alpine:3.22 \
  tar -C /restore -xzf /backup/grafana-data.tar.gz
```

Substitute the appropriate volume and archive for the service being restored.

## Prometheus retention and recovery

Prometheus historical metrics are useful but not equivalent to configuration. Prometheus configuration and alert rules live in Git. If historical TSDB data is expendable after a disaster, Prometheus can be recreated with a fresh volume and will resume collecting new data. Restore `prometheus-data` only when retaining historical metrics is worth the additional recovery work.

## Restore validation

A restore is complete only after:

- Compose renders successfully;
- required containers are healthy/running;
- Prometheus targets are UP;
- alert rules load;
- Alertmanager is connected;
- Grafana datasource/dashboards work;
- Uptime Kuma monitors and notifications are present;
- MariaDB metrics report `mysql_up == 1`; and
- a controlled notification test succeeds when the notification path itself was restored or changed.
