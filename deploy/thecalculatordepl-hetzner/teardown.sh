#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-hcloud}"
HCLOUD_NETWORK_NAME="${HCLOUD_NETWORK_NAME:-${CLUSTER_NAME}-net}"
HCLOUD_FIREWALL_NAME="${HCLOUD_FIREWALL_NAME:-${CLUSTER_NAME}-fw}"
WORKER_COUNT="${WORKER_COUNT:-2}"

if ! command -v hcloud >/dev/null 2>&1; then
  echo "hcloud is required to delete the Hetzner resources" >&2
  exit 1
fi

echo "▶ Deleting Hetzner servers for '${CLUSTER_NAME}'..."
for name in "${CLUSTER_NAME}-server-1" $(seq 1 "${WORKER_COUNT}" | sed "s|^|${CLUSTER_NAME}-agent-|"); do
  if hcloud server describe "${name}" >/dev/null 2>&1; then
    hcloud server delete "${name}" >/dev/null
    echo "  ✓ Deleted ${name}"
  else
    echo "  – ${name} not found, skipping"
  fi
done

echo "▶ Deleting Hetzner firewall '${HCLOUD_FIREWALL_NAME}'..."
if hcloud firewall describe "${HCLOUD_FIREWALL_NAME}" >/dev/null 2>&1; then
  hcloud firewall delete "${HCLOUD_FIREWALL_NAME}" >/dev/null
  echo "  ✓ Firewall deleted"
else
  echo "  – Firewall not found, skipping"
fi

echo "▶ Deleting Hetzner network '${HCLOUD_NETWORK_NAME}'..."
if hcloud network describe "${HCLOUD_NETWORK_NAME}" >/dev/null 2>&1; then
  hcloud network delete "${HCLOUD_NETWORK_NAME}" >/dev/null
  echo "  ✓ Network deleted"
else
  echo "  – Network not found, skipping"
fi
