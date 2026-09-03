#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-north-1}"
CLUSTER_NAME="${CLUSTER_NAME:-thecalculatorspin-eks}"

if ! command -v eksctl >/dev/null 2>&1; then
  echo "eksctl is required to delete the EKS cluster" >&2
  exit 1
fi

echo "▶ Deleting EKS cluster '${CLUSTER_NAME}' in region '${AWS_REGION}'..."
if eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
  echo "  ✓ Cluster deleted"
else
  echo "  – Cluster not found, skipping"
fi
