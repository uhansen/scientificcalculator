wit_bindgen::generate!({
    path: "wit",
    world: "calculator-cli",
    generate_all,
});

use buildbyhansen::the_calculater::calculator::calculate;

fn main() {
    println!("Scientific Calculator — type 'q' to quit");
    println!("Supported: add  subtract  multiply  divide  sin  cos  tan  arctan");
    println!("           mod  div  e  ln  sum  avg");
    println!();

    loop {
        print!("calculate: ");
        use std::io::Write;
        std::io::stdout().flush().unwrap();

        let mut line = String::new();
        match std::io::stdin().read_line(&mut line) {
            Ok(0) | Err(_) => break, // EOF
            Ok(_) => {}
        }

        let input = line.trim();
        if input == "q" || input == "quit" {
            break;
        }
        if input.is_empty() {
            continue;
        }

        let result = calculate(input);
        println!("{}", result);
    }
}
