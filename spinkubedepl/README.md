# SpinKube Deployment — `thecalculaterspin`

Deploy the `thecalculaterspin` Spin HTTP app to a local [k3d](https://k3d.io/) Kubernetes cluster using [SpinKube](https://www.spinkube.dev/), with the OCI artifact pushed to [ttl.sh](https://ttl.sh) (ephemeral, zero-auth container registry).

## Folder structure

```
spinkubedepl/
├── README.md
├── scripts/
│   ├── 01-install-cert-manager.sh   # cert-manager (SpinKube webhook prerequisite)
│   ├── 02-install-spinkube.sh       # kwasm-operator + spin-operator (Helm)
│   └── 03-push-and-deploy.sh        # push OCI to ttl.sh and apply SpinApp
└── manifests/
    ├── executor.yaml                # SpinAppExecutor (containerd-shim-spin)
    └── spinapp.yaml                 # SpinApp CRD template (image substituted at deploy time)
```

## Prerequisites

| Tool | Install |
|---|---|
| [k3d](https://k3d.io/) | `brew install k3d` or from releases |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | `brew install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | `brew install helm` |
| [Spin v4](https://spinframework.dev/install) | `curl -fsSL https://spinframework.dev/downloads/install.sh \| bash` |
| Rust + `wasm32-wasip2` target | `rustup target add wasm32-wasip2` |
| [wac-cli](https://github.com/bytecodealliance/wac) | `cargo install wac-cli` |

## Step 1 — Create a k3d cluster (if not already running)

```sh
k3d cluster create uha-cluster \
  --port "8080:80@loadbalancer" \
  --agents 2
```

Verify:
```sh
kubectl get nodes
```

## Step 2 — Install cert-manager

cert-manager is required by the SpinKube operator's admission webhooks.

```sh
chmod +x spinkubedepl/scripts/01-install-cert-manager.sh
./spinkubedepl/scripts/01-install-cert-manager.sh
```

## Step 3 — Install SpinKube

Installs **kwasm-operator** (deploys the `containerd-shim-spin` runtime to nodes) and **spin-operator** (the Kubernetes controller that understands `SpinApp` resources).

```sh
chmod +x spinkubedepl/scripts/02-install-spinkube.sh
./spinkubedepl/scripts/02-install-spinkube.sh
```

What this does:
1. Adds `kwasm` and `spin-operator` Helm repos
2. Installs `kwasm-operator` in the `kwasm` namespace
3. Annotates all nodes with `kwasm.sh/kwasm-node=true` → triggers shim DaemonSet
4. Installs `spin-operator` from `oci://ghcr.io/spinkube/charts/spin-operator`

## Step 4 — Build, push to ttl.sh, and deploy

```sh
chmod +x spinkubedepl/scripts/03-push-and-deploy.sh
./spinkubedepl/scripts/03-push-and-deploy.sh
```

What this does:
1. Runs `spin build` inside `thecalculaterspin/` (compiles Rust + composes with `the-calculater`)
2. Generates a unique image name: `ttl.sh/thecalculaterspin-<uuid>:24h`
3. Pushes the Spin OCI artifact with `spin registry push`
4. Applies `manifests/executor.yaml` (SpinAppExecutor) and a patched `manifests/spinapp.yaml`
5. Waits for the pod to become ready

> **Note:** Images on ttl.sh expire after 24 hours. Re-run `03-push-and-deploy.sh` to redeploy with a fresh image.

### Optional: override TTL
```sh
TTL=1h ./spinkubedepl/scripts/03-push-and-deploy.sh
```

## Step 5 — Access the app

Forward the Service port locally:
```sh
kubectl port-forward svc/thecalculaterspin 8080:80
```

In another terminal:
```sh
# Arithmetic
curl "http://localhost:8080/?expr=add(2,3)"         # → 5
curl "http://localhost:8080/?expr=subtract(10,4)"   # → 6
curl "http://localhost:8080/?expr=multiply(6,7)"    # → 42
curl "http://localhost:8080/?expr=divide(9,3)"      # → 3

# Trigonometric (degrees)
curl "http://localhost:8080/?expr=sin(30)"          # → 0.5
curl "http://localhost:8080/?expr=cos(60)"          # → 0.5
curl "http://localhost:8080/?expr=tan(45)"          # → 1
curl "http://localhost:8080/?expr=arctan(1)"        # → 45

# Modulo / integer division
curl "http://localhost:8080/?expr=mod(10,3)"        # → 1
curl "http://localhost:8080/?expr=div(10,3)"        # → 3

# Logarithmic
curl "http://localhost:8080/?expr=e()"              # → 2.718281828...
curl "http://localhost:8080/?expr=ln(2.718281828)"  # → ~1

# Statistics
curl "http://localhost:8080/?expr=sum(1,2,3,4,5)"  # → 15
curl "http://localhost:8080/?expr=avg(1,2,3,4,5)"  # → 3
```

## Useful commands

```sh
# Check SpinApp status
kubectl get spinapp

# Check the pod
kubectl get pods -l core.spinkube.dev/app-name=thecalculaterspin

# View logs
kubectl logs -l core.spinkube.dev/app-name=thecalculaterspin

# Tear down
kubectl delete spinapp thecalculaterspin
kubectl delete spinappexecutor containerd-shim-spin
```

## How it works

```
ttl.sh (OCI registry)
        │  spin registry push
        ▼
SpinApp CRD  ──── spin-operator ──► Pod (containerd-shim-spin runtime)
                                          │
                                          ▼
                                  thecalculaterspin-composed.wasm
                                  (Spin HTTP handler + the-calculater)
```

The `spin-operator` watches for `SpinApp` resources, creates a Kubernetes Deployment using the `wasmtime-spin-v2` RuntimeClass, and the `containerd-shim-spin` runs the Spin app directly — no Docker image, no full Linux container runtime needed.
