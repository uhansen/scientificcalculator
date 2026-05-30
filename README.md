# Scientific Calculator – WASM Components

WebAssembly components built in Rust, TypeScript, C#, and Python, following the [Bytecode Alliance guides](https://component-model.bytecodealliance.org/language-support/).

| Component | Language | Interface |
|---|---|---|
| `arithmetic-calculator` | Rust | `add` `subtract` `multiply` `divide` |
| `trigonometric-calculator` | Rust | `sin` `cos` `tan` `arctan` |
| `moddiv` | TypeScript | `mod` `div` |
| `logaritmic-calculator` | C# / .NET 10 | `e` `ln` |
| `statistics-calculator` | Python | `sum` `avg` |
| `the-calculator` | Composed (all 5) | `calculate(string) → string` |
| `thecalculatorspin` | Rust (Spin HTTP app) | HTTP API wrapping `the-calculator` |

## Components

### `the-calculator` (Rust shell — composed from all five sub-components)
A composed WASM component that bundles all five calculators into a single binary.
Exports the `buildbyhansen:the-calculator/calculator@0.1.0` interface with one method:

```
calculate(expr: string) -> string
```

Accepts function-call style expressions and routes them to the correct sub-component:

| Expression | Routes to |
|---|---|
| `add(2,3)` `subtract(5,1)` `multiply(2,4)` `divide(9,3)` | arithmetic |
| `sin(45)` `cos(60)` `tan(30)` `arctan(1)` | trigonometric |
| `mod(7,3)` `div(7,3)` | moddiv |
| `e()` `ln(2.718)` | logaritmic |
| `sum(1,2,3)` `avg(1,2,3,4)` | statistics |

### `arithmetic-calculator` (Rust, wasm32-wasip2)
Exports an `arithmetic` interface with:
- `add(x: f64, y: f64) -> f64`
- `subtract(x: f64, y: f64) -> f64`
- `multiply(x: f64, y: f64) -> f64`
- `divide(x: f64, y: f64) -> result<f64, string>` — returns an error on division by zero

### `trigonometric-calculator` (Rust, wasm32-wasip2)
Exports a `trigonometric` interface with (angles in degrees):
- `sin(degrees: f64) -> f64`
- `cos(degrees: f64) -> f64`
- `tan(degrees: f64) -> f64`
- `arctan(value: f64) -> f64` — returns degrees

### `moddiv` (TypeScript → WASM via jco)
Exports a `moddiv` interface with:
- `mod(x: f64, y: f64) -> f64` — remainder of x divided by y
- `div(x: f64, y: f64) -> f64` — quotient of x divided by y

### `logaritmic-calculator` (C# / .NET 10, componentize-dotnet)
Exports a `logaritmic` interface with:
- `e() -> f64` — Euler's number (≈ 2.71828…)
- `ln(x: f64) -> f64` — natural logarithm of x

### `statistics-calculator` (Python, componentize-py)
Exports a `statistics` interface with:
- `sum(numbers: list<f64>) -> f64` — sum of a list of numbers
- `avg(numbers: list<f64>) -> f64` — arithmetic mean (returns 0.0 for empty list)

### `thecalculatorspin` (Rust, Spin v4 HTTP app)
An HTTP application built with [Spin](https://spinframework.dev) that wraps `the-calculator` and exposes it over HTTP. Send a GET request with an `?calculate=` query parameter; the result is returned as plain text.

### `thecalculatorcli` (Rust, WASI CLI)
An interactive command-line REPL that imports `the-calculator` via WIT and is composed with it using `wac`. Run with `wasmtime run` for an interactive calculator prompt.

## Prerequisites

Install the tools required for the languages you want to build. All five are needed to compose `the-calculator`.

### All components
```sh
# Rust toolchain + WASI target
rustup target add wasm32-wasip2

# WASM inspection tool
cargo install --locked wasm-tools

# Component composition tool (wac)
cargo install wac-cli
```

### `arithmetic-calculator` and `trigonometric-calculator` (Rust)
No additional tools — the Rust toolchain above is sufficient.

### `moddiv` (TypeScript)
Requires [Node.js](https://nodejs.org/) ≥ 18. npm dependencies (`jco`, `typescript`) are installed locally via `npm install`.

### `logaritmic-calculator` (C# / .NET)
Requires [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

### `statistics-calculator` (Python)
Requires Python 3.10+ and `componentize-py`:
```sh
pip install componentize-py
```

### `thecalculatorspin` (Spin HTTP app)
Requires [Spin v4](https://spinframework.dev/install) in addition to the Rust toolchain and `wac-cli` listed above:
```sh
# Install Spin
curl -fsSL https://spinframework.dev/downloads/install.sh | bash
```

## Build

The five sub-components must be built before the composed `the-calculator` binary can be produced. Follow steps 1–5 in order, then run the composition in step 6.

### Step 1 — Rust: arithmetic-calculator, trigonometric-calculator, and the-calculator shell

The Cargo workspace at the repo root builds all three Rust crates at once:

```sh
cargo build --target wasm32-wasip2 --release
```

Output (in the shared `target/` directory):

```
target/wasm32-wasip2/release/arithmetic_calculator.wasm
target/wasm32-wasip2/release/trigonometric_calculator.wasm
target/wasm32-wasip2/release/the_calculator.wasm   ← shell (imports not yet satisfied)
```

To build a single crate:
```sh
cargo build -p arithmetic-calculator --target wasm32-wasip2 --release
cargo build -p trigonometric-calculator --target wasm32-wasip2 --release
cargo build -p the-calculator --target wasm32-wasip2 --release
```

### Step 2 — TypeScript: moddiv

```sh
cd moddiv
npm install          # installs jco and typescript locally
npm run build        # tsc (TS → JS) then jco componentize (JS → WASM)
cd ..
```

Output: `moddiv/moddiv.wasm`

### Step 3 — C#: logaritmic-calculator

```sh
cd logaritmic-calculator
dotnet build -c Release
cd ..
```

Output: `logaritmic-calculator/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculator.wasm`

### Step 4 — Python: statistics-calculator

```sh
cd statistics-calculator
componentize-py --wit-path wit/component.wit --world statistics-calculator componentize app -o statistics-calculator.wasm
cd ..
```

Output: `statistics-calculator/statistics-calculator.wasm`

### Step 5 — Verify sub-components (optional)

Confirm each sub-component exports the expected interface:

```sh
wasm-tools component wit target/wasm32-wasip2/release/arithmetic_calculator.wasm
wasm-tools component wit target/wasm32-wasip2/release/trigonometric_calculator.wasm
wasm-tools component wit moddiv/moddiv.wasm
wasm-tools component wit logaritmic-calculator/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculator.wasm
wasm-tools component wit statistics-calculator/statistics-calculator.wasm
```

### Step 6 — Compose: the-calculator

`wac plug` wires the exports of each sub-component into the matching imports of the shell, producing a fully self-contained binary. All five sub-components are embedded; only WASI host imports remain external.

```sh
wac plug \
  --plug target/wasm32-wasip2/release/arithmetic_calculator.wasm \
  --plug target/wasm32-wasip2/release/trigonometric_calculator.wasm \
  --plug moddiv/moddiv.wasm \
  --plug logaritmic-calculator/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculator.wasm \
  --plug statistics-calculator/statistics-calculator.wasm \
  target/wasm32-wasip2/release/the_calculator.wasm \
  -o the-calculator/the-calculator.wasm
```

Output: `the-calculator/the-calculator.wasm`

Verify the composed component exposes only the single `calculate` export and no sub-component imports:

```sh
wasm-tools component wit the-calculator/the-calculator.wasm | grep -E "^  (import|export)"
```

### Step 7 — Build and run: thecalculatorspin

```sh
cd thecalculatorspin

# Compile to WASM and compose with the-calculator
spin build

# Start the HTTP server
spin up --listen 127.0.0.1:3000
```

Test in another terminal:
```sh
curl "http://127.0.0.1:3000/?calculate=add(2,3)"      # → 5
curl "http://127.0.0.1:3000/?calculate=sin(30)"        # → 0.5
curl "http://127.0.0.1:3000/?calculate=multiply(6,7)"  # → 42
```

See **[Run with Spin](#run-with-spin-thecalculatorspin)** below for the full list of curl examples.

## Run with wasmtime

Requires [wasmtime](https://wasmtime.dev/) ≥ 18. Arguments use [WAVE syntax](https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-wave#readme) — the function call and its arguments are passed as a single quoted string.

### `the-calculator` (composed component)

```sh
# Arithmetic
wasmtime run --invoke 'calculate("add(2,2)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("subtract(10,3)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("multiply(6,7)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("divide(9,3)")' the-calculator/the-calculator.wasm

# Trigonometric (degrees)
wasmtime run --invoke 'calculate("sin(90)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("cos(0)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("tan(45)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("arctan(1)")' the-calculator/the-calculator.wasm

# Modulo / integer division
wasmtime run --invoke 'calculate("mod(10,3)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("div(10,3)")' the-calculator/the-calculator.wasm

# Logarithmic
wasmtime run --invoke 'calculate("e()")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("ln(2.718281828)")' the-calculator/the-calculator.wasm

# Statistics (variable number of arguments)
wasmtime run --invoke 'calculate("sum(1,2,3,4,5)")' the-calculator/the-calculator.wasm
wasmtime run --invoke 'calculate("avg(1,2,3,4,5)")' the-calculator/the-calculator.wasm
```

Errors are returned as strings:

```sh
wasmtime run --invoke 'calculate("divide(5,0)")' the-calculator/the-calculator.wasm
# → "Error: division by zero"

wasmtime run --invoke 'calculate("unknown(1)")' the-calculator/the-calculator.wasm
# → "Error: Unknown function: 'unknown'"
```




## Run interactively with `thecalculatorcli`

`thecalculatorcli` is a WASI CLI Rust component that provides an interactive calculator prompt. It imports `the-calculator` and is composed with it using `wac`.

### Prerequisites

- Rust with `wasm32-wasip2` target: `rustup target add wasm32-wasip2`
- `wac-cli`: `cargo install wac-cli`
- `wasmtime` ≥ 18

### Build

```sh
cd thecalculatorcli
cargo build --target wasm32-wasip2 --release
wac plug \
  --plug ../the-calculator/the-calculator.wasm \
  target/wasm32-wasip2/release/thecalculatorcli.wasm \
  -o thecalculatorcli-composed.wasm
```

### Run

```sh
wasmtime run thecalculatorcli/thecalculatorcli-composed.wasm
```

Example session:

```
Scientific Calculator — type 'q' to quit
Supported: add  subtract  multiply  divide  sin  cos  tan  arctan
           mod  div  e  ln  sum  avg

calculate: add(2,2)
4
calculate: multiply(6,7)
42
calculate: sin(30)
0.49999999999999994
calculate: sum(1,2,3,4,5)
15
calculate: q
```

Type any expression supported by `the-calculator`. Enter `q` or `quit` to exit.

---

## Run with Spin (`thecalculatorspin`)

`thecalculatorspin` is a Spin v4 HTTP application that exposes `the-calculator` as an HTTP endpoint. Send a GET request with a `?calculate=` query parameter; the result is returned as plain text.

### Prerequisites

```sh
# Install Spin v4
curl -fsSL https://spinframework.dev/downloads/install.sh | bash
# or manually: https://github.com/spinframework/spin/releases

# Install wac (WASM composition tool)
cargo install wac-cli
```

### Build the Spin app

```sh
cd thecalculatorspin

# 1. Compile to WASM (wasm32-wasip2)
cargo build --target wasm32-wasip2 --release

# 2. Compose with the-calculator
wac plug --plug ../the-calculator/the-calculator.wasm \
  target/wasm32-wasip2/release/thecalculatorspin.wasm \
  -o thecalculatorspin-composed.wasm
```

Or use `spin build` to run both steps via the build command in `spin.toml`:

```sh
cd thecalculatorspin
spin build
```

### Run and call the HTTP API

```sh
cd thecalculatorspin
spin up --listen 127.0.0.1:3000
```

In another terminal:

```sh
# Arithmetic
curl "http://127.0.0.1:3000/?calculate=add(2,3)"         # → 5
curl "http://127.0.0.1:3000/?calculate=subtract(10,4)"   # → 6
curl "http://127.0.0.1:3000/?calculate=multiply(6,7)"    # → 42
curl "http://127.0.0.1:3000/?calculate=divide(9,3)"      # → 3

# Trigonometric (degrees)
curl "http://127.0.0.1:3000/?calculate=sin(30)"          # → 0.5
curl "http://127.0.0.1:3000/?calculate=cos(60)"          # → 0.5
curl "http://127.0.0.1:3000/?calculate=tan(45)"          # → 1
curl "http://127.0.0.1:3000/?calculate=arctan(1)"        # → 45

# Modulo / integer division
curl "http://127.0.0.1:3000/?calculate=mod(10,3)"        # → 1
curl "http://127.0.0.1:3000/?calculate=div(10,3)"        # → 3

# Logarithmic
curl "http://127.0.0.1:3000/?calculate=e()"              # → 2.718281828...
curl "http://127.0.0.1:3000/?calculate=ln(2.718281828)"  # → ~1

# Statistics
curl "http://127.0.0.1:3000/?calculate=sum(1,2,3,4,5)"  # → 15
curl "http://127.0.0.1:3000/?calculate=avg(1,2,3,4,5)"  # → 3
```

## Deploy on k3d / SpinKube (local Kubernetes)

The `thecalculatordepl/` folder contains everything needed to run `thecalculatorspin` on a local [k3d](https://k3d.io) cluster with [SpinKube](https://www.spinkube.dev) and [KEDA](https://keda.sh) HTTP autoscaling.

### How it works

```
curl localhost:3000
  → Traefik (k3d port 3000→80)
    → KEDA HTTP interceptor proxy  ← buffers requests, triggers scale-up
      → thecalculatorspin (SpinApp pod, wasmtime-spin-v2 runtime)
```

KEDA HTTP Add-on watches incoming request volume and scales the deployment between 1 and 5 replicas. After 60 s of inactivity, replicas return to 1.

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| [k3d](https://k3d.io) | ≥ 5.0 | `brew install k3d` / [k3d.io](https://k3d.io/#installation) |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | any | `brew install kubectl` |
| [Helm](https://helm.sh) | ≥ 3.0 | `brew install helm` |
| [Spin CLI](https://spinframework.dev/install) | ≥ 3.6 | `curl -fsSL https://spinframework.dev/downloads/install.sh \| bash` |
| Docker (Docker Desktop / Rancher Desktop / OrbStack) | running | required by k3d |

### Deploy

```sh
# From the repo root — one command does everything:
bash thecalculatordepl/deploy.sh
```

The script performs these steps in order:

1. **Push image** — authenticates to `ghcr.io` via GitHub CLI token, runs `spin registry push ghcr.io/uhansen/thecalculatorspin:latest`, and creates an `imagePullSecret` in the cluster so nodes can pull the private package
2. **Create cluster** — k3d cluster using `ghcr.io/spinframework/containerd-shim-spin/k3d:v0.24.0` (Spin shim pre-installed, no extra operator needed)
3. **cert-manager** v1.16.3 — required by spin-operator webhooks
4. **spin-operator** v0.6.1 — SpinApp CRD controller
5. **RuntimeClass + ShimExecutor** — wire the containerd shim into Kubernetes scheduling
6. **KEDA** 2.19.0 — core autoscaler
7. **KEDA HTTP Add-on** 0.14.0 — `HTTPScaledObject` CRD + interceptor proxy
8. **SpinApp + Ingress** — deploys the app and routes Traefik through the KEDA interceptor
9. **HTTPScaledObject** — configures autoscaling (min=1, max=5, scaledownPeriod=60s)
10. **Patch Traefik** — enables ExternalName service backends (required for the interceptor route)

### Test

```sh
curl "http://localhost:3000/?calculate=add(2,3)"       # → 5
curl "http://localhost:3000/?calculate=multiply(6,7)"  # → 42
curl "http://localhost:3000/?calculate=sin(30)"         # → 0.5
```

### Check autoscaling

```sh
# Current state of the HTTPScaledObject
kubectl get httpscaledobject thecalculatorspin

# Watch pods scale up under load
kubectl get pods -n default -w

# Watch the underlying ScaledObject / HPA
kubectl get scaledobject -n default
kubectl get hpa -n default
```

### Tear down

```sh
bash thecalculatordepl/teardown.sh
```

### Files

| File | Purpose |
|---|---|
| `thecalculatordepl/deploy.sh` | Full end-to-end deploy script |
| `thecalculatordepl/teardown.sh` | Delete the cluster |
| `thecalculatordepl/k3d-config.yaml` | k3d cluster spec (shim node image, port 3000→80) |
| `thecalculatordepl/spinapp.yaml` | SpinApp CR + ExternalName proxy Service + Traefik Ingress |
| `thecalculatordepl/httpscaledobject.yaml` | KEDA HTTPScaledObject (min=1 → max=5) |

### Notes

- **ghcr.io image:** `ghcr.io/uhansen/thecalculatorspin:latest` — stored permanently in GitHub Container Registry (no expiry). The package is private; `deploy.sh` automatically creates an `imagePullSecret` (`ghcr-pull-secret`) in the cluster using the GitHub token. Requires a GitHub token with `write:packages` scope to push (set `GITHUB_TOKEN` env var, or ensure `gh auth token` has the scope — run `gh auth refresh -s write:packages` if needed).
- **Re-deploying:** Re-run `deploy.sh` to push a new build and refresh the imagePullSecret, then `kubectl rollout restart deployment/thecalculatorspin`.
- **min=1 (not 0):** The spin-operator reconciles `replicas: 1` from the SpinApp spec. Setting `min: 1` in the `HTTPScaledObject` keeps both controllers in agreement. True scale-to-zero would require removing the `replicas` field from the SpinApp and is not yet supported cleanly by spin-operator v0.6.1.
- The cluster uses Spin shim **v0.24.0** (Spin 3.6.3 / wasmtime 42). The app was built with spin-sdk 5.2.0 (Spin 3.6.1 series) — compatible.

## WASM Binary Sizes

| File | Size | Notes |
|---|---|---|
| `target/wasm32-wasip2/release/trigonometric_calculator.wasm` | 27 KB | Rust — no runtime overhead |
| `target/wasm32-wasip2/release/arithmetic_calculator.wasm` | 66 KB | Rust — no runtime overhead |
| `target/wasm32-wasip2/release/thecalculatorspin.wasm` | 262 KB | Spin HTTP shell (before composition) |
| `logaritmic-calculator/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculator.wasm` | 2.5 MB | C# / .NET 10 |
| `moddiv/moddiv.wasm` | 12 MB | TypeScript — embeds StarlingMonkey JS engine |
| `statistics-calculator/statistics-calculator.wasm` | 18 MB | Python — embeds CPython runtime |
| `the-calculator/the-calculator.wasm` | 32 MB | Composed: all 5 sub-components bundled |
| `thecalculatorspin/thecalculatorspin-composed.wasm` | 32 MB | Composed Spin app (Spin shell + the-calculator) |
| `thecalculatorcli/thecalculatorcli-composed.wasm` | 32 MB | Composed CLI REPL (CLI shell + the-calculator) |

> The size difference between languages is mainly due to embedded runtimes: Rust compiles directly to WASM with no runtime, while TypeScript (SpiderMonkey/StarlingMonkey) and Python (CPython) must bundle their interpreters inside the component.
