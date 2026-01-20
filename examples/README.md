# Platform → Roc Callbacks - Complete Implementation

This directory contains examples demonstrating how to implement callbacks from the platform (Zig) back into Roc code.

## What This Demonstrates

**Traditional Pattern (Unidirectional):**
```
Roc Code → Platform Functions → Foreign Operations
```

**With Callbacks (Bidirectional):**
```
Roc Code → Platform Functions → Foreign Operations
                ↓
        Roc Callback Functions
```

## Examples

### 1. Simple Callback Demo (`simple_callback/`)
A minimal example showing string processing callbacks.

**Files:**
- `main.roc` - Roc application with callback functions
- `platform/main.roc` - Platform definition
- `platform/Callbacks.roc` - Callback interface
- `platform/host.zig` - Zig host implementation
- `IMPLEMENTATION.md` - Detailed implementation guide

**What it shows:**
- Registering a callback function with the platform
- Platform invoking the callback
- Callbacks returning results or errors
- One-shot callbacks vs. stored callbacks

### 2. Event Callback Demo (`callback_demo/`)
A more complex example demonstrating event-driven callbacks.

**Files:**
- `main.roc` - Event handling application
- `platform/Events.roc` - Event interface
- `platform/host.zig` - Zig host with event loop

**What it shows:**
- Event loop driven by platform
- Multiple event types (Connected, Disconnected, Message, Error)
- Error handling in callback chain
- Stream-based event processing

## Key Pattern: The `_caller` Function

Roc automatically generates `_caller` functions that wrap exposed functions with FFI glue code:

```zig
// Roc generates this automatically
extern fn roc__main_for_host_1_caller([*]u8, *const RocStr, [*]u8, *RocStr) void;

// Platform can call it!
roc__main_for_host_1_caller(&env, &result, &input);
```

## Architecture

```
┌─────────────────────────────────────┐
│        Roc Application               │
│  ┌───────────────────────────────┐  │
│  │  main! {                     │  │
│  │    Callbacks.set_callback!(  │  │
│  │      handle_string!          │  │
│  │    )?                        │  │
│  │                             │  │
│  │    Callbacks.invoke!(       │  │
│  │      "test"                 │  │
│  │    )?                        │  │
│  │  }                           │  │
│  │                               │  │
│  │  handle_string! = |s| { ... } │  │
│  └───────────────────────────────┘  │
└─────────────┬───────────────────────┘
              │ Calls hosted function
              ↓
┌─────────────────────────────────────┐
│      Platform (Zig)                  │
│  ┌───────────────────────────────┐  │
│  │  hostedSetCallback {         │  │
│  │    // Store callback         │  │
│  │    host.cb = {               │  │
│  │      .caller = roc_X_caller, │  │
│  │      .env = env              │  │
│  │    }                         │  │
│  │  }                           │  │
│  │                               │  │
│  │  hostedInvoke {              │  │
│  │    // Call back to Roc!      │  │
│  │    host.cb.caller(           │  │
│  │      &env, &result, &input   │  │
│  │    )                         │  │
│  │  }                           │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Comparison: Pull vs Push Models

### Pull Model (Current notey)
```roc
event_loop! = || {
    event = WebServer.accept!()  # Roc pulls events
    handle_event!(event)
    event_loop!()  # Recursive
}
```

**Pros:**
- Simple, explicit control flow
- Easy to debug
- No closure complexity

**Cons:**
- Recursive calls
- Platform async capabilities wasted
- Higher overhead

### Push Model (Callbacks)
```roc
WebServer.on_event!(handle_event!)?
# Platform drives, Roc handles
```

**Pros:**
- Platform uses optimal async I/O
- No recursive calls in Roc
- Better for long-running operations

**Cons:**
- More complex implementation
- Harder to debug
- Requires closure handling

## Use Cases for Callbacks

1. **Event-Driven I/O**: Web servers, file watchers
2. **Async Operations**: HTTP clients, database queries
3. **GUI Development**: Button clicks, key presses
4. **Streaming**: Process data as it arrives
5. **Background Tasks**: Workers, schedulers

## Implementation Checklist

To add callbacks to your platform:

- [ ] Define callback type signature in platform interface
- [ ] Implement `set_callback!` hosted function to store callback
- [ ] Implement invoke logic that calls the stored callback
- [ ] Handle callback results (Ok/Err)
- [ ] Test with different callback patterns
- [ ] Document the callback contract

## Current Status

**Working:**
- ✅ Pattern demonstration
- ✅ Complete architecture
- ✅ Type-safe interfaces
- ✅ Error handling

**Demo-Only:**
- ⚠️ Mock `_caller` functions (need Roc integration)
- ⚠️ Simplified closure extraction
- ⚠️ Partial memory management

**For Production:**
- 🔲 Integrate with actual Roc-generated `_caller` functions
- 🔲 Implement proper closure extraction
- 🔲 Add comprehensive memory management
- 🔲 Full testing suite

## Learn More

- `simple_callback/IMPLEMENTATION.md` - Complete implementation guide
- `callback_demo/README.md` - Event-driven example documentation
- `../../docs/callroc.md` - Original `_caller` pattern documentation

## Conclusion

Platform → Roc callbacks enable powerful, event-driven architectures while maintaining Roc's simplicity. The `_caller` pattern provides a clean interface for bidirectional FFI communication.

These examples demonstrate that callbacks are technically feasible and can be used to build sophisticated applications in Roc that leverage the platform's capabilities fully.
