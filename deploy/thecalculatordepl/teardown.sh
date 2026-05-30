#!/usr/bin/env bash
# teardown.sh – Removes the uha-cluster k3d cluster and associated secrets
set -euo pipefail

CLUSTER_NAME="uha-cluster"

echo "▶ Deleting k3d cluster '${CLUSTER_NAME}'…"
if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  k3d cluster delete "${CLUSTER_NAME}"
  echo "  ✓ Cluster deleted"
else
  echo "  – Cluster not found, skipping"
fi

echo ""
echo "✓ Teardown complete."
