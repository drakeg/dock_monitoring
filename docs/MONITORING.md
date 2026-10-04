# Monitoring and Dashboarding Guide

This guide describes how the infrastructure in this repository is intended to be used after the containers are running. The Compose stack provides the monitoring components; this document covers the operational layer: metrics collection, dashboards, availability checks, and alerting.

## Monitoring architecture

```text
Linux host ───────────────> Node Exporter ──┐
Docker containers ─────────> cAdvisor ──────┤
Traefik ───────────────────> /metrics ──────┤
                                            v
                                      Prometheus
                                            │
                                            v
                                         Grafana

Applications / infrastructure ───────> Uptime Kuma
                                             │
                                             v
                                      Notifications
```

Each component has a distinct responsibility:

- **Node Exporter** exposes Linux host metrics.
- **cAdvisor** exposes Docker/container resource metrics.
- **Traefik** exposes reverse-proxy metrics.
- **Prometheus** scrapes, stores, and queries time-series metrics.
- **Grafana** turns Prometheus data into dashboards and visualizations.
- **Uptime Kuma** actively checks whether services are reachable and healthy.
- **MariaDB** stores Uptime Kuma application data.
- **Dockge** manages Compose stacks; it is an administration tool rather than a monitoring data source.

## 1. Prometheus targets

Prometheus is the central metrics collector. Its scrape configuration is stored in `prometheus/prometheus.yml`.

| Job | Target | Purpose |
| --- | --- | --- |
| `prometheus` | `prometheus:9090` | Prometheus self-monitoring |
| `cadvisor` | `cadvisor:8080` | Docker/container metrics |
| `node-exporter` | `node-exporter:9100` | Linux host metrics |
| `traefik` | `traefik:8082` | Reverse-proxy metrics |
| `mariadb` | `mysqld-exporter:9104` | MariaDB database metrics |

Prometheus is available on the LAN at `http://SERVER-IP:9091`. The **Status > Targets** page should show configured targets as healthy before Grafana dashboards are expected to work correctly. The default scrape and evaluation interval is 15 seconds.

## 2. Grafana datasource

Grafana's Prometheus datasource is provisioned automatically by `grafana/provisioning/datasources/prometheus.yml` and uses:

```text
http://prometheus:9090
```

Grafana is available on the LAN at `http://SERVER-IP:3002`. Because Grafana and Prometheus communicate over the Docker network, Grafana should use `prometheus:9090`, not the host's published `9091` port.

## Dashboard import checklist

The dashboards below are the standard Grafana dashboards currently validated for this stack. Treat this table as the authoritative import checklist. Add dashboards here as they are selected and verified; do not require an untested community dashboard simply because it looks useful.

| Required | Dashboard | Grafana ID | Datasource | Metrics source | Status |
| --- | --- | ---: | --- | --- | --- |
| Yes | Node Exporter Full | **1860** | Prometheus | Node Exporter | Verified working |
| Yes | cAdvisor exporter - Docker containers Overview | **21743** | Prometheus | cAdvisor | Verified working |

### Standard import procedure

For every dashboard listed by Grafana ID:

1. Open **Grafana > Dashboards**.
2. Select **New > Import**.
3. Enter the dashboard ID from the table above.
4. Select **Load**.
5. Select the provisioned **Prometheus** datasource when prompted.
6. Select **Import**.
7. Verify that panels populate with current data and that dashboard variables/drop-downs return expected hosts or containers.
8. If a dashboard is customized, document the customization here and prefer exporting/provisioning the finalized JSON from this repository.

### Verification

**Node Exporter Full (1860)** is considered working when host-level panels populate, including CPU/load, memory, filesystem/disk, network, and uptime/system information.

**cAdvisor exporter - Docker containers Overview (21743)** is considered working when container names are present and CPU, memory, network, and related container panels contain current data.

If a required dashboard does not populate, verify **Prometheus > Status > Targets** before changing the dashboard. The relevant exporter target should be UP.

### Future dashboards

Additional dashboards may be added for Traefik, Prometheus itself, application-specific metrics, databases, or other exporters as the environment grows. Before a dashboard becomes part of the standard installation:

1. Verify that its required exporter/metrics already exist or deliberately add them.
2. Confirm its PromQL matches the labels produced by the deployed exporter version.
3. Confirm useful panels populate.
4. Avoid duplicating information already covered well by an existing dashboard.
5. Record its exact name, Grafana ID (or repository JSON path), datasource, prerequisites, and purpose in this checklist.
6. Mark it required or optional.
7. Prefer repository-provisioned dashboard JSON after customization/stabilization.

## 3. Host dashboard

The first dashboard being configured is **Node Exporter Full**, Grafana dashboard ID **1860**.

In Grafana:

1. Open **Dashboards**.
2. Select **New > Import**.
3. Enter dashboard ID `1860`.
4. Load the dashboard.
5. Select the provisioned **Prometheus** datasource.
6. Import the dashboard.

This dashboard provides host-level visibility such as CPU/load, memory/swap, filesystem capacity, disk activity, network traffic, uptime, and other Node Exporter metrics.

## 4. Docker/container dashboard

After host metrics are working, add a cAdvisor-based Grafana dashboard. The container dashboard should emphasize operational information:

- container CPU utilization
- memory usage and limits
- network receive/transmit
- filesystem/storage activity
- running containers
- resource-heavy containers
- resource trends over time

Dashboard queries must match the labels exported by the cAdvisor version actually running. Do not assume an old community dashboard will work unchanged.

The selected container dashboard is **cAdvisor exporter - Docker containers Overview**, Grafana dashboard ID **21743**. It has been verified against this stack and is working with the current cAdvisor metrics.

Manual imports are acceptable while evaluating dashboards. Once a dashboard is selected and customized for ongoing use, prefer provisioning it from this repository.

## 5. Uptime Kuma monitoring

Prometheus/Grafana and Uptime Kuma solve different problems. Prometheus/Grafana show resource behavior and trends; Uptime Kuma actively verifies that services respond.

Uptime Kuma is available at `http://SERVER-IP:3001`.

Initial monitors should include:

| Service | Suggested check | Default endpoint |
| --- | --- | --- |
| Grafana | HTTP | `http://SERVER-IP:3002` |
| Prometheus | HTTP | `http://SERVER-IP:9091` |
| Dockge | HTTP | `http://SERVER-IP:5001` |
| Traefik | HTTP/TCP as appropriate | `SERVER-IP:80` |
| Uptime Kuma | External/self-monitoring strategy | `http://SERVER-IP:3001` |

Add application stacks as they are deployed. Prefer dedicated application health endpoints such as `/health`, `/healthz`, or `/api/health` when available. A TCP check proves only that a port accepts a connection; an HTTP health endpoint can verify more of the application stack.

MariaDB is intentionally not exposed to the LAN and is normally monitored indirectly through Uptime Kuma health and Docker metrics unless a database-specific check is required.

### Notifications

The initial notification method for this deployment is **Email (SMTP)**. Uptime Kuma supports many additional notification providers, so the notification layer is intentionally not tied to email.

To configure any notification provider:

1. Open **Uptime Kuma**.
2. Open **Settings > Notifications**.
3. Choose **Setup Notification**.
4. Select the desired notification provider.
5. Enter the provider-specific connection information or credentials.
6. Use **Test** to verify delivery before saving.
7. Save the notification.
8. Associate it with the appropriate monitors. Notification channels can be reused across multiple monitors.

#### Email (SMTP)

For email, select **Email (SMTP)** and configure the values required by the mail provider, normally:

- SMTP hostname
- SMTP port
- SMTP security/TLS mode
- username and password or provider-specific SMTP credential
- From address
- To address
- optional CC/BCC
- optional custom subject/body

Common SMTP configurations use STARTTLS on port 587 or TLS on port 465, but the actual settings must match the selected mail provider. Do not disable TLS/STARTTLS merely to make a configuration work unless the SMTP server is intentionally trusted and designed for unencrypted SMTP.

Use Uptime Kuma's **Test** function and confirm that the test message arrives before assigning the notification to production monitors.

Do **not** store SMTP passwords or provider credentials in this repository.

#### Other notification providers

Uptime Kuma supports a large collection of built-in/integrated notification services. Examples include:

- Discord
- Slack
- Microsoft Teams
- Telegram
- Gotify
- Pushover
- Signal
- Mattermost
- webhooks
- Apprise, which can extend delivery to many additional services

The exact fields vary by provider. Webhook-based providers typically require a webhook URL; API-based providers may require a token/key; messaging providers may require channel, room, or recipient identifiers.

When enabling another provider, follow the same pattern: create it under **Settings > Notifications**, supply only the credentials required by that provider, test it, save it, and associate it with the desired monitors.

Uptime Kuma's current notification-provider list is the authoritative source for available integrations because supported providers can change between releases.

#### Multiple channels

Multiple notification channels can coexist. A future configuration could, for example, use email for normal infrastructure alerts and add another provider for higher-priority or faster notifications.

Avoid configuring every provider for every monitor by default. Notifications should remain actionable and low-noise.

## 6. Alerting

Alerts should be actionable and low-noise.

**Availability alerts (Uptime Kuma):** service unavailable, HTTP health failure, or repeated connection failure. Allow appropriate tolerance for brief restarts.

**Host alerts (Prometheus/Grafana):** filesystem approaching capacity, sustained memory pressure, sustained high CPU/load, or an exporter/scrape target becoming unavailable.

**Container alerts:** sustained abnormal CPU usage, memory approaching a configured limit, repeated unavailability, or unexpectedly missing metrics from important containers.

Tune thresholds from observed normal behavior rather than treating generic example thresholds as production defaults.

## 7. Application onboarding

For each application added under `/opt/docker`:

1. Determine whether it exposes a health endpoint.
2. Add an Uptime Kuma availability monitor.
3. Determine whether it exposes Prometheus-format metrics.
4. Add a Prometheus scrape job when useful.
5. Add or extend a Grafana dashboard when the metrics provide operational value.
6. Define alerts only for conditions that require action.
7. Document application-specific monitoring configuration in its repository.

## Dashboard and alert configuration as code

The long-term goal is to keep finalized monitoring configuration in source control. A future repository layout can include:

```text
grafana/
└── provisioning/
    ├── datasources/
    │   └── prometheus.yml
    └── dashboards/
        ├── dashboards.yml
        └── json/
            ├── host.json
            └── containers.json

prometheus/
├── prometheus.yml
└── rules/
    └── alerts.yml
```

Do not commit notification credentials, API tokens, passwords, or other secrets.

## Tool responsibilities

| Need | Primary tool |
| --- | --- |
| Linux host metrics | Node Exporter |
| Docker/container metrics | cAdvisor |
| Reverse-proxy metrics | Traefik |
| Metrics storage/query | Prometheus |
| Visual dashboards | Grafana |
| Availability/health checks | Uptime Kuma |
| Availability notifications | Uptime Kuma |
| Metrics-based alerts | Grafana/Prometheus |
| Compose administration | Dockge |

This avoids duplicating every check in every tool.

## Current status

### Completed

- Docker Compose monitoring infrastructure deployed.
- Prometheus configured for Prometheus, cAdvisor, Node Exporter, Traefik, and MariaDB through `mysqld_exporter`.
- Prometheus and Grafana persistent storage configured.
- Prometheus datasource provisioned in Grafana.
- Node Exporter Full dashboard (ID 1860) imported and working.
- cAdvisor exporter - Docker containers Overview dashboard (ID 21743) imported and working.
- Node Exporter collecting host metrics.
- cAdvisor collecting container metrics.
- Traefik Prometheus metrics enabled.
- Uptime Kuma deployed with dedicated MariaDB.
- Dockge deployed for Compose management.
- Management services available on selected LAN ports.
- Restricted Docker Socket Proxy used for Traefik.
- Uptime Kuma infrastructure monitors and IONOS Email (SMTP) notifications configured and verified.
- Rootless Docker published-port issue documented; `monitoring` remains non-internal.
- MariaDB upgraded from 11 to 12.3 LTS with a pre-upgrade logical backup and post-upgrade validation.
- Dedicated least-privilege `mysqld_exporter` account configured.
- `mariadb` Prometheus target at `mysqld-exporter:9104` verified **UP**; MariaDB/exporter ports remain private.

### In progress

- Select and validate a MariaDB/MySQL Grafana dashboard against the deployed `mysqld_exporter` metrics.
- Define and validate low-noise Prometheus alert rules for host, target, container, and MariaDB conditions.

### Planned

- Add additional Uptime Kuma notification channels if useful.
- Define useful host/container alerts.
- Provision finalized dashboards from this repository.
- Add application-specific monitoring as additional stacks are onboarded.

## Guiding principles

The monitoring system should remain:

- **Reproducible** — configuration belongs in source control where practical.
- **Actionable** — alerts identify conditions worth responding to.
- **Low-noise** — harmless/transient events do not constantly notify.
- **Layered** — metrics and availability checks complement rather than duplicate each other.
- **Secure** — databases, exporters, and Docker API access stay off the LAN unless necessary.
- **Portable** — host-specific values remain environment configuration or clearly documented deployment steps.


## Uptime Kuma infrastructure monitor baseline

The following infrastructure monitors have been configured and verified working. Use Docker service/container DNS names for internal service monitoring rather than the host LAN address and published host ports.

| Monitor | Type | Target | Status |
| --- | --- | --- | --- |
| Prometheus | HTTP(s) | `http://prometheus:9090` | Verified UP |
| Grafana | HTTP(s) | `http://grafana:3000` | Verified UP |
| Dockge | HTTP(s) | `http://dockge:5001` | Verified UP |
| Traefik Metrics | HTTP(s) | `http://traefik:8082/metrics` | Verified UP |

### Standard alert settings

Use these defaults for the infrastructure monitors unless a service has a documented reason to differ:

- Heartbeat interval: **60 seconds**
- Retries: **3**
- Retry interval: **30 seconds**
- Notification: the configured **Mad Mallards email/SMTP** notification
- HTTP status: require a successful HTTP response appropriate to the endpoint

These settings reduce noise from brief container restarts while still detecting sustained failures quickly.

### Docker DNS requirement

Container-name monitoring requires Uptime Kuma and the monitored service to share at least one Docker network. Uptime Kuma is attached to `monitoring` for Prometheus/Grafana/Traefik and to `proxy` for Dockge. If a monitor reports `getaddrinfo ENOTFOUND <service>`, verify shared network membership before substituting the host IP.

Internal Docker-DNS checks validate the application/service directly and avoid unnecessary dependency on host port publishing. They do **not** prove that a published LAN port or external route is reachable. Add a separate path-level or external monitor when that distinction matters.

### Uptime Kuma availability

Do not treat a Uptime Kuma self-monitor as sufficient availability monitoring. If the Kuma container, Docker host, network, power, or site fails, that same Kuma instance may be unable to send the outage notification. A future independent/external monitor should check Uptime Kuma or another externally reachable endpoint on this infrastructure.



## MariaDB observability

MariaDB remains private on the `uptime-db` Docker network. Database metrics are collected by Prometheus through `mysqld_exporter`; neither MariaDB port 3306 nor exporter port 9104 is published to the LAN.

The exporter also joins `monitoring` so Prometheus can scrape `mysqld-exporter:9104`.

### Monitoring account

Create a dedicated database account rather than using the MariaDB root or Uptime Kuma application account. The exporter project's documented baseline grants are `PROCESS`, `REPLICATION CLIENT`, and `SELECT`. Limit the account to a small number of connections.

Generate a unique password and place the same value in the local, uncommitted `.env` as `MYSQLD_EXPORTER_PASSWORD`. Do not commit the password.

Example SQL, run as an administrative MariaDB user:

```sql
CREATE USER 'exporter'@'%' IDENTIFIED BY 'REPLACE_WITH_EXPORTER_PASSWORD'
  WITH MAX_USER_CONNECTIONS 3;
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'%';
```

The `%` host is used because the exporter is a separate container with a dynamic address on the private Docker network. Network isolation and the absence of a published MariaDB port prevent this from making the database publicly reachable.

The exporter itself is configured for no more than two open connections per scrape, below the database user's three-connection limit.

### Verification

After creating the database account and setting `MYSQLD_EXPORTER_PASSWORD`:

1. Start/recreate `mysqld-exporter` and Prometheus with Docker Compose.
2. Open **Prometheus > Status > Targets**.
3. Verify the `mariadb` target at `mysqld-exporter:9104` is **UP**.
4. Query `mysql_up`; the expected value is `1`.
5. Confirm exporter port 9104 and MariaDB port 3306 are not published to the LAN.
6. Only after metrics are verified, select/import a MariaDB/MySQL Grafana dashboard and add it to the authoritative dashboard checklist.

This deployment has completed these checks: the `mariadb` target is verified **UP** in Prometheus and the exporter is collecting from MariaDB 12.3 LTS without publishing ports 3306 or 9104 to the LAN.

### Version safety

The production policy is to track the latest supported MariaDB LTS series. The current target is `mariadb:12.3`. Patch/maintenance updates within the selected LTS should be applied promptly. Moving to a newer LTS is expected rather than ignored, but because MariaDB is stateful the migration must include a verified backup, compatibility/release-note review, validation, and a documented restore path. Rolling/non-LTS releases are not the production target merely because their version number is higher.


## MariaDB 11 to 12.3 LTS migration record

The production deployment successfully migrated the existing Uptime Kuma database from MariaDB 11 to MariaDB 12.3 LTS without losing application data, monitors, or notification configuration.

The validated migration pattern is:

1. Create a timestamped logical backup with `mariadb-dump --all-databases --single-transaction --routines --events --triggers` and retain it outside the database volume.
2. Pull the selected LTS image and recreate only `uptime-db`; do not use `docker compose down -v`.
3. Wait for the MariaDB container health check to report healthy.
4. Verify `SELECT VERSION();` reports the intended LTS version.
5. Run `mariadb-upgrade` and require a successful result (or confirmation that no further upgrade is required).
6. Verify the configured Uptime Kuma database still contains tables.
7. Verify Uptime Kuma is healthy and confirm existing monitors and notification configuration are present.
8. Verify the MariaDB Prometheus target is UP and `mysql_up` reports `1` after the exporter is deployed.
9. Retain the pre-upgrade backup until the upgraded service has been observed operating normally and the rollback window has passed.

An in-place downgrade is **not** the rollback strategy. Restore from the verified pre-upgrade backup into a compatible MariaDB instance if rollback is required.

### Prometheus configuration reload note

The Prometheus configuration file is bind-mounted read-only. After changing `prometheus/prometheus.yml`, verify the running container sees the expected configuration. If it does not, recreate Prometheus with `docker compose up -d --force-recreate prometheus` and re-check **Status > Targets**. This exact condition was encountered while enabling the MariaDB scrape job and was resolved by recreating Prometheus.
