#!/usr/bin/env bash
set -euo pipefail

AZ_RESOURCE_GROUP="${AZ_RESOURCE_GROUP:-rg-thecalculatorspin-aks}"

if ! command -v az >/dev/null 2>&1; then
  echo "az is required to delete the AKS resource group" >&2
  exit 1
fi

echo "▶ Deleting Azure resource group '${AZ_RESOURCE_GROUP}'..."
if az group exists --name "${AZ_RESOURCE_GROUP}" | grep -q true; then
  az group delete --name "${AZ_RESOURCE_GROUP}" --yes --no-wait
  echo "  ✓ Deletion requested"
else
  echo "  – Resource group not found, skipping"
fi
