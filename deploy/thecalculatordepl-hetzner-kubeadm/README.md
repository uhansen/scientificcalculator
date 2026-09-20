# Hetzner Cloud kubeadm deployment

This deployment path adds a **tutorial-inspired Hetzner Cloud kubeadm
cluster** beside the existing `deploy/thecalculatordepl-hetzner/` `k3s`
deployment.

It follows the Hetzner community Kubernetes tutorial more closely:

- `hcloud` CLI creates the network, firewall, and servers
- the nodes are bootstrapped with containerd, kubelet, kubeadm, and kubectl
- the control plane is initialized with `kubeadm init`
- workers join with `kubeadm join`
- Hetzner Cloud Controller Manager, flannel, and Hetzner CSI are installed
- Envoy Gateway, SpinKube, KEDA, and the app are installed on top

The existing `k3s` Hetzner deployment remains unchanged and is still the
simpler option. This kubeadm path exists for users who want a setup that more
closely resembles upstream Kubernetes.

## Prerequisites

- `hcloud`
- `jq`
- `ssh`
- `scp`
- `kubectl`
- `helm`
- `spin`
- `gh`
- `curl`
- `sed`

Environment:

- `HCLOUD_TOKEN`
- `HCLOUD_SSH_KEY` set to an existing Hetzner Cloud SSH key name or ID

## Deploy

Run:

```sh
bash deploy/thecalculatordepl-hetzner-kubeadm/deploy.sh
```

Useful overrides:

- `CLUSTER_NAME`
- `HCLOUD_LOCATION`
- `HCLOUD_NETWORK_ZONE`
- `HCLOUD_IMAGE`
- `CONTROL_PLANE_SERVER_TYPE`
- `WORKER_SERVER_TYPE`
- `WORKER_COUNT`
- `KUBERNETES_VERSION`
- `KUBERNETES_SERIES`
- `KUBECONFIG_PATH`
- `HCLOUD_LOAD_BALANCER_NAME`
- `HCLOUD_LOAD_BALANCER_LOCATION`
- `HCLOUD_LOAD_BALANCER_TYPE`
- `HCLOUD_LOAD_BALANCER_USE_PRIVATE_IP`

The deploy script:

1. pushes the Spin image to GHCR
2. creates or reuses the Hetzner network, firewall, control-plane server, and workers
3. bootstraps containerd and Kubernetes packages on every node
4. initializes the control plane with kubeadm
5. installs Hetzner CCM, flannel, and Hetzner CSI
6. joins workers to the cluster
7. installs Envoy Gateway, SpinKube, KEDA, and the app
8. waits for the Gateway address and verifies the API

## Verify

The script verifies automatically. You can also test manually:

```sh
curl -H 'Host: thecalculatorspin.local' \
  "http://<envoy-load-balancer-address>/?calculate=add(2,3)"
```

Expected response:

```text
5
```

## Teardown

Run:

```sh
bash deploy/thecalculatordepl-hetzner-kubeadm/teardown.sh
```

Behavior:

- removes the app and Envoy/KEDA/SpinKube resources when kubeconfig is present
- deletes the Hetzner servers created for this deployment
- deletes the Hetzner firewall and network
- optionally removes the generated kubeconfig when `DELETE_KUBECONFIG=true`

## Notes

- This path uses **Envoy Gateway** instead of Traefik.
- Hetzner CCM exposes Envoy with a Hetzner Load Balancer using
  `Service type=LoadBalancer` annotations.
- `INSTALL_HCLOUD_CSI=true` by default, so dynamic Hetzner volumes are
  available for workloads that need CSI-backed persistent storage.
- This deployment creates billable Hetzner resources: servers, networking, and
  a load balancer.
