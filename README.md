# Docker Monitoring Infrastructure

[![License](https://img.shields.io/github/license/drakeg/dock_monitoring)](https://github.com/drakeg/dock_monitoring/blob/main/LICENSE)


A Docker Compose infrastructure, monitoring, management, and ticketing stack for Linux Docker hosts.

The stack combines Traefik, Prometheus, Grafana, cAdvisor, Node Exporter, Uptime Kuma, MariaDB, Dockge, and a restricted Docker socket proxy. It is intended for LAN administration and monitoring without requiring the host to become the network's DNS or DHCP server.

## Services

| Service | Purpose | Default LAN access |
| --- | --- | --- |
| Traefik | Reverse proxy and Prometheus metrics | HTTP `:80`, HTTPS `:443` |
| Dockge | Docker Compose stack management | `:5001` |
| Uptime Kuma | Availability monitoring | `:3001` |
| Prometheus | Metrics collection and storage | `:9091` |
| Grafana | Dashboards and visualization | `:3002` |
| cAdvisor | Container resource metrics | Internal only |
| Node Exporter | Host metrics | Internal only |
| MariaDB | Uptime Kuma database | Internal only |
| Docker Socket Proxy | Restricted Docker API for Traefik | Internal only |
| Request Tracker 6 | Infrastructure ticketing and operational system of record | `:8088` |
| PostgreSQL | Request Tracker database | Internal only |

The exposed management ports bind to the Docker host. Restrict access to trusted LANs with the host firewall as appropriate.

## Repository layout

```text
.
├── compose.yml
├── .env.example
├── .gitignore
├── grafana/
│   └── provisioning/
│       └── datasources/
│           └── prometheus.yml
└── prometheus/
    └── prometheus.yml
```

Persistent application data is stored in named Docker volumes rather than this repository.

## Requirements

- Linux Docker host
- Docker Engine
- Docker Compose v2
- A Docker socket accessible to the user running the stack
- Ports selected in `.env` available on the host

This stack has been used with both rootful and rootless Docker. The Docker socket location differs between those configurations; see **Docker socket configuration** below.

## Installation

Clone the repository and enter it:

```bash
git clone https://github.com/drakeg/dock_monitoring.git
cd dock_monitoring
```

Create the local environment file:

```bash
cp .env.example .env
```

Edit `.env` and replace all placeholder passwords before starting the stack.

Validate and start:

```bash
docker compose config
docker compose up -d
```

Do not commit `.env`. It contains local configuration and secrets and is ignored by Git.

## Docker socket configuration

The current Compose file is configured for a conventional/rootful Docker socket:

```text
/var/run/docker.sock
```

This socket is mounted into:

- `docker-socket-proxy`, read-only, so Traefik can discover containers through a restricted API.
- `dockge`, read/write, because Dockge must manage Docker containers and Compose stacks.

To see the socket used by the active Docker context:

```bash
docker context inspect --format '{{.Endpoints.docker.Host}}'
```

A normal Docker installation commonly reports:

```text
unix:///var/run/docker.sock
```

A rootless Docker installation may instead report a path similar to:

```text
unix:///run/user/1000/docker.sock
```

Set `DOCKER_SOCKET_PATH` in the host-specific `.env` file to the socket reported by the active Docker context. The container-side path remains `/var/run/docker.sock`, so no Compose edits are required when moving the stack between rootful and rootless hosts.

For a conventional/rootful Ubuntu installation:

```dotenv
DOCKER_SOCKET_PATH=/var/run/docker.sock
```

For a rootless Fedora installation using UID 1000:

```dotenv
DOCKER_SOCKET_PATH=/run/user/1000/docker.sock
```

The default remains `/var/run/docker.sock` when `DOCKER_SOCKET_PATH` is omitted.

## Configuration

The committed `.env.example` contains the supported environment variables. Copy it to `.env` and make machine-specific changes there.

Important defaults:

| Variable | Default | Purpose |
| --- | --- | --- |
| `TZ` | `America/New_York` | Container timezone |
| `TRAEFIK_HTTP_PORT` | `80` | Traefik HTTP host port |
| `TRAEFIK_HTTPS_PORT` | `443` | Traefik HTTPS host port |
| `DOCKGE_PORT` | `5001` | Dockge host port |
| `UPTIME_KUMA_PORT` | `3001` | Uptime Kuma host port |
| `PROMETHEUS_RETENTION` | `30d` | Prometheus retention |
| `GRAFANA_PORT` | `3002` | Grafana host port |

The example `.home` hostnames used by Traefik do **not** automatically create DNS records. Direct `SERVER-IP:PORT` access works without changing LAN DNS or DHCP. If friendly names are desired, provide them through an existing DNS service or the client system's hosts file.

## Network design

The stack uses four Docker networks:

- **proxy** — Traefik and applications that can be routed through it.
- **monitoring** — Prometheus, Grafana, exporters, and monitoring services.
- **docker-api** — internal network between Traefik and the restricted Docker socket proxy.
- **uptime-db** — internal network between Uptime Kuma and MariaDB.

### Important rootless Docker note

Do **not** mark the `monitoring` network as `internal: true` when host-published monitoring ports are required on a rootless Docker installation.

During deployment, Docker correctly stored Prometheus' `9091:9090` port binding but did not actually publish it while Prometheus was attached only to an internal monitoring network. Removing `internal: true` from `monitoring` restored the host port.

The `docker-api` and `uptime-db` networks remain internal because neither needs host/LAN connectivity.

## Security model

The stack deliberately limits direct exposure:

- MariaDB is not published to the host.
- cAdvisor is not published to the host.
- Node Exporter is not published to the host.
- Docker Socket Proxy is not published to the host.
- Traefik receives restricted, read-only Docker API access through Docker Socket Proxy.
- Destructive Docker API methods are disabled in the socket proxy.
- Dockge has direct Docker socket access because container management requires it. Treat Dockge as a privileged administrative application and restrict it to trusted users/networks.
- Most containers use `no-new-privileges:true`.
- cAdvisor requires elevated host access to collect container metrics.

Do not expose the management interfaces directly to the public Internet without adding appropriate authentication, TLS, firewalling, and access controls.

## Prometheus

Prometheus listens on port `9090` inside its container and is published on host port `9091`.

The host port is intentionally different because port `9090` may already be occupied by another service on Fedora systems.

Configured scrape targets:

- Prometheus
- cAdvisor
- Node Exporter
- Traefik metrics

Prometheus data is retained for 30 days by default and stored in the `prometheus-data` named volume.

## Grafana

Grafana is published on port `3002` by default.

The Prometheus datasource is provisioned automatically from:

```text
grafana/provisioning/datasources/prometheus.yml
```

It connects over the Docker monitoring network using:

```text
http://prometheus:9090
```

The Grafana admin username/password environment variables initialize a new Grafana database. If the persistent Grafana volume already exists, changing `GRAFANA_ADMIN_PASSWORD` does not automatically change the existing admin password.

A useful starting host dashboard is **Node Exporter Full**, Grafana dashboard ID **1860**.

## Uptime Kuma and MariaDB

Uptime Kuma 2 uses the dedicated MariaDB service in this stack.

MariaDB:

- has no published host port;
- is reachable by Uptime Kuma on the private `uptime-db` network;
- stores its data in `uptime-db-data`;
- has an extended startup health-check period to accommodate first-time database initialization.

Uptime Kuma is published on port `3001` by default.

## Dockge

Dockge is published on port `5001` by default and manages Compose stacks under:

```text
/opt/docker
```

The host directory is mounted at the same absolute path inside the Dockge container. `PUID=1000` and `PGID=1000` are currently configured in `compose.yml`; adjust them if the Docker host's administrative user uses different IDs.

Because Dockge has direct Docker socket access, access to Dockge is effectively administrative access to the Docker host.

## Traefik

Traefik discovers containers through `docker-socket-proxy` rather than mounting the Docker socket directly.

The socket proxy permits the read operations required for discovery while disabling destructive methods and sensitive Docker API areas.

Traefik also exposes Prometheus-format metrics internally on port `8082`, which Prometheus scrapes as `traefik:8082`.

If host ports 80 or 443 are already in use, change `TRAEFIK_HTTP_PORT` and `TRAEFIK_HTTPS_PORT` in `.env`, for example to `8080` and `8443`.

## Common troubleshooting

### Traefik reports Docker provider 503 errors

If Traefik reports errors such as:

```text
503 Service Unavailable
No server is available to handle this request
```

and Docker Socket Proxy logs `503` responses for `/_ping` or `/version`, verify the host Docker socket path:

```bash
docker context inspect --format '{{.Endpoints.docker.Host}}'
```

The socket proxy can be reachable from Traefik while still being unable to reach the Docker daemon if the wrong host socket is mounted.

### Prometheus is running but host port is missing

Prometheus logs may show that it is healthy and listening on `0.0.0.0:9090` while `docker ps` only shows:

```text
9090/tcp
```

instead of a published `9091->9090` mapping.

First confirm the Compose configuration contains the binding. If Docker stores the binding but does not publish it on a rootless host, ensure the `monitoring` network is **not** configured as `internal: true`.

### Grafana password differs from .env

Grafana's admin environment variables initialize a new database. They do not overwrite credentials already stored in the persistent Grafana volume.

### MariaDB first startup

Initial MariaDB database creation can take longer than subsequent starts. The Compose health check allows a five-minute startup period. Do not delete the database volume merely because first initialization takes time unless logs show an actual unrecoverable database problem.

## Updating

Pull newer images and recreate the stack:

```bash
docker compose pull
docker compose up -d
```

Named volumes remain intact during normal container recreation.

Avoid `docker compose down -v` unless you intentionally want to delete persistent application data.

## Persistent volumes

The stack defines:

- `prometheus-data`
- `grafana-data`
- `uptime-kuma-data`
- `uptime-db-data`
- `dockge-data`

Back up these volumes according to the recovery requirements of the environment.

## Monitoring and dashboarding

The deployment details in this README are complemented by a dedicated operational guide covering Prometheus targets, Grafana dashboards, Uptime Kuma monitors, alerting, application onboarding, and the plan to move finalized dashboards/alerts into source control.

See [docs/MONITORING.md](docs/MONITORING.md).
- [Development plan](docs/DEVELOPMENT_PLAN.md) — roadmap, current priorities, and completion criteria.

## Planned monitoring configuration

The infrastructure is ready for application-level configuration. Planned next steps include:

1. Grafana host dashboards using Node Exporter.
2. Grafana container dashboards using cAdvisor.
3. Uptime Kuma monitors for infrastructure and application health endpoints.
4. Actionable alerts for service availability, disk capacity, memory pressure, and other operational conditions.
5. Consistent organization of Compose applications under `/opt/docker` for Dockge management.

## License

No license is currently specified by this repository.

## Alertmanager local configuration

Alertmanager intentionally keeps deployment-specific email addresses out of Git. Before the first `docker compose up -d` on a host, create the local configuration file:

```bash
cp alertmanager/alertmanager.yml.example alertmanager/alertmanager.yml
```

Then replace the non-secret email address/username placeholders in `alertmanager/alertmanager.yml` and set `ALERTMANAGER_SMTP_PASSWORD` in `.env`. Compose uses a bind mount with host-path creation disabled, so a missing config now fails clearly instead of Docker creating an `alertmanager.yml` directory.


### cAdvisor on rootless Docker

cAdvisor needs both the Docker daemon socket and Docker data root. The defaults target rootful Docker:

```dotenv
DOCKER_SOCKET_PATH=/var/run/docker.sock
DOCKER_DATA_ROOT=/var/lib/docker
```

For a rootless Docker installation, set both values to that user's Docker locations. For example, for UID/user `drakeg` on the Fedora development host:

```dotenv
DOCKER_SOCKET_PATH=/run/user/1000/docker.sock
DOCKER_DATA_ROOT=/home/drakeg/.local/share/docker
```

After changing either value, recreate cAdvisor so the bind mounts are updated:

```bash
docker compose up -d --force-recreate cadvisor prometheus
```

Verify the Prometheus cAdvisor target is UP and that cAdvisor exports `container_*` metrics before troubleshooting Grafana dashboard queries.


### Container metrics backend

Prometheus uses `docker-exporter` for per-container CPU, memory, network, block-I/O, state, health, and lifecycle metrics. It reads Docker's stats API through the existing read-only Docker socket and exposes cAdvisor-compatible metric names, allowing the existing container Grafana dashboard to remain useful without requiring cAdvisor's privileged host inspection.

cAdvisor remains in the stack for compatibility/testing on hosts where its broader host/cgroup inspection is useful, but Prometheus no longer depends on it for the standard container dashboard.

For rootless Docker, set `DOCKER_SOCKET_PATH` to the rootless daemon socket and `DOCKER_SOCKET_GID` to the numeric group visible on that mounted socket. On the current Fedora development host the observed socket group is `971`:

```dotenv
DOCKER_SOCKET_PATH=/run/user/1000/docker.sock
DOCKER_DATA_ROOT=/home/drakeg/.local/share/docker
DOCKER_SOCKET_GID=971
```

After changing these values, recreate the exporter and Prometheus:

```bash
docker compose up -d --force-recreate docker-exporter prometheus
```

Verify `docker-exporter:9713` is UP in Prometheus and query `container_cpu_usage_seconds_total` before troubleshooting Grafana.


## Request Tracker 6

Request Tracker (RT) provides the ticketing/system-of-record layer for infrastructure operations. The stack pins RT to 6.0.3 and keeps its PostgreSQL database on the private `rt-db` network.

RT is exposed through the `rt-web` Caddy gateway rather than publishing the RT FastCGI service directly. The default LAN endpoint is:

```text
http://SERVER-IP:8088
```

Change `RT_PORT` in `.env` if needed. Traefik can also route the configured `RT_HOSTNAME` (default `rt.home`) when local DNS/hosts resolution is available.

### First-time RT initialization

Set `RT_DB_PASSWORD` and the other optional RT values in `.env`, then run:

```bash
bash scripts/init-rt.sh
```

The helper starts PostgreSQL, waits for database readiness, runs RT's database initialization against the already-created database, and starts RT plus its web gateway.

RT database initialization is a first-install operation. Do not rerun initialization against an existing populated RT database. Future RT version changes must use RT's documented database upgrade procedure and a verified backup.

The regular web gateway explicitly blocks `/REST/1.0/NoAuth/mail-gateway`. Inbound email will be implemented separately so an unauthenticated mail-ingress endpoint is not accidentally exposed on the normal LAN/web listener.

### RT persistence

The RT foundation adds these named volumes:

- `rt-db-data` — PostgreSQL database state.
- `rt-data` — RT variable/application state under `/opt/rt/var`.
- `rt-caddy-data` and `rt-caddy-config` — Caddy runtime state.

Do not use `docker compose down -v` on a populated RT deployment. Backup/restore automation for RT is tracked as part of the ticketing roadmap.

### Planned RT integration

The next ticketing increments will add:

- Prometheus/Uptime Kuma health monitoring for RT.
- A dedicated Alertmanager-to-RT bridge with alert deduplication and recovery handling.
- Backup/restore automation for PostgreSQL and RT state.
- RT AI extension evaluation/configuration without requiring an AI provider for base operation.
- RT MCP/REST integration for operational agents.

### RT canonical URL

Set `RT_WEB_URL` in `.env` to the **exact** browser URL, including scheme, host and port (for example `http://192.168.1.10:8088/`). This prevents RT inline-edit and other domain-sensitive features from failing with a `localhost` warning. After changing it, run `docker compose up -d --force-recreate rt`. When accessing RT through Traefik instead, use the actual routed URL (including HTTPS if enabled).

## Jenkins CI controller (optional)

Jenkins is an opt-in service, so existing deployments do not start it automatically. Set `JENKINS_PORT` (default `8089`) and optionally `JENKINS_HOSTNAME` in `.env`, then run:

```bash
docker compose --profile jenkins up -d jenkins
docker compose --profile jenkins exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open `http://SERVER-IP:8089/` and complete the Jenkins setup wizard. Configure the Jenkins URL to the same browser address under **Manage Jenkins → System**. Persistent controller state is in `jenkins-data`; back it up before upgrades. The controller does **not** mount the host Docker socket or run privileged; use a separate, least-privilege build agent for container builds. For GitHub integration, install/configure the GitHub Branch Source plugin and use multibranch pipelines with repository Jenkinsfiles. Webhook delivery requires a reachable HTTPS endpoint and an authenticated integration; direct LAN-only Jenkins cannot receive GitHub.com webhooks without a secure relay or VPN. Prefer HTTPS before entering credentials over a shared network.

## Repeatable local development setup

For disposable, trusted **local testing only**, copy the documented defaults from `.env.example` and run:

```bash
bash scripts/dev-up.sh
```

The helper creates `.env` if absent, discovers the Docker socket group, starts databases, initializes an empty RT schema, and configures the MariaDB metrics exporter account. It does not delete volumes. Existing populated RT databases with mismatched credentials stop with an error instead of being reset. The placeholder passwords in `.env.example` are development-only: replace them before any shared or production deployment. The script requires Bash, Docker Compose, and GNU `sed`/`stat` (Linux). Jenkins remains opt-in.
