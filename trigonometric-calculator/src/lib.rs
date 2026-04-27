use std::f64::consts::PI;

mod bindings {
    wit_bindgen::generate!({
        path: "wit/world.wit",
    });

    use super::TrigCalculator;
    export!(TrigCalculator);
}

struct TrigCalculator;

impl bindings::exports::docs::trigonometric_calculator::trigonometric::Guest for TrigCalculator {
    fn sin(degrees: f64) -> f64 {
        (degrees * PI / 180.0).sin()
    }

    fn cos(degrees: f64) -> f64 {
        (degrees * PI / 180.0).cos()
    }

    fn tan(degrees: f64) -> f64 {
        (degrees * PI / 180.0).tan()
    }

    fn arctan(value: f64) -> f64 {
        value.atan() * 180.0 / PI
    }
}
