# Telekom/T Cloud Public CCE deployment

This deployment path targets Telekom/T-Systems **T Cloud Public / Open
Telekom Cloud Cloud Container Engine (CCE)**.

It uses a **bash wrapper** as the user-facing entry point and **Terraform**
internally for:

- creating or reusing a CCE cluster
- creating a node pool for Terraform-created clusters
- retrieving a kubeconfig for the target cluster

After the cluster is ready, the script installs:

- cert-manager
- Runtime Class Manager
- the Spin shim
- spin-operator
- KEDA + KEDA HTTP Add-on
- Envoy Gateway
- the `thecalculatorspin` Spin application

Unlike the AWS and Azure shell deploy scripts, this path uses **Envoy Gateway**
instead of Traefik and exposes it through Telekom/OpenTelekomCloud ELB
annotations on a `Service type=LoadBalancer`.

## Prerequisites

- `kubectl`
- `helm`
- `spin`
- `gh`
- `curl`
- `sed`
- either:
  - `mise` with `terraform@1.16.3`, or
  - a directly installed `terraform`

You also need OpenTelekomCloud/T Cloud Public authentication via either:

- `OS_CLOUD`, or
- the common OpenStack-style environment variables:
  - `OS_AUTH_URL`
  - `OS_REGION_NAME`
  - `OS_PROJECT_NAME`
  - plus one of:
    - `OS_ACCESS_KEY` and `OS_SECRET_KEY`, or
    - `OS_USERNAME`, `OS_PASSWORD`, and `OS_USER_DOMAIN_NAME`

You must provide existing networking inputs for the first version of this
deployment:

- `CCE_VPC_ID`
- `CCE_SUBNET_ID`
- `CCE_AVAILABILITY_ZONE`
- `CCE_SSH_KEY_NAME`

> [!IMPORTANT]
> The OpenTelekomCloud provider documentation notes that CCE must be
> authorized first through the console or an IAM agency. If this step has not
> been done yet, cluster creation can fail with a `CCE is not authorized`
> error.

## Create or reuse behavior

By default, `deploy.sh` creates a new CCE cluster and node pool.

To reuse an existing cluster instead, set one of:

- `CCE_EXISTING_CLUSTER_ID`
- `CCE_EXISTING_CLUSTER_NAME`

In reuse mode, the script still installs or updates the Kubernetes add-ons and
application resources, but it does **not** destroy the cluster during
`teardown.sh`.

## Deploy

Run:

```sh
bash deploy/thecalculatordepl-telekom/deploy.sh
```

Useful overrides:

- `CLUSTER_NAME`
- `CCE_CLUSTER_FLAVOR`
- `CCE_CLUSTER_VERSION`
- `CCE_NODE_FLAVOR`
- `CCE_NODE_COUNT`
- `CCE_NODE_OS`
- `KUBECONFIG_PATH`
- `APP_HOST`
- `IMAGE`

### ELB behavior

By default, the script configures Envoy Gateway to **autocreate a public ELB**
using `kubernetes.io/elb.autocreate`.

Useful overrides:

- `CCE_ELB_ID` to bind Envoy to an existing ELB instead
- `CCE_ELB_CLASS`
- `CCE_ELB_BANDWIDTH_NAME`
- `CCE_ELB_BANDWIDTH_CHARGEMODE`
- `CCE_ELB_BANDWIDTH_SIZE`
- `CCE_ELB_BANDWIDTH_SHARETYPE`
- `CCE_ELB_EIP_TYPE`
- `CCE_ELB_L7_FLAVOR_NAME`
- `CCE_ELB_L4_FLAVOR_NAME`
- `CCE_ELB_AVAILABILITY_ZONE`

## Verify

The deploy script waits for the Gateway address and verifies the app
automatically. You can also verify it manually:

```sh
curl -H 'Host: thecalculatorspin.local' \
  "http://<gateway-address>/?calculate=add(2,3)"
```

Expected response:

```text
5
```

## Teardown

Run:

```sh
bash deploy/thecalculatordepl-telekom/teardown.sh
```

Behavior:

- always removes the app and Envoy Gateway routing resources if kubeconfig is
  available
- destroys the Terraform-created CCE cluster and node pool
- leaves external VPC/subnet resources untouched
- skips Terraform cluster destruction when the deployment reused an existing
  cluster

When reusing a cluster, shared add-ons are left in place by default. Set:

```sh
REMOVE_SHARED_ADDONS=true
```

if you want `teardown.sh` to remove the Envoy/KEDA/SpinKube add-ons as well.
