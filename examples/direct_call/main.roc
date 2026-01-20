app [main!] {
    pf: platform "./platform/main.roc",
}

import pf.Caller
import pf.Stdout

main! : List(Str) => [Ok({}), Err(Str)]
main! = |_args| {
    Stdout.line!("=== Direct Call Demo ===")
    Stdout.line!("Demonstrates Platform → Roc communication")
    Stdout.line!("")

    # Example 1: Register and call a string processor
    Stdout.line!("Example 1: Registering callback...")

    match Caller.register!("uppercase") {
        Ok(id) => {
            Stdout.line!("  ✓ Registered 'uppercase' with ID: ${id.to_str()}")
        }
        Err(msg) => {
            Stdout.line!("  ✗ Failed to register: ${msg}")
            return Err("Registration failed")
        }
    }

    # Call the registered function from the platform
    Stdout.line!("  Platform invoking 'uppercase'...")
    match Caller.call_registered!(0, "hello from platform!") {
        Ok(result) => {
            Stdout.line!("  Result: \"${result}\"")
        }
        Err(msg) => {
            Stdout.line!("  Error: ${msg}")
        }
    }

    Stdout.line!("")

    # Example 2: Register another function
    match Caller.register!("process") {
        Ok(id) => {
            Stdout.line!("Example 2: Registered 'process' with ID: ${id.to_str()}")
            match Caller.call_registered!(1, "transform me") {
                Ok(result) => {
                    Stdout.line!("  Result: \"${result}\"")
                }
                Err(msg) => {
                    Stdout.line!("  Error: ${msg}")
                }
            }
        }
        Err(msg) => {
            Stdout.line!("  Error: ${msg}")
        }
    }

    Stdout.line!("")

    # Show total registrations
    count = Caller.count!({})
    Stdout.line!("Total registered callbacks: ${count.to_str()}")
    Stdout.line!("")
    Stdout.line!("=== Demo Complete ===")

    Ok({})
}

# This example uses a registration pattern instead of passing functions directly,
# which avoids the closure handling issues in the current Roc interpreter.
# The platform maintains a registry of functions by ID, and can call them
# using the _caller pattern.
