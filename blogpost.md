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
package docs:arithmetic-calculator@0.1.0;

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
moddiv (TypeScript)                ─┼──► the-calculater (Rust shell)
logaritmic-calculater (C#)         ─┤
statistics-calculator (Python)     ─┘
```

The shell declares its imports in WIT:

```wit
world the-calculater {
    import docs:arithmetic-calculator/arithmetic@0.1.0;
    import docs:trigonometric-calculator/trigonometric@0.1.0;
    import docs:moddiv/moddiv@0.1.0;
    import docs:logaritmic-calculater/logaritmic@0.1.0;
    import docs:statistics-calculator/statistics@0.1.0;

    export docs:the-calculater/calculator@0.1.0;
}
```

The `wac plug` tool resolves each import by matching it against the exports of the provided sub-components and links them together:

```sh
wac plug \
  --plug arithmetic_calculator.wasm \
  --plug trigonometric_calculator.wasm \
  --plug moddiv.wasm \
  --plug logaritmic-calculater.wasm \
  --plug statistics-calculator.wasm \
  the_calculater.wasm \
  -o the-calculater.wasm
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
A component that implements `docs:arithmetic-calculator/arithmetic@0.1.0` can be swapped for any other conforming implementation. This enables a registry-based ecosystem of interchangeable components — much like npm or crates.io, but language-neutral and with strong interface contracts.

---

## Where Things Stand

The Component Model is still evolving. The specification is largely stable, the major toolchains have solid support, and runtimes like Wasmtime implement it in production. But the registry ecosystem, async support (WASI 0.3), and debugger integration are still maturing.

What exists today is already enough to build real, multi-language systems. The scientific calculator in this repository is a small but concrete example: five components in Rust, TypeScript, C#, and Python, each independently buildable and verifiable, composed into a single binary with a single entry point, runnable with a one-liner:

```sh
wasmtime run --invoke 'calculate("add(2,2)")' the-calculater/the-calculater.wasm
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
│  thecalculaterspin          │  ← Spin HTTP app (Rust, wasm32-wasip2)
│  exports wasi:http/handler  │
│  imports docs:the-calculater│
└────────────┬────────────────┘
             │  (composed in by wac plug)
             ▼
┌─────────────────────────────┐
│  the-calculater.wasm        │  ← composed component (5 sub-components)
│  arithmetic · trig · moddiv │
│  logarithmic · statistics   │
└─────────────────────────────┘
```

The Spin app imports the `calculate(string) → string` interface from `the-calculater`. At build time, `wac plug` fills that import by embedding the composed calculator binary directly into the Spin component. The resulting binary is fully self-contained: Spin only needs to provide the WASI host APIs.

### Implementing the handler

The handler is a Rust async function decorated with `#[http_service]` from `spin-sdk 6.0.0`:

```rust
use spin_sdk::http::body::IncomingBodyExt;
use spin_sdk::http::{IntoResponse, Request, StatusCode};
use spin_sdk::{http_service, wit_bindgen};

wit_bindgen::generate!({
    path: "wit",
    world: "calculator-import",
    generate_all,
});

#[http_service]
async fn handle(req: Request) -> impl IntoResponse {
    let expr = get_expr(req).await;
    let result = docs::the_calculater::calculator::calculate(&expr);
    (StatusCode::OK, result)
}
```

`wit_bindgen::generate!` reads the local WIT file that declares the import of `docs:the-calculater/calculator@0.1.0`, and generates the Rust bindings. The `calculate()` call looks like a normal function call — the Component Model handles the rest.

Expressions are passed as a `?expr=` query parameter on GET requests:

```rust
fn get_expr(req: &Request) -> String {
    if let Some(query) = req.uri().query() {
        for pair in query.split('&') {
            if let Some(value) = pair.strip_prefix("expr=") {
                return urlencoded_decode(value);
            }
        }
    }
    String::new()
}
```

### Building the Spin app

```sh
cd thecalculaterspin

# Step 1: compile the Spin handler to WASM
cargo build --target wasm32-wasip2 --release

# Step 2: compose — plug the-calculater into the Spin component
wac plug --plug ../the-calculater/the-calculater.wasm \
  target/wasm32-wasip2/release/thecalculaterspin.wasm \
  -o thecalculaterspin-composed.wasm
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
curl "http://127.0.0.1:3000/?expr=add(2,3)"         # → 5
curl "http://127.0.0.1:3000/?expr=multiply(6,7)"    # → 42
curl "http://127.0.0.1:3000/?expr=divide(9,3)"      # → 3

# Trigonometric (degrees)
curl "http://127.0.0.1:3000/?expr=sin(30)"          # → 0.5
curl "http://127.0.0.1:3000/?expr=arctan(1)"        # → 45

# Logarithmic
curl "http://127.0.0.1:3000/?expr=e()"              # → 2.718281828...
curl "http://127.0.0.1:3000/?expr=ln(2.718281828)"  # → ~1

# Statistics
curl "http://127.0.0.1:3000/?expr=sum(1,2,3,4,5)"  # → 15
curl "http://127.0.0.1:3000/?expr=avg(1,2,3,4,5)"  # → 3
```

### What this demonstrates

A few things stand out about this workflow:

**WASM composition scales to real services.** The same `wac plug` command used to compose five calculator sub-components is used again here — this time to embed a 32 MB composed binary inside a Spin HTTP handler. The mechanism is identical.

**The interface contract is the API.** The Spin handler doesn't know that `the-calculater` is made of Rust, TypeScript, C#, and Python. It sees one WIT interface: `calculate(string) → string`. Language implementation details are invisible at composition time.

**Cold start is fast.** Because WebAssembly modules are pre-compiled and sandboxed, Spin can instantiate the component per-request with very low overhead — no JVM startup, no Python interpreter initialization on the hot path.

The full source for `thecalculaterspin` is in the [scientificcalculater repository](https://github.com/uhansen/scientificcalculater).
