#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

wasm-tools component embed wit/world.wit complex.core.wat -o complex.core.wasm
wasm-tools component new complex.core.wasm -o complex-calculator.wasm
wasm-tools parse complex.component.wat -o complex-calculator.component.wasm

for component in complex-calculator.wasm complex-calculator.component.wasm; do
  wasm-tools validate "$component"
  wasm-tools component wit "$component"
done

./test.sh
