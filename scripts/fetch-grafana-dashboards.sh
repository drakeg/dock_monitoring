#!/bin/sh
set -eu

DEST="${1:-/dashboards}"
mkdir -p "$DEST"

fetch_dashboard() {
  id="$1"
  revision="$2"
  filename="$3"

  url="https://grafana.com/api/dashboards/${id}/revisions/${revision}/download"
  tmp="$DEST/.${filename}.tmp"

  echo "Fetching Grafana dashboard ${id} revision ${revision}..."
  wget -qO "$tmp" "$url"

  # Grafana.com import templates use datasource input variables. File
  # provisioning does not prompt for inputs, so bind both common Prometheus
  # placeholders to the stable provisioned datasource UID.
  sed \
    -e 's/${DS_PROMETHEUS}/prometheus/g' \
    -e 's/${ds_prometheus}/prometheus/g' \
    "$tmp" > "$DEST/$filename"
  rm -f "$tmp"

  test -s "$DEST/$filename"
}

# Revisions are deliberately pinned. Update only after validating a newer
# revision against this stack.
fetch_dashboard 1860 45 node-exporter-full.json
fetch_dashboard 21743 3 cadvisor-docker-overview.json
fetch_dashboard 14969 1 mysql-overview.json

echo "Grafana dashboard bootstrap complete."
