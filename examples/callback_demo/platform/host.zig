//! Platform Host with Platform → Roc Callback Support
//! Demonstrates calling back into Roc functions from Zig code

const std = @import("std");
const builtins = @import("builtins");

// ============================================================================
// Roc String Type Helper
// ============================================================================

const RocStr = builtins.str.RocStr;

// Helper function to get bytes from RocStr
fn getAsSlice(roc_str: *const RocStr) []const u8 {
    if (roc_str.len() == 0) return "";
    return roc_str.asSlice();
}

// ============================================================================
// Event Types (must match Events.roc definition)
// ============================================================================

const EventPayload = extern union {
    // Connected/Disconnected: U64 at offset 0
    client_id: u64,
    // Error: Str at offset 0
    err_str: RocStr,
    // Message: U64 at offset 0, Str at offset 8
    message: extern struct {
        client_id: u64,
        text: RocStr,
    },
    // Shutdown: no payload
};

const Event = extern struct {
    payload: EventPayload,
    discriminant: u8, // 0=Connected, 1=Disconnected, 2=Error, 3=Message, 4=Shutdown
};

// ============================================================================
// Result Types
// ============================================================================

const ResultUnit = extern struct {
    discriminant: u8, // 0=Err, 1=Ok
    payload: RocStr,   // Error message if Err
};

// ============================================================================
// Host Environment
// ============================================================================

const HostEnv = struct {
    allocator: std.mem.Allocator,
    event_handler: ?EventHandler = null,
};

const EventHandler = struct {
    caller: *const fn (*anyopaque, *anyopaque, *anyopaque) callconv(.c) void,
    env: *anyopaque,
};

// ============================================================================
// Global State
// ============================================================================

var global_host: ?*HostEnv = null;
var is_running = false;

// Use C allocator for Roc allocations
const c_allocator = std.heap.c_allocator;

// Allocation tracking
var alloc_count: usize = 0;
var dealloc_count: usize = 0;
var total_allocated: usize = 0;

// ============================================================================
// Hosted Functions
// ============================================================================

/// A Roc closure - function pointer + captured environment
const RocClosure = extern struct {
    caller: *const fn (*builtins.host_abi.RocOps, *anyopaque, *anyopaque) callconv(.c) void,
    captures: *anyopaque,
};

/// Events.run_with_callback! : (Str => {}) => {}
/// Receives a Roc callback. Currently, the interpreter-based runtime doesn't support
/// direct invocation of Roc closures from the host. This would require either:
/// 1. A native code compiler (not the interpreter)
/// 2. A callback registration/invocation API in the interpreter
fn hostedRunWithCallback(
    _: *builtins.host_abi.RocOps,
    ret_ptr: *anyopaque,
    args_ptr: *anyopaque,
) callconv(.c) void {
    _ = ret_ptr; // Returns {}
    _ = args_ptr; // The closure captures (not a callable function pointer in interpreter mode)

    const stdout = std.fs.File.stdout();

    stdout.writeAll("Platform: Received Roc closure data\n") catch {};
    stdout.writeAll("Platform: In interpreter mode, closures are not directly callable.\n") catch {};
    stdout.writeAll("Platform: True callbacks require native compilation.\n") catch {};
}

/// Events.set_event_handler! (legacy - not used in simplified demo)
fn hostedSetEventHandler(
    ops: *builtins.host_abi.RocOps,
    ret_ptr: *anyopaque,
    args_ptr: *anyopaque,
) callconv(.c) void {
    const result: *ResultUnit = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    // The args_ptr contains the function pointer and environment
    // In practice, Roc would pass a closure structure here
    // For this demo, we'll simulate receiving a callback

    _ = args_ptr; // Would extract callback from this

    // Store a dummy handler (in real implementation, this would extract from args)
    host.event_handler = .{
        .caller = roc_dummy_event_handler_caller,
        .env = ops.env,
    };

    result.discriminant = 1; // Ok
    result.payload = RocStr.empty();
}

/// Events.run_event_loop! : () => [Ok({}), Err(Str)]
/// Runs the event loop, calling the registered Roc callback for each event
fn hostedRunEventLoop(
    ops: *builtins.host_abi.RocOps,
    ret_ptr: *anyopaque,
    args_ptr: *anyopaque,
) callconv(.c) void {
    _ = args_ptr;
    const result: *ResultUnit = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    if (host.event_handler == null) {
        result.discriminant = 0; // Err
        result.payload = RocStr.fromSliceSmall("No event handler registered");
        return;
    }

    const handler = host.event_handler.?;

    // Simulate an event stream
    const events = [_]Event{
        // Connected event
        .{
            .payload = .{ .client_id = 1 },
            .discriminant = 0,
        },
        // Message event
        .{
            .payload = .{ .message = .{
                .client_id = 1,
                .text = RocStr.fromSliceSmall("Hello from callback!"),
            } },
            .discriminant = 3,
        },
        // Message event
        .{
            .payload = .{ .message = .{
                .client_id = 1,
                .text = RocStr.fromSliceSmall("Platform calling Roc..."),
            } },
            .discriminant = 3,
        },
        // Disconnected event
        .{
            .payload = .{ .client_id = 1 },
            .discriminant = 1,
        },
        // Shutdown event
        .{
            .payload = undefined,
            .discriminant = 4,
        },
    };

    // Call the Roc callback for each event
    for (events) |event| {
        var callback_result: ResultUnit = undefined;

        // Call the Roc callback function
        // This is the key: Platform calling back into Roc!
        handler.caller(
            handler.env,
            @ptrCast(&callback_result),
            @ptrCast(@constCast(&event)),
        );

        // Check if callback returned an error
        if (callback_result.discriminant == 0) {
            const err_msg = callback_result.payload;
            if (err_msg.len() > 0) {
                const stderr = std.fs.File.stderr();
                stderr.writeAll("Callback error: ") catch {};
                stderr.writeAll(getAsSlice(&err_msg)) catch {};
                stderr.writeAll("\n") catch {};
            }
            // Stop the event loop on error
            result.discriminant = 0;
            result.payload = callback_result.payload;
            return;
        }
    }

    // Event loop completed successfully
    result.discriminant = 1; // Ok
    result.payload = RocStr.empty();
}

/// Events.send_welcome! : U64 => [Ok({}), Err(Str)]
/// (Placeholder implementation)
fn hostedSendWelcome(
    ops: *builtins.host_abi.RocOps,
    ret_ptr: *anyopaque,
    args_ptr: *anyopaque,
) callconv(.c) void {
    _ = ops;
    _ = args_ptr;
    const result: *ResultUnit = @ptrCast(@alignCast(ret_ptr));

    // Just return Ok for now
    result.discriminant = 1;
    result.payload = RocStr.empty();
}

/// Events.send_message! : (U64, Str) => [Ok({}), Err(Str)]
/// (Placeholder implementation)
fn hostedSendMessage(
    _: *builtins.host_abi.RocOps,
    ret_ptr: *anyopaque,
    args_ptr: *anyopaque,
) callconv(.c) void {
    const Args = extern struct {
        client_id: u64,
        message: RocStr,
    };
    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const result: *ResultUnit = @ptrCast(@alignCast(ret_ptr));

    _ = args.client_id;
    _ = args.message;

    // Just return Ok for now
    result.discriminant = 1;
    result.payload = RocStr.empty();
}

/// Events.start_background! : {} => [Ok({}), Err(Str)]
/// (Placeholder implementation)
fn hostedStartBackground(
    _: *builtins.host_abi.RocOps,
    ret_ptr: *anyopaque,
    args_ptr: *anyopaque,
) callconv(.c) void {
    _ = args_ptr;
    const result: *ResultUnit = @ptrCast(@alignCast(ret_ptr));

    // Just return Ok for now
    result.discriminant = 1;
    result.payload = RocStr.empty();
}

/// Stdout.line! : Str => {}
fn hostedStdoutLine(
    ops: *builtins.host_abi.RocOps,
    ret_ptr: *anyopaque,
    args_ptr: *anyopaque,
) callconv(.c) void {
    _ = ops;
    _ = ret_ptr;

    const Args = extern struct {
        str: RocStr,
    };
    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const str = getAsSlice(&args.str);

    const stdout = std.fs.File.stdout();
    stdout.writeAll(str) catch {};
    stdout.writeAll("\n") catch {};
}

// ============================================================================
// Hosted Function Table
// ============================================================================

const hosted_function_ptrs = [_]builtins.host_abi.HostedFn{
    // Events.run_with_callback!
    hostedRunWithCallback,
    // Stdout.line!
    hostedStdoutLine,
};

// ============================================================================
// Platform Entry Point
// ============================================================================

/// Roc allocation function using C allocator
fn rocAllocFn(roc_alloc: *builtins.host_abi.RocAlloc, env: *anyopaque) callconv(.c) void {
    _ = env;

    const result = c_allocator.rawAlloc(
        roc_alloc.length,
        std.mem.Alignment.fromByteUnits(@max(roc_alloc.alignment, @alignOf(usize))),
        @returnAddress(),
    );

    roc_alloc.answer = result orelse {
        const stderr: std.fs.File = .stderr();
        stderr.writeAll("\x1b[31mHost error:\x1b[0m allocation failed, out of memory\n") catch {};
        std.process.exit(1);
    };
}

/// Roc deallocation function using C allocator
fn rocDeallocFn(roc_dealloc: *builtins.host_abi.RocDealloc, env: *anyopaque) callconv(.c) void {
    _ = env;
    dealloc_count += 1;
    const slice = @as([*]u8, @ptrCast(roc_dealloc.ptr))[0..0];
    c_allocator.rawFree(
        slice,
        std.mem.Alignment.fromByteUnits(@max(roc_dealloc.alignment, @alignOf(usize))),
        @returnAddress(),
    );
}

/// Roc reallocation function using C allocator
fn rocReallocFn(roc_realloc: *builtins.host_abi.RocRealloc, env: *anyopaque) callconv(.c) void {
    _ = env;

    const align_enum = std.mem.Alignment.fromByteUnits(@max(roc_realloc.alignment, @alignOf(usize)));

    const new_ptr = c_allocator.rawAlloc(roc_realloc.new_length, align_enum, @returnAddress()) orelse {
        const stderr: std.fs.File = .stderr();
        stderr.writeAll("\x1b[31mHost error:\x1b[0m reallocation failed, out of memory\n") catch {};
        std.process.exit(1);
    };

    const old_ptr: [*]const u8 = @ptrCast(roc_realloc.answer);
    @memcpy(new_ptr[0..roc_realloc.new_length], old_ptr[0..roc_realloc.new_length]);

    const old_slice = @as([*]u8, @ptrCast(roc_realloc.answer))[0..0];
    c_allocator.rawFree(old_slice, align_enum, @returnAddress());

    roc_realloc.answer = new_ptr;
}


export fn platform_main(argc: c_int, argv: [*][*:0]u8) c_int {
    const allocator = std.heap.c_allocator;

    var host_env = HostEnv{
        .allocator = allocator,
        .event_handler = null,
    };
    global_host = &host_env;

    const stdout = std.fs.File.stdout();

    stdout.writeAll("=== Zig Platform Host Initialized ===\n") catch {};
    stdout.writeAll("Platform → Roc callback mechanism is enabled\n\n") catch {};

    var roc_ops = builtins.host_abi.RocOps{
        .env = @as(*anyopaque, @ptrCast(&host_env)),
        .roc_alloc = rocAllocFn,
        .roc_dealloc = rocDeallocFn,
        .roc_realloc = rocReallocFn,
        .roc_dbg = undefined,
        .roc_expect_failed = undefined,
        .roc_crashed = undefined,
        .hosted_fns = .{
            .count = hosted_function_ptrs.len,
            .fns = @ptrCast(@constCast(&hosted_function_ptrs)),
        },
    };

    _ = argv;
    _ = argc;

    // Dummy return and args - Roc will dereference these even if not used
    var ret: u8 = 0;
    var args: u8 = 0;

    // Call Roc main function
    roc__main(&roc_ops, @as(*anyopaque, @ptrCast(&ret)), @as(*anyopaque, @ptrCast(&args)));

    stdout.writeAll("\n=== Platform Shutting Down ===\n") catch {};

    return 0;
}

// ============================================================================
// Roc Main Function Declaration
// ============================================================================

extern fn roc__main(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, arg_ptr: *anyopaque) callconv(.c) void;

// ============================================================================
// Mock Roc List Type
// ============================================================================

const RocList = extern struct {
    len: usize,
    bytes: [*]u8,
};

// ============================================================================
// Dummy Event Handler for Demo
// ============================================================================

fn roc_dummy_event_handler_caller(
    env: *anyopaque,
    ret_ptr: *anyopaque,
    arg_ptr: *anyopaque,
) callconv(.c) void {
    _ = env;

    const event: *const Event = @ptrCast(@alignCast(arg_ptr));

    const stdout = std.fs.File.stdout();
    var buf: [1024]u8 = undefined;

    switch (event.discriminant) {
        0 => { // Connected
            const msg = std.fmt.bufPrint(&buf, "🟢 Platform callback: Client {} connected\n", .{event.payload.client_id}) catch return;
            stdout.writeAll(msg) catch {};
        },
        1 => { // Disconnected
            const msg = std.fmt.bufPrint(&buf, "🔴 Platform callback: Client {} disconnected\n", .{event.payload.client_id}) catch return;
            stdout.writeAll(msg) catch {};
        },
        2 => { // Error
            const msg_str = getAsSlice(&event.payload.err_str);
            const msg = std.fmt.bufPrint(&buf, "⚠️  Platform callback: Error: {s}\n", .{msg_str}) catch return;
            stdout.writeAll(msg) catch {};
        },
        3 => { // Message
            const msg_str = getAsSlice(&event.payload.message.text);
            const msg = std.fmt.bufPrint(&buf, "💬 Platform callback: Client {} sent: \"{s}\"\n", .{
                event.payload.message.client_id,
                msg_str,
            }) catch return;
            stdout.writeAll(msg) catch {};
        },
        4 => { // Shutdown
            stdout.writeAll("⏹️  Platform callback: Shutdown requested\n") catch {};
        },
        else => {
            const msg = std.fmt.bufPrint(&buf, "❓ Platform callback: Unknown event type {}\n", .{event.discriminant}) catch return;
            stdout.writeAll(msg) catch {};
        },
    }

    // Return Ok({}) to the callback
    const result: *ResultUnit = @ptrCast(@alignCast(ret_ptr));
    result.discriminant = 1; // Ok
    result.payload = RocStr.empty();
}

export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    return platform_main(argc, argv);
}
