#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/terraform-deploy-common.sh"

AZ_LOCATION="${AZ_LOCATION:-denmarkeast}"
PROJECT="${PROJECT:-scientificcalculator}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
AZ_RESOURCE_GROUP="${AZ_RESOURCE_GROUP:-rg-thecalculatorspin-aks}"
CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-aks}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.31}"
AUTHORIZED_IP_RANGES="${AUTHORIZED_IP_RANGES:-$(detect_public_cidr)}"
VNET_CIDR="${VNET_CIDR:-10.60.0.0/16}"
NODE_SUBNET_CIDR="${NODE_SUBNET_CIDR:-10.60.1.0/24}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.245.0.0/24}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D4s_v5}"
NODE_COUNT="${NODE_COUNT:-3}"
NODE_OS_DISK_SIZE_GB="${NODE_OS_DISK_SIZE_GB:-50}"
APP_NAME="${APP_NAME:-thecalculatorspin}"
APP_HOST="${APP_HOST:-thecalculatorspin.example.internal}"
IMAGE="${IMAGE:-ghcr.io/uhansen/thecalculatorspin:latest}"
GHCR_USER="${GHCR_USER:-uhansen}"
STATE_RESOURCE_GROUP_NAME="${STATE_RESOURCE_GROUP_NAME:-rg-thecalculatorspin-tfstate}"

bootstrap_dir="${SCRIPT_DIR}/bootstrap"
backend_file="${SCRIPT_DIR}/backend.hcl"
tfvars_file="${SCRIPT_DIR}/terraform.auto.tfvars"

account_user="$(slugify_alnum "${USER:-uha}")"
account_suffix="$(date +%m%d%H%M%S)"
STATE_STORAGE_ACCOUNT_NAME="${STATE_STORAGE_ACCOUNT_NAME:-$(printf 'scalc%stf%s' "${account_user}" "${account_suffix}" | cut -c1-24)}"

require_cmds bash az kubectl helm gh curl sed mise

info "Azure Terraform deploy for ${APP_NAME}"

ghcr_token="$(resolve_registry_token)"

if [[ ! -f "${backend_file}" || "${TF_REFRESH_BACKEND_CONFIG:-false}" == "true" ]]; then
  info "Bootstrapping Azure Storage backend ${STATE_STORAGE_ACCOUNT_NAME}"
  (
    cd "${bootstrap_dir}"
    tf init -backend=false -input=false
    if [[ "${TF_AUTO_APPROVE:-true}" == "true" ]]; then
      tf apply -auto-approve \
        -var="location=${AZ_LOCATION}" \
        -var="state_resource_group_name=${STATE_RESOURCE_GROUP_NAME}" \
        -var="state_storage_account_name=${STATE_STORAGE_ACCOUNT_NAME}"
    else
      tf apply \
        -var="location=${AZ_LOCATION}" \
        -var="state_resource_group_name=${STATE_RESOURCE_GROUP_NAME}" \
        -var="state_storage_account_name=${STATE_STORAGE_ACCOUNT_NAME}"
    fi
    tf output -raw backend_hcl_snippet > "${backend_file}"
  )
  ok "Generated ${backend_file}"
fi

write_file "${tfvars_file}" \
"location = \"${AZ_LOCATION}\"
project = \"${PROJECT}\"
environment = \"${ENVIRONMENT}\"
resource_group_name = \"${AZ_RESOURCE_GROUP}\"
cluster_name = \"${CLUSTER_NAME}\"
kubernetes_version = \"${KUBERNETES_VERSION}\"
authorized_ip_ranges = [\"${AUTHORIZED_IP_RANGES}\"]
vnet_cidr = \"${VNET_CIDR}\"
node_subnet_cidr = \"${NODE_SUBNET_CIDR}\"
pod_cidr = \"${POD_CIDR}\"
service_cidr = \"${SERVICE_CIDR}\"
node_vm_size = \"${NODE_VM_SIZE}\"
node_count = ${NODE_COUNT}
node_os_disk_size_gb = ${NODE_OS_DISK_SIZE_GB}
app_name = \"${APP_NAME}\"
app_host = \"${APP_HOST}\"
ghcr_username = \"${GHCR_USER}\"
ghcr_token = \"${ghcr_token}\"
image = \"${IMAGE}\"
"
ok "Wrote ${tfvars_file}"

info "Planning and applying the main AKS stack"
run_tf_plan_apply "${SCRIPT_DIR}" -backend-config="${backend_file}"

if [[ "${TF_PLAN_ONLY:-false}" == "true" ]]; then
  exit 0
fi

info "Updating kubeconfig"
run_output_command "${SCRIPT_DIR}" kubeconfig_update_command

info "Looking up the public Envoy endpoint"
gateway_address="$(run_output_command "${SCRIPT_DIR}" envoy_gateway_hostname_lookup)"
ok "Gateway address: ${gateway_address}"

info "Verifying the calculator endpoint"
bash -lc "$(terraform_output_raw "${SCRIPT_DIR}" verify_command)"
ok "Azure deployment complete"
