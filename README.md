# Scientific Calculator – WASM Components

Two WebAssembly components implemented in Rust targeting `wasm32-wasip2`, following the [Bytecode Alliance guide](https://component-model.bytecodealliance.org/language-support/building-a-simple-component/rust.html).

## Components

### `arithmetic-calculator`
Exports an `arithmetic` interface with:
- `add(x: f64, y: f64) -> f64`
- `subtract(x: f64, y: f64) -> f64`
- `multiply(x: f64, y: f64) -> f64`
- `divide(x: f64, y: f64) -> result<f64, string>` — returns an error on division by zero

### `trigonometric-calculator`
Exports a `trigonometric` interface with (angles in degrees):
- `sin(degrees: f64) -> f64`
- `cos(degrees: f64) -> f64`
- `tan(degrees: f64) -> f64`
- `arctan(value: f64) -> f64` — returns degrees

## Prerequisites

```sh
rustup target add wasm32-wasip2
cargo install --locked wasm-tools
```

## Build

From the repo root (the Cargo workspace builds both components):

```sh
cargo build --target wasm32-wasip2 --release
```

Or build individually:

```sh
cargo build -p arithmetic-calculator --target wasm32-wasip2 --release
cargo build -p trigonometric-calculator --target wasm32-wasip2 --release
```

Output binaries (shared workspace `target/` at repo root):

```
target/wasm32-wasip2/release/arithmetic_calculator.wasm
target/wasm32-wasip2/release/trigonometric_calculator.wasm
```

## Inspect

```sh
wasm-tools component wit target/wasm32-wasip2/release/arithmetic_calculator.wasm
wasm-tools component wit target/wasm32-wasip2/release/trigonometric_calculator.wasm
```
