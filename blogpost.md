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
