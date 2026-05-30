
wit_bindgen::generate!({
    path: "wit",
    world: "the-calculator",
    generate_all,
});

use buildbyhansen::arithmetic_calculator::arithmetic as arith;
use buildbyhansen::logaritmic_calculator::logaritmic as log;
use buildbyhansen::moddiv::moddiv as md;
use buildbyhansen::statistics_calculator::statistics as stats;
use buildbyhansen::trigonometric_calculator::trigonometric as trig;

struct Component;

impl exports::buildbyhansen::the_calculator::calculator::Guest for Component {
    fn calculate(expr: String) -> String {
        match parse_and_dispatch(&expr) {
            Ok(result) => result,
            Err(e) => format!("Error: {e}"),
        }
    }
}

fn parse_and_dispatch(expr: &str) -> Result<String, String> {
    let expr = expr.trim();

    let paren = expr
        .find('(')
        .ok_or("Invalid expression: expected '('")?;
    let func = expr[..paren].trim().to_lowercase();

    let close = expr
        .rfind(')')
        .ok_or("Invalid expression: expected ')'")?;
    let args_str = expr[paren + 1..close].trim();

    let args: Vec<f64> = if args_str.is_empty() {
        vec![]
    } else {
        args_str
            .split(',')
            .map(|a| {
                a.trim()
                    .parse::<f64>()
                    .map_err(|_| format!("Invalid number: '{}'", a.trim()))
            })
            .collect::<Result<Vec<_>, _>>()?
    };

    let result = match func.as_str() {
        // ── Arithmetic ──────────────────────────────────────────────────────
        "add" => {
            need(&args, 2, "add")?;
            arith::add(args[0], args[1]).to_string()
        }
        "subtract" => {
            need(&args, 2, "subtract")?;
            arith::subtract(args[0], args[1]).to_string()
        }
        "multiply" => {
            need(&args, 2, "multiply")?;
            arith::multiply(args[0], args[1]).to_string()
        }
        "divide" => {
            need(&args, 2, "divide")?;
            arith::divide(args[0], args[1]).map_err(|e| e)?
                .to_string()
        }

        // ── Trigonometric ────────────────────────────────────────────────────
        "sin" => {
            need(&args, 1, "sin")?;
            trig::sin(args[0]).to_string()
        }
        "cos" => {
            need(&args, 1, "cos")?;
            trig::cos(args[0]).to_string()
        }
        "tan" => {
            need(&args, 1, "tan")?;
            trig::tan(args[0]).to_string()
        }
        "arctan" => {
            need(&args, 1, "arctan")?;
            trig::arctan(args[0]).to_string()
        }

        // ── ModDiv ───────────────────────────────────────────────────────────
        "mod" => {
            need(&args, 2, "mod")?;
            md::mod_(args[0], args[1]).to_string()
        }
        "div" => {
            need(&args, 2, "div")?;
            md::div(args[0], args[1]).to_string()
        }

        // ── Logarithmic ──────────────────────────────────────────────────────
        "e" => {
            need(&args, 0, "e")?;
            log::e().to_string()
        }
        "ln" => {
            need(&args, 1, "ln")?;
            log::ln(args[0]).to_string()
        }

        // ── Statistics ───────────────────────────────────────────────────────
        "sum" => {
            if args.is_empty() {
                return Err("sum requires at least one number".into());
            }
            stats::sum(&args).to_string()
        }
        "avg" => {
            if args.is_empty() {
                return Err("avg requires at least one number".into());
            }
            stats::avg(&args).to_string()
        }

        other => return Err(format!("Unknown function: '{other}'")),
    };

    Ok(result)
}

fn need(args: &[f64], n: usize, func: &str) -> Result<(), String> {
    if args.len() == n {
        Ok(())
    } else {
        Err(format!(
            "{func} expects {n} argument(s), got {}",
            args.len()
        ))
    }
}

export!(Component);
