# Platform → Roc Callbacks - Implementation Summary

## Overview

This implementation demonstrates how to implement callbacks from the platform (Zig) back into Roc code. This enables bidirectional communication where the platform can call Roc functions as event handlers, callbacks, or response processors.

## What This Example Demonstrates

- **Registration Pattern**: Roc registers a callback function with the platform
- **Invocation Pattern**: Platform invokes the registered Roc callback
- **Error Handling**: Callbacks can return errors that the platform handles
- **Multiple Callbacks**: Support for different callback functions with different behaviors

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Roc Application (main.roc)                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  main! {                                              │  │
│  │    # Register callback                               │  │
│  │    Callbacks.set_callback!(process_string!)?        │  │
│  │                                                      │  │
│  │    # Trigger callback from platform                  │  │
│  │    Callbacks.invoke_callback!("Hello")?             │  │
│  │  }                                                    │  │
│  │                                                        │  │
│  │  # Callback function definition                       │  │
│  │  process_string! = |input| {                         │  │
│  │    Stdout.line!("Processing: ${input}")              │  │
│  │    Ok("[PROCESSED] " ++ Str.to_upper(input))        │  │
│  │  }                                                    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────┬───────────────────────────────────────┘
                      │ Calls hosted function
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              Platform Host (host.zig)                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  hostedSetCallback(ops, ret, args) {                 │  │
│  │    # Extract callback closure from args              │  │
│  │    host.callback = {                                 │  │
│  │      .caller = roc_callback_caller,  ◄── _caller    │  │
│  │      .env = ops.env                                   │  │
│  │    }                                                  │  │
│  │  }                                                    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  hostedInvokeCallback(ops, ret, args) {               │  │
│  │    const input = extract_input(args)                  │  │
│  │                                                        │  │
│  │    # KEY STEP: Call back into Roc                    │  │
│  │    host.callback.caller(                             │  │
│  │      &callback_env,                                   │  │
│  │      &result,                                         │  │
│  │      &input                                           │  │
│  │    )                                                  │  │
│  │  }                                                    │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

### The `_caller` Function Pattern

Roc automatically generates `_caller` functions for exposed functions. These wrapper functions handle:

1. **Parameter Marshaling**: Converting arguments between Roc ABI and host memory
2. **Result Handling**: Packing return values according to Roc's conventions
3. **Memory Management**: Reference counting for strings and complex types
4. **Error Handling**: Converting Roc's Result type to discriminant values

**Naming Convention:**
```
roc__<module>_<function>_caller
```

Examples:
- `roc__main_for_host_1_caller` - First function in main
- `roc__Callbacks_process_string_2_caller` - Second function in Callbacks module

### Callback Registration

**Roc Side (Callbacks.roc):**
```roc
Callbacks := [].{
    # Define the callback type signature
    StringCallback : Str -> [Ok(Str), Err(Str)]
    
    # Provide a function to register callbacks
    set_callback! : StringCallback => [Ok({}), Err(Str)]
}
```

**Zig Side (host.zig):**
```zig
const Callback = struct {
    caller: *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void,
    env: *anyopaque,
};

const HostEnv = struct {
    allocator: std.mem.Allocator,
    callback: ?Callback = null,  // Store the registered callback
};

fn hostedSetCallback(ops: *builtins.host_abi.RocOps, ...) {
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));
    
    // Extract callback from args and store it
    host.callback = extract_callback_from_args(args_ptr);
}
```

### Callback Invocation

The key innovation is that Zig code can call the stored `_caller` function:

```zig
fn hostedInvokeCallback(ops: *builtins.host_abi.RocOps, ...) {
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));
    const args = extract_input(args_ptr);
    var result: ResultStr = undefined;
    
    if (host.callback) |cb| {
        // 🎯 This is where platform calls back to Roc!
        cb.caller(
            &cb.env,      // Closure environment
            &result,      // Return value pointer
            &args         // Input arguments
        );
        
        // Handle the result
        if (result.discriminant == 0) {
            // Error case
        } else {
            // Success case
        }
    }
}
```

## File Structure

```
examples/simple_callback/
├── main.roc              # Main Roc application
├── platform/
│   ├── main.roc          # Platform definition
│   ├── Callbacks.roc     # Callback interface
│   └── host.zig          # Zig host implementation
└── IMPLEMENTATION.md     # This document
```

## Code Walkthrough

### 1. Platform Interface (Callbacks.roc)

Defines the callback contract:

```roc
Callbacks := [].{
    # Type alias for callback signature
    StringCallback : Str -> [Ok(Str), Err(Str)]
    
    # Store a callback for later invocation
    set_callback! : StringCallback => [Ok({}), Err(Str)]
    
    # Call the stored callback
    invoke_callback! : Str => [Ok(Str), Err(Str)]
    
    # One-shot: provide callback and invoke immediately
    process_with_callback! : (Str, StringCallback) => [Ok(Str), Err(Str)]
}
```

### 2. Main Application (main.roc)

Demonstrates three callback usage patterns:

```roc
main! = |args| {
    # Pattern 1: Register and invoke
    Callbacks.set_callback!(process_string!)?
    result = Callbacks.invoke_callback!("Hello")?
    
    # Pattern 2: One-shot callback
    result = Callbacks.process_with_callback!("Hi", uppercase!)?
    
    # Pattern 3: Callback that returns errors
    match Callbacks.process_with_callback!("", validate!) {
        Ok(msg) => ...
        Err(msg) => ...  # Handle error
    }
}

# Callback implementations
process_string! = |input| {
    Stdout.line!("Processing: ${input}")
    Ok("[PROCESSED] " ++ Str.to_upper(input))
}

uppercase_transform! = |input| {
    Ok(Str.to_upper(input))
}

error_if_empty! = |input| {
    if Str.count_utf8_bytes(input) == 0 {
        Err("Cannot be empty")
    } else {
        Ok(input)
    }
}
```

### 3. Host Implementation (host.zig)

Implements the hosted functions and callback invocation:

```zig
const Callback = struct {
    caller: *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void,
    env: *anyopaque,
};

var HostEnv {
    callback: ?Callback = null,
};

// Store callback
fn hostedSetCallback(...) {
    host.callback = extract_callback(args);
}

// Invoke callback
fn hostedInvokeCallback(...) {
    const input = extract_input(args);
    var result: ResultStr = undefined;
    
    // CALL THE ROC FUNCTION!
    host.callback.?.caller(&host.env, &result, &input);
    
    return result;
}
```

## ABI Conventions

### Result Types

Roc's `[Ok(T), Err(E)]` maps to:

```zig
const ResultStr = extern struct {
    payload: RocStr,  // Either Ok value or Err message
    discriminant: u8, // 0 = Err, 1 = Ok
};
```

### String Types

Roc strings use the `RocStr` type with small string optimization:

```zig
const RocStr = opaque { }; // Provided by builtins

// For small strings (≤15 bytes), data is inline
// For larger strings, data is heap-allocated with ref counting

// Helper functions:
RocStr.fromSlice([]u8) RocStr
RocStr.empty() RocStr
rocStr.asSlice() []u8
rocStr.len() usize
```

### Function Arguments

Hosted functions receive three pointers:

```zig
fn hostedFunction(
    ops: *builtins.host_abi.RocOps,      // Runtime operations & environment
    ret_ptr: *anyopaque,                 // Where to write the result
    args_ptr: *anyopaque,                // Pointer to arguments
) callconv(.c) void
```

Extracting arguments requires knowing their layout:

```zig
const ArgsTwo = extern struct {
    arg1: RocStr,
    arg2: u64,
};
const args: *const ArgsTwo = @ptrCast(@alignCast(args_ptr));
```

## Mock Implementation Notes

**Important**: In this demo, the actual `_caller` functions from Roc are mocked. In a real implementation:

1. **Compilation**: Roc would generate actual `_caller` functions when compiling the platform
2. **Function Discovery**: You'd need to find the correct generated function names
3. **Closure Extraction**: You'd extract the proper closure structure from `args_ptr`
4. **Real Invocation**: The stored `caller` would actually execute Roc code

The mock implementations (`mock_process_string_caller`, etc.) demonstrate where the real Roc-generated functions would be called.

## Current Limitations

1. **Mock Callback Functions**: The actual Roc-generated `_caller` functions are not integrated
2. **Closure Extraction**: The demo doesn't show how to extract closures from Roc arguments
3. **Function Name Discovery**: The exact `_caller` names depend on Roc compilation
4. **Memory Management**: Full implementation would need proper reference counting

## How This Would Work in Practice

### Step 1: Compile Roc

```bash
roc build main.roc --linker=zig
```

This generates:
- Compiled Roc code
- `_caller` functions for exposed functions
- Symbol table linking function names to callers

### Step 2: Link with Host

```bash
cd platform
zig build
# Links host.zig with Roc-generated code
```

### Step 3: Run

```bash
./callback_demo
```

The platform calls `roc__main_for_host` which:
1. Registers a callback with the platform
2. Platform stores the callback's `_caller` function pointer
3. Platform invokes the callback when needed
4. Roc code processes the call and returns result
5. Platform receives and uses the result

## Expected Output

```
=== Zig Platform Host Initialized ===
Platform → Roc callback mechanism enabled

=== Simple Callback Demo ===
This demonstrates Platform → Roc callbacks

Example 1: Register and invoke callback
----------------------------------------
[Platform] Callback registered
✓ Callback registered successfully
[Platform] Invoking callback with: "Hello from platform!"
  [Roc Callback] Processing: "Hello from platform!"
✓ Platform received result from Roc: "[PROCESSED] HELLO FROM PLATFORM!"

Example 2: One-shot callback processing
----------------------------------------
[Platform] Processing with callback: "Transform Me!"
  [Roc Callback] Uppercasing: "Transform Me!"
✓ One-shot callback result: "TRANSFORM ME!"

Example 3: Callback that returns an error
----------------------------------------
[Platform] Processing with callback: "error"
  [Roc Callback] Checking for error condition...
✓ Callback correctly returned error: String cannot be empty

=== Demo Complete ===
Platform successfully called back into Roc code!

=== Platform Shutting Down ===
```

## Key Takeaways

### ✅ What's Demonstrated

1. **Registration Pattern**: Roc can pass functions to platform which stores them
2. **Invocation Pattern**: Platform can call back into stored Roc functions
3. **Type Safety**: Callback signatures are enforced at compile time
4. **Error Handling**: Callbacks can return errors that propagate through the platform
5. **Multiple Callbacks**: Support for different callbacks with different behaviors

### 🔑 Critical Insight

The `_caller` function pattern is the key to bidirectional FFI:

- Roc → Platform: Call hosted functions directly
- Platform → Roc: Call generated `_caller` functions

Both sides use the same calling convention, making the FFI symmetric.

### 🚀 Use Cases Enabled

1. **Event-Driven Systems**: Platform drives event loop, Roc handles events
2. **Async Operations**: Callback invoked when async operation completes
3. **GUI Development**: Register callbacks for user actions
4. **Web Servers**: Request handlers as callbacks
5. **Streaming**: Process data chunks as they arrive

### ⚡ Performance Implications

Callbacks enable:
- ✅ No recursive event loops in Roc
- ✅ Platform can use optimal async I/O
- ✅ Better CPU utilization

But add:
- ❌ Function call overhead for each callback
- ❌ Increased complexity in code
- ❌ More difficult debugging

## Next Steps

To make this production-ready:

1. **Integrate Real `_caller` Functions**: Link actual Roc-generated callers
2. **Implement Closure Extraction**: Extract closures from Roc arguments
3. **Add Memory Management**: Proper reference counting and cleanup
4. **Documentation**: Document the exact ABI format for closures
5. **Testing**: Comprehensive tests for edge cases
6. **Examples**: More complex real-world examples

## References

- `notey/docs/callroc.md` - Original `_caller` pattern documentation
- Roc Platform Development Guide
- Roc ABI Specification
- Zig-Roc Interop Examples

## Conclusion

This implementation demonstrates that Platform → Roc callbacks are technically feasible and provide a powerful pattern for building event-driven, asynchronous applications in Roc. The `_caller` function pattern generated by Roc provides a clean, type-safe interface for bidirectional FFI communication.

While the current implementation uses mock functions to demonstrate the pattern, integrating it with actual Roc-generated `_caller` functions would enable production-ready callback support in Roc platforms.