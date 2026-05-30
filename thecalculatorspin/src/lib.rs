use anyhow::Result;
use spin_sdk::http::{IntoResponse, Method, Request, Response};
use spin_sdk::http_component;

wit_bindgen::generate!({
    path: "wit",
    world: "calculator-import",
    generate_all,
});

/// HTTP handler: GET /?calculate=<expression>
/// Delegates to the-calculator composed component and returns the result.
#[http_component]
fn handle(req: Request) -> Result<impl IntoResponse> {
    if req.method() != &Method::Get {
        return Ok(Response::new(405, "Only GET is supported\n"));
    }

    let expr = get_expr(&req);

    if expr.is_empty() {
        return Ok(Response::new(
            200,
            "Missing expression.\n\
             Usage: GET /?calculate=<expression>\n\
             Examples:\n\
             - add(2,3)    subtract(10,4)    multiply(3,7)    divide(10,2)\n\
             - sin(30)     cos(45)           tan(60)          arctan(1)\n\
             - mod(10,3)   div(10,3)\n\
             - e()         ln(2.718)\n\
             - sum(1,2,3)  avg(4,5,6)\n",
        ));
    }

    let result = buildbyhansen::the_calculator::calculator::calculate(&expr);
    Ok(Response::new(200, result))
}

fn get_expr(req: &Request) -> String {
    let uri = req.uri();
    let query = uri.split('?').nth(1).unwrap_or("");
    for pair in query.split('&') {
        if let Some(value) = pair.strip_prefix("calculate=") {
            return urlencoded_decode(value);
        }
    }
    String::new()
}

fn urlencoded_decode(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '+' {
            result.push(' ');
        } else if c == '%' {
            let h1 = chars.next().unwrap_or('0');
            let h2 = chars.next().unwrap_or('0');
            let hex = format!("{}{}", h1, h2);
            if let Ok(byte) = u8::from_str_radix(&hex, 16) {
                result.push(byte as char);
            }
        } else {
            result.push(c);
        }
    }
    result
}

