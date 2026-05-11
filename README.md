# Scientific Calculator – WASM Components

WebAssembly components built in Rust, TypeScript, C#, and Python, following the [Bytecode Alliance guides](https://component-model.bytecodealliance.org/language-support/).

## Components

### `the-calculater` (Rust shell — composed from all five sub-components)
A composed WASM component that bundles all five calculators into a single binary.
Exports the `docs:the-calculater/calculator@0.1.0` interface with one method:

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

## Prerequisites

```sh
rustup target add wasm32-wasip2
cargo install --locked wasm-tools
cargo install wac-cli          # for composing the-calculater
```

## Build

### `the-calculater` (composed)

First build all five sub-components (see below), then:

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

### Rust components (arithmetic + trigonometric + the-calculater shell)

From the repo root (the Cargo workspace builds all three):

```sh
cargo build --target wasm32-wasip2 --release
```

Output binaries (shared workspace `target/` at repo root):

```
target/wasm32-wasip2/release/arithmetic_calculator.wasm
target/wasm32-wasip2/release/trigonometric_calculator.wasm
target/wasm32-wasip2/release/the_calculater.wasm   # shell (unlinked)
```

### `moddiv` (TypeScript)

```sh
cd moddiv
npm install
npm run build   # compiles TypeScript → JS, then componentizes → moddiv.wasm
```

### `logaritmic-calculater` (C# / .NET 10)

Requires [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0).

```sh
cd logaritmic-calculater
dotnet build -c Release
# output: bin/Release/net10.0/wasi-wasm/native/logaritmic-calculater.wasm
```

### `statistics-calculator` (Python)

Requires Python 3.10+ and `componentize-py`.

```sh
pip install componentize-py
cd statistics-calculator
componentize-py --wit-path wit/component.wit --world statistics-calculator componentize app -o statistics-calculator.wasm
```

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

## Inspect

```sh
wasm-tools component wit the-calculater/the-calculater.wasm
wasm-tools component wit target/wasm32-wasip2/release/arithmetic_calculator.wasm
wasm-tools component wit target/wasm32-wasip2/release/trigonometric_calculator.wasm
wasm-tools component wit moddiv/moddiv.wasm
wasm-tools component wit logaritmic-calculater/bin/Release/net10.0/wasi-wasm/native/logaritmic-calculater.wasm
wasm-tools component wit statistics-calculator/statistics-calculator.wasm
```
