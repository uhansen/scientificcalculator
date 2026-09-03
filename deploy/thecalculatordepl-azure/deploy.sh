#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

AZ_LOCATION="${AZ_LOCATION:-westeurope}"
AZ_RESOURCE_GROUP="${AZ_RESOURCE_GROUP:-rg-thecalculatorspin-aks}"
CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-aks}"
NODE_COUNT="${NODE_COUNT:-3}"
NODE_VM_SIZE="${NODE_VM_SIZE:-Standard_D4s_v5}"

require_cmds bash az kubectl helm spin gh curl sed

info "Azure AKS deploy for ${APP_NAME}"

push_spin_image

info "Step 2: Preparing Azure subscription and resource group"
az account show >/dev/null
az provider register --namespace Microsoft.ContainerService >/dev/null
az group create --name "${AZ_RESOURCE_GROUP}" --location "${AZ_LOCATION}" >/dev/null
ok "Resource group ready: ${AZ_RESOURCE_GROUP}"

info "Step 3: Creating or reusing AKS cluster ${CLUSTER_NAME}"
if az aks show --resource-group "${AZ_RESOURCE_GROUP}" --name "${CLUSTER_NAME}" >/dev/null 2>&1; then
  ok "Cluster ${CLUSTER_NAME} already exists"
else
  az aks create \
    --resource-group "${AZ_RESOURCE_GROUP}" \
    --name "${CLUSTER_NAME}" \
    --location "${AZ_LOCATION}" \
    --node-count "${NODE_COUNT}" \
    --node-vm-size "${NODE_VM_SIZE}" \
    --enable-managed-identity \
    --generate-ssh-keys \
    --yes >/dev/null
  ok "Cluster ${CLUSTER_NAME} created"
fi

az aks get-credentials \
  --resource-group "${AZ_RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --overwrite-existing >/dev/null
kubectl cluster-info >/dev/null

install_traefik "${SCRIPT_DIR}/traefik-values.yaml"
install_cert_manager
install_runtime_class_manager_and_shim
install_spin_operator
install_keda
deploy_spin_resources "${SCRIPT_DIR}/spinapp.yaml" "${SCRIPT_DIR}/httpscaledobject.yaml"

LB_ADDRESS="$(wait_for_lb_address "${TRAEFIK_NAMESPACE}" traefik)"
ok "Traefik load balancer address: ${LB_ADDRESS}"
verify_http_api "${LB_ADDRESS}"
