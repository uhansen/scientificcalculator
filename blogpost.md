# Building Polyglot Applications with WebAssembly Components

![WASM components diagram](wasm-components.drawio.svg)

## What is WebAssembly?

WebAssembly (WASM) started life as a compilation target for the browser. The idea was simple: take performance-critical code written in C, C++, or Rust and run it at near-native speed inside a web page, without plugins and without trusting arbitrary native binaries. The first version shipped in all major browsers in 2017.

But WASM quickly outgrew the browser. The same properties that make it attractive on the client — compact binary format, deterministic execution, strong sandboxing — also make it an interesting target for server-side workloads, edge computing, plug-in systems, and portable tooling.

At its core, a WebAssembly module is a portable, sandboxed binary. It has no access to the file system, the network, or the operating system unless the host explicitly grants it. Memory is a flat, isolated buffer. There are no global mutable singletons that bleed across module boundaries. A module either runs correctly or it traps — it cannot corrupt the host process.

---

## Pros and Cons

### Advantages

**Portability**  
A `.wasm` binary compiled once runs anywhere a WASM runtime exists — browsers, servers (via Wasmtime, WasmEdge, or WAMR), edge nodes, or embedded devices. No recompilation for each target platform.

**Language agnosticism**  
Rust, C, C++, Go, TypeScript, C#, Python, Swift, and many others can all compile to WASM. Teams can choose the language that fits the problem rather than the one the platform dictates.

**Security by default**  
The sandbox is opt-in outward, not opt-out. A module cannot read your files, open network connections, or call OS APIs unless the host explicitly provides those capabilities. This makes WASM an excellent foundation for running untrusted or third-party code safely.

**Deterministic execution**  
Given the same inputs and host-provided resources, a WASM program behaves identically across runtimes. This is valuable for reproducible builds, auditing, and testing.

**Small, fast cold starts**  
WASM binaries are compact and stream-compilable. Runtimes like Wasmtime use Cranelift to JIT-compile them to native code quickly, enabling sub-millisecond cold starts — a significant advantage over container-based serverless workloads.

**Isolation without containers**  
Multiple WASM modules can run in the same OS process, fully isolated from each other. This is far cheaper than running separate containers or VMs.

### Disadvantages

**Immature ecosystem**  
Tooling, debugging support, observability, and language-specific libraries are still catching up. Debugging a running WASM module is harder than debugging native code, and not every language's standard library works out of the box.

**Limited host access**  
The sandbox is both a strength and a constraint. Interacting with the file system, sockets, or clocks requires explicit WASI (WebAssembly System Interface) APIs, and not all runtimes implement every WASI proposal at the same version.

**Interoperability friction**  
Passing complex data (strings, lists, structs) between the host and a module — or between two modules — used to require manual, error-prone ABI glue. Each language runtime serialised data differently.

**No native threading model (yet)**  
WASM threads are available but limited. The threading proposal is still evolving, and shared-memory concurrency looks different from native threads.

**Binary size for managed languages**  
Compiling a .NET or Python runtime into a WASM module can produce large binaries (tens of megabytes). Toolchains like `componentize-dotnet` and `componentize-py` are improving this, but it remains a concern for size-sensitive deployments.

---

## The WASM Component Model

The original WASM spec only knows about integers, floats, and linear memory. Passing a string between two modules meant agreeing on a memory layout, writing glue code, and hoping nothing changed. This worked for single-module embeddings but broke down badly in multi-module systems.

The **Component Model** is a specification from the [Bytecode Alliance](https://bytecodealliance.org/) that solves this. It adds:

- **WIT (WebAssembly Interface Types)** — a high-level IDL for describing the interface a component exposes or requires. WIT understands strings, records, variants, lists, options, results, and resources. No more manual memory layout negotiations.
- **Component binaries** — a new binary format layered on top of core WASM modules. A component declares exactly what it exports and what it imports, in terms of WIT types.
- **Canonical ABI** — a standardised encoding that maps WIT values to linear memory, so any two components can exchange data regardless of which language they were written in.

A WIT interface looks like this:

```wit
package buildbyhansen:arithmetic-calculator@0.1.0;

interface arithmetic {
    add: func(x: f64, y: f64) -> f64;
    subtract: func(x: f64, y: f64) -> f64;
    multiply: func(x: f64, y: f64) -> f64;
    divide: func(x: f64, y: f64) -> result<f64, string>;
}

world calculator {
    export arithmetic;
}
```

Language toolchains (`wit-bindgen` for Rust, `jco` for TypeScript/JavaScript, `componentize-dotnet` for C#, `componentize-py` for Python) read this WIT file and generate the necessary boilerplate — imports, exports, type conversions — so that the developer only writes business logic.

The result is a component that is self-describing: its binary carries the full WIT interface, which any tool can read with `wasm-tools component wit my-component.wasm`.

---

## Composition

If the Component Model gives components a shared language for describing interfaces, **composition** is the mechanism for wiring them together.

Rather than calling an HTTP endpoint or linking shared libraries at compile time, composition connects the *export* of one component to the *import* of another at the binary level, before the combined program ever runs. The result is a single, self-contained WASM binary.

### How it works

Consider a system with five sub-components — each written in a different language — and a shell component that imports all five:

```
arithmetic-calculator (Rust)       ─┐
trigonometric-calculator (Rust)    ─┤
moddiv-calculator (TypeScript)                ─┼──► the-calculator (Rust shell)
logaritmic-calculator (C#)         ─┤
statistics-calculator (Python)     ─┘
```

The shell declares its imports in WIT:

```wit
world the-calculator {
    import buildbyhansen:arithmetic-calculator/arithmetic@0.1.0;
    import buildbyhansen:trigonometric-calculator/trigonometric@0.1.0;
    import buildbyhansen:moddiv-calculator/moddiv@0.1.0;
    import buildbyhansen:logaritmic-calculator/logaritmic@0.1.0;
    import buildbyhansen:statistics-calculator/statistics@0.1.0;

    export buildbyhansen:the-calculator/calculator@0.1.0;
}
```

The `wac plug` tool resolves each import by matching it against the exports of the provided sub-components and links them together:

```sh
wac plug \
  --plug arithmetic_calculator.wasm \
  --plug trigonometric_calculator.wasm \
  --plug moddiv-calculator.wasm \
  --plug logaritmic-calculator.wasm \
  --plug statistics-calculator.wasm \
  the_calculator.wasm \
  -o the-calculator.wasm
```

The composed output has no sub-component imports left — only WASI host APIs remain external. Five separate binaries, written in four different languages, become one.

### Why this matters

**True polyglot systems without shared runtimes**  
The Rust runtime, the .NET runtime, the Python interpreter, and the JavaScript engine all coexist inside a single binary without needing to know about each other. The Component Model's Canonical ABI is the only shared contract.

**Composability at the binary level**  
Components can be combined without access to source code. A C# component is as composable as a Rust one — what matters is the WIT interface, not the implementation language.

**Fine-grained capability control**  
Because each component's imports and exports are explicit and verified, you can reason about what a composed system can and cannot do before running it.

**Reusable, versioned building blocks**  
A component that implements `buildbyhansen:arithmetic-calculator/arithmetic@0.1.0` can be swapped for any other conforming implementation. This enables a registry-based ecosystem of interchangeable components — much like npm or crates.io, but language-neutral and with strong interface contracts.

---

## Where Things Stand

The Component Model is still evolving. The specification is largely stable, the major toolchains have solid support, and runtimes like Wasmtime implement it in production. But the registry ecosystem, async support (WASI 0.3), and debugger integration are still maturing.

What exists today is already enough to build real, multi-language systems. The scientific calculator in this repository is a small but concrete example: five components in Rust, TypeScript, C#, and Python, each independently buildable and verifiable, composed into a single binary with a single entry point, runnable with a one-liner:

```sh
wasmtime run --invoke 'calculate("add(2,2)")' components/the-calculator/the-calculator.wasm
# → "4"
```

The promise of WebAssembly was always portability. The Component Model extends that promise from *run anywhere* to *compose with anything*.

## An Interactive CLI with `thecalculatorcli`

Once `the-calculator` is composed into a single WASM binary it can be used directly from the command line — no HTTP server, no deployment, just `wasmtime run`. To make this ergonomic, `thecalculatorcli` is a WASI CLI Rust component that wraps `the-calculator` in an interactive REPL.

### What is WASI CLI?

[WASI CLI](https://github.com/WebAssembly/wasi-cli) is a WASI P2 proposal that standardises command-line program behaviour for WASM components: stdin/stdout/stderr streams, environment variables, process exit, and terminal detection. A component that exports `wasi:cli/run` is a proper WASI command — any compliant runtime (Wasmtime ≥ 18) can run it with `wasmtime run`.

When you target `wasm32-wasip2` in Rust and write a `main()` function, the Rust runtime automatically exports `wasi:cli/run`, so the component is a first-class WASI command with no extra boilerplate.

### The implementation

`thecalculatorcli` is a small Rust binary that imports `the-calculator` via WIT and reads from stdin in a loop:

```rust
wit_bindgen::generate!({
    path: "wit",
    world: "calculator-cli",
    generate_all,
});

use buildbyhansen::the_calculator::calculator::calculate;

fn main() {
    println!("Scientific Calculator — type 'q' to quit");
    println!("Supported: add  subtract  multiply  divide  sin  cos  tan  arctan");
    println!("           mod  div  e  ln  sum  avg");
    println!();

    loop {
        print!("calculate: ");
        use std::io::Write;
        std::io::stdout().flush().unwrap();

        let mut line = String::new();
        match std::io::stdin().read_line(&mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }

        let input = line.trim();
        if input == "q" || input == "quit" { break; }
        if input.is_empty() { continue; }

        println!("{}", calculate(input));
    }
}
```

The WIT imports `buildbyhansen:the-calculator/calculator@0.1.0`. At composition time, `wac plug` embeds the full 32 MB composed calculator binary inside the CLI shell — the same mechanism as `thecalculatorspin`.

### Build and run

```sh
cd applications/thecalculatorcli
cargo build --target wasm32-wasip2 --release
wac plug \
  --plug ../../components/the-calculator/the-calculator.wasm \
  target/wasm32-wasip2/release/thecalculatorcli.wasm \
  -o thecalculatorcli-composed.wasm
```

```sh
wasmtime run applications/thecalculatorcli/thecalculatorcli-composed.wasm
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

You can verify what the component actually exports:

```sh
wasm-tools component wit thecalculatorcli/thecalculatorcli-composed.wasm | grep -E "export|run"
# → export wasi:cli/run@0.2.6
```

This confirms it is a proper WASI P2 command. The Rust `main()` function maps directly to `wasi:cli/run` — no extra configuration needed.

### Why this matters

The same WIT interface and composition tool (`wac plug`) that builds the CLI REPL is used again for the Spin HTTP service in the next section. `the-calculator` is not a library — it is a self-contained binary component with a stable, versioned interface. Consuming it from a CLI or an HTTP handler requires nothing more than declaring the import in WIT and composing at build time. The Component Model's interface contract is the only shared dependency.

---

## Deploying as a Spin HTTP Application

Building a composed WASM binary is satisfying, but invoking it with `wasmtime run --invoke` from the command line is not how most software gets used. To make the calculator accessible as a real serverless service, we wrap it in a [Spin](https://spinframework.dev) HTTP application.

### What is Spin?

Spin is an open-source framework from Fermyon (now aquired by Akamai) for building serverless-style applications on top of WebAssembly. You write a handler function; Spin provides the HTTP server, the WASI host implementation, and the runtime plumbing. The key property for this project: **Spin components are WASM components**. A Spin HTTP app is just a WASM component that exports `wasi:http/handler`. That makes it a first-class participant in the Component Model.

### The architecture

```
HTTP request
     │
     ▼
┌─────────────────────────────┐
│  thecalculatorspin          │  ← Spin 3.6+ HTTP app (Rust, wasm32-wasip2)
│  exports wasi:http/handler  │
│  imports buildbyhansen:the-calculator│
└────────────┬────────────────┘
             │  (composed in by wac plug)
             ▼
┌─────────────────────────────┐
│  the-calculator.wasm        │  ← composed component (5 sub-components)
│  arithmetic · trig · moddiv-calculator │
│  logarithmic · statistics   │
└─────────────────────────────┘
```

The Spin app imports the `calculate(string) → string` interface from `the-calculator`. At build time, `wac plug` fills that import by embedding the composed calculator binary directly into the Spin component. The resulting binary is fully self-contained: Spin only needs to provide the WASI host APIs.

### Implementing the handler

The handler is a synchronous Rust function decorated with `#[http_component]` from `spin-sdk 5.2.0`:

```rust
use anyhow::Result;
use spin_sdk::http::{IntoResponse, Method, Request, Response};
use spin_sdk::http_component;

wit_bindgen::generate!({
    path: "wit",
    world: "calculator-import",
    generate_all,
});

#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    if req.method() != &Method::Get {
        return Ok(Response::new(405, "Only GET is supported\n"));
    }
    let expr = get_expr(&req);
    let result = buildbyhansen::the_calculator::calculator::calculate(&expr);
    Ok(Response::new(200, result))
}
```

`wit_bindgen::generate!` reads the local WIT file that declares the import of `buildbyhansen:the-calculator/calculator@0.1.0`, and generates the Rust bindings. The `calculate()` call looks like a normal function call — the Component Model handles the rest.

Expressions are passed as a `?calculate=` query parameter on GET requests:

```rust
fn get_expr(req: &Request) -> String {
    let uri = req.uri();
    let query = uri.split('?').nth(1).unwrap_or("");
    for pair in query.split('&') {
        if let Some(value) = pair.strip_prefix("calculate=") {
            return urlencoded_decode(value);
        }
    }
    String::new()
}
```

### Building the Spin app

```sh
cd applications/thecalculatorspin

# Step 1: compile the Spin handler to WASM
cargo build --target wasm32-wasip2 --release

# Step 2: compose — plug the-calculator into the Spin component
wac plug --plug ../../components/the-calculator/the-calculator.wasm \
  target/wasm32-wasip2/release/thecalculatorspin.wasm \
  -o thecalculatorspin-composed.wasm
```

Or in one command via `spin.toml`'s build hook:

```sh
spin build
```

### Running and calling the API

```sh
spin up --listen 127.0.0.1:3000
```

```sh
# Arithmetic
curl "http://127.0.0.1:3000/?calculate=add(2,3)"         # → 5
curl "http://127.0.0.1:3000/?calculate=multiply(6,7)"    # → 42
curl "http://127.0.0.1:3000/?calculate=divide(9,3)"      # → 3

# Trigonometric (degrees)
curl "http://127.0.0.1:3000/?calculate=sin(30)"          # → 0.5
curl "http://127.0.0.1:3000/?calculate=arctan(1)"        # → 45

# Logarithmic
curl "http://127.0.0.1:3000/?calculate=e()"              # → 2.718281828...
curl "http://127.0.0.1:3000/?calculate=ln(2.718281828)"  # → ~1

# Statistics
curl "http://127.0.0.1:3000/?calculate=sum(1,2,3,4,5)"  # → 15
curl "http://127.0.0.1:3000/?calculate=avg(1,2,3,4,5)"  # → 3
```

### What this demonstrates

A few things stand out about this workflow:

**WASM composition scales to real services.** The same `wac plug` command used to compose five calculator sub-components is used again here — this time to embed a 32 MB composed binary inside a Spin HTTP handler. The mechanism is identical.

**The interface contract is the API.** The Spin handler doesn't know that `the-calculator` is made of Rust, TypeScript, C#, and Python. It sees one WIT interface: `calculate(string) → string`. Language implementation details are invisible at composition time.

**Cold start is fast.** Because WebAssembly modules are pre-compiled and sandboxed, Spin can instantiate the component per-request with very low overhead — no JVM startup, no Python interpreter initialization on the hot path.

The full source for `thecalculatorspin` is in the [scientificcalculator repository](https://github.com/uhansen/scientificcalculator).

---

## Deploying on Kubernetes with SpinKube

Running the calculator locally with `spin up` is convenient for development. For production-like deployments the app runs on [k3d](https://k3d.io) (a local Kubernetes cluster) with [SpinKube](https://www.spinkube.dev) as the WASM runtime operator and [KEDA](https://keda.sh) for HTTP-triggered autoscaling.

### The stack

```
curl localhost:3000
  → Traefik (k3d port 3000 → 80)
    → KEDA HTTP interceptor proxy  ← buffers requests, triggers scale-up
      → thecalculatorspin pod (SpinApp, containerd-shim-spin runtime)
```

- **k3d** runs a local Kubernetes cluster with a custom node image that has the [containerd-shim-spin](https://github.com/spinframework/containerd-shim-spin) pre-installed. No KWasm node provisioning is needed.
- **spin-operator** watches `SpinApp` custom resources and creates Deployments that use the `wasmtime-spin-v2` RuntimeClass.
- **KEDA HTTP Add-on** adds an `HTTPScaledObject` CRD. An interceptor proxy sits in front of the app, buffers requests, and triggers scale-up on demand. After 60 s of idle, the deployment scales back to 1 replica.
- The container image is a Spin OCI artifact pushed to `ghcr.io` — no traditional Docker container, just the `.wasm` binary packed as an OCI image.

### Image and deployment

The Spin app is packaged as an OCI image and pushed to GitHub Container Registry:

```sh
spin registry push ghcr.io/uhansen/thecalculatorspin:latest
```

The deploy script (`deploy/thecalculatordepl/deploy.sh`) performs all ten steps in order — cluster creation, cert-manager, spin-operator, RuntimeClass, KEDA, KEDA HTTP Add-on, SpinApp, HTTPScaledObject, and a Traefik patch for ExternalName services — with a single command:

```sh
bash deploy/thecalculatordepl/deploy.sh
```

After the cluster is up:

```sh
curl "http://localhost:3000/?calculate=add(2,3)"       # → 5
curl "http://localhost:3000/?calculate=multiply(6,7)"  # → 42
curl "http://localhost:3000/?calculate=sin(30)"        # → 0.5
```

### What makes this interesting

**WASM as the deployment unit.** There is no Dockerfile. The `spin registry push` command packages the `.wasm` component as an OCI artifact. SpinKube pulls that artifact and runs it directly inside containerd via the Spin shim — no Linux container filesystem, no libc, no user-space interpreter.

**Cold start is negligible.** Wasmtime JIT-compiles the WASM binary to native code at module load time. Pod startup is dominated by Kubernetes scheduling, not runtime initialisation.

**Scale-to-one on idle.** KEDA's HTTPScaledObject keeps a minimum of 1 replica so the spin-operator and Kubernetes stay in sync. True scale-to-zero is possible but requires additional coordination with the SpinApp spec's `replicas` field — a known limitation of spin-operator v0.6.1.

The full deployment manifests are in `thecalculatordepl/` in the [scientificcalculator repository](https://github.com/uhansen/scientificcalculator).

---

## Load Testing and Scale Behaviour

With the service running in k3d, the next question is: does it hold up under load? The `calculatorstresstest` tool is a .NET console application that fires concurrent HTTP requests at the service for a configurable duration and prints live throughput and latency statistics.

### Running the stress test

```sh
cd tests/calculatorstresstest
dotnet run -c Release -- \
  --url         http://localhost:3000 \
  --concurrency 10 \
  --duration    60 \
  --ramp        5
```

The `--ramp` flag staggers worker startup over the first 5 seconds — this avoids a thundering-herd spike and gives KEDA time to begin scaling before the full load arrives. Output during the run looks like:

```
╔══════════════════════════════════════════════════════════╗
║          calculatorstresstest — HTTP load test           ║
╠══════════════════════════════════════════════════════════╣
║  URL          : http://localhost:3000                    ║
║  Concurrency  : 20                                       ║
║  Duration     : 60s (ramp 5s)                            ║
╚══════════════════════════════════════════════════════════╝

  [ 12s /  60s]    847 req/s  total:   9821  errors:     0  remaining:  48s
```

### Watching Kubernetes scale in parallel

While the stress test runs, the KEDA HTTP interceptor is counting in-flight requests and adjusting the SpinApp replica count. Use the monitoring script to see both outputs together:

```sh
./tests/calculatorstresstest/run-with-k8s-monitor.sh
```

Every 3 seconds the script prints the current Kubernetes state alongside the live stress-test metrics:

```
┌── k8s status @ 10:25:04 (poll #4) ──────────────────────┐
│  SpinApp replicas  : desired=3 ready=3                    │
│  Running pods      : 3                                    │
│    thecalculatorspin-7d8f-aaa  true  Running  0          │
│    thecalculatorspin-7d8f-bbb  true  Running  0          │
│    thecalculatorspin-7d8f-ccc  true  Running  0          │
│  KEDA HTTPScaled   : ready=True scaleTarget=thecalcul... │
└──────────────────────────────────────────────────────────┘
```

To watch pod lifecycle in a dedicated terminal:

```sh
# Watch pods scale up during load, then back down after idle
kubectl get pods -n default -l core.spinkube.dev/app=thecalculatorspin -w

# Watch SpinApp replica count
kubectl get spinapp thecalculatorspin -n default -w

# Watch KEDA scaler state
kubectl get httpscaledobject thecalculatorspin -n default -w
```

### What the numbers show

At 10 concurrent workers the service sustains roughly **900–1 100 req/s** on a local k3d cluster with two agent nodes. p50 latency stays under 10 ms; p99 stays under 20 ms. These numbers are dominated by the TCP round-trip through the Traefik → KEDA interceptor → SpinApp chain running entirely on localhost, not by the WASM execution time itself.

After the test finishes, KEDA's idle timer fires after 60 seconds and the replica count drops back to 1. Sending the first request after scale-down causes a ~200–500 ms cold start — the time for Kubernetes to schedule a new pod and for the Spin shim to load and JIT-compile the 32 MB WASM binary. Every subsequent request on the warm pod completes in single-digit milliseconds.

### The test result summary

```
╔══════════════════════════════════════════════════════════╗
║                     Test Summary                         ║
╠══════════════════════════════════════════════════════════╣
║  Duration     : 15.0s                                    ║
║  Concurrency  : 10                                       ║
║  Total req    : 14 689                                   ║
║  Success      : 14 689                                   ║
║  Errors       : 0                                        ║
║  Throughput   : 977.1 req/s                              ║
╠══════════════════════════════════════════════════════════╣
║  Latency avg  : 8.7 ms                                   ║
║  Latency p50  : 8.3 ms                                   ║
║  Latency p95  : 13.0 ms                                  ║
║  Latency p99  : 15.5 ms                                  ║
╚══════════════════════════════════════════════════════════╝
```

Zero errors. The composed WASM binary — five sub-components, four languages, 32 MB — handles sustained concurrent HTTP load without issue.

---

## CI/CD Pipeline

The manual build-compose-push loop works for local development, but for a shared repository it needs to be automated. The project uses a GitHub Actions workflow that builds the entire component chain, pushes the OCI image to `ghcr.io`, and opens a pull request to `master` — all triggered by a push to any `topic/**` branch.

### The workflow in one diagram

```
push to topic/my-feature
        │
        ▼
┌─────────────────────────────────┐
│  Job: build-and-push            │
│  ─────────────────────────────  │
│  1. Install tools               │
│     Rust 1.93  · wasm32-wasip2  │
│     .NET 10    · Node 22        │
│     Python 3.12· componentize   │
│     wac-cli    · Spin 3.6.1     │
│  2. Build all sub-components    │
│     cargo build (Rust)          │
│     npm run build (TypeScript)  │
│     dotnet build (C#)           │
│     componentize-py (Python)    │
│  3. Compose the-calculator.wasm │
│  4. spin build → composed .wasm │
│  5. spin registry push          │
│     :topic-myfeature-abc1234    │
│     :latest                     │
│  6. Update spinapp.yaml         │
│     sed → exact image tag       │
│  7. git commit + push back      │
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│  Job: open-pr                   │
│  ─────────────────────────────  │
│  1. Create PR to master         │
│  2. Request Copilot review      │
│  3. Enable auto-merge           │
└─────────────────────────────────┘
```

### GitOps write-back

After pushing the OCI image the workflow patches `deploy/thecalculatordepl/spinapp.yaml` with the exact immutable tag:

```yaml
# before
image: "ghcr.io/uhansen/thecalculatorspin:latest"

# after (committed back to the topic branch by github-actions[bot])
image: "ghcr.io/uhansen/thecalculatorspin:topic-my-feature-abc1234"
```

The updated manifest is committed by `github-actions[bot]` and pushed back to the topic branch. When the PR is merged, `master` contains deployment manifests that point to the exact build that was reviewed. Deploying the reviewed build is then:

```sh
kubectl apply -f deploy/thecalculatordepl/spinapp.yaml
```

No image tag lookup, no guessing — the manifest and the image are always in sync.

### Copilot code review and auto-merge

A `.github/CODEOWNERS` file assigns `@github-copilot` as the required reviewer for every file. When the pipeline opens the PR, GitHub automatically requests a Copilot code review. Once Copilot approves and the `Build & Push OCI image` status check passes, the PR auto-merges to `master`.

Branch protection on `master` enforces both conditions:

- At least one approving review (satisfied by Copilot)
- The `build-and-push` job must succeed

This means no human needs to be in the loop for routine changes on topic branches — the feedback cycle is: push → build → review → merge.

### Caching for fast builds

The workflow caches four artifact stores to minimise per-run build time:

| Cache | Key |
|-------|-----|
| Cargo registry + target | Cargo.lock hash |
| npm node_modules | package-lock.json hash |
| NuGet packages | *.csproj hash |
| pip (componentize-py) | requirements hash |

On a warm cache run (no dependency changes) the full build-compose-push cycle completes in approximately 8–12 minutes — dominated by the Rust compilation of the WASM targets.

## Using `the-calculator` as a Plugin

The CLI and Spin approaches both embed `the-calculator` at *build time* via `wac plug` — the composed binary is sealed before it runs. A different pattern treats the WASM component as a *runtime plugin*: the host application loads whatever path the user supplies at startup, wires up WASI, and calls into the component through a stable WIT interface. The component can be swapped without recompiling the host.

This is the classic plugin architecture — think scripting language extensions or VSCode language servers — but realised entirely through the WASM Component Model. The host and plugin share nothing except a versioned WIT contract.

### The Rust host — `calculatorrustapp`

`calculatorrustapp` is a native Rust binary that embeds `wasmtime` as a library. It accepts `--plugin <path>` at startup and runs a REPL identical to `thecalculatorcli`, but the component is loaded from disk at runtime rather than composed in at build time.

```rust
wasmtime::component::bindgen!({
    path: "wit",
    world: "the-calculator",
});

fn main() -> Result<()> {
    let cli = Cli::parse();         // --plugin path/to/the-calculator.wasm

    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = Engine::new(&config)?;

    let component = Component::from_file(&engine, &cli.plugin)?;  // runtime load

    let mut linker: Linker<HostState> = Linker::new(&engine);
    wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;          // full WASI P2

    let mut store = Store::new(&engine, HostState { wasi, table });
    let calc = TheCalculator::instantiate(&mut store, &component, &linker)?;
    let calculator = calc.buildbyhansen_the_calculator_calculator();

    loop {
        // ... read line, call calculator.call_calculate(&mut store, input)
    }
}
```

`bindgen!` generates a typed Rust wrapper from the WIT file at *compile time*, so every call to `call_calculate` is type-checked against the interface — even though the concrete WASM binary is not known until runtime.

#### Build

```sh
cd applications/calculatorrustapp
cargo build --release        # native binary, not WASM
```

#### Run

```sh
./target/release/calculatorrustapp \
  --plugin ../../components/the-calculator/the-calculator.wasm
```

```
Scientific Calculator — wasmtime plugin host
Plugin: ../../components/the-calculator/the-calculator.wasm
Type 'q' to quit.
Supported syntax: func(arg1, arg2, ...)
Functions:  add  subtract  multiply  divide  sin  cos  tan  arctan  mod  div  e  ln  sum  avg

calculate: add(3,4)
7
calculate: sum(1,2,3,4,5)
15
calculate: divide(22,7)
3.142857142857143
calculate: q
```

Because the host implements the full `WasiView` trait — providing `WasiCtx` and `ResourceTable` — it supports every component in the polyglot composition, including the .NET logarithmic calculator and the componentize-py statistics calculator.

### The Python host — `calculatorpythonapp`

The same plugin pattern works in Python using the `wasmtime` pip package. The Python host exposes an identical `--plugin` / REPL interface.

```python
config = Config()
config.wasm_component_model = True
engine = Engine(config)

comp = component.Component.from_file(engine, args.plugin)   # runtime load
linker = component.Linker(engine)
linker.add_wasip2()
store = Store(engine, WasiConfig())
instance = linker.instantiate(store, comp)

iface_idx = comp.get_export_index("buildbyhansen:the-calculator/calculator@0.1.0")
calc_idx  = instance.get_export_index(store, "calculate", iface_idx)
calculate = instance.get_func(store, calc_idx)

result = calculate(store, expr)
calculate.post_return(store)   # required for string-returning functions
```

#### Run

```sh
cd applications/calculatorpythonapp
pip install -r requirements.txt
python main.py --plugin ../../components/the-calculator/the-calculator.wasm
```

#### Polyglot limitation in the Python host

The Python wasmtime package is a thin C-extension wrapper around the same `libwasmtime` used by the Rust host, but it does not fully implement the WASI CLI host callbacks (`wasi:cli/stdout` etc.) for background threads. The .NET logarithmic component and the componentize-py statistics component both spawn worker threads that call back into the store via those interfaces — and the C API panics because the Python-side store context is not thread-safe in the same way.

The Python host isolates each calculation in a child subprocess. If the subprocess aborts (SIGABRT), the parent catches it and returns a descriptive error rather than crashing:

```
calculate: ln(2.71828)
Error: 'ln' uses a polyglot component (.NET or Python runtime) that requires
WASI CLI stdio from a background thread — not supported by the Python
wasmtime C API. Use calculatorrustapp for full support.
```

Functions backed by pure Rust or JavaScript components (`add`, `subtract`, `multiply`, `divide`, `sin`, `cos`, `tan`, `arctan`, `mod`, `div`) work correctly in both hosts.

### Plugin vs. composition — when to use each

| | Composed (wac plug) | Plugin (wasmtime host) |
|---|---|---|
| Component loaded | Build time | Runtime — swappable |
| Distribution | Single WASM binary | Host binary + separate `.wasm` |
| Language of host | WASM component | Any language with wasmtime binding |
| WASI support | Provided by outer runtime (wasmtime run, Spin) | Host must implement WasiView |
| Use case | Serverless, edge, portable CLI | Desktop apps, IDEs, extensible tools |

Both approaches use the same `the-calculator.wasm` and the same WIT interface. The Component Model's value is that neither the components nor their polyglot origins change — only how they are packaged and delivered.

---

