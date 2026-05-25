#!/usr/bin/env bash
# Install cert-manager — required by the SpinKube admission webhooks.
set -euo pipefail

CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.14.3}"

echo "==> Installing cert-manager ${CERT_MANAGER_VERSION}..."
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"

echo "==> Waiting for cert-manager webhook to be ready..."
kubectl rollout status deployment/cert-manager         -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager --timeout=120s
kubectl rollout status deployment/cert-manager-webhook    -n cert-manager --timeout=120s

echo "==> cert-manager is ready."
