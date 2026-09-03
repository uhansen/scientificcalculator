#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

AWS_REGION="${AWS_REGION:-eu-north-1}"
CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-eks}"
NODE_COUNT="${NODE_COUNT:-3}"
NODE_INSTANCE_TYPE="${NODE_INSTANCE_TYPE:-m5.large}"

require_cmds bash aws eksctl kubectl helm spin gh curl sed

info "AWS EKS deploy for ${APP_NAME}"

push_spin_image

info "Step 2: Creating or reusing EKS cluster ${CLUSTER_NAME}"
cluster_config="$(mktemp)"
sed \
  -e "s|__CLUSTER_NAME__|${CLUSTER_NAME}|g" \
  -e "s|__AWS_REGION__|${AWS_REGION}|g" \
  -e "s|__NODE_COUNT__|${NODE_COUNT}|g" \
  -e "s|__NODE_INSTANCE_TYPE__|${NODE_INSTANCE_TYPE}|g" \
  "${SCRIPT_DIR}/eksctl-cluster.yaml" > "${cluster_config}"

if eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  ok "Cluster ${CLUSTER_NAME} already exists"
else
  eksctl create cluster -f "${cluster_config}"
  ok "Cluster ${CLUSTER_NAME} created"
fi
rm -f "${cluster_config}"

aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
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
