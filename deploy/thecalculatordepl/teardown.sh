#!/usr/bin/env bash
# teardown.sh – Removes the local k3d or kind cluster
set -euo pipefail

CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-k3d}"
CLUSTER_NAME="${CLUSTER_NAME:-uha-cluster}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "${CLUSTER_PROVIDER}" == "kind" ]]; then
  export CLUSTER_NAME
  exec bash "${REPO_ROOT}/deploy/thecalculatordepl-kind/teardown.sh"
fi

if [[ "${CLUSTER_PROVIDER}" != "k3d" ]]; then
  echo "  ✗ Unsupported CLUSTER_PROVIDER: ${CLUSTER_PROVIDER}" >&2
  echo "    Supported values: k3d, kind" >&2
  exit 1
fi

echo "▶ Deleting k3d cluster '${CLUSTER_NAME}'…"
if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  k3d cluster delete "${CLUSTER_NAME}"
  echo "  ✓ Cluster deleted"
else
  echo "  – Cluster not found, skipping"
fi

echo ""
echo "✓ Teardown complete."
