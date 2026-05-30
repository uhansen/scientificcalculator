#!/usr/bin/env bash
# deploy.sh – Deploys thecalculatorspin on SpinKube / k3d with KEDA HTTP scale-to-zero
# Run from any directory; the script locates the repo root automatically.
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CLUSTER_NAME="uha-cluster"
GHCR_USER="uhansen"
IMAGE="ghcr.io/${GHCR_USER}/thecalculatorspin:latest"

CERT_MANAGER_VERSION="v1.16.3"
SPIN_OPERATOR_VERSION="v0.6.1"
KEDA_VERSION="2.19.0"
KEDA_HTTP_ADDON_VERSION="0.14.0"
SCALEDOWN_PERIOD=60   # seconds idle before scaling down (min=1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SPIN_APP_DIR="${REPO_ROOT}/thecalculatorspin"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { echo ""; echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
wait_rollout() {
  local ns="${1}" res="${2}"
  kubectl rollout status "${res}" -n "${ns}" --timeout=180s
}

# ---------------------------------------------------------------------------
# Step 1 – Authenticate to ghcr.io, push WASM image, create imagePullSecret
# ---------------------------------------------------------------------------
info "Step 1: Pushing WASM image to ghcr.io (${IMAGE})"

# Use GITHUB_TOKEN env var if set, otherwise fall back to gh CLI token.
# The token must have the 'write:packages' scope.
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  if ! gh auth status --hostname github.com &>/dev/null; then
    echo "  ✗ Not logged in to GitHub. Run: gh auth login"
    exit 1
  fi
  GITHUB_TOKEN="$(gh auth token)"
fi

echo "${GITHUB_TOKEN}" | spin registry login \
  --username "${GHCR_USER}" \
  --password-stdin \
  ghcr.io

(
  cd "${SPIN_APP_DIR}"
  spin registry push "${IMAGE}"
)
ok "Image pushed: ${IMAGE}"

# Create (or refresh) imagePullSecret so k3d nodes can pull from ghcr.io.
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GITHUB_TOKEN}" \
  --namespace=default \
  --dry-run=client -o yaml | kubectl apply -f -
ok "imagePullSecret ghcr-pull-secret created/updated"

# ---------------------------------------------------------------------------
# Step 2 – k3d cluster (shim v0.24.0 pre-installed in the node image)
# ---------------------------------------------------------------------------
info "Step 2: k3d cluster (image: spinframework/containerd-shim-spin/k3d:v0.24.0)"
if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  ok "Cluster ${CLUSTER_NAME} already exists"
else
  k3d cluster create --config "${SCRIPT_DIR}/k3d-config.yaml"
  ok "Cluster ${CLUSTER_NAME} created"
fi
kubectl cluster-info --context "k3d-${CLUSTER_NAME}" > /dev/null

# ---------------------------------------------------------------------------
# Step 3 – cert-manager
# ---------------------------------------------------------------------------
info "Step 3: cert-manager ${CERT_MANAGER_VERSION}"
if kubectl get namespace cert-manager &>/dev/null; then
  ok "cert-manager namespace already present"
else
  kubectl apply -f \
    "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
fi
wait_rollout cert-manager deployment/cert-manager
wait_rollout cert-manager deployment/cert-manager-webhook
wait_rollout cert-manager deployment/cert-manager-cainjector
ok "cert-manager ready"

# ---------------------------------------------------------------------------
# Step 4 – spin-operator CRDs
# ---------------------------------------------------------------------------
info "Step 4: spin-operator CRDs"
kubectl apply -f \
  "https://github.com/spinframework/spin-operator/releases/download/${SPIN_OPERATOR_VERSION}/spin-operator.crds.yaml"
ok "CRDs applied"

# ---------------------------------------------------------------------------
# Step 5 – spin-operator Helm chart
# ---------------------------------------------------------------------------
info "Step 5: spin-operator ${SPIN_OPERATOR_VERSION}"
helm upgrade --install spin-operator \
  --namespace spin-operator \
  --create-namespace \
  --version "${SPIN_OPERATOR_VERSION#v}" \
  oci://ghcr.io/spinframework/charts/spin-operator \
  --wait
ok "spin-operator ready"

# ---------------------------------------------------------------------------
# Step 6 – RuntimeClass and ShimExecutor
# ---------------------------------------------------------------------------
info "Step 6: RuntimeClass + ShimExecutor"
kubectl apply -f \
  "https://github.com/spinframework/spin-operator/releases/download/${SPIN_OPERATOR_VERSION}/spin-operator.runtime-class.yaml"
kubectl apply -f \
  "https://github.com/spinframework/spin-operator/releases/download/${SPIN_OPERATOR_VERSION}/spin-operator.shim-executor.yaml"
ok "RuntimeClass and ShimExecutor applied"

# ---------------------------------------------------------------------------
# Step 7 – KEDA
# ---------------------------------------------------------------------------
info "Step 7: KEDA ${KEDA_VERSION}"
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo update kedacore
helm upgrade --install keda \
  --namespace keda \
  --create-namespace \
  kedacore/keda \
  --version "${KEDA_VERSION}" \
  --wait
ok "KEDA ready"

# ---------------------------------------------------------------------------
# Step 8 – KEDA HTTP Add-on (enables HTTPScaledObject / scale-to-zero)
# ---------------------------------------------------------------------------
info "Step 8: KEDA HTTP Add-on ${KEDA_HTTP_ADDON_VERSION}"
helm upgrade --install keda-add-ons-http \
  --namespace keda \
  kedacore/keda-add-ons-http \
  --version "${KEDA_HTTP_ADDON_VERSION}" \
  --wait
ok "KEDA HTTP Add-on ready"

# ---------------------------------------------------------------------------
# Step 9 – Deploy SpinApp + proxy Service + Ingress
# ---------------------------------------------------------------------------
info "Step 9: Deploying SpinApp + proxy Service + Ingress"
kubectl apply -f "${SCRIPT_DIR}/spinapp.yaml"
wait_rollout default deployment/thecalculatorspin
ok "SpinApp running"

# ---------------------------------------------------------------------------
# Step 10 – HTTPScaledObject (scale-to-zero after ${SCALEDOWN_PERIOD}s idle)
# ---------------------------------------------------------------------------
info "Step 10: Applying HTTPScaledObject (min=0, max=5, scaledownPeriod=${SCALEDOWN_PERIOD}s)"
kubectl apply -f "${SCRIPT_DIR}/httpscaledobject.yaml"
ok "HTTPScaledObject applied – scale-to-zero is active"

# ---------------------------------------------------------------------------
# Done – verify
# ---------------------------------------------------------------------------
info "Verification"
echo "  Waiting for interceptor to stabilise…"
sleep 5
RESULT=$(curl -sf "http://localhost:3000/?calculate=add(2,3)" || echo "")
if [ "${RESULT}" = "5" ]; then
  ok "HTTP API responds correctly: add(2,3) = ${RESULT}"
else
  echo "  ⚠ Response: '${RESULT}' (expected '5'). Try manually:"
  echo "    curl 'http://localhost:3000/?calculate=add(2,3)'"
fi

echo ""
echo "═════════════════════════════════════════════════════════════"
echo " thecalculatorspin is running on SpinKube + KEDA HTTP!"
echo " curl \"http://localhost:3000/?calculate=add(2,3)\""
echo " Scale-down: idle for ${SCALEDOWN_PERIOD}s → 1 replica (min)"
echo " kubectl get httpscaledobject thecalculatorspin"
echo "═════════════════════════════════════════════════════════════"
