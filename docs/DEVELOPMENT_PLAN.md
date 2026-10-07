# Development Plan

This document is the development roadmap for the Docker monitoring infrastructure. It complements the deployment instructions in the README and the operational monitoring guide in `docs/MONITORING.md`.

The stack should remain host-OS agnostic wherever Docker provides the abstraction. Host-specific instructions belong only where the host materially changes Docker installation, permissions, networking, storage, security, or troubleshooting.

## Goals

- Provide reliable monitoring and management for Docker hosts and application stacks.
- Keep configuration reproducible in source control.
- Keep databases, exporters, and Docker API access off the LAN unless exposure is required.
- Prefer Docker DNS and private networks for service-to-service communication.
- Provide actionable, low-noise notifications.
- Make ports, hostnames, credentials, and deployment-specific values configurable without editing Compose.
- Keep production dependencies on the latest appropriate supported LTS where the upstream project offers an LTS channel, while performing stateful LTS migrations deliberately and safely.
- Document every required dashboard, exporter, monitor, alert, and operational dependency.

## Phase 1 — Infrastructure foundation

Status: **Completed**

- Docker Compose infrastructure stack.
- Traefik reverse proxy.
- Restricted Docker Socket Proxy.
- Dockge.
- Uptime Kuma with dedicated MariaDB.
- Prometheus.
- Grafana.
- Node Exporter.
- cAdvisor.
- Persistent volumes.
- Private Docker networks.
- Environment-based configuration.
- Direct LAN access where deliberately enabled.
- Core deployment/security/troubleshooting documentation.

## Phase 2 — Baseline observability

Status: **Completed**

- Prometheus scraping Prometheus, Node Exporter, cAdvisor, and Traefik.
- Grafana Prometheus datasource.
- Node Exporter Full dashboard, ID 1860.
- cAdvisor exporter - Docker containers Overview dashboard, ID 21743.
- Uptime Kuma email/SMTP notification through the Mad Mallards IONOS-hosted mail service.
- Verified Kuma monitors for Prometheus, Grafana, Dockge, and Traefik.
- Standard availability-monitor retry/heartbeat policy.
- Docker-DNS monitoring convention.

## Phase 3 — Database observability and alerting

Status: **Completed**

### MariaDB metrics

- [x] Add Prometheus `mysqld_exporter`.
- [x] Keep exporter access private; do not publish MariaDB or exporter ports to the LAN.
- [x] Use a dedicated least-privilege database monitoring account.
- [x] Add the exporter as a Prometheus scrape target and verify it UP.
- [x] Select and validate the **mysql overview** Grafana dashboard, ID **14969**, against the deployed exporter.
- [x] Add the exact dashboard name/ID, datasource, prerequisites, and verification criteria to the dashboard checklist.

### Metrics-based alerts

A source-controlled baseline rule set covers the core conditions below. Alertmanager notification delivery has been deployed and verified end-to-end with controlled FIRING and RESOLVED email tests. Continue tuning thresholds only from observed production behavior.

Define and validate actionable alerts for:

- Host filesystem capacity.
- Sustained memory pressure.
- Sustained CPU/load.
- Prometheus scrape target failures.
- Important container disappearance/unavailability where metrics can reliably identify it.
- MariaDB/exporter availability.
- Database connection/resource conditions that are genuinely actionable.

- [x] Source-controlled Prometheus baseline alert rules.
- [x] Internal Alertmanager integration.
- [x] SMTP notification delivery without committed credentials.
- [x] Controlled FIRING notification test.
- [x] Controlled RESOLVED notification test.
- [x] Temporary notification-test rule removed after validation.

Tune thresholds from observed normal behavior. Avoid alerting on harmless transient events already handled by Kuma retries.

## Phase 4 — Stateful-service upgrade safety

Status: **Current**

- [x] Migrate the production Uptime Kuma database from MariaDB 11 to MariaDB 12.3 LTS with a verified pre-upgrade backup and post-upgrade validation.
- Track the latest supported MariaDB LTS series; the current target is MariaDB 12.3 LTS.
- Apply patch/maintenance releases within the selected LTS promptly.
- Surface new LTS releases for planned migration rather than ignoring them.
- Do not move production to rolling/non-LTS releases solely because their version number is newer.
- Configure dependency automation so stateful major/LTS upgrades require deliberate review rather than unattended deployment.
- Document backup, clean shutdown, upgrade, validation, `mariadb-upgrade`, and restore/rollback procedures.
- Treat the pre-upgrade backup as the rollback path rather than assuming an in-place major-version downgrade is safe.
- Review other stateful services for the same latest-supported-LTS policy where their upstream projects provide LTS channels.

## Phase 5 — Infrastructure ticketing

Status: **Current**

- [x] Select Request Tracker 6 as the infrastructure ticketing/system-of-record platform.
- [x] Add an RT 6.0.3 containerized foundation with a dedicated private PostgreSQL database.
- [x] Make RT port, hostname, identity, and database credentials environment-configurable.
- [x] Block the unauthenticated RT mail-gateway endpoint from the normal web listener.
- [ ] Validate first-time RT initialization on rootful Ubuntu and rootless Fedora.
- [ ] Add Prometheus/Uptime Kuma health monitoring for RT.
- [ ] Add RT database and application-state backup/restore automation and a restore drill.
- [ ] Add a dedicated Alertmanager-to-RT integration service.
- [ ] Deduplicate repeated firing alerts into one ticket and update/resolve tickets on recovery.
- [ ] Map alert severity and useful labels into RT ticket metadata.
- [ ] Evaluate and configure RT AI capabilities without making an external AI provider mandatory.
- [ ] Add RT MCP/REST access for authorized operational agents.

## Phase 6 — Application onboarding

Status: **Planned**

For every application stack deployed to the host:

1. Identify a real HTTP health endpoint where available.
2. Add a Uptime Kuma monitor.
3. Prefer application-level HTTP health checks over simple TCP checks.
4. Use Docker DNS for internal checks when Kuma shares the application's network.
5. Add an external/path-level check when user-facing reachability matters.
6. Add Prometheus scraping when the application exposes useful metrics.
7. Add and validate Grafana dashboards only when they provide operational value.
8. Define application-specific alerts.
9. Document the monitoring contract in the application's own repository.

## Phase 7 — External monitoring

Status: **Planned**

- Add monitoring independent of this Docker host.
- Verify Uptime Kuma or another externally reachable endpoint.
- Ensure a host/network/power failure can generate a notification even when the local Kuma instance is unavailable.
- Add public/external route checks only where services are intentionally externally reachable.

## Phase 8 — Configuration as code

Status: **Planned**

- Provision finalized Grafana dashboards from the repository.
- Store dashboard JSON after customization/stabilization.
- Store Prometheus alert rules in source control.
- Evaluate reproducible Uptime Kuma monitor configuration/backup approaches.
- Never commit notification credentials, database passwords, API tokens, or other secrets.
- [x] Add validation/tests for Compose, Prometheus rules/configuration, and Alertmanager configuration in CI.

## Phase 9 — Operations and hardening

Status: **Ongoing**

- Review container image updates and security fixes.
- Apply stateless stable/security upgrades promptly when compatible.
- Prefer the latest supported LTS for production software when upstream provides an LTS channel.
- Require migration review for major/LTS stateful upgrades, but do not use migration risk as a reason to remain indefinitely on an older supported line.
- Review network exposure and published ports.
- Review Docker Socket Proxy permissions.
- [x] Add documented backup/restore procedures and a reproducible backup script for MariaDB and stateful monitoring volumes.
- [x] Execute and validate the first production backup: MariaDB logical dump, all configured volume archives, archive integrity checks, and automatic service restart completed successfully on 2026-10-04.
- [x] Add an isolated, non-production MariaDB restore drill that verifies the expected Uptime Kuma database and tables without touching live state.
- Execute the restore drill successfully before considering MariaDB disaster recovery validated.
- Keep documentation synchronized with verified production behavior.
- Remove obsolete workarounds after they are no longer needed.
- Continue reducing manual configuration where doing so does not expose secrets or create unsafe automation.

## Definition of done for monitoring additions

A monitoring feature is complete when:

- configuration is reproducible;
- secrets are excluded from source control;
- the target is verified working;
- the relevant dashboard/monitor/alert is tested;
- documentation includes exact setup and verification instructions;
- failure behavior is understood;
- notification behavior is tested where applicable; and
- unnecessary network exposure has not been introduced.

## Roadmap maintenance

Update this document as work moves between **Planned**, **Current**, and **Completed**. Detailed operational instructions belong in `docs/MONITORING.md`; this document should remain the concise project-level roadmap and record of development priorities.
