app [main!] {
    pf: platform "./platform/main.roc",
}

import pf.Stdout
import pf.Callbacks

main! : List(Str) => [Ok({}), Err(Str)]
main! = |_args| {
    Stdout.line!("=== Simple Callback Demo ===")
    Stdout.line!("This demonstrates Platform → Roc callbacks")
    Stdout.line!("")

    # Example 1: Register a callback and invoke it
    Stdout.line!("Example 1: Register and invoke callback")
    Stdout.line!("----------------------------------------")

    match Callbacks.set_callback!(process_string!) {
        Ok({}) => {
            Stdout.line!("✓ Callback registered successfully")
        }
        Err(msg) => {
            Stdout.line!("✗ Failed to register callback: ${msg}")
            return Err("Failed to register callback")
        }
    }

    Stdout.line!("Platform will now invoke the callback...")
    match Callbacks.invoke_callback!("Hello from platform!") {
        Ok(result) => {
            Stdout.line!("✓ Platform received result from Roc: \"${result}\"")
        }
        Err(msg) => {
            Stdout.line!("✗ Callback returned error: ${msg}")
        }
    }

    Stdout.line!("")

    # Example 2: Process a string with a one-shot callback
    Stdout.line!("Example 2: One-shot callback processing")
    Stdout.line!("----------------------------------------")

    match Callbacks.process_with_callback!("Transform Me!", uppercase_transform!) {
        Ok(result) => {
            Stdout.line!("✓ One-shot callback result: \"${result}\"")
        }
        Err(msg) => {
            Stdout.line!("✗ One-shot callback returned error: ${msg}")
        }
    }

    Stdout.line!("")

    # Example 3: Demonstrate callback that returns an error
    Stdout.line!("Example 3: Callback that returns an error")
    Stdout.line!("----------------------------------------")

    match Callbacks.process_with_callback!("error", error_if_empty!) {
        Ok(result) => {
            Stdout.line!("✓ Unexpected success: \"${result}\"")
        }
        Err(msg) => {
            Stdout.line!("✓ Callback correctly returned error: ${msg}")
        }
    }

    Stdout.line!("")
    Stdout.line!("=== Demo Complete ===")
    Stdout.line!("Platform successfully called back into Roc code!")
    Ok({})
}

# Callback function that processes a string
# Called by the platform
process_string! : Str => [Ok(Str), Err(Str)]
process_string! = |input| {
    Stdout.line!("  [Roc Callback] Processing: \"${input}\"")

    # Simple transformation: add a prefix and convert to uppercase
    if Str.count_utf8_bytes(input) == 0 {
        Err("Input string is empty")
    } else {
        result = "[PROCESSED] " ++ Str.to_upper(input)
        Ok(result)
    }
}

# One-shot callback: transform string to uppercase
uppercase_transform! : Str => [Ok(Str), Err(Str)]
uppercase_transform! = |input| {
    Stdout.line!("  [Roc Callback] Uppercasing: \"${input}\"")
    Ok(Str.to_upper(input))
}

# Callback that returns an error for empty strings
error_if_empty! : Str => [Ok(Str), Err(Str)]
error_if_empty! = |input| {
    Stdout.line!("  [Roc Callback] Checking for error condition...")

    if Str.count_utf8_bytes(input) == 0 {
        Err("String cannot be empty")
    } else {
        Ok(input)
    }
}
