#!/usr/bin/env bash
# Install SpinKube on the local k3d cluster.
#
# This script:
#   1. Installs kwasm-operator (deploys containerd-shim-spin to nodes via DaemonSet)
#   2. Annotates all nodes so kwasm installs the shim
#   3. Installs spin-operator via Helm (creates SpinApp + SpinAppExecutor CRDs)
set -euo pipefail

SPIN_OPERATOR_VERSION="${SPIN_OPERATOR_VERSION:-0.4.0}"

echo "==> Adding Helm repos..."
helm repo add kwasm    https://kwasm.sh/kwasm-operator/
helm repo add spin-operator https://charts.spinkube.dev/
helm repo update

echo "==> Installing kwasm-operator..."
helm upgrade --install kwasm-operator kwasm/kwasm-operator \
  --namespace kwasm \
  --create-namespace \
  --wait

echo "==> Annotating nodes to trigger shim installation..."
kubectl annotate node --all kwasm.sh/kwasm-node=true --overwrite

echo "==> Waiting for kwasm DaemonSet to roll out..."
kubectl rollout status daemonset/kwasm-node-installer -n kwasm --timeout=120s 2>/dev/null || \
  echo "  (DaemonSet may not exist yet — kwasm installed shim directly, continuing)"

echo "==> Installing spin-operator v${SPIN_OPERATOR_VERSION}..."
helm upgrade --install spin-operator \
  oci://ghcr.io/spinkube/charts/spin-operator \
  --version "${SPIN_OPERATOR_VERSION}" \
  --namespace spin-operator \
  --create-namespace \
  --wait

echo "==> SpinKube is ready."
echo ""
echo "Next steps:"
echo "  Apply the SpinAppExecutor:  kubectl apply -f manifests/executor.yaml"
echo "  Then push and deploy:       ./scripts/03-push-and-deploy.sh"
