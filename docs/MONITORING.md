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

Prometheus is available on the LAN at `http://SERVER-IP:9091`. The **Status > Targets** page should show configured targets as healthy before Grafana dashboards are expected to work correctly. The default scrape and evaluation interval is 15 seconds.

## 2. Grafana datasource

Grafana's Prometheus datasource is provisioned automatically by `grafana/provisioning/datasources/prometheus.yml` and uses:

```text
http://prometheus:9090
```

Grafana is available on the LAN at `http://SERVER-IP:3002`. Because Grafana and Prometheus communicate over the Docker network, Grafana should use `prometheus:9090`, not the host's published `9091` port.

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
- Prometheus configured for Prometheus, cAdvisor, Node Exporter, and Traefik.
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
- Rootless Docker published-port issue documented; `monitoring` remains non-internal.

### In progress

- Configure Uptime Kuma monitors and initial Email (SMTP) notification.

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
