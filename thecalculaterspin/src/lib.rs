use spin_sdk::http::{IntoResponse, Method, Request, StatusCode};
use spin_sdk::{http_service, wit_bindgen};

wit_bindgen::generate!({
    path: "wit",
    world: "calculator-import",
    generate_all,
});

/// HTTP handler: GET /?expr=<expression>
/// Delegates to the-calculater composed component and returns the result.
#[http_service]
async fn handle(req: Request) -> impl IntoResponse {
    if req.method() != Method::GET {
        return (StatusCode::METHOD_NOT_ALLOWED, "Only GET is supported\n".to_string());
    }

    let expr = get_expr(&req);

    if expr.is_empty() {
        return (
            StatusCode::OK,
            "Missing expression.\n\
             Usage: GET /?expr=<expression>\n\
             Examples:\n\
             - add(2,3)    subtract(10,4)    multiply(3,7)    divide(10,2)\n\
             - sin(30)     cos(45)           tan(60)          arctan(1)\n\
             - mod(10,3)   div(10,3)\n\
             - e()         ln(2.718)\n\
             - sum(1,2,3)  avg(4,5,6)\n"
                .to_string(),
        );
    }

    let result = docs::the_calculater::calculator::calculate(&expr);
    (StatusCode::OK, result)
}

fn get_expr(req: &Request) -> String {
    if let Some(query) = req.uri().query() {
        for pair in query.split('&') {
            if let Some(value) = pair.strip_prefix("expr=") {
                return urlencoded_decode(value);
            }
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

