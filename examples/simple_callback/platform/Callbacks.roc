Callbacks := [].{
    ## A simple callback function that processes a string and returns a result
    ## This demonstrates Platform → Roc communication
    StringCallback : Str -> [Ok(Str), Err(Str)]

    ## Register a callback function with the platform
    ## The stored callback can be called later by platform code
    set_callback! : StringCallback => [Ok({}), Err(Str)]

    ## Trigger the callback from the platform with a string argument
    ## This demonstrates the platform calling back into Roc
    invoke_callback! : Str => [Ok(Str), Err(Str)]

    ## Alternative: Set a callback and invoke it in one operation
    ## Useful for one-shot processing
    process_with_callback! : (Str, StringCallback) => [Ok(Str), Err(Str)]

    ## Check if a callback is currently registered
    has_callback! : {} => Bool

    ## Clear (unregister) the current callback
    clear_callback! : {} => {}
}
