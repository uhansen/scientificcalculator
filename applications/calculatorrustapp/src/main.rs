use std::io::Write;

use anyhow::Result;
use clap::Parser;
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder, WasiCtxView, WasiView};

wasmtime::component::bindgen!({
    path: "wit",
    world: "the-calculator",
});

struct HostState {
    wasi: WasiCtx,
    table: wasmtime::component::ResourceTable,
}

impl WasiView for HostState {
    fn ctx(&mut self) -> WasiCtxView<'_> {
        WasiCtxView {
            ctx: &mut self.wasi,
            table: &mut self.table,
        }
    }
}

/// Native Rust host that loads the-calculator WASM component as a plugin.
#[derive(Parser)]
#[command(name = "calculatorrustapp", about = "Scientific Calculator — wasmtime plugin host")]
struct Cli {
    /// Path to the calculator WASM component plugin
    #[arg(long, short)]
    plugin: String,
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = Engine::new(&config)?;

    let component = Component::from_file(&engine, &cli.plugin)?;

    let mut linker: Linker<HostState> = Linker::new(&engine);
    wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;

    let wasi = WasiCtxBuilder::new().inherit_stderr().build();
    let state = HostState {
        wasi,
        table: wasmtime::component::ResourceTable::new(),
    };
    let mut store = Store::new(&engine, state);

    let calc = TheCalculator::instantiate(&mut store, &component, &linker)?;
    let calculator = calc.buildbyhansen_the_calculator_calculator();

    println!("Scientific Calculator — wasmtime plugin host");
    println!("Plugin: {}", cli.plugin);
    println!("Type 'q' to quit.");
    println!("Supported syntax: func(arg1, arg2, ...)");
    println!("Functions:  add  subtract  multiply  divide  sin  cos  tan  arctan  mod  div  e  ln  sum  avg");
    println!();

    loop {
        print!("calculate: ");
        std::io::stdout().flush()?;

        let mut line = String::new();
        match std::io::stdin().read_line(&mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }

        let input = line.trim();
        if input == "q" || input == "quit" {
            break;
        }
        if input.is_empty() {
            continue;
        }

        let result = calculator.call_calculate(&mut store, input)?;
        println!("{}", result);
    }

    Ok(())
}
