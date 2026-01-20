# Platform → Roc Callbacks Implementation

This example demonstrates how to implement callbacks from the platform (Zig) back into Roc code. This is the reverse of the typical pattern where Roc calls platform functions.

## Overview

In most Roc applications, the communication is unirectional:
```
Roc Code → Platform Functions → Foreign Operations
```

Callback support enables bidirectional communication:
```
Roc Code → Platform Functions → Foreign Operations
                ↓
        Roc Callback Functions (for events, async operations, etc.)
```

## Key Pattern: The `_caller` Function

Roc automatically generates `_caller` functions for exposed functions. These caller functions wrap the Roc function with the necessary ABI logic for parameter marshaling, result handling, and memory management.

### Pattern from `callroc.md`:

```zig
// Roc generates this automatically for exposed functions
extern fn roc__main_for_host_1_caller([*]u8, *const RocStr, [*]u8, *RocStr) void;

// Usage in platform code:
pub export fn main() c_int {
    const input = RocStr.fromSlice("hello");
    defer input.decref(null);

    var result: RocStr = undefined;
    roc__main_for_host_1_caller(null, &input, null, &result);
    defer result.decref(null);

    std.debug.print("{s}\n", .{result.asSlice()});
    return 0;
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Roc Application                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  main! {                                                │  │
│  │    Events.set_event_handler!(handle_event!)          │  │
│  │    Events.run_event_loop!()                           │  │
│  │  }                                                    │  │
│  │                                                        │  │
│  │  handle_event! = |event| { ... }  ◄── Callback       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────┬───────────────────────────────────────┘
                      │ Calls platform
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  Platform (Zig)                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  hostedSetEventHandler(...)                          │  │
│  │    // Stores Roc function pointer & environment      │  │
│  │    host.event_handler = {                            │  │
│  │      .caller = roc_handler_caller,  ◄── _caller      │  │
│  │      .env = closure_environment                      │  │
│  │    }                                                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  hostedRunEventLoop(...)                              │  │
│  │    for (events) |event| {                            │  │
│  │      // Call back into Roc!                           │  │
│  │      host.event_handler.caller(                      │  │
│  │        &closure_env,                                 │  │
│  │        &result,                                      │  │
│  │        &event                                        │  │
│  │      )                                                │  │
│  │    }                                                  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. Platform Interface (Roc)

Define the callback interface in `platform/Events.roc`:

```roc
Events := [].{
    Event := [Connected(U64), Disconnected(U64), Message(U64, Str), Error(Str), Shutdown]
    
    ## Register a Roc function as the event handler
    set_event_handler! : (Event -> [Ok({}), Err(Str)]) => [Ok({}), Err(Str)]
    
    ## Run event loop, calling the registered callback for each event
    run_event_loop! : () => [Ok({}), Err(Str)]
}
```

### 2. Roc Application

Create a callback function and register it:

```roc
main! = |args| {
    # Register our handler
    Events.set_event_handler!(handle_event!)?
    
    # Start loop - platform will call back into Roc
    Events.run_event_loop!()
}

handle_event! : Events.Event => [Ok({}), Err(Str)]
handle_event! = |event| {
    match event {
        Connected(client_id) => {
            Stdout.line!("Client ${client_id} connected")
            Ok({})
        }
        Message(client_id, text) => {
            Stdout.line!("Received: ${text}")
            Events.send_message!(client_id, "Echo: ${text}")
        }
        # ... handle other events
    }
}
```

### 3. Platform Host (Zig)

Implement the callback storage and invocation:

```zig
// Store the Roc callback
const EventHandler = struct {
    caller: *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void,
    env: *anyopaque,
};

var host_env = HostEnv{
    .event_handler = null,
    // ...
};

// Accept the callback from Roc
fn hostedSetEventHandler(ops: *builtins.host_abi.RocOps, ...) callconv(.c) void {
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));
    
    // Extract the caller function from args (in real implementation)
    host.event_handler = .{
        .caller = roc_handler_caller,
        .env = closure_environment,
    };
}

// Call back into Roc
fn hostedRunEventLoop(ops: *builtins.host_abi.RocOps, ...) callconv(.c) void {
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));
    
    for (events) |event| {
        var result: ResultUnit = undefined;
        
        // This is the key line: calling Roc from Zig!
        host.event_handler.?.caller(
            &closure_env,
            &result,
            &event,
        );
        
        // Handle result...
    }
}
```

## Function Naming Convention

Roc generates `_caller` functions with this naming pattern:

```
roc__<module>_<function>_caller
```

Examples:
- `roc__main_for_host_1_caller` - First exposed function in main module
- `roc__Events_handle_event_2_caller` - Second exposed function in Events module

The exact name depends on:
1. Module name
2. Function name
3. Position in the exposes list

## Passing Data Through Callbacks

### Roc Side

```roc
# Callback accepts structured data
handle_stream! : StreamEvent => [Ok({}), Err(Str)]
handle_stream! = |event| {
    match event {
        DataReceived(bytes) => {
            # Process the byte array
        }
        StreamClosed => {
            # Cleanup
        }
    }
}
```

### Platform Side

```zig
// Define event structure matching Roc
const StreamEventPayload = extern union {
    // DataReceived: U64 count at offset 0
    byte_count: u64,
    // StreamClosed: no payload
};

const StreamEvent = extern struct {
    payload: StreamEventPayload,
    discriminant: u8, // 0=DataReceived, 1=StreamClosed
};

// Create and send event
var event: StreamEvent = undefined;
event.discriminant = 0;
event.payload.byte_count = bytes_received;

roc_callback_caller(&env, &result, &event);
```

## Error Handling in Callbacks

Callbacks can return errors, which the platform must handle:

```roc
handle_event! = |event| {
    match event {
        Error(msg) => {
            # Return error to stop processing
            Err("Cannot continue: ${msg}")
        }
        other => Ok({})
    }
}
```

```zig
// Platform checks callback result
handler.caller(&env, &result, &event);

if (result.discriminant == 0) { // Error
    // Stop event loop or take corrective action
    return Err(result.payload);
}
```

## Use Cases

### 1. Event-Driven I/O

Instead of Roc polling for events:
```roc
# Old: Pull model
event_loop! = || {
    event = WebServer.accept!()
    handle_event!(event)
    event_loop!()
}
```

Use callbacks:
```roc
# New: Push model
WebServer.on_event!(handle_event!)?
# Platform drives execution here
```

### 2. Async Operations

```roc
fetch_data! = |url| {
    # Register callback for when data arrives
    HttpClient.start_fetch!(url, handle_response!)?
}

handle_response! = HttpResponse => [Ok({}), Err(Str)]
handle_response! = |response| {
    # Process response when it arrives
}
```

### 3. Background Tasks

```roc
TaskManager.spawn!({
    Task.run_async!(process_item!)
})
```

### 4. GUI Event Handling

```roc
Window.on_click!(handle_click!)
Window.on_keypress!(handle_key!)
```

## Memory Management

### Reference Counting

Roc strings and complex types use reference counting:

```zig
// When receiving data from Roc
const input = RocStr.fromSlice("hello");
defer input.decref(null); // Important!

// Pass to Roc callback
roc_callback_caller(&env, &result, &input);

// Roc takes ownership if needed
```

### Allocations in Callbacks

The callback must use the provided allocator from `RocOps`:

```zig
fn hostedRunEventLoop(ops: *builtins.host_abi.RocOps, ...) {
    // Use ops.env to get host environment
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));
    
    // Use host.allocator for allocations
    const data = host.allocator.alloc(u8, 1024) catch return;
    defer host.allocator.free(data);
    
    // Create Roc string from data
    const roc_str = RocStr.init(data.ptr, data.len, ops);
    defer roc_str.decref(null);
    
    // Pass to callback
    handler.caller(&env, &result, &event);
}
```

## Trade-offs

### Push Model (Callbacks)

**Pros:**
- ✅ Platform can use optimal async I/O strategies
- ✅ No recursive calls in Roc code
- ✅ Better support for long-running operations
- ✅ Simpler event handling in some cases

**Cons:**
- ❌ More complex implementation (closures, function pointers)
- ❌ Harder to debug (call flow spans languages)
- ❌ Requires careful memory management
- ❌ Less transparent control flow

### Pull Model (Polling)

**Pros:**
- ✅ Simple to implement and understand
- ✅ Explicit control flow in Roc
- ✅ Easy to debug and test
- ✅ No closure complexity

**Cons:**
- ❌ Recursive event loops
- ❌ Platform async capabilities wasted
- ❌ Higher overhead for some patterns
- ❌ Less natural for event-driven systems

## Building and Running

```bash
# Build the Zig host library
cd platform
zig build x64musl

# Build the Roc application
roc build main.roc --linker=zig -o callback_demo

# Run
./callback_demo
```

## Expected Output

```
=== Zig Platform Host Initialized ===
Platform → Roc callback mechanism is enabled

=== Callback Demo: Platform → Roc ===

This demo shows the platform calling back into Roc code.
The platform will manage the event loop and call our handler.

Registering event handler...
✓ Event handler registered successfully

Starting event loop (platform will drive execution)...

🟢 Callback: Client 1 connected
💬 Callback: Received from client 1: "Hello from callback!"
   → Sending to client 1: "Echo: Hello from callback!"
💬 Callback: Received from client 1: "Platform calling Roc..."
   → Sending to client 1: "Echo: Platform calling Roc..."
🔴 Callback: Client 1 disconnected
⏹️  Callback: Platform requesting shutdown

=== Demo Complete ===
The platform successfully called back into Roc code!

=== Platform Shutting Down ===
```

## Limitations and Future Work

### Current Limitations

1. **Closure Passing**: This demo simulates closure passing. A complete implementation needs to:
   - Extract real closure from Roc
   - Handle captured variables
   - Manage closure lifetime

2. **Function Discovery**: The exact `_caller` naming pattern depends on Roc's compilation.
   - May need reflection or metadata
   - Depends on module structure
   - Can change between compiler versions

3. **Thread Safety**: This demo is single-threaded. Multi-threaded usage requires:
   - Proper synchronization
   - Atomic operations
   - Thread-safe Roc runtime

### Future Enhancements

1. **Automatic Binding Generation**: Tools to generate glue code
2. **Type-safe Callbacks**: Compile-time verification of callback signatures
3. **Async/Await Support**: Integration with Roc's effect system
4. **Stream Abstraction**: More sophisticated stream processing APIs

## Related Documentation

- `callroc.md` - The original _caller pattern documentation
- Roc Platform Development Guide
- Roc ABI Specification
- Zig-Roc Interop Examples

## Conclusion

Platform → Roc callbacks enable powerful, event-driven architectures while maintaining Roc's simplicity. The `_caller` pattern generated by Roc provides a clean interface for bidirectional FFI communication.

This implementation demonstrates that callbacks are technically feasible and can be used to build sophisticated event-driven applications in Roc.