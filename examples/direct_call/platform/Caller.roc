## Caller Module
## Demonstrates platform → Roc communication using registered function references
##
## Instead of passing closures directly (which causes issues), we register
## function identifiers that the platform can look up and call using the
## _caller pattern.

Caller := [].{
    ## Register a function with the platform by name
    ## Returns an opaque reference that the platform can use to call the function
    register! : Str => [Ok(U64), Err(Str)]

    ## Call a registered function with a string argument
    ## This demonstrates the platform calling back into Roc using the _caller pattern
    ## The function must have signature: Str -> [Ok(Str), Err(Str)]
    call_registered! : U64, Str => [Ok(Str), Err(Str)]

    ## Get the number of registered functions
    count! : {} => U64

    ## Clear all registered functions
    clear! : {} => {}
}
