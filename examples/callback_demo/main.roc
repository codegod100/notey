app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Events

main! = || {
    Stdout.line!("=== Callback Demo: Platform → Roc ===")
    Stdout.line!("")
    Stdout.line!("This demo shows how Roc can pass a callback to the platform.")
    Stdout.line!("")
    
    # Define our callback - this function will be passed to the platform
    my_callback = |msg| {
        Stdout.line!("🔔 Roc callback received: ${msg}")
    }
    
    # Pass our callback to the platform
    Stdout.line!("Passing callback to platform...")
    Events.run_with_callback!(my_callback)
    
    Stdout.line!("")
    Stdout.line!("=== Demo Complete ===")
}
