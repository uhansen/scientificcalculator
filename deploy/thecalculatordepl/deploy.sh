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

CERT_MANAGER_VERSION="v1.21.1"
RUNTIME_CLASS_MANAGER_VERSION="0.2.0"
SPIN_SHIM_VERSION="v0.25.1"
SPIN_OPERATOR_VERSION="v0.6.1"
KEDA_VERSION="2.20.2"
KEDA_HTTP_ADDON_VERSION="0.15.0"
SCALEDOWN_PERIOD=60   # seconds idle before scaling down (min=1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPIN_APP_DIR="${REPO_ROOT}/applications/thecalculatorspin"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { echo ""; echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
wait_rollout() {
  local ns="${1}" res="${2}"
  kubectl rollout status "${res}" -n "${ns}" --timeout=180s
}

wait_for_shim() {
  local name="${1}" attempts="${2:-60}" i ready total
  for ((i = 1; i <= attempts; i++)); do
    ready="$(kubectl get shim "${name}" -o jsonpath='{.status.nodesReady}' 2>/dev/null || echo 0)"
    total="$(kubectl get shim "${name}" -o jsonpath='{.status.nodes}' 2>/dev/null || echo 0)"
    if [[ -n "${ready}" && -n "${total}" && "${ready}" != "0" && "${ready}" == "${total}" ]]; then
      ok "Shim ${name} ready on ${ready}/${total} nodes"
      return 0
    fi
    sleep 5
  done
  echo "  ✗ Shim ${name} did not become ready on all labeled nodes"
  kubectl get shim "${name}" -o wide || true
  return 1
}

# ---------------------------------------------------------------------------
# Step 1 – Authenticate to ghcr.io, push WASM image, create imagePullSecret
# ---------------------------------------------------------------------------
info "Step 1: Pushing WASM image to ghcr.io (${IMAGE})"

# Prefer an explicit package-write token if one is available.
# Accepted env vars: GHCR_TOKEN, CR_PAT, or GITHUB_TOKEN.
# Otherwise fall back to the GitHub CLI token.
# The token must have the 'write:packages' scope.
REGISTRY_TOKEN="${GHCR_TOKEN:-${CR_PAT:-${GITHUB_TOKEN:-}}}"
if [[ -z "${REGISTRY_TOKEN}" ]]; then
  if ! gh auth status --hostname github.com &>/dev/null; then
    echo "  ✗ Not logged in to GitHub. Run: gh auth login"
    exit 1
  fi
  REGISTRY_TOKEN="$(gh auth token)"
fi

echo "${REGISTRY_TOKEN}" | spin registry login \
  --username "${GHCR_USER}" \
  --password-stdin \
  ghcr.io

(
  cd "${SPIN_APP_DIR}"
  spin registry push "${IMAGE}"
)
ok "Image pushed: ${IMAGE}"

# Create (or refresh) imagePullSecret so k3d nodes can pull from ghcr.io.
if [[ -f "${HOME}/.docker/config.json" ]]; then
  kubectl create secret generic ghcr-pull-secret     --from-file=.dockerconfigjson="${HOME}/.docker/config.json"     --type=kubernetes.io/dockerconfigjson     --namespace=default     --dry-run=client -o yaml | kubectl apply -f -
else
  kubectl create secret docker-registry ghcr-pull-secret     --docker-server=ghcr.io     --docker-username="${GHCR_USER}"     --docker-password="${REGISTRY_TOKEN}"     --namespace=default     --dry-run=client -o yaml | kubectl apply -f -
fi
ok "imagePullSecret ghcr-pull-secret created/updated"

# ---------------------------------------------------------------------------
# Step 2 – k3d cluster
# ---------------------------------------------------------------------------
info "Step 2: k3d cluster"
if k3d cluster list 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
  ok "Cluster ${CLUSTER_NAME} already exists"
else
  k3d cluster create --config "${SCRIPT_DIR}/k3d-config.yaml"
  ok "Cluster ${CLUSTER_NAME} created"
fi
kubectl cluster-info --context "k3d-${CLUSTER_NAME}" > /dev/null

# ---------------------------------------------------------------------------
# Step 3 – Traefik ExternalName support
# ---------------------------------------------------------------------------
info "Step 3: Traefik ExternalName support"
kubectl apply -f "${SCRIPT_DIR}/traefik-helmchartconfig.yaml"
wait_rollout kube-system deployment/traefik
ok "Traefik updated"

# ---------------------------------------------------------------------------
# Step 4 – cert-manager
# ---------------------------------------------------------------------------
info "Step 4: cert-manager ${CERT_MANAGER_VERSION}"
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
# Step 5 – runtime-class-manager + Spin shim install
# ---------------------------------------------------------------------------
info "Step 5: runtime-class-manager ${RUNTIME_CLASS_MANAGER_VERSION} + shim ${SPIN_SHIM_VERSION}"
helm upgrade --install runtime-class-manager \
  --namespace runtime-class-manager \
  --create-namespace \
  --version "${RUNTIME_CLASS_MANAGER_VERSION}" \
  oci://ghcr.io/spinframework/charts/runtime-class-manager \
  --wait
kubectl apply -f \
  "https://github.com/spinframework/containerd-shim-spin/releases/download/${SPIN_SHIM_VERSION}/runtime-class-manager-shim-v1alpha1-${SPIN_SHIM_VERSION}.yaml"
kubectl label node --all spin=true --overwrite
wait_for_shim spin-v2
kubectl get runtimeclass wasmtime-spin-v2 > /dev/null
ok "runtime-class-manager installed and runtime class created"

# ---------------------------------------------------------------------------
# Step 6 – spin-operator CRDs
# ---------------------------------------------------------------------------
info "Step 6: spin-operator CRDs"
kubectl apply -f \
  "https://github.com/spinframework/spin-operator/releases/download/${SPIN_OPERATOR_VERSION}/spin-operator.crds.yaml"
ok "CRDs applied"

# ---------------------------------------------------------------------------
# Step 7 – spin-operator Helm chart
# ---------------------------------------------------------------------------
info "Step 7: spin-operator ${SPIN_OPERATOR_VERSION}"
helm upgrade --install spin-operator \
  --namespace spin-operator \
  --create-namespace \
  --version "${SPIN_OPERATOR_VERSION#v}" \
  oci://ghcr.io/spinframework/charts/spin-operator \
  --wait
ok "spin-operator ready"

# ---------------------------------------------------------------------------
# Step 8 – ShimExecutor
# ---------------------------------------------------------------------------
info "Step 8: ShimExecutor"
kubectl apply -f \
  "https://github.com/spinframework/spin-operator/releases/download/${SPIN_OPERATOR_VERSION}/spin-operator.shim-executor.yaml"
ok "ShimExecutor applied"

# ---------------------------------------------------------------------------
# Step 9 – KEDA
# ---------------------------------------------------------------------------
info "Step 9: KEDA ${KEDA_VERSION}"
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
# Step 10 – KEDA HTTP Add-on (enables HTTPScaledObject / scale-to-zero)
# ---------------------------------------------------------------------------
info "Step 10: KEDA HTTP Add-on ${KEDA_HTTP_ADDON_VERSION}"
helm upgrade --install keda-add-ons-http \
  --namespace keda \
  kedacore/keda-add-ons-http \
  --version "${KEDA_HTTP_ADDON_VERSION}" \
  --wait
ok "KEDA HTTP Add-on ready"

# ---------------------------------------------------------------------------
# Step 11 – Deploy SpinApp + proxy Service + Ingress
# ---------------------------------------------------------------------------
info "Step 11: Deploying SpinApp + proxy Service + Ingress"
kubectl apply -f "${SCRIPT_DIR}/spinapp.yaml"
wait_rollout default deployment/thecalculatorspin
ok "SpinApp running"

# ---------------------------------------------------------------------------
# Step 12 – HTTPScaledObject (scale-to-zero after ${SCALEDOWN_PERIOD}s idle)
# ---------------------------------------------------------------------------
info "Step 12: Applying HTTPScaledObject (min=0, max=5, scaledownPeriod=${SCALEDOWN_PERIOD}s)"
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
