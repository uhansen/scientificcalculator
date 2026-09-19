# Terraform deployment for AWS EKS + Envoy Gateway + SpinKube

This Terraform stack provisions a complete AWS environment for
`thecalculatorspin`:

- VPC with public and private subnets across three AZs
- EKS with a private managed node group
- AWS Load Balancer Controller via IRSA
- cert-manager, Runtime Class Manager, Spin shim, spin-operator
- KEDA + KEDA HTTP Add-on
- Envoy Gateway with a public Network Load Balancer
- the private GHCR-hosted Spin application

The existing `deploy/thecalculatordepl-aws/deploy.sh` `eksctl` path remains
available. This Terraform stack is an additional deployment option.

## Prerequisites

- Terraform `>= 1.10`
- `aws`, `kubectl`, and `helm`
- AWS credentials able to create:
  - S3
  - VPC, subnets, internet/NAT gateways
  - IAM roles and policies
  - EKS clusters and managed node groups
- A GHCR token with pull access to `ghcr.io/uhansen/thecalculatorspin`

## Layout

- `bootstrap/` creates the S3 backend bucket
- the root Terraform stack creates AWS infrastructure and Kubernetes resources
- `charts/` contains small local Helm charts for pinned CRDs and app manifests

## 1. Bootstrap remote state

From the repository root:

```sh
cd deploy/thecalculatordepl-aws/terraform/bootstrap
terraform init
terraform apply -var='state_bucket_name=<globally-unique-bucket>' -var='aws_region=eu-north-1'
```

Use the `backend_hcl_snippet` output to create a real `backend.hcl` file next
to the main stack, or copy `../backend.hcl.example` and replace the placeholder
bucket name.

## 2. Configure the main stack

Copy the examples:

```sh
cd ..
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Edit at least:

- `cluster_endpoint_public_access_cidrs`
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
> Because Terraform manages the Kubernetes pull secret, the GHCR token is stored
> in Terraform state. Use the encrypted S3 backend and tightly restrict access
> to that bucket.

## 3. Initialize and apply

```sh
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## 4. Verify

Update kubeconfig if needed:

```sh
aws eks update-kubeconfig --name thecalculatorspin-eks --region eu-north-1
```

Find the public Envoy endpoint:

```sh
kubectl get gateway thecalculatorspin-http -n default -o jsonpath='{.status.addresses[0].value}'
```

Verify the app:

```sh
curl -H 'Host: <app_host>' "http://<gateway-hostname>/?calculate=add(2,3)"
```

Expected response:

```text
5
```

## Notes

- The stack creates a **public HTTP** endpoint backed by an AWS Network Load
  Balancer.
- The VPC uses **three AZs** with **one shared NAT gateway** to balance cost
  and resilience.
- The EKS API is public and private, but the public endpoint is restricted to
  the CIDRs you provide.
- Destroy the application stack before deleting the bootstrap bucket:

```sh
terraform destroy
```

Then remove the backend bucket only if you intentionally want to retire the
state location.
