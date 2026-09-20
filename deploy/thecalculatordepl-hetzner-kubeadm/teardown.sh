#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${REPO_ROOT}/deploy/lib/spinkube-common.sh"

CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-hcloud-kubeadm}"
HCLOUD_NETWORK_NAME="${HCLOUD_NETWORK_NAME:-${CLUSTER_NAME}-net}"
HCLOUD_FIREWALL_NAME="${HCLOUD_FIREWALL_NAME:-${CLUSTER_NAME}-fw}"
WORKER_COUNT="${WORKER_COUNT:-2}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${SCRIPT_DIR}/.kubeconfig-${CLUSTER_NAME}}"
DELETE_KUBECONFIG="${DELETE_KUBECONFIG:-false}"
REMOVE_SHARED_ADDONS="${REMOVE_SHARED_ADDONS:-true}"

require_cmds bash hcloud kubectl helm sed

if [[ -f "${KUBECONFIG_PATH}" ]]; then
  export KUBECONFIG="${KUBECONFIG_PATH}"
  info "Removing application resources from the cluster"
  helm uninstall envoy-gateway-resources -n default >/dev/null 2>&1 || true
  helm uninstall "${APP_NAME}" -n default >/dev/null 2>&1 || true

  if [[ "${REMOVE_SHARED_ADDONS}" == "true" ]]; then
    helm uninstall envoy-gateway -n envoy-gateway-system >/dev/null 2>&1 || true
    helm uninstall keda-add-ons-http -n keda >/dev/null 2>&1 || true
    helm uninstall keda -n keda >/dev/null 2>&1 || true
    helm uninstall spin-operator -n spin-operator >/dev/null 2>&1 || true
    helm uninstall runtime-class-manager -n runtime-class-manager >/dev/null 2>&1 || true
    kubectl delete spinappexecutor containerd-shim-spin -n spin-operator --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete shim spin-v2 --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete runtimeclass wasmtime-spin-v2 --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete -f "https://raw.githubusercontent.com/hetznercloud/csi-driver/${HCLOUD_CSI_VERSION:-v2.21.2}/deploy/kubernetes/hcloud-csi.yml" --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete -f "https://github.com/flannel-io/flannel/releases/download/${FLANNEL_VERSION:-v0.28.5}/kube-flannel.yml" --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete -f "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/${HCLOUD_CCM_VERSION:-v1.32.0}/ccm.yaml" --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n kube-system delete secret hcloud --ignore-not-found >/dev/null 2>&1 || true
  fi
fi

echo "▶ Deleting Hetzner servers for '${CLUSTER_NAME}'..."
for name in "${CONTROL_PLANE_NAME:-${CLUSTER_NAME}-control-plane-1}" $(seq 1 "${WORKER_COUNT}" | sed "s|^|${CLUSTER_NAME}-worker-|"); do
  if hcloud server describe "${name}" >/dev/null 2>&1; then
    hcloud server delete "${name}" >/dev/null
    echo "  ✓ Deleted ${name}"
  else
    echo "  – ${name} not found, skipping"
  fi
done

echo "▶ Deleting Hetzner firewall '${HCLOUD_FIREWALL_NAME}'..."
if hcloud firewall describe "${HCLOUD_FIREWALL_NAME}" >/dev/null 2>&1; then
  hcloud firewall delete "${HCLOUD_FIREWALL_NAME}" >/dev/null
  echo "  ✓ Firewall deleted"
else
  echo "  – Firewall not found, skipping"
fi

echo "▶ Deleting Hetzner network '${HCLOUD_NETWORK_NAME}'..."
if hcloud network describe "${HCLOUD_NETWORK_NAME}" >/dev/null 2>&1; then
  hcloud network delete "${HCLOUD_NETWORK_NAME}" >/dev/null
  echo "  ✓ Network deleted"
else
  echo "  – Network not found, skipping"
fi

rm -f "${SCRIPT_DIR}/.firewall-rules.json"
if [[ "${DELETE_KUBECONFIG}" == "true" ]]; then
  rm -f "${KUBECONFIG_PATH}"
fi
