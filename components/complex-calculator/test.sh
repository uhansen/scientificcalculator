#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if (( $# > 1 )) || [[ "${1:-}" != "" && "${1:-}" != "--composed" ]]; then
  echo "Usage: $0 [--composed]" >&2
  exit 1
fi

expect() {
  local expected="$1"
  shift
  local actual
  actual="$("$@")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Failed: %s\nExpected: %s\nActual: %s\n' "$*" "$expected" "$actual" >&2
    exit 1
  fi
}

tmp="$(mktemp -d)"
trap 'rm -f "$tmp/expected.core.wasm" "$tmp/expected.wasm"; rmdir "$tmp"' EXIT

# Compare against a component derived from the WIT, not just against each other.
wasm-tools component embed wit/world.wit --dummy-names legacy -o "$tmp/expected.core.wasm"
wasm-tools component new "$tmp/expected.core.wasm" -o "$tmp/expected.wasm"
expected_wit="$(wasm-tools component wit "$tmp/expected.wasm")"
cmp wit/world.wit ../the-calculator/wit/deps/complex-calculator/world.wit

for component in complex-calculator.wasm complex-calculator.component.wasm; do
  expect "$expected_wit" wasm-tools component wit "$component"
  expect '{re: 4, im: 6}' wasmtime run --invoke \
    'add({re: 1, im: 2}, {re: 3, im: 4})' "$component"
  expect '{re: -1, im: -3}' wasmtime run --invoke \
    'add({re: -1.5, im: 2.25}, {re: 0.5, im: -5.25})' "$component"
  expect '{re: 0, im: 0}' wasmtime run --invoke \
    'add({re: 1, im: -2}, {re: -1, im: 2})' "$component"
  expect '{re: inf, im: nan}' wasmtime run --invoke \
    'add({re: inf, im: nan}, {re: 1, im: 2})' "$component"
done

if [[ "${1:-}" == "--composed" ]]; then
  calculator=../the-calculator/the-calculator.wasm
  wasm-tools validate "$calculator"
  calculator_wit="$(wasm-tools component wit "$calculator")"
  if grep -Eq '^  import buildbyhansen:' <<< "$calculator_wit"; then
    echo "Composed calculator still imports a calculator sub-component" >&2
    exit 1
  fi
  expect '"4+6i"' wasmtime run --invoke 'calculate("cadd(1,2,3,4)")' "$calculator"
  expect '"-1-3i"' wasmtime run --invoke 'calculate("cadd(-1.5,2.25,0.5,-5.25)")' "$calculator"
  expect '"0+0i"' wasmtime run --invoke 'calculate("cadd(1,-2,-1,2)")' "$calculator"
  expect '"Error: cadd expects 4 argument(s), got 3"' \
    wasmtime run --invoke 'calculate("cadd(1,2,3)")' "$calculator"
  expect '"Error: cadd expects 4 argument(s), got 5"' \
    wasmtime run --invoke 'calculate("cadd(1,2,3,4,5)")' "$calculator"
  expect "\"Error: Invalid number: \\'x\\'\"" \
    wasmtime run --invoke 'calculate("cadd(1,2,x,4)")' "$calculator"
  expect '"5"' wasmtime run --invoke 'calculate("add(2,3)")' "$calculator"
  expect '"1"' wasmtime run --invoke 'calculate("sin(90)")' "$calculator"
  expect '"1"' wasmtime run --invoke 'calculate("mod(7,3)")' "$calculator"
  expect '"0"' wasmtime run --invoke 'calculate("ln(1)")' "$calculator"
  expect '"6"' wasmtime run --invoke 'calculate("sum(1,2,3)")' "$calculator"
fi

echo "Complex calculator checks passed"
