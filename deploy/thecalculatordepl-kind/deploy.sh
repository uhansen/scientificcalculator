#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

APP_NAME="${APP_NAME:-thecalculatorspin}"
REGISTRY_MODE="${REGISTRY_MODE:-local}"
LOCAL_REGISTRY_NAME="${LOCAL_REGISTRY_NAME:-kind-registry}"
LOCAL_REGISTRY_PORT="${LOCAL_REGISTRY_PORT:-5001}"
GHCR_USER="${GHCR_USER:-uhansen}"
IMAGE="${IMAGE:-$(
  if [[ "${REGISTRY_MODE}" == "local" ]]; then
    printf 'localhost:%s/%s:latest' "${LOCAL_REGISTRY_PORT}" "${APP_NAME}"
  else
    printf 'ghcr.io/%s/%s:latest' "${GHCR_USER}" "${APP_NAME}"
  fi
)}"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

CLUSTER_NAME="${CLUSTER_NAME:-uha-cluster}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-ghcr.io/spinframework/containerd-shim-spin/kind:v0.25.1}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-3000}"
HOST_HTTPS_PORT="${HOST_HTTPS_PORT:-3443}"
KIND_CONTEXT="kind-${CLUSTER_NAME}"

if [[ "${REGISTRY_MODE}" == "local" ]]; then
  require_cmds bash kind kubectl helm spin curl sed docker
else
  require_cmds bash kind kubectl helm spin gh curl sed docker
fi

ensure_local_registry() {
  local attempt

  if [[ "${REGISTRY_MODE}" != "local" ]]; then
    return 0
  fi

  info "Preparing local OCI registry ${LOCAL_REGISTRY_NAME} on localhost:${LOCAL_REGISTRY_PORT}"
  if [[ "$(docker inspect -f '{{.State.Running}}' "${LOCAL_REGISTRY_NAME}" 2>/dev/null || true)" != "true" ]]; then
    docker run \
      -d \
      --restart=always \
      -p "127.0.0.1:${LOCAL_REGISTRY_PORT}:5000" \
      --network bridge \
      --name "${LOCAL_REGISTRY_NAME}" \
      registry:3 >/dev/null
  fi

  for attempt in $(seq 1 30); do
    if curl -fsS "http://localhost:${LOCAL_REGISTRY_PORT}/v2/" >/dev/null; then
      ok "Local registry ready"
      return 0
    fi
    sleep 1
  done
  die "Local registry ${LOCAL_REGISTRY_NAME} did not become ready on localhost:${LOCAL_REGISTRY_PORT}"
}

configure_local_registry_for_kind() {
  local registry_dir node

  if [[ "${REGISTRY_MODE}" != "local" ]]; then
    return 0
  fi

  info "Configuring kind to pull from localhost:${LOCAL_REGISTRY_PORT}"
  if [[ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "${LOCAL_REGISTRY_NAME}")" == "null" ]]; then
    docker network connect kind "${LOCAL_REGISTRY_NAME}"
  fi

  registry_dir="/etc/containerd/certs.d/localhost:${LOCAL_REGISTRY_PORT}"
  for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
    docker exec "${node}" mkdir -p "${registry_dir}"
    cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${registry_dir}/hosts.toml"
[host."http://${LOCAL_REGISTRY_NAME}:5000"]
EOF
  done

  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${LOCAL_REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
  ok "kind registry alias configured"
}

remove_stale_runtimeclass() {
  local handler

  handler="$(kubectl get runtimeclass wasmtime-spin-v2 -o jsonpath='{.handler}' 2>/dev/null || true)"
  if [[ -n "${handler}" && "${handler}" != "spin-v2" ]]; then
    info "Removing stale RuntimeClass wasmtime-spin-v2 (handler=${handler})"
    kubectl delete shim spin-v2 --ignore-not-found
    kubectl delete runtimeclass wasmtime-spin-v2
    ok "Stale RuntimeClass state removed"
    return 0
  fi

  if kubectl get shim spin-v2 >/dev/null 2>&1 && [[ -z "${handler}" ]]; then
    info "Removing stale Shim spin-v2 so RuntimeClass can be recreated"
    kubectl delete shim spin-v2
    ok "Stale Shim removed"
  fi
}

restart_existing_app_pods() {
  if kubectl get deployment "${APP_NAME}" -n default >/dev/null 2>&1; then
    info "Restarting existing ${APP_NAME} pods after runtime changes"
    kubectl delete pod -n default -l "core.spinkube.dev/app-name=${APP_NAME}" --ignore-not-found
    ok "Existing app pods restarted"
  fi
}

push_spin_image() {
  if [[ "${REGISTRY_MODE}" == "local" ]]; then
    info "Step 1: Pushing WASM image to local registry (${IMAGE})"
    ensure_local_registry
    (
      cd "${SPIN_APP_DIR}"
      spin registry push --insecure "${IMAGE}"
    )
    ok "Image pushed: ${IMAGE}"
    return 0
  fi

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
  if [[ "${REGISTRY_MODE}" == "local" ]]; then
    info "Skipping image pull secret for local registry"
    return 0
  fi

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

apply_template() {
  local template_file="${1}" tmp_file
  tmp_file="$(mktemp)"
  render_template "${template_file}" > "${tmp_file}"
  if [[ "${REGISTRY_MODE}" == "local" ]]; then
    sed -i '/^  imagePullSecrets:$/,/^    - name: ghcr-pull-secret$/d' "${tmp_file}"
  fi
  kubectl apply -f "${tmp_file}"
  rm -f "${tmp_file}"
}

info "kind deploy for ${APP_NAME} (${REGISTRY_MODE} registry)"

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
configure_local_registry_for_kind
remove_stale_runtimeclass

info "Step 3: Installing Runtime Class Manager and configuring the spin runtime"
install_runtime_class_manager_and_shim
restart_existing_app_pods

install_cert_manager
install_spin_operator
install_keda
install_traefik "${SCRIPT_DIR}/traefik-values.yaml"
deploy_spin_resources "${SCRIPT_DIR}/spinapp.yaml" "${SCRIPT_DIR}/httpscaledobject.yaml"

APP_ADDRESS="localhost:${HOST_HTTP_PORT}"
ok "App reachable at ${APP_ADDRESS}"
verify_http_api "${APP_ADDRESS}"
