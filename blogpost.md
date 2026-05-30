# Building Polyglot Applications with WebAssembly Components

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

## Deploying as a Spin HTTP Application

Building a composed WASM binary is satisfying, but invoking it with `wasmtime run --invoke` from the command line is not how most software gets used. To make the calculator accessible as a real service, we wrap it in a [Spin](https://spinframework.dev) HTTP application.

### What is Spin?

Spin is an open-source framework from Fermyon for building serverless-style applications on top of WebAssembly. You write a handler function; Spin provides the HTTP server, the WASI host implementation, and the runtime plumbing. The key property for this project: **Spin components are WASM components**. A Spin HTTP app is just a WASM component that exports `wasi:http/handler`. That makes it a first-class participant in the Component Model.

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

## An Interactive CLI with `thecalculatorcli`

The same composed binary that powers the HTTP service can be used from the command line — no HTTP server, no deployment, just `wasmtime run`. To make this ergonomic, `thecalculatorcli` is a WASI CLI Rust component that wraps `the-calculator` in an interactive REPL.

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

The WIT world mirrors the Spin app's: it imports `buildbyhansen:the-calculator/calculator@0.1.0`. At composition time, `wac plug` embeds the full 32 MB composed calculator binary inside the CLI shell — the same mechanism as `thecalculatorspin`.

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

The same WIT interface and composition tool (`wac plug`) used to build the HTTP service powers the CLI REPL. `the-calculator` is not a library — it is a self-contained binary component with a stable, versioned interface. Consuming it from a CLI or an HTTP handler requires nothing more than declaring the import in WIT and composing at build time. The Component Model's interface contract is the only shared dependency.

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
