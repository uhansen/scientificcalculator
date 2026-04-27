mod bindings {
    wit_bindgen::generate!({
        path: "wit/world.wit",
    });

    use super::Calculator;
    export!(Calculator);
}

struct Calculator;

impl bindings::exports::docs::arithmetic_calculator::arithmetic::Guest for Calculator {
    fn add(x: f64, y: f64) -> f64 {
        x + y
    }

    fn subtract(x: f64, y: f64) -> f64 {
        x - y
    }

    fn multiply(x: f64, y: f64) -> f64 {
        x * y
    }

    fn divide(x: f64, y: f64) -> Result<f64, String> {
        if y == 0.0 {
            Err(String::from("division by zero"))
        } else {
            Ok(x / y)
        }
    }
}
