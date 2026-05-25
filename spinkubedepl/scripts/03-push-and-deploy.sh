#!/usr/bin/env bash
# Build the Spin app, push it to ttl.sh, and deploy to the k3d cluster.
#
# Usage (from repo root or spinkubedepl/):
#   ./spinkubedepl/scripts/03-push-and-deploy.sh
#
# Environment variables:
#   TTL          — image TTL, default "24h" (max). Use "1h", "6h", etc.
#   SPIN_APP_DIR — path to thecalculaterspin directory, default auto-detected
set -euo pipefail

TTL="${TTL:-24h}"

# Resolve repo root and spin app directory regardless of where the script is invoked from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPIN_APP_DIR="${SPIN_APP_DIR:-${REPO_ROOT}/thecalculaterspin}"
MANIFEST="${SCRIPT_DIR}/../manifests/spinapp.yaml"

if [[ ! -f "${SPIN_APP_DIR}/spin.toml" ]]; then
  echo "ERROR: spin.toml not found in ${SPIN_APP_DIR}" >&2
  exit 1
fi

# Generate a short unique suffix so each push gets a fresh image reference
SUFFIX="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | cut -c1-8 || od -An -tx1 /dev/urandom | tr -d ' \n' | head -c8)"
IMAGE="ttl.sh/thecalculaterspin-${SUFFIX}:${TTL}"

echo "==> Building thecalculaterspin..."
(cd "${SPIN_APP_DIR}" && spin build)

echo "==> Pushing OCI artifact to ttl.sh..."
echo "    Image: ${IMAGE}"
(cd "${SPIN_APP_DIR}" && spin registry push "${IMAGE}")

echo "==> Patching manifests/spinapp.yaml with image reference..."
# Write a temporary spinapp manifest with the real image substituted
TMP_MANIFEST="$(mktemp)"
sed "s|IMAGE_PLACEHOLDER|${IMAGE}|g" "${MANIFEST}" > "${TMP_MANIFEST}"

echo "==> Applying SpinAppExecutor..."
kubectl apply -f "${SCRIPT_DIR}/../manifests/executor.yaml"

echo "==> Deploying SpinApp..."
kubectl apply -f "${TMP_MANIFEST}"
rm -f "${TMP_MANIFEST}"

echo ""
echo "==> Deployed! Waiting for pod to become ready..."
kubectl wait spinapp/thecalculaterspin --for=condition=Ready --timeout=120s 2>/dev/null || \
  kubectl rollout status deployment/thecalculaterspin --timeout=120s 2>/dev/null || \
  echo "  (Could not wait — check 'kubectl get spinapp,pod' manually)"

echo ""
echo "==> To access the app, run:"
echo "    kubectl port-forward svc/thecalculaterspin 8080:80"
echo ""
echo "    Then in another terminal:"
echo "    curl 'http://localhost:8080/?expr=add(2,3)'"
echo "    curl 'http://localhost:8080/?expr=sin(30)'"
echo "    curl 'http://localhost:8080/?expr=multiply(6,7)'"
echo ""
echo "    Image will expire in ${TTL} on ttl.sh. Re-run this script to redeploy."
