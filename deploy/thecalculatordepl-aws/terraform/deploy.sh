#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/terraform-deploy-common.sh"

AWS_REGION="${AWS_REGION:-eu-north-1}"
PROJECT="${PROJECT:-scientificcalculator}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-eks}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.33}"
VPC_CIDR="${VPC_CIDR:-10.42.0.0/16}"
NODE_INSTANCE_TYPE="${NODE_INSTANCE_TYPE:-m5.large}"
NODE_DESIRED_SIZE="${NODE_DESIRED_SIZE:-2}"
NODE_MIN_SIZE="${NODE_MIN_SIZE:-2}"
NODE_MAX_SIZE="${NODE_MAX_SIZE:-3}"
NODE_DISK_SIZE="${NODE_DISK_SIZE:-50}"
NODE_CAPACITY_TYPE="${NODE_CAPACITY_TYPE:-ON_DEMAND}"
APP_NAME="${APP_NAME:-thecalculatorspin}"
APP_HOST="${APP_HOST:-thecalculatorspin.example.internal}"
IMAGE="${IMAGE:-ghcr.io/uhansen/thecalculatorspin:latest}"
GHCR_USER="${GHCR_USER:-uhansen}"
CLUSTER_ENDPOINT_PUBLIC_ACCESS_CIDRS="${CLUSTER_ENDPOINT_PUBLIC_ACCESS_CIDRS:-$(detect_public_cidr)}"

bootstrap_dir="${SCRIPT_DIR}/bootstrap"
backend_file="${SCRIPT_DIR}/backend.hcl"
tfvars_file="${SCRIPT_DIR}/terraform.auto.tfvars"

bucket_user="$(slugify_alnum "${USER:-uha}")"
bucket_suffix="$(date +%Y%m%d%H%M%S)"
STATE_BUCKET_NAME="${STATE_BUCKET_NAME:-$(printf 'scientificcalculator-tfstate-%s-%s' "${bucket_user}" "${bucket_suffix}" | cut -c1-63)}"

require_cmds bash aws kubectl helm gh curl sed mise

info "AWS Terraform deploy for ${APP_NAME}"

ghcr_token="$(resolve_registry_token)"

if [[ ! -f "${backend_file}" || "${TF_REFRESH_BACKEND_CONFIG:-false}" == "true" ]]; then
  info "Bootstrapping S3 backend ${STATE_BUCKET_NAME}"
  (
    cd "${bootstrap_dir}"
    tf init -backend=false -input=false
    if [[ "${TF_AUTO_APPROVE:-true}" == "true" ]]; then
      tf apply -auto-approve \
        -var="state_bucket_name=${STATE_BUCKET_NAME}" \
        -var="aws_region=${AWS_REGION}"
    else
      tf apply \
        -var="state_bucket_name=${STATE_BUCKET_NAME}" \
        -var="aws_region=${AWS_REGION}"
    fi
    tf output -raw backend_hcl_snippet > "${backend_file}"
  )
  ok "Generated ${backend_file}"
fi

write_file "${tfvars_file}" \
"aws_region = \"${AWS_REGION}\"
project = \"${PROJECT}\"
environment = \"${ENVIRONMENT}\"
cluster_name = \"${CLUSTER_NAME}\"
kubernetes_version = \"${KUBERNETES_VERSION}\"
cluster_endpoint_public_access_cidrs = [\"${CLUSTER_ENDPOINT_PUBLIC_ACCESS_CIDRS}\"]
node_instance_types = [\"${NODE_INSTANCE_TYPE}\"]
node_desired_size = ${NODE_DESIRED_SIZE}
node_min_size = ${NODE_MIN_SIZE}
node_max_size = ${NODE_MAX_SIZE}
node_disk_size = ${NODE_DISK_SIZE}
node_capacity_type = \"${NODE_CAPACITY_TYPE}\"
vpc_cidr = \"${VPC_CIDR}\"
app_name = \"${APP_NAME}\"
app_host = \"${APP_HOST}\"
ghcr_username = \"${GHCR_USER}\"
ghcr_token = \"${ghcr_token}\"
image = \"${IMAGE}\"
"
ok "Wrote ${tfvars_file}"

info "Planning and applying the main EKS stack"
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
ok "AWS deployment complete"
