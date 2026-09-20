# Terraform deployment for Azure AKS + Envoy Gateway + SpinKube

This Terraform stack provisions a complete Azure environment for
`thecalculatorspin`:

- Resource group, VNet, and a node subnet
- AKS with Azure CNI Overlay networking and a default node pool
- cert-manager, Runtime Class Manager, Spin shim, spin-operator
- KEDA + KEDA HTTP Add-on
- Envoy Gateway with a public Azure Load Balancer
- the private GHCR-hosted Spin application

AKS's built-in cloud provider provisions a Standard SKU Azure Load Balancer
automatically for a `Service type=LoadBalancer`, so **no separate
load-balancer controller** (and no Workload Identity / IRSA-equivalent) is
installed or required — this is the main structural difference from the AWS
EKS Terraform stack.

The existing `deploy/thecalculatordepl-azure/deploy.sh` `az aks` path remains
available. This Terraform stack is an additional deployment option.

## Prerequisites

- Terraform `>= 1.10`
- `az`, `kubectl`, and `helm`
- An authenticated `az login` session able to create:
  - Storage accounts and blob containers
  - Resource groups, VNets, subnets
  - AKS clusters and node pools
  - Role assignments (`Storage Blob Data Contributor` on the state storage
    account, scoped to your own identity)
- A GHCR token with pull access to `ghcr.io/uhansen/thecalculatorspin`

## Layout

- `bootstrap/` creates the Storage Account backend
- the root Terraform stack creates Azure infrastructure and Kubernetes
  resources
- `charts/` contains small local Helm charts for pinned CRDs and app
  manifests (reused, almost unchanged, from the AWS EKS stack — they are
  cloud-agnostic)

## 1. Bootstrap remote state

From the repository root:

```sh
cd deploy/thecalculatordepl-azure/terraform/bootstrap
terraform init
terraform apply -var='state_storage_account_name=<globally-unique-name>' -var='location=denmarkeast'
```

Use the `backend_hcl_snippet` output to create a real `backend.hcl` file next
to the main stack, or copy `../backend.hcl.example` and replace the
placeholders.

## 2. Configure the main stack

Copy the examples:

```sh
cd ..
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Edit at least:

- `authorized_ip_ranges`
- `ghcr_username`
- `ghcr_token`
- `app_host`

Example `terraform.tfvars` additions:

```hcl
app_host      = "thecalculatorspin.example.internal"
ghcr_username = "uhansen"
ghcr_token    = "replace-me"
```

> [!WARNING]
> Because Terraform manages the Kubernetes pull secret, the GHCR token is
> stored in Terraform state. Use the encrypted Storage Account backend and
> tightly restrict access to that storage account.

## 3. Initialize and apply

```sh
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## 4. Verify

Update kubeconfig if needed:

```sh
az aks get-credentials --resource-group rg-thecalculatorspin-aks --name thecalculatorspin-aks --overwrite-existing
```

Find the public Envoy endpoint:

```sh
kubectl get gateway thecalculatorspin-http -n default -o jsonpath='{.status.addresses[0].value}'
```

Verify the app:

```sh
curl -H 'Host: <app_host>' "http://<gateway-address>/?calculate=add(2,3)"
```

Expected response:

```text
5
```

## Notes

- The stack creates a **public HTTP** endpoint backed by a Standard SKU Azure
  Load Balancer, provisioned natively by AKS's cloud provider — no additional
  controller is installed.
- Uses **Azure CNI Overlay** networking: nodes consume VNet IPs from the node
  subnet, pods use a separate overlay CIDR, avoiding VNet IP exhaustion.
- The AKS API is public, but restricted to the CIDRs you provide via
  `authorized_ip_ranges`.
- The Terraform state backend authenticates with Azure AD
  (`use_azuread_auth = true`); the identity running `terraform init`/`apply`
  needs the `Storage Blob Data Contributor` role on the state storage account
  (granted automatically to the bootstrap caller).
- Destroy the application stack before deleting the bootstrap storage
  account:

```sh
terraform destroy
```

Then remove the backend storage account only if you intentionally want to
retire the state location.
