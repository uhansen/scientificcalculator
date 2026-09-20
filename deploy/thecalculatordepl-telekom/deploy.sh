#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

tf() {
  if command -v mise >/dev/null 2>&1; then
    mise exec terraform@1.16.3 -- terraform "$@"
  else
    terraform "$@"
  fi
}

require_terraform() {
  if command -v mise >/dev/null 2>&1; then
    return 0
  fi
  command -v terraform >/dev/null 2>&1 || die "Required command not found: terraform (or mise with terraform@1.16.3)"
}

require_otc_auth() {
  if [[ -n "${OS_CLOUD:-}" ]]; then
    return 0
  fi

  [[ -n "${OS_AUTH_URL:-}" ]] || die "Set OS_AUTH_URL or OS_CLOUD for Telekom/OpenTelekomCloud authentication"
  [[ -n "${OS_REGION_NAME:-}" ]] || die "Set OS_REGION_NAME or OS_CLOUD for Telekom/OpenTelekomCloud authentication"
  [[ -n "${OS_PROJECT_NAME:-}" ]] || die "Set OS_PROJECT_NAME or OS_CLOUD for Telekom/OpenTelekomCloud authentication"

  if [[ -n "${OS_ACCESS_KEY:-}" || -n "${OS_SECRET_KEY:-}" ]]; then
    [[ -n "${OS_ACCESS_KEY:-}" && -n "${OS_SECRET_KEY:-}" ]] || die "Set both OS_ACCESS_KEY and OS_SECRET_KEY"
    return 0
  fi

  [[ -n "${OS_USERNAME:-}" ]] || die "Set OS_USERNAME (or OS_ACCESS_KEY/OS_SECRET_KEY, or OS_CLOUD)"
  [[ -n "${OS_PASSWORD:-}" ]] || die "Set OS_PASSWORD (or OS_ACCESS_KEY/OS_SECRET_KEY, or OS_CLOUD)"
  [[ -n "${OS_USER_DOMAIN_NAME:-}" ]] || die "Set OS_USER_DOMAIN_NAME (or OS_CLOUD)"
}

wait_for_gateway_address() {
  local namespace="${1}" gateway="${2}" attempts="${3:-90}" i address
  for ((i = 1; i <= attempts; i++)); do
    address="$(kubectl get gateway "${gateway}" -n "${namespace}" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
    if [[ -n "${address}" ]]; then
      echo "${address}"
      return 0
    fi
    sleep 10
  done
  die "Gateway ${namespace}/${gateway} did not receive a public address"
}

install_envoy_gateway() {
  info "Installing Envoy Gateway ${ENVOY_GATEWAY_VERSION}"
  helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
    --namespace envoy-gateway-system \
    --create-namespace \
    --version "${ENVOY_GATEWAY_VERSION}" \
    --wait \
    --set crds.enabled=true >/dev/null
  ok "Envoy Gateway ready"
}

deploy_envoy_and_application() {
  local app_values envoy_values

  app_values="$(mktemp)"
  envoy_values="$(mktemp)"

  cat >"${app_values}" <<EOF
app:
  name: ${APP_NAME}
  host: ${APP_HOST}
  namespace: default
  image: ${IMAGE}
  imagePullSecret: ghcr-pull-secret
  executor: containerd-shim-spin
autoscaling:
  minReplicas: 1
  maxReplicas: 5
  concurrency: 10
  scaledownPeriod: ${SCALEDOWN_PERIOD}
EOF

  if [[ -n "${CCE_ELB_ID:-}" ]]; then
    cat >"${envoy_values}" <<EOF
app:
  name: ${APP_NAME}
  host: ${APP_HOST}
  namespace: default
envoyGateway:
  className: ${APP_NAME}-envoy
  gatewayName: ${APP_NAME}-http
  proxy:
    name: ${APP_NAME}-envoyproxy
    namespace: default
    annotations:
      kubernetes.io/elb.id: "${CCE_ELB_ID}"
keda:
  namespace: keda
  interceptorServiceName: keda-add-ons-http-interceptor-proxy
  interceptorServicePort: 8080
EOF
  else
    cat >"${envoy_values}" <<EOF
app:
  name: ${APP_NAME}
  host: ${APP_HOST}
  namespace: default
envoyGateway:
  className: ${APP_NAME}-envoy
  gatewayName: ${APP_NAME}-http
  proxy:
    name: ${APP_NAME}-envoyproxy
    namespace: default
    annotations:
      kubernetes.io/elb.class: "${CCE_ELB_CLASS}"
      kubernetes.io/elb.http-redirect: "true"
      kubernetes.io/elb.listen-ports: '[{"HTTP": 80},{"HTTPS": 443}]'
      kubernetes.io/elb.autocreate: '{"type":"public","bandwidth_name":"${CCE_ELB_BANDWIDTH_NAME}","bandwidth_chargemode":"${CCE_ELB_BANDWIDTH_CHARGEMODE}","bandwidth_size":${CCE_ELB_BANDWIDTH_SIZE},"bandwidth_sharetype":"${CCE_ELB_BANDWIDTH_SHARETYPE}","eip_type":"${CCE_ELB_EIP_TYPE}","l7_flavor_name":"${CCE_ELB_L7_FLAVOR_NAME}","l4_flavor_name":"${CCE_ELB_L4_FLAVOR_NAME}","available_zone":["${CCE_ELB_AVAILABILITY_ZONE}"]}'
keda:
  namespace: keda
  interceptorServiceName: keda-add-ons-http-interceptor-proxy
  interceptorServicePort: 8080
EOF
  fi

  info "Deploying Spin application via Helm"
  create_image_pull_secret
  helm upgrade --install "${APP_NAME}" "${SCRIPT_DIR}/charts/thecalculator-app" \
    --namespace default \
    --wait \
    -f "${app_values}" >/dev/null

  info "Configuring Envoy Gateway routing resources"
  helm upgrade --install envoy-gateway-resources "${SCRIPT_DIR}/charts/envoy-gateway-resources" \
    --namespace default \
    --wait \
    -f "${envoy_values}" >/dev/null

  rm -f "${app_values}" "${envoy_values}"
  ok "Application and Envoy resources applied"
}

CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-cce}"
PROJECT="${PROJECT:-scientificcalculator}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
CCE_CLUSTER_FLAVOR="${CCE_CLUSTER_FLAVOR:-cce.s1.small}"
CCE_CLUSTER_VERSION="${CCE_CLUSTER_VERSION:-v1.30}"
CCE_VPC_ID="${CCE_VPC_ID:-}"
CCE_SUBNET_ID="${CCE_SUBNET_ID:-}"
CCE_API_ACCESS_TRUSTLIST="${CCE_API_ACCESS_TRUSTLIST:-$(curl -fsS https://api.ipify.org 2>/dev/null || curl -fsS https://ifconfig.me 2>/dev/null || true)}"
CCE_AVAILABILITY_ZONE="${CCE_AVAILABILITY_ZONE:-}"
CCE_SSH_KEY_NAME="${CCE_SSH_KEY_NAME:-}"
CCE_NODE_FLAVOR="${CCE_NODE_FLAVOR:-s3.large.2}"
CCE_NODE_COUNT="${CCE_NODE_COUNT:-3}"
CCE_NODE_OS="${CCE_NODE_OS:-HCE OS 2.0}"
CCE_EXISTING_CLUSTER_ID="${CCE_EXISTING_CLUSTER_ID:-}"
CCE_EXISTING_CLUSTER_NAME="${CCE_EXISTING_CLUSTER_NAME:-}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${SCRIPT_DIR}/.kubeconfig-${CLUSTER_NAME}}"
CCE_ELB_ID="${CCE_ELB_ID:-}"
CCE_ELB_CLASS="${CCE_ELB_CLASS:-performance}"
CCE_ELB_BANDWIDTH_NAME="${CCE_ELB_BANDWIDTH_NAME:-${APP_NAME}-bandwidth}"
CCE_ELB_BANDWIDTH_CHARGEMODE="${CCE_ELB_BANDWIDTH_CHARGEMODE:-traffic}"
CCE_ELB_BANDWIDTH_SIZE="${CCE_ELB_BANDWIDTH_SIZE:-5}"
CCE_ELB_BANDWIDTH_SHARETYPE="${CCE_ELB_BANDWIDTH_SHARETYPE:-PER}"
CCE_ELB_EIP_TYPE="${CCE_ELB_EIP_TYPE:-5_bgp}"
CCE_ELB_L7_FLAVOR_NAME="${CCE_ELB_L7_FLAVOR_NAME:-L7_flavor.elb.s1.small}"
CCE_ELB_L4_FLAVOR_NAME="${CCE_ELB_L4_FLAVOR_NAME:-L4_flavor.elb.s1.small}"
CCE_ELB_AVAILABILITY_ZONE="${CCE_ELB_AVAILABILITY_ZONE:-${CCE_AVAILABILITY_ZONE}}"

require_cmds bash kubectl helm spin gh curl sed
require_terraform
require_otc_auth

[[ -n "${CCE_VPC_ID}" ]] || die "Set CCE_VPC_ID to an existing Telekom/OpenTelekomCloud VPC ID"
[[ -n "${CCE_SUBNET_ID}" ]] || die "Set CCE_SUBNET_ID to an existing Telekom/OpenTelekomCloud subnet network ID"
[[ -n "${CCE_AVAILABILITY_ZONE}" ]] || die "Set CCE_AVAILABILITY_ZONE (for example eu-de-01)"
[[ -n "${CCE_SSH_KEY_NAME}" ]] || die "Set CCE_SSH_KEY_NAME to an existing Telekom/OpenTelekomCloud key pair name"
[[ -n "${CCE_API_ACCESS_TRUSTLIST}" ]] || die "Could not determine CCE_API_ACCESS_TRUSTLIST automatically; set it explicitly"
[[ "${CCE_API_ACCESS_TRUSTLIST}" == */* ]] || CCE_API_ACCESS_TRUSTLIST="${CCE_API_ACCESS_TRUSTLIST}/32"
[[ -n "${CCE_ELB_AVAILABILITY_ZONE}" || -n "${CCE_ELB_ID}" ]] || die "Set CCE_ELB_AVAILABILITY_ZONE or CCE_ELB_ID"

info "Telekom/OpenTelekomCloud CCE deploy for ${APP_NAME}"

push_spin_image

info "Applying Terraform CCE foundation"
cat >"${SCRIPT_DIR}/terraform/terraform.auto.tfvars" <<EOF
project              = "${PROJECT}"
environment          = "${ENVIRONMENT}"
cluster_name         = "${CLUSTER_NAME}"
existing_cluster_id  = "${CCE_EXISTING_CLUSTER_ID}"
existing_cluster_name = "${CCE_EXISTING_CLUSTER_NAME}"
cluster_flavor       = "${CCE_CLUSTER_FLAVOR}"
cluster_version      = "${CCE_CLUSTER_VERSION}"
vpc_id               = "${CCE_VPC_ID}"
subnet_id            = "${CCE_SUBNET_ID}"
api_access_trustlist = ["${CCE_API_ACCESS_TRUSTLIST}"]
availability_zone    = "${CCE_AVAILABILITY_ZONE}"
ssh_key_name         = "${CCE_SSH_KEY_NAME}"
node_flavor          = "${CCE_NODE_FLAVOR}"
node_count           = ${CCE_NODE_COUNT}
node_os              = "${CCE_NODE_OS}"
EOF

(
  cd "${SCRIPT_DIR}/terraform"
  tf init -input=false >/dev/null
  if [[ "${TF_AUTO_APPROVE:-true}" == "true" ]]; then
    tf apply -auto-approve
  else
    tf apply
  fi
  tf output -raw kubeconfig > "${KUBECONFIG_PATH}"
)
chmod 600 "${KUBECONFIG_PATH}"
export KUBECONFIG="${KUBECONFIG_PATH}"
kubectl cluster-info >/dev/null
ok "Kubeconfig written to ${KUBECONFIG_PATH}"

install_cert_manager
install_runtime_class_manager_and_shim
install_spin_operator
install_keda
install_envoy_gateway
deploy_envoy_and_application

GATEWAY_ADDRESS="$(wait_for_gateway_address default "${APP_NAME}-http")"
ok "Envoy Gateway public address: ${GATEWAY_ADDRESS}"
verify_http_api "${GATEWAY_ADDRESS}"
