#!/usr/bin/env bash

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.1}"
RUNTIME_CLASS_MANAGER_VERSION="${RUNTIME_CLASS_MANAGER_VERSION:-0.2.0}"
SPIN_SHIM_VERSION="${SPIN_SHIM_VERSION:-v0.25.1}"
SPIN_OPERATOR_VERSION="${SPIN_OPERATOR_VERSION:-v0.6.1}"
KEDA_VERSION="${KEDA_VERSION:-2.20.2}"
KEDA_HTTP_ADDON_VERSION="${KEDA_HTTP_ADDON_VERSION:-0.15.0}"
APP_NAME="${APP_NAME:-thecalculatorspin}"
APP_HOST="${APP_HOST:-thecalculatorspin.local}"
INGRESS_CLASS="${INGRESS_CLASS:-traefik}"
SCALEDOWN_PERIOD="${SCALEDOWN_PERIOD:-60}"
TRAEFIK_NAMESPACE="${TRAEFIK_NAMESPACE:-traefik}"
GHCR_USER="${GHCR_USER:-uhansen}"
IMAGE="${IMAGE:-ghcr.io/${GHCR_USER}/${APP_NAME}:latest}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SPIN_APP_DIR="${SPIN_APP_DIR:-${REPO_ROOT}/applications/thecalculatorspin}"

info() { echo ""; echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*" >&2; }
die()  { echo "  ✗ $*" >&2; exit 1; }

require_cmds() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
  done
}

wait_rollout() {
  local namespace="${1}" resource="${2}"
  kubectl rollout status "${resource}" -n "${namespace}" --timeout=300s
}

wait_for_deployment() {
  local namespace="${1}" name="${2}" attempts="${3:-60}" i
  for ((i = 1; i <= attempts; i++)); do
    if kubectl get deployment "${name}" -n "${namespace}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  die "Deployment ${namespace}/${name} did not appear"
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
  kubectl get shim "${name}" -o wide || true
  die "Shim ${name} did not become ready on all labeled nodes"
}

wait_for_lb_address() {
  local namespace="${1}" service="${2}" attempts="${3:-90}" i hostname ip
  for ((i = 1; i <= attempts; i++)); do
    hostname="$(kubectl get svc "${service}" -n "${namespace}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    ip="$(kubectl get svc "${service}" -n "${namespace}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -n "${hostname}" ]]; then
      echo "${hostname}"
      return 0
    fi
    if [[ -n "${ip}" ]]; then
      echo "${ip}"
      return 0
    fi
    sleep 10
  done
  die "Service ${namespace}/${service} did not receive a load balancer address"
}

resolve_registry_token() {
  REGISTRY_TOKEN="${GHCR_TOKEN:-${CR_PAT:-${GITHUB_TOKEN:-}}}"
  if [[ -z "${REGISTRY_TOKEN}" ]]; then
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
      die "Not logged in to GitHub. Run: gh auth login"
    fi
    REGISTRY_TOKEN="$(gh auth token)"
  fi
}

push_spin_image() {
  info "Step 1: Pushing WASM image to ghcr.io (${IMAGE})"
  resolve_registry_token
  echo "${REGISTRY_TOKEN}" | spin registry login \
    --username "${GHCR_USER}" \
    --password-stdin \
    ghcr.io
  (
    cd "${SPIN_APP_DIR}"
    spin registry push "${IMAGE}"
  )
  ok "Image pushed: ${IMAGE}"
}

create_image_pull_secret() {
  info "Creating/refreshing ghcr-pull-secret"
  if [[ -f "${HOME}/.docker/config.json" ]]; then
    kubectl create secret generic ghcr-pull-secret \
      --from-file=.dockerconfigjson="${HOME}/.docker/config.json" \
      --type=kubernetes.io/dockerconfigjson \
      --namespace=default \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    resolve_registry_token
    kubectl create secret docker-registry ghcr-pull-secret \
      --docker-server=ghcr.io \
      --docker-username="${GHCR_USER}" \
      --docker-password="${REGISTRY_TOKEN}" \
      --namespace=default \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
  ok "imagePullSecret ghcr-pull-secret created/updated"
}

install_traefik() {
  local values_file="${1}"
  info "Installing Traefik ingress controller"
  helm repo add traefik https://traefik.github.io/charts >/dev/null 2>&1 || true
  helm repo update traefik >/dev/null
  helm upgrade --install traefik traefik/traefik \
    --namespace "${TRAEFIK_NAMESPACE}" \
    --create-namespace \
    --wait \
    -f "${values_file}"
  wait_rollout "${TRAEFIK_NAMESPACE}" deployment/traefik
  ok "Traefik ready"
}

install_cert_manager() {
  info "Installing cert-manager ${CERT_MANAGER_VERSION}"
  if ! kubectl get namespace cert-manager >/dev/null 2>&1; then
    kubectl apply -f \
      "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  fi
  wait_rollout cert-manager deployment/cert-manager
  wait_rollout cert-manager deployment/cert-manager-webhook
  wait_rollout cert-manager deployment/cert-manager-cainjector
  ok "cert-manager ready"
}

install_runtime_class_manager_and_shim() {
  info "Installing runtime-class-manager ${RUNTIME_CLASS_MANAGER_VERSION} and shim ${SPIN_SHIM_VERSION}"
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
  kubectl get runtimeclass wasmtime-spin-v2 >/dev/null
  ok "Runtime class and shim ready"
}

install_spin_operator() {
  info "Installing spin-operator ${SPIN_OPERATOR_VERSION}"
  kubectl apply -f \
    "https://github.com/spinframework/spin-operator/releases/download/${SPIN_OPERATOR_VERSION}/spin-operator.crds.yaml"
  helm upgrade --install spin-operator \
    --namespace spin-operator \
    --create-namespace \
    --version "${SPIN_OPERATOR_VERSION#v}" \
    oci://ghcr.io/spinframework/charts/spin-operator \
    --wait
  kubectl apply -f \
    "https://github.com/spinframework/spin-operator/releases/download/${SPIN_OPERATOR_VERSION}/spin-operator.shim-executor.yaml"
  ok "spin-operator ready"
}

install_keda() {
  info "Installing KEDA ${KEDA_VERSION}"
  helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1 || true
  helm repo update kedacore >/dev/null
  helm upgrade --install keda \
    --namespace keda \
    --create-namespace \
    kedacore/keda \
    --version "${KEDA_VERSION}" \
    --wait

  info "Installing KEDA HTTP Add-on ${KEDA_HTTP_ADDON_VERSION}"
  helm upgrade --install keda-add-ons-http \
    --namespace keda \
    kedacore/keda-add-ons-http \
    --version "${KEDA_HTTP_ADDON_VERSION}" \
    --wait
  ok "KEDA and HTTP Add-on ready"
}

render_template() {
  local template_file="${1}"
  sed \
    -e "s|__APP_NAME__|${APP_NAME}|g" \
    -e "s|__IMAGE__|${IMAGE}|g" \
    -e "s|__APP_HOST__|${APP_HOST}|g" \
    -e "s|__INGRESS_CLASS__|${INGRESS_CLASS}|g" \
    -e "s|__SCALEDOWN_PERIOD__|${SCALEDOWN_PERIOD}|g" \
    "${template_file}"
}

apply_template() {
  local template_file="${1}" tmp_file
  tmp_file="$(mktemp)"
  render_template "${template_file}" > "${tmp_file}"
  kubectl apply -f "${tmp_file}"
  rm -f "${tmp_file}"
}

deploy_spin_resources() {
  local spinapp_template="${1}" httpscaled_template="${2}"
  info "Deploying SpinApp, proxy Service, Ingress, and HTTPScaledObject"
  create_image_pull_secret
  apply_template "${spinapp_template}"
  wait_for_deployment default "${APP_NAME}"
  wait_rollout default "deployment/${APP_NAME}"
  apply_template "${httpscaled_template}"
  ok "Application resources applied"
}

verify_http_api() {
  local address="${1}" attempts="${2:-24}" i result
  info "Verification"
  for ((i = 1; i <= attempts; i++)); do
    result="$(curl -fsS -H "Host: ${APP_HOST}" "http://${address}/?calculate=add(2,3)" 2>/dev/null || true)"
    if [[ "${result}" == "5" ]]; then
      ok "HTTP API responds correctly via ${address}: add(2,3) = ${result}"
      echo ""
      echo "═════════════════════════════════════════════════════════════"
      echo " ${APP_NAME} is running on SpinKube + KEDA HTTP"
      echo " curl -H 'Host: ${APP_HOST}' 'http://${address}/?calculate=add(2,3)'"
      echo "═════════════════════════════════════════════════════════════"
      return 0
    fi
    sleep 10
  done
  warn "Verification did not return the expected result yet."
  warn "Try manually: curl -H 'Host: ${APP_HOST}' 'http://${address}/?calculate=add(2,3)'"
  return 1
}
