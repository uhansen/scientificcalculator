#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

HCLOUD_LOCATION="${HCLOUD_LOCATION:-fsn1}"
HCLOUD_NETWORK_ZONE="${HCLOUD_NETWORK_ZONE:-eu-central}"
HCLOUD_SERVER_TYPE="${HCLOUD_SERVER_TYPE:-cpx21}"
HCLOUD_K3S_VERSION="${HCLOUD_K3S_VERSION:-v1.32.6+k3s1}"
CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-hcloud}"
HCLOUD_NETWORK_NAME="${HCLOUD_NETWORK_NAME:-${CLUSTER_NAME}-net}"
HCLOUD_FIREWALL_NAME="${HCLOUD_FIREWALL_NAME:-${CLUSTER_NAME}-fw}"
HCLOUD_SSH_KEY="${HCLOUD_SSH_KEY:-}"
HCLOUD_CLUSTER_CIDR="${HCLOUD_CLUSTER_CIDR:-10.42.0.0/16}"
HCLOUD_SERVICE_CIDR="${HCLOUD_SERVICE_CIDR:-10.43.0.0/16}"
HCLOUD_NODE_SUBNET="${HCLOUD_NODE_SUBNET:-10.0.1.0/24}"
CONTROL_PLANE_NAME="${CONTROL_PLANE_NAME:-${CLUSTER_NAME}-server-1}"
WORKER_COUNT="${WORKER_COUNT:-2}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${SCRIPT_DIR}/kubeconfig}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)

require_cmds bash hcloud jq ssh scp kubectl helm spin gh curl sed
[[ -n "${HCLOUD_TOKEN:-}" ]] || die "HCLOUD_TOKEN must be set"
[[ -n "${HCLOUD_SSH_KEY}" ]] || die "HCLOUD_SSH_KEY must be set to an SSH key name or ID already registered in Hetzner Cloud"

create_firewall_rules() {
  cat > "${SCRIPT_DIR}/firewall-rules.json" <<EOF
[
  {"direction":"in","protocol":"tcp","port":"22","source_ips":["0.0.0.0/0","::/0"]},
  {"direction":"in","protocol":"tcp","port":"80","source_ips":["0.0.0.0/0","::/0"]},
  {"direction":"in","protocol":"tcp","port":"443","source_ips":["0.0.0.0/0","::/0"]},
  {"direction":"in","protocol":"tcp","port":"6443","source_ips":["0.0.0.0/0","::/0"]},
  {"direction":"in","protocol":"tcp","port":"1-65535","source_ips":["${HCLOUD_NODE_SUBNET}"]},
  {"direction":"in","protocol":"udp","port":"1-65535","source_ips":["${HCLOUD_NODE_SUBNET}"]}
]
EOF
}

wait_for_ssh() {
  local host="${1}" attempts="${2:-60}" i
  for ((i = 1; i <= attempts; i++)); do
    if ssh "${SSH_OPTS[@]}" "root@${host}" "echo ok" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  die "SSH did not become available on ${host}"
}

server_public_ip() {
  hcloud server describe "${1}" -o json | jq -r '.server.public_net.ipv4.ip'
}

server_private_ip() {
  hcloud server describe "${1}" -o json | jq -r '.server.private_net[0].ip'
}

provision_network() {
  info "Step 2: Creating or reusing Hetzner private network"
  if hcloud network describe "${HCLOUD_NETWORK_NAME}" >/dev/null 2>&1; then
    ok "Network ${HCLOUD_NETWORK_NAME} already exists"
  else
    hcloud network create --name "${HCLOUD_NETWORK_NAME}" --ip-range 10.0.0.0/8 >/dev/null
    hcloud network add-subnet \
      --type cloud \
      --network-zone "${HCLOUD_NETWORK_ZONE}" \
      --ip-range "${HCLOUD_NODE_SUBNET}" \
      "${HCLOUD_NETWORK_NAME}" >/dev/null
    ok "Network ${HCLOUD_NETWORK_NAME} created"
  fi
}

provision_firewall() {
  info "Step 3: Creating or reusing Hetzner firewall"
  create_firewall_rules
  if hcloud firewall describe "${HCLOUD_FIREWALL_NAME}" >/dev/null 2>&1; then
    ok "Firewall ${HCLOUD_FIREWALL_NAME} already exists"
  else
    hcloud firewall create --name "${HCLOUD_FIREWALL_NAME}" --rules-file "${SCRIPT_DIR}/firewall-rules.json" >/dev/null
    ok "Firewall ${HCLOUD_FIREWALL_NAME} created"
  fi
}

create_server_if_missing() {
  local name="${1}"
  if hcloud server describe "${name}" >/dev/null 2>&1; then
    ok "Server ${name} already exists"
  else
    hcloud server create \
      --name "${name}" \
      --type "${HCLOUD_SERVER_TYPE}" \
      --image ubuntu-24.04 \
      --location "${HCLOUD_LOCATION}" \
      --network "${HCLOUD_NETWORK_NAME}" \
      --firewall "${HCLOUD_FIREWALL_NAME}" \
      --ssh-key "${HCLOUD_SSH_KEY}" \
      >/dev/null
    ok "Server ${name} created"
  fi
}

install_k3s_server() {
  local public_ip="${1}" private_ip="${2}"
  info "Step 4: Installing k3s server on ${CONTROL_PLANE_NAME}"
  wait_for_ssh "${public_ip}"
  ssh "${SSH_OPTS[@]}" "root@${public_ip}" \
    "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${HCLOUD_K3S_VERSION}' INSTALL_K3S_EXEC='server --disable traefik --write-kubeconfig-mode 644 --node-ip ${private_ip} --cluster-cidr ${HCLOUD_CLUSTER_CIDR} --service-cidr ${HCLOUD_SERVICE_CIDR} --kubelet-arg cloud-provider=external --kube-controller-manager-arg cloud-provider=external' sh -" >/dev/null
  ok "k3s server installed"
}

install_k3s_agents() {
  local control_public_ip="${1}" control_private_ip="${2}" token worker_name worker_public_ip worker_private_ip
  token="$(ssh "${SSH_OPTS[@]}" "root@${control_public_ip}" "cat /var/lib/rancher/k3s/server/node-token")"
  for worker_name in $(seq 1 "${WORKER_COUNT}"); do
    local node_name="${CLUSTER_NAME}-agent-${worker_name}"
    create_server_if_missing "${node_name}"
    worker_public_ip="$(server_public_ip "${node_name}")"
    worker_private_ip="$(server_private_ip "${node_name}")"
    wait_for_ssh "${worker_public_ip}"
    ssh "${SSH_OPTS[@]}" "root@${worker_public_ip}" \
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${HCLOUD_K3S_VERSION}' K3S_URL='https://${control_private_ip}:6443' K3S_TOKEN='${token}' INSTALL_K3S_EXEC='agent --node-ip ${worker_private_ip} --kubelet-arg cloud-provider=external' sh -" >/dev/null
    ok "k3s agent installed on ${node_name}"
  done
}

configure_kubeconfig() {
  local control_public_ip="${1}"
  info "Step 5: Fetching kubeconfig"
  scp "${SSH_OPTS[@]}" "root@${control_public_ip}:/etc/rancher/k3s/k3s.yaml" "${KUBECONFIG_PATH}" >/dev/null
  sed -i "s|127.0.0.1|${control_public_ip}|g" "${KUBECONFIG_PATH}"
  export KUBECONFIG="${KUBECONFIG_PATH}"
  kubectl cluster-info >/dev/null
  ok "kubeconfig written to ${KUBECONFIG_PATH}"
}

install_hcloud_ccm() {
  info "Step 6: Installing Hetzner Cloud Controller Manager"
  kubectl -n kube-system create secret generic hcloud \
    --from-literal=token="${HCLOUD_TOKEN}" \
    --from-literal=network="${HCLOUD_NETWORK_NAME}" \
    --dry-run=client -o yaml | kubectl apply -f -
  helm repo add hcloud https://charts.hetzner.cloud >/dev/null 2>&1 || true
  helm repo update hcloud >/dev/null
  helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
    --namespace kube-system \
    --set networking.enabled=true \
    --set networking.clusterCIDR="${HCLOUD_CLUSTER_CIDR}" \
    --wait
  ok "Hetzner CCM ready"
}

render_hetzner_traefik_values() {
  local tmp_file
  tmp_file="$(mktemp)"
  sed -e "s|__HCLOUD_LOCATION__|${HCLOUD_LOCATION}|g" "${SCRIPT_DIR}/traefik-values.yaml" > "${tmp_file}"
  echo "${tmp_file}"
}

info "Hetzner Cloud k3s deploy for ${APP_NAME}"

push_spin_image
provision_network
provision_firewall
create_server_if_missing "${CONTROL_PLANE_NAME}"
CONTROL_PLANE_PUBLIC_IP="$(server_public_ip "${CONTROL_PLANE_NAME}")"
CONTROL_PLANE_PRIVATE_IP="$(server_private_ip "${CONTROL_PLANE_NAME}")"
install_k3s_server "${CONTROL_PLANE_PUBLIC_IP}" "${CONTROL_PLANE_PRIVATE_IP}"
install_k3s_agents "${CONTROL_PLANE_PUBLIC_IP}" "${CONTROL_PLANE_PRIVATE_IP}"
configure_kubeconfig "${CONTROL_PLANE_PUBLIC_IP}"
install_hcloud_ccm
TRAEFIK_VALUES_FILE="$(render_hetzner_traefik_values)"
install_traefik "${TRAEFIK_VALUES_FILE}"
rm -f "${TRAEFIK_VALUES_FILE}"
install_cert_manager
install_runtime_class_manager_and_shim
install_spin_operator
install_keda
deploy_spin_resources "${SCRIPT_DIR}/spinapp.yaml" "${SCRIPT_DIR}/httpscaledobject.yaml"

LB_ADDRESS="$(wait_for_lb_address "${TRAEFIK_NAMESPACE}" traefik)"
ok "Traefik load balancer address: ${LB_ADDRESS}"
verify_http_api "${LB_ADDRESS}"
