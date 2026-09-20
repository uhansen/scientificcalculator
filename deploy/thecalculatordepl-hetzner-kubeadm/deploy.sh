#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

HCLOUD_LOCATION="${HCLOUD_LOCATION:-fsn1}"
HCLOUD_NETWORK_ZONE="${HCLOUD_NETWORK_ZONE:-eu-central}"
HCLOUD_IMAGE="${HCLOUD_IMAGE:-ubuntu-24.04}"
CONTROL_PLANE_SERVER_TYPE="${CONTROL_PLANE_SERVER_TYPE:-cx23}"
WORKER_SERVER_TYPE="${WORKER_SERVER_TYPE:-cx33}"
CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-hcloud-kubeadm}"
HCLOUD_NETWORK_NAME="${HCLOUD_NETWORK_NAME:-${CLUSTER_NAME}-net}"
HCLOUD_FIREWALL_NAME="${HCLOUD_FIREWALL_NAME:-${CLUSTER_NAME}-fw}"
HCLOUD_LOAD_BALANCER_NAME="${HCLOUD_LOAD_BALANCER_NAME:-${CLUSTER_NAME}-envoy}"
HCLOUD_LOAD_BALANCER_LOCATION="${HCLOUD_LOAD_BALANCER_LOCATION:-${HCLOUD_LOCATION}}"
HCLOUD_LOAD_BALANCER_TYPE="${HCLOUD_LOAD_BALANCER_TYPE:-lb11}"
HCLOUD_LOAD_BALANCER_USE_PRIVATE_IP="${HCLOUD_LOAD_BALANCER_USE_PRIVATE_IP:-true}"
HCLOUD_SSH_KEY="${HCLOUD_SSH_KEY:-}"
HCLOUD_NETWORK_RANGE="${HCLOUD_NETWORK_RANGE:-10.0.0.0/16}"
HCLOUD_NODE_SUBNET="${HCLOUD_NODE_SUBNET:-10.0.0.0/16}"
POD_NETWORK_CIDR="${POD_NETWORK_CIDR:-10.244.0.0/16}"
CONTROL_PLANE_NAME="${CONTROL_PLANE_NAME:-${CLUSTER_NAME}-control-plane-1}"
WORKER_COUNT="${WORKER_COUNT:-2}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${SCRIPT_DIR}/.kubeconfig-${CLUSTER_NAME}}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.36.2}"
KUBERNETES_SERIES="${KUBERNETES_SERIES:-v$(printf '%s' "${KUBERNETES_VERSION#v}" | cut -d. -f1,2)}"
CONTAINERD_VERSION="${CONTAINERD_VERSION:-2.3.1}"
RUNC_VERSION="${RUNC_VERSION:-1.4.3}"
CNI_PLUGINS_VERSION="${CNI_PLUGINS_VERSION:-1.9.1}"
HCLOUD_CCM_VERSION="${HCLOUD_CCM_VERSION:-v1.32.0}"
FLANNEL_VERSION="${FLANNEL_VERSION:-v0.28.5}"
HCLOUD_CSI_VERSION="${HCLOUD_CSI_VERSION:-v2.21.2}"
INSTALL_HCLOUD_CSI="${INSTALL_HCLOUD_CSI:-true}"
SSH_SOURCE_CIDRS="${SSH_SOURCE_CIDRS:-0.0.0.0/0,::/0}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)

require_cmds bash hcloud jq ssh scp kubectl helm spin gh curl sed awk grep
[[ -n "${HCLOUD_TOKEN:-}" ]] || die "HCLOUD_TOKEN must be set"
[[ -n "${HCLOUD_SSH_KEY}" ]] || die "HCLOUD_SSH_KEY must be set to an existing Hetzner Cloud SSH key name or ID"

ssh_run() {
  local host="${1}"
  shift
  ssh "${SSH_OPTS[@]}" "root@${host}" "$@"
}

scp_from() {
  local host="${1}" remote_path="${2}" local_path="${3}"
  scp "${SSH_OPTS[@]}" "root@${host}:${remote_path}" "${local_path}" >/dev/null
}

wait_for_ssh() {
  local host="${1}" attempts="${2:-90}" i
  for ((i = 1; i <= attempts; i++)); do
    if ssh_run "${host}" "echo ok" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  die "SSH did not become available on ${host}"
}

wait_for_node_ready() {
  local node_name="${1}" attempts="${2:-90}" i
  for ((i = 1; i <= attempts; i++)); do
    if kubectl get node "${node_name}" >/dev/null 2>&1; then
      local ready
      ready="$(kubectl get node "${node_name}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || true)"
      if [[ "${ready}" == "True" ]]; then
        return 0
      fi
    fi
    sleep 10
  done
  die "Node ${node_name} did not become Ready"
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

server_public_ip() {
  hcloud server describe "${1}" -o json | jq -r '.server.public_net.ipv4.ip'
}

server_private_ip() {
  hcloud server describe "${1}" -o json | jq -r '.server.private_net[0].ip'
}

server_id() {
  hcloud server describe "${1}" -o json | jq -r '.server.id'
}

network_id() {
  hcloud network describe "${1}" -o json | jq -r '.network.id'
}

split_csv_to_json_array() {
  local input="${1}" sep="${2:-,}"
  awk -v value="${input}" -v FS="${sep}" 'BEGIN { printf "["; for (i = 1; i <= split(value, parts, FS); i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i]); if (parts[i] == "") continue; if (printed++) printf ","; printf "\"%s\"", parts[i] } printf "]" }'
}

create_firewall_rules() {
  local firewall_rules_file="${SCRIPT_DIR}/.firewall-rules.json"
  local ssh_sources_json
  ssh_sources_json="$(split_csv_to_json_array "${SSH_SOURCE_CIDRS}")"
  cat > "${firewall_rules_file}" <<EOF
[
  {"direction":"in","protocol":"tcp","port":"22","source_ips":${ssh_sources_json}},
  {"direction":"in","protocol":"tcp","port":"80","source_ips":["0.0.0.0/0","::/0"]},
  {"direction":"in","protocol":"tcp","port":"443","source_ips":["0.0.0.0/0","::/0"]},
  {"direction":"in","protocol":"tcp","port":"6443","source_ips":["0.0.0.0/0","::/0"]},
  {"direction":"in","protocol":"tcp","port":"1-65535","source_ips":["${HCLOUD_NODE_SUBNET}"]},
  {"direction":"in","protocol":"udp","port":"1-65535","source_ips":["${HCLOUD_NODE_SUBNET}"]}
]
EOF
}

provision_network() {
  info "Step 2: Creating or reusing Hetzner network"
  if hcloud network describe "${HCLOUD_NETWORK_NAME}" >/dev/null 2>&1; then
    ok "Network ${HCLOUD_NETWORK_NAME} already exists"
  else
    hcloud network create --name "${HCLOUD_NETWORK_NAME}" --ip-range "${HCLOUD_NETWORK_RANGE}" >/dev/null
    hcloud network add-subnet "${HCLOUD_NETWORK_NAME}" \
      --network-zone "${HCLOUD_NETWORK_ZONE}" \
      --type server \
      --ip-range "${HCLOUD_NODE_SUBNET}" >/dev/null
    ok "Network ${HCLOUD_NETWORK_NAME} created"
  fi
  HCLOUD_NETWORK_ID="$(network_id "${HCLOUD_NETWORK_NAME}")"
}

provision_firewall() {
  info "Step 3: Creating or reusing Hetzner firewall"
  create_firewall_rules
  if hcloud firewall describe "${HCLOUD_FIREWALL_NAME}" >/dev/null 2>&1; then
    ok "Firewall ${HCLOUD_FIREWALL_NAME} already exists"
  else
    hcloud firewall create --name "${HCLOUD_FIREWALL_NAME}" --rules-file "${SCRIPT_DIR}/.firewall-rules.json" >/dev/null
    ok "Firewall ${HCLOUD_FIREWALL_NAME} created"
  fi
}

create_server_if_missing() {
  local name="${1}" server_type="${2}"
  if hcloud server describe "${name}" >/dev/null 2>&1; then
    ok "Server ${name} already exists"
  else
    hcloud server create \
      --name "${name}" \
      --type "${server_type}" \
      --image "${HCLOUD_IMAGE}" \
      --location "${HCLOUD_LOCATION}" \
      --network "${HCLOUD_NETWORK_NAME}" \
      --firewall "${HCLOUD_FIREWALL_NAME}" \
      --ssh-key "${HCLOUD_SSH_KEY}" >/dev/null
    ok "Server ${name} created"
  fi
}

bootstrap_node() {
  local node_name="${1}" host="${2}" private_ip="${3}"
  info "Bootstrapping Kubernetes prerequisites on ${node_name}"
  wait_for_ssh "${host}"
  ssh "${SSH_OPTS[@]}" "root@${host}" \
    "NODE_PRIVATE_IP='${private_ip}' KUBERNETES_SERIES='${KUBERNETES_SERIES}' CONTAINERD_VERSION='${CONTAINERD_VERSION}' RUNC_VERSION='${RUNC_VERSION}' CNI_PLUGINS_VERSION='${CNI_PLUGINS_VERSION}' bash -s" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg jq socat conntrack

cat <<'EOF' >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<'EOF' >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward                = 1
net.ipv6.conf.default.forwarding   = 1
EOF
sysctl --system >/dev/null

if ! command -v containerd >/dev/null 2>&1 || [[ ! -x /usr/local/bin/containerd ]]; then
  curl -fsSLo /tmp/containerd.tgz "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
  tar Czxvf /usr/local /tmp/containerd.tgz >/dev/null
fi

curl -fsSLo /usr/lib/systemd/system/containerd.service \
  https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
systemctl daemon-reload

curl -fsSLo /tmp/runc.amd64 "https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.amd64"
install -m 755 /tmp/runc.amd64 /usr/local/sbin/runc

mkdir -p /opt/cni/bin
curl -fsSLo /tmp/cni.tgz "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-v${CNI_PLUGINS_VERSION}.tgz"
tar Czxvf /opt/cni/bin /tmp/cni.tgz >/dev/null

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd

mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_SERIES}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_SERIES}/deb/ /
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl >/dev/null

cat <<EOF >/etc/default/kubelet
KUBELET_EXTRA_ARGS=--cloud-provider=external --node-ip=${NODE_PRIVATE_IP}
EOF
systemctl enable kubelet
systemctl daemon-reload
systemctl restart kubelet
REMOTE
  ok "${node_name} bootstrapped"
}

initialize_control_plane() {
  local public_ip="${1}" private_ip="${2}"
  info "Initializing kubeadm control plane on ${CONTROL_PLANE_NAME}"
  ssh "${SSH_OPTS[@]}" "root@${public_ip}" \
    "KUBERNETES_VERSION='${KUBERNETES_VERSION}' POD_NETWORK_CIDR='${POD_NETWORK_CIDR}' CONTROL_PRIVATE_IP='${private_ip}' CONTROL_PUBLIC_IP='${public_ip}' bash -s" <<'REMOTE'
set -euo pipefail
if [[ ! -f /etc/kubernetes/admin.conf ]]; then
  kubeadm config images pull
  kubeadm init \
    --pod-network-cidr="${POD_NETWORK_CIDR}" \
    --kubernetes-version="${KUBERNETES_VERSION}" \
    --upload-certs \
    --apiserver-cert-extra-sans "${CONTROL_PRIVATE_IP},${CONTROL_PUBLIC_IP}"
fi
mkdir -p /root/.kube
cp -f /etc/kubernetes/admin.conf /root/.kube/config
REMOTE
  ok "Control plane initialized"
}

configure_kubeconfig() {
  local control_public_ip="${1}"
  info "Fetching kubeconfig"
  scp_from "${control_public_ip}" "/etc/kubernetes/admin.conf" "${KUBECONFIG_PATH}"
  sed -i "s|https://.*:6443|https://${control_public_ip}:6443|g" "${KUBECONFIG_PATH}"
  chmod 600 "${KUBECONFIG_PATH}"
  export KUBECONFIG="${KUBECONFIG_PATH}"
  kubectl cluster-info >/dev/null
  ok "kubeconfig written to ${KUBECONFIG_PATH}"
}

install_hcloud_ccm() {
  info "Installing Hetzner Cloud Controller Manager"
  kubectl -n kube-system create secret generic hcloud \
    --from-literal=token="${HCLOUD_TOKEN}" \
    --from-literal=network="${HCLOUD_NETWORK_ID}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl apply -f "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/${HCLOUD_CCM_VERSION}/ccm.yaml" >/dev/null
  kubectl -n kube-system patch deployment hcloud-cloud-controller-manager --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"HCLOUD_NETWORK","valueFrom":{"secretKeyRef":{"name":"hcloud","key":"network"}}}}]' >/dev/null 2>&1 || true
  kubectl rollout status deployment/hcloud-cloud-controller-manager -n kube-system --timeout=300s >/dev/null
  ok "Hetzner CCM ready"
}

install_flannel() {
  info "Installing flannel ${FLANNEL_VERSION}"
  kubectl apply -f "https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION}/kube-flannel.yml" >/dev/null
  kubectl -n kube-flannel patch daemonset kube-flannel-ds --type merge \
    -p '{"spec":{"template":{"spec":{"tolerations":[{"key":"node.cloudprovider.kubernetes.io/uninitialized","operator":"Exists","effect":"NoSchedule"}]}}}}' >/dev/null 2>&1 || true
  kubectl -n kube-system patch deployment coredns --type merge \
    -p '{"spec":{"template":{"spec":{"tolerations":[{"key":"node.cloudprovider.kubernetes.io/uninitialized","operator":"Exists","effect":"NoSchedule"}]}}}}' >/dev/null 2>&1 || true
  kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s >/dev/null
  kubectl rollout status deployment/coredns -n kube-system --timeout=300s >/dev/null
  ok "flannel ready"
}

provider_id_for() {
  printf 'hcloud://%s' "$(server_id "$1")"
}

ensure_provider_ids() {
  local node_name current provider
  info "Ensuring provider IDs are set on nodes"
  for node_name in "${CONTROL_PLANE_NAME}" $(seq 1 "${WORKER_COUNT}" | sed "s|^|${CLUSTER_NAME}-worker-|"); do
    provider="$(provider_id_for "${node_name}")"
    current="$(kubectl get node "${node_name}" -o jsonpath='{.spec.providerID}' 2>/dev/null || true)"
    if [[ "${current}" != "${provider}" ]]; then
      kubectl patch node "${node_name}" -p "{\"spec\":{\"providerID\":\"${provider}\"}}" >/dev/null
    fi
  done
  ok "Provider IDs verified"
}

install_hcloud_csi() {
  if [[ "${INSTALL_HCLOUD_CSI}" != "true" ]]; then
    warn "Skipping Hetzner CSI driver because INSTALL_HCLOUD_CSI=${INSTALL_HCLOUD_CSI}"
    return 0
  fi

  info "Installing Hetzner CSI driver ${HCLOUD_CSI_VERSION}"
  kubectl apply -f "https://raw.githubusercontent.com/hetznercloud/csi-driver/${HCLOUD_CSI_VERSION}/deploy/kubernetes/hcloud-csi.yml" >/dev/null
  kubectl rollout status deployment/hcloud-csi-controller -n kube-system --timeout=300s >/dev/null
  kubectl rollout status daemonset/hcloud-csi-node -n kube-system --timeout=300s >/dev/null
  ok "Hetzner CSI ready"
}

control_join_command() {
  ssh_run "${CONTROL_PLANE_PUBLIC_IP}" "kubeadm token create --print-join-command"
}

join_workers() {
  local join_command worker_name worker_public_ip worker_private_ip
  join_command="$(control_join_command)"
  info "Joining worker nodes"
  for worker_name in $(seq 1 "${WORKER_COUNT}"); do
    local node_name="${CLUSTER_NAME}-worker-${worker_name}"
    worker_public_ip="$(server_public_ip "${node_name}")"
    worker_private_ip="$(server_private_ip "${node_name}")"
    if kubectl get node "${node_name}" >/dev/null 2>&1; then
      ok "Worker ${node_name} already joined"
      continue
    fi
    ssh "${SSH_OPTS[@]}" "root@${worker_public_ip}" "KUBELET_NODE_IP='${worker_private_ip}' bash -s" <<REMOTE
set -euo pipefail
if [[ -f /etc/kubernetes/kubelet.conf ]]; then
  kubeadm reset -f >/dev/null 2>&1 || true
fi
${join_command}
systemctl restart kubelet
REMOTE
    wait_for_node_ready "${node_name}"
    ok "Worker ${node_name} joined"
  done
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
      load-balancer.hetzner.cloud/name: "${HCLOUD_LOAD_BALANCER_NAME}"
      load-balancer.hetzner.cloud/location: "${HCLOUD_LOAD_BALANCER_LOCATION}"
      load-balancer.hetzner.cloud/type: "${HCLOUD_LOAD_BALANCER_TYPE}"
      load-balancer.hetzner.cloud/use-private-ip: "${HCLOUD_LOAD_BALANCER_USE_PRIVATE_IP}"
keda:
  namespace: keda
  interceptorServiceName: keda-add-ons-http-interceptor-proxy
  interceptorServicePort: 8080
EOF

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

info "Hetzner Cloud kubeadm deploy for ${APP_NAME}"

push_spin_image
provision_network
provision_firewall
create_server_if_missing "${CONTROL_PLANE_NAME}" "${CONTROL_PLANE_SERVER_TYPE}"
for worker_name in $(seq 1 "${WORKER_COUNT}"); do
  create_server_if_missing "${CLUSTER_NAME}-worker-${worker_name}" "${WORKER_SERVER_TYPE}"
done

CONTROL_PLANE_PUBLIC_IP="$(server_public_ip "${CONTROL_PLANE_NAME}")"
CONTROL_PLANE_PRIVATE_IP="$(server_private_ip "${CONTROL_PLANE_NAME}")"

bootstrap_node "${CONTROL_PLANE_NAME}" "${CONTROL_PLANE_PUBLIC_IP}" "${CONTROL_PLANE_PRIVATE_IP}"
for worker_name in $(seq 1 "${WORKER_COUNT}"); do
  node_name="${CLUSTER_NAME}-worker-${worker_name}"
  bootstrap_node "${node_name}" "$(server_public_ip "${node_name}")" "$(server_private_ip "${node_name}")"
done

initialize_control_plane "${CONTROL_PLANE_PUBLIC_IP}" "${CONTROL_PLANE_PRIVATE_IP}"
configure_kubeconfig "${CONTROL_PLANE_PUBLIC_IP}"
install_hcloud_ccm
install_flannel
join_workers
ensure_provider_ids
install_hcloud_csi
install_cert_manager
install_runtime_class_manager_and_shim
install_spin_operator
install_keda
install_envoy_gateway
deploy_envoy_and_application

GATEWAY_ADDRESS="$(wait_for_gateway_address default "${APP_NAME}-http")"
ok "Envoy Gateway public address: ${GATEWAY_ADDRESS}"
verify_http_api "${GATEWAY_ADDRESS}"
