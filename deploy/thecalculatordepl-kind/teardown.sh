#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-uha-cluster}"

if ! command -v kind >/dev/null 2>&1; then
  echo "kind is required to delete the cluster" >&2
  exit 1
fi

echo "▶ Deleting kind cluster '${CLUSTER_NAME}'..."
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "  ✓ Cluster deleted"
else
  echo "  – Cluster not found, skipping"
fi

echo ""
echo "✓ Teardown complete."
