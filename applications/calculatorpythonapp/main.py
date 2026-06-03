#!/usr/bin/env python3
"""Scientific Calculator — wasmtime plugin host (Python).

Each calculation runs in an isolated subprocess so that WASM components
built with componentize-py (.NET, Python runtimes) that use WASI CLI
internals from background threads cannot crash the host process.
"""

import argparse
import subprocess
import sys
import textwrap


WORKER_SCRIPT = textwrap.dedent("""\
    import sys
    from wasmtime import Config, Engine, Store, WasiConfig
    from wasmtime import component

    plugin_path, expr = sys.argv[1], sys.argv[2]

    config = Config()
    config.wasm_component_model = True
    engine = Engine(config)
    comp = component.Component.from_file(engine, plugin_path)
    linker = component.Linker(engine)
    linker.add_wasip2()
    store = Store(engine, WasiConfig())
    instance = linker.instantiate(store, comp)
    iface_idx = comp.get_export_index("buildbyhansen:the-calculator/calculator@0.1.0")
    calc_idx = instance.get_export_index(store, "calculate", iface_idx)
    calculate = instance.get_func(store, calc_idx)
    result = calculate(store, expr)
    calculate.post_return(store)
    print(result)
""")


def calculate(plugin_path: str, expr: str) -> str:
    """Run one calculation in an isolated subprocess and return the result."""
    proc = subprocess.run(
        [sys.executable, "-c", WORKER_SCRIPT, plugin_path, expr],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        return proc.stdout.strip()
    # Detect a wasmtime WASI CLI panic (from .NET / componentize-py components
    # that access WASI stdio from background threads)
    stderr = proc.stderr
    if "panicked" in stderr or "Aborted" in stderr:
        func = expr.split("(")[0].strip()
        return (
            f"Error: '{func}' uses a polyglot component (.NET or Python runtime) "
            f"that requires WASI CLI stdio from a background thread — "
            f"not supported by the Python wasmtime C API. "
            f"Use calculatorrustapp for full support."
        )
    return f"Error: worker exited with code {proc.returncode}: {stderr.strip()}"


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="calculatorpythonapp",
        description="Scientific Calculator — wasmtime plugin host",
    )
    parser.add_argument("--plugin", "-p", required=True, help="Path to the calculator WASM component plugin")
    args = parser.parse_args()

    print("Scientific Calculator — wasmtime plugin host (Python)")
    print(f"Plugin: {args.plugin}")
    print("Type 'q' to quit.")
    print("Supported syntax: func(arg1, arg2, ...)")
    print("Functions:  add  subtract  multiply  divide  sin  cos  tan  arctan  mod  div  e  ln  sum  avg")
    print()

    while True:
        try:
            line = input("calculate: ")
        except (EOFError, KeyboardInterrupt):
            print()
            break

        expr = line.strip()
        if expr in ("q", "quit"):
            break
        if not expr:
            continue

        print(calculate(args.plugin, expr))


if __name__ == "__main__":
    main()
