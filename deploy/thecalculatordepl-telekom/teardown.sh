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

CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-cce}"
PROJECT="${PROJECT:-scientificcalculator}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
CCE_CLUSTER_FLAVOR="${CCE_CLUSTER_FLAVOR:-cce.s1.small}"
CCE_CLUSTER_VERSION="${CCE_CLUSTER_VERSION:-v1.30}"
CCE_VPC_ID="${CCE_VPC_ID:-}"
CCE_SUBNET_ID="${CCE_SUBNET_ID:-}"
CCE_API_ACCESS_TRUSTLIST="${CCE_API_ACCESS_TRUSTLIST:-0.0.0.0/0}"
CCE_AVAILABILITY_ZONE="${CCE_AVAILABILITY_ZONE:-}"
CCE_SSH_KEY_NAME="${CCE_SSH_KEY_NAME:-}"
CCE_NODE_FLAVOR="${CCE_NODE_FLAVOR:-s3.large.2}"
CCE_NODE_COUNT="${CCE_NODE_COUNT:-3}"
CCE_NODE_OS="${CCE_NODE_OS:-HCE OS 2.0}"
CCE_EXISTING_CLUSTER_ID="${CCE_EXISTING_CLUSTER_ID:-}"
CCE_EXISTING_CLUSTER_NAME="${CCE_EXISTING_CLUSTER_NAME:-}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${SCRIPT_DIR}/.kubeconfig-${CLUSTER_NAME}}"
REMOVE_SHARED_ADDONS="${REMOVE_SHARED_ADDONS:-false}"

require_cmds bash kubectl helm sed
require_terraform

if [[ -f "${KUBECONFIG_PATH}" ]]; then
  export KUBECONFIG="${KUBECONFIG_PATH}"
  info "Removing application resources from the cluster"
  helm uninstall envoy-gateway-resources -n default >/dev/null 2>&1 || true
  helm uninstall "${APP_NAME}" -n default >/dev/null 2>&1 || true

  if [[ -z "${CCE_EXISTING_CLUSTER_ID}" && -z "${CCE_EXISTING_CLUSTER_NAME}" || "${REMOVE_SHARED_ADDONS}" == "true" ]]; then
    helm uninstall envoy-gateway -n envoy-gateway-system >/dev/null 2>&1 || true
    helm uninstall keda-add-ons-http -n keda >/dev/null 2>&1 || true
    helm uninstall keda -n keda >/dev/null 2>&1 || true
    helm uninstall spin-operator -n spin-operator >/dev/null 2>&1 || true
    helm uninstall runtime-class-manager -n runtime-class-manager >/dev/null 2>&1 || true

    kubectl delete spinappexecutor containerd-shim-spin -n spin-operator --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete shim spin-v2 --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete runtimeclass wasmtime-spin-v2 --ignore-not-found >/dev/null 2>&1 || true
  else
    warn "Leaving shared add-ons in place because this deployment reused an existing cluster"
    warn "Set REMOVE_SHARED_ADDONS=true if you want teardown.sh to remove Envoy/KEDA/SpinKube add-ons as well"
  fi
fi

if [[ -n "${CCE_EXISTING_CLUSTER_ID}" || -n "${CCE_EXISTING_CLUSTER_NAME}" ]]; then
  warn "Skipping Terraform cluster destruction because this deployment reused an existing cluster"
  exit 0
fi

[[ -n "${CCE_VPC_ID}" ]] || die "Set CCE_VPC_ID before running teardown.sh for a Terraform-created cluster"
[[ -n "${CCE_SUBNET_ID}" ]] || die "Set CCE_SUBNET_ID before running teardown.sh for a Terraform-created cluster"
[[ -n "${CCE_AVAILABILITY_ZONE}" ]] || die "Set CCE_AVAILABILITY_ZONE before running teardown.sh for a Terraform-created cluster"
[[ -n "${CCE_SSH_KEY_NAME}" ]] || die "Set CCE_SSH_KEY_NAME before running teardown.sh for a Terraform-created cluster"

cat >"${SCRIPT_DIR}/terraform/terraform.auto.tfvars" <<EOF
project              = "${PROJECT}"
environment          = "${ENVIRONMENT}"
cluster_name         = "${CLUSTER_NAME}"
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

info "Destroying Terraform-managed CCE resources"
(
  cd "${SCRIPT_DIR}/terraform"
  tf init -input=false >/dev/null
  if [[ "${TF_AUTO_APPROVE:-true}" == "true" ]]; then
    tf destroy -auto-approve
  else
    tf destroy
  fi
)
ok "Telekom/OpenTelekomCloud CCE resources destroyed"
