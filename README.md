# Scientific Calculator – WASM Components

WebAssembly components built in Rust, TypeScript, C#, and Python, following the [Bytecode Alliance guides](https://component-model.bytecodealliance.org/language-support/).

| Component | Language | Interface |
|---|---|---|
| `arithmetic-calculator` | Rust | `add` `subtract` `multiply` `divide` |
| `trigonometric-calculator` | Rust | `sin` `cos` `tan` `arctan` |
| `moddiv` | TypeScript | `mod` `div` |
| `logaritmic-calculater` | C# / .NET 10 | `e` `ln` |
| `statistics-calculator` | Python | `sum` `avg` |
| `the-calculater` | Composed (all 5) | `calculate(string) → string` |
| `thecalculaterspin` | Rust (Spin HTTP app) | HTTP API wrapping `the-calculater` |

## Components

### `the-calculater` (Rust shell — composed from all five sub-components)
A composed WASM component that bundles all five calculators into a single binary.
Exports the `buildbyhansen:the-calculater/calculator@0.1.0` interface with one method:

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

### `logaritmic-calculater` (C# / .NET 10, componentize-dotnet)
Exports a `logaritmic` interface with:
- `e() -> f64` — Euler's number (≈ 2.71828…)
- `ln(x: f64) -> f64` — natural logarithm of x

### `statistics-calculator` (Python, componentize-py)
Exports a `statistics` interface with:
- `sum(numbers: list<f64>) -> f64` — sum of a list of numbers
- `avg(numbers: list<f64>) -> f64` — arithmetic mean (returns 0.0 for empty list)

### `thecalculaterspin` (Rust, Spin v4 HTTP app)
An HTTP application built with [Spin](https://spinframework.dev) that wraps `the-calculater` and exposes it over HTTP. Send a GET request with an `?expr=` query parameter; the result is returned as plain text.

## Prerequisites

Install the tools required for the languages you want to build. All five are needed to compose `the-calculater`.

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

### `logaritmic-calculater` (C# / .NET)
Requires [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

### `statistics-calculator` (Python)
Requires Python 3.10+ and `componentize-py`:
```sh
pip install componentize-py
```

### `thecalculaterspin` (Spin HTTP app)
Requires [Spin v4](https://spinframework.dev/install) in addition to the Rust toolchain and `wac-cli` listed above:
```sh
# Install Spin
curl -fsSL https://spinframework.dev/downloads/install.sh | bash
```

## Build

The five sub-components must be built before the composed `the-calculater` binary can be produced. Follow steps 1–5 in order, then run the composition in step 6.

### Step 1 — Rust: arithmetic-calculator, trigonometric-calculator, and the-calculater shell

The Cargo workspace at the repo root builds all three Rust crates at once:

```sh
cargo build --target wasm32-wasip2 --release
```

Output (in the shared `target/` directory):

```
target/wasm32-wasip2/release/arithmetic_calculator.wasm
target/wasm32-wasip2/release/trigonometric_calculator.wasm
target/wasm32-wasip2/release/the_calculater.wasm   ← shell (imports not yet satisfied)
```

To build a single crate:
```sh
cargo build -p arithmetic-calculator --target wasm32-wasip2 --release
cargo build -p trigonometric-calculator --target wasm32-wasip2 --release
cargo build -p the-calculater --target wasm32-wasip2 --release
```

### Step 2 — TypeScript: moddiv

```sh
cd moddiv
npm install          # installs jco and typescript locally
npm run build        # tsc (TS → JS) then jco componentize (JS → WASM)
cd ..
```

Output: `moddiv/moddiv.wasm`

### Step 3 — C#: logaritmic-calculater

```sh
cd logaritmic-calculater
dotnet build -c Release
cd ..
```

Output: `logaritmic-calculater/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculater.wasm`

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
wasm-tools component wit logaritmic-calculater/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculater.wasm
wasm-tools component wit statistics-calculator/statistics-calculator.wasm
```

### Step 6 — Compose: the-calculater

`wac plug` wires the exports of each sub-component into the matching imports of the shell, producing a fully self-contained binary. All five sub-components are embedded; only WASI host imports remain external.

```sh
wac plug \
  --plug target/wasm32-wasip2/release/arithmetic_calculator.wasm \
  --plug target/wasm32-wasip2/release/trigonometric_calculator.wasm \
  --plug moddiv/moddiv.wasm \
  --plug logaritmic-calculater/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculater.wasm \
  --plug statistics-calculator/statistics-calculator.wasm \
  target/wasm32-wasip2/release/the_calculater.wasm \
  -o the-calculater/the-calculater.wasm
```

Output: `the-calculater/the-calculater.wasm`

Verify the composed component exposes only the single `calculate` export and no sub-component imports:

```sh
wasm-tools component wit the-calculater/the-calculater.wasm | grep -E "^  (import|export)"
```

### Step 7 — Build and run: thecalculaterspin

```sh
cd thecalculaterspin

# Compile to WASM and compose with the-calculater
spin build

# Start the HTTP server
spin up --listen 127.0.0.1:3000
```

Test in another terminal:
```sh
curl "http://127.0.0.1:3000/?expr=add(2,3)"      # → 5
curl "http://127.0.0.1:3000/?expr=sin(30)"        # → 0.5
curl "http://127.0.0.1:3000/?expr=multiply(6,7)"  # → 42
```

See **[Run with Spin](#run-with-spin-thecalculaterspin)** below for the full list of curl examples.

## Run with wasmtime

Requires [wasmtime](https://wasmtime.dev/) ≥ 18. Arguments use [WAVE syntax](https://github.com/bytecodealliance/wasm-tools/tree/main/crates/wasm-wave#readme) — the function call and its arguments are passed as a single quoted string.

### `the-calculater` (composed component)

```sh
# Arithmetic
wasmtime run --invoke 'calculate("add(2,2)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("subtract(10,3)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("multiply(6,7)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("divide(9,3)")' the-calculater/the-calculater.wasm

# Trigonometric (degrees)
wasmtime run --invoke 'calculate("sin(90)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("cos(0)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("tan(45)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("arctan(1)")' the-calculater/the-calculater.wasm

# Modulo / integer division
wasmtime run --invoke 'calculate("mod(10,3)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("div(10,3)")' the-calculater/the-calculater.wasm

# Logarithmic
wasmtime run --invoke 'calculate("e()")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("ln(2.718281828)")' the-calculater/the-calculater.wasm

# Statistics (variable number of arguments)
wasmtime run --invoke 'calculate("sum(1,2,3,4,5)")' the-calculater/the-calculater.wasm
wasmtime run --invoke 'calculate("avg(1,2,3,4,5)")' the-calculater/the-calculater.wasm
```

Errors are returned as strings:

```sh
wasmtime run --invoke 'calculate("divide(5,0)")' the-calculater/the-calculater.wasm
# → "Error: division by zero"

wasmtime run --invoke 'calculate("unknown(1)")' the-calculater/the-calculater.wasm
# → "Error: Unknown function: 'unknown'"
```




## Run with Spin (`thecalculaterspin`)

`thecalculaterspin` is a Spin v4 HTTP application that exposes `the-calculater` as an HTTP endpoint. Send a GET request with a `?expr=` query parameter; the result is returned as plain text.

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
cd thecalculaterspin

# 1. Compile to WASM (wasm32-wasip2)
cargo build --target wasm32-wasip2 --release

# 2. Compose with the-calculater
wac plug --plug ../the-calculater/the-calculater.wasm \
  target/wasm32-wasip2/release/thecalculaterspin.wasm \
  -o thecalculaterspin-composed.wasm
```

Or use `spin build` to run both steps via the build command in `spin.toml`:

```sh
cd thecalculaterspin
spin build
```

### Run and call the HTTP API

```sh
cd thecalculaterspin
spin up --listen 127.0.0.1:3000
```

In another terminal:

```sh
# Arithmetic
curl "http://127.0.0.1:3000/?expr=add(2,3)"         # → 5
curl "http://127.0.0.1:3000/?expr=subtract(10,4)"   # → 6
curl "http://127.0.0.1:3000/?expr=multiply(6,7)"    # → 42
curl "http://127.0.0.1:3000/?expr=divide(9,3)"      # → 3

# Trigonometric (degrees)
curl "http://127.0.0.1:3000/?expr=sin(30)"          # → 0.5
curl "http://127.0.0.1:3000/?expr=cos(60)"          # → 0.5
curl "http://127.0.0.1:3000/?expr=tan(45)"          # → 1
curl "http://127.0.0.1:3000/?expr=arctan(1)"        # → 45

# Modulo / integer division
curl "http://127.0.0.1:3000/?expr=mod(10,3)"        # → 1
curl "http://127.0.0.1:3000/?expr=div(10,3)"        # → 3

# Logarithmic
curl "http://127.0.0.1:3000/?expr=e()"              # → 2.718281828...
curl "http://127.0.0.1:3000/?expr=ln(2.718281828)"  # → ~1

# Statistics
curl "http://127.0.0.1:3000/?expr=sum(1,2,3,4,5)"  # → 15
curl "http://127.0.0.1:3000/?expr=avg(1,2,3,4,5)"  # → 3
```

## WASM Binary Sizes

| File | Size | Notes |
|---|---|---|
| `target/wasm32-wasip2/release/trigonometric_calculator.wasm` | 27 KB | Rust — no runtime overhead |
| `target/wasm32-wasip2/release/arithmetic_calculator.wasm` | 66 KB | Rust — no runtime overhead |
| `target/wasm32-wasip2/release/thecalculaterspin.wasm` | 262 KB | Spin HTTP shell (before composition) |
| `logaritmic-calculater/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculater.wasm` | 2.5 MB | C# / .NET 10 |
| `moddiv/moddiv.wasm` | 12 MB | TypeScript — embeds StarlingMonkey JS engine |
| `statistics-calculator/statistics-calculator.wasm` | 18 MB | Python — embeds CPython runtime |
| `the-calculater/the-calculater.wasm` | 32 MB | Composed: all 5 sub-components bundled |
| `thecalculaterspin/thecalculaterspin-composed.wasm` | 32 MB | Composed Spin app (Spin shell + the-calculater) |

> The size difference between languages is mainly due to embedded runtimes: Rust compiles directly to WASM with no runtime, while TypeScript (SpiderMonkey/StarlingMonkey) and Python (CPython) must bundle their interpreters inside the component.
