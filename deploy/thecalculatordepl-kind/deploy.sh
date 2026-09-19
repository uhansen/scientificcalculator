#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

CLUSTER_NAME="${CLUSTER_NAME:-uha-cluster}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-ghcr.io/spinframework/containerd-shim-spin/kind:v0.25.1}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-3000}"
HOST_HTTPS_PORT="${HOST_HTTPS_PORT:-3443}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

require_cmds bash kind kubectl helm spin gh curl sed docker

info "kind deploy for ${APP_NAME}"

push_spin_image

info "Step 2: Creating or reusing kind cluster ${CLUSTER_NAME}"
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  ok "Cluster ${CLUSTER_NAME} already exists"
else
  cluster_config="$(mktemp)"
  sed \
    -e "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" \
    -e "s|__NODE_IMAGE__|${KIND_NODE_IMAGE}|g" \
    -e "s|__HOST_HTTP_PORT__|${HOST_HTTP_PORT}|g" \
    -e "s|__HOST_HTTPS_PORT__|${HOST_HTTPS_PORT}|g" \
    "${SCRIPT_DIR}/kind-config.yaml" > "${cluster_config}"
  kind create cluster --config "${cluster_config}"
  rm -f "${cluster_config}"
  ok "Cluster ${CLUSTER_NAME} created"
fi

kubectl config use-context "${KIND_CONTEXT}" >/dev/null
kubectl cluster-info >/dev/null

info "Step 3: Applying RuntimeClass wasmtime-spin-v2 (shim baked into the node image)"
kubectl apply -f "${SCRIPT_DIR}/runtimeclass.yaml"
ok "RuntimeClass ready"

install_cert_manager
install_spin_operator
install_keda
install_traefik "${SCRIPT_DIR}/traefik-values.yaml"
deploy_spin_resources "${SCRIPT_DIR}/spinapp.yaml" "${SCRIPT_DIR}/httpscaledobject.yaml"

APP_ADDRESS="localhost:${HOST_HTTP_PORT}"
ok "App reachable at ${APP_ADDRESS}"
verify_http_api "${APP_ADDRESS}"
