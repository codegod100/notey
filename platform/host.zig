//! WebSocket Chat Server Platform Host
//! Implements a WebSocket server for the Roc chat application
const std = @import("std");
const builtins = @import("builtins");

// SQLite cImport
const sqlite = @cImport({
    // Add include path to build.zig to make this work
    @cInclude("sqlite3.h");
});

// Use lower-level C environ access to avoid std.os.environ initialization issues
extern var environ: [*:null]?[*:0]u8;
extern fn getenv(name: [*:0]const u8) ?[*:0]u8;

comptime {
    _ = &environ;
    _ = &getenv;
}

fn initEnviron() void {
    if (@import("builtin").os.tag != .windows) {
        _ = environ;
        _ = getenv("PATH");
    }
}

/// Global flag to track if dbg or expect_failed was called.
var debug_or_expect_called: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

// Use C allocator for Roc allocations
const c_allocator = std.heap.c_allocator;

// Allocation tracking
var alloc_count: usize = 0;
var dealloc_count: usize = 0;
var total_allocated: usize = 0;

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

    // Track allocation
    alloc_count += 1;
    total_allocated += roc_alloc.length;
    if (alloc_count % 100 == 0) {
        const stderr = std.fs.File.stderr();
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "ALLOC STATS: allocs={} deallocs={} diff={} total_bytes={}\n", .{ alloc_count, dealloc_count, alloc_count - dealloc_count, total_allocated }) catch "ALLOC STATS: ???\n";
        stderr.writeAll(msg) catch {};
    }
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

/// Roc debug function
fn rocDbgFn(roc_dbg: *const builtins.host_abi.RocDbg, env: *anyopaque) callconv(.c) void {
    _ = env;
    debug_or_expect_called.store(true, .release);
    const message = roc_dbg.utf8_bytes[0..roc_dbg.len];
    const stderr = std.fs.File.stderr();
    stderr.writeAll("\x1b[33mdbg:\x1b[0m ") catch {};
    stderr.writeAll(message) catch {};
    stderr.writeAll("\n") catch {};
}

/// Roc expect failed function
fn rocExpectFailedFn(roc_expect: *const builtins.host_abi.RocExpectFailed, env: *anyopaque) callconv(.c) void {
    _ = env;
    debug_or_expect_called.store(true, .release);
    const source_bytes = roc_expect.utf8_bytes[0..roc_expect.len];
    const trimmed = std.mem.trim(u8, source_bytes, " \t\n\r");
    const stderr = std.fs.File.stderr();
    stderr.writeAll("\x1b[33mexpect failed:\x1b[0m ") catch {};
    stderr.writeAll(trimmed) catch {};
    stderr.writeAll("\n") catch {};
}

/// Roc crashed function
fn rocCrashedFn(roc_crashed: *const builtins.host_abi.RocCrashed, env: *anyopaque) callconv(.c) noreturn {
    _ = env;
    const message = roc_crashed.utf8_bytes[0..roc_crashed.len];
    const stderr = std.fs.File.stderr();
    stderr.writeAll("\n\x1b[31mRoc crashed:\x1b[0m ") catch {};
    stderr.writeAll(message) catch {};
    stderr.writeAll("\n") catch {};
    std.process.exit(1);
}

// External symbols provided by the Roc runtime
extern fn roc__main_for_host(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, arg_ptr: ?*anyopaque) callconv(.c) void;

// OS-specific entry point handling
comptime {
    if (!@import("builtin").is_test) {
        @export(&main, .{ .name = "main" });
        if (@import("builtin").os.tag == .windows) {
            @export(&__main, .{ .name = "__main" });
        }
    }
}

fn __main() callconv(.c) void {}

fn main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    initEnviron();
    return platform_main(argc, argv);
}

// Roc types
const RocStr = builtins.str.RocStr;
const RocList = builtins.list.RocList;

// ============================================================================
// WebSocket Server Implementation
// ============================================================================

const WebSocketOpcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};

const WebSocketClient = struct {
    id: u64,
    stream: std.net.Stream,
    is_websocket: bool = false,
    is_closed: bool = false,
};

const WebSocketEvent = union(enum) {
    connected: u64,
    disconnected: u64,
    message: struct { client_id: u64, text: []const u8 },
    err: []const u8,
    shutdown: void,
};

const WebSocketServer = struct {
    allocator: std.mem.Allocator,
    listener: ?std.net.Server,
    clients: std.AutoHashMap(u64, WebSocketClient),
    next_client_id: u64,
    event_queue: std.ArrayListUnmanaged(WebSocketEvent),
    is_running: bool,
    static_dir: ?[]const u8,

    fn init(allocator: std.mem.Allocator) WebSocketServer {
        return .{
            .allocator = allocator,
            .listener = null,
            .clients = std.AutoHashMap(u64, WebSocketClient).init(allocator),
            .next_client_id = 1,
            .event_queue = .{},
            .is_running = false,
            .static_dir = null,
        };
    }

    fn deinit(self: *WebSocketServer) void {
        if (self.listener) |*l| {
            l.deinit();
        }

        var it = self.clients.valueIterator();
        while (it.next()) |client| {
            client.stream.close();
        }
        self.clients.deinit();
        self.event_queue.deinit(self.allocator);
    }

    fn listen(self: *WebSocketServer, port: u16) !void {
        const address = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
        self.listener = try address.listen(.{
            .reuse_address = true,
        });
        self.is_running = true;
        self.static_dir = "static";
    }

    fn accept(self: *WebSocketServer) !WebSocketEvent {
        while (true) {
            // First check event queue
            if (self.event_queue.items.len > 0) {
                return self.event_queue.orderedRemove(0);
            }

            if (!self.is_running) {
                return .shutdown;
            }

            var listener = &(self.listener.?);

            // Set up poll to check for new connections and client data
            var poll_fds = std.ArrayListUnmanaged(std.posix.pollfd){};
            defer poll_fds.deinit(self.allocator);

            // Add listener socket
            try poll_fds.append(self.allocator, .{
                .fd = listener.stream.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            });

            // Add all client sockets
            var client_ids = std.ArrayListUnmanaged(u64){};
            defer client_ids.deinit(self.allocator);

            var it = self.clients.iterator();
            while (it.next()) |entry| {
                if (!entry.value_ptr.is_closed) {
                    try poll_fds.append(self.allocator, .{
                        .fd = entry.value_ptr.stream.handle,
                        .events = std.posix.POLL.IN,
                        .revents = 0,
                    });
                    try client_ids.append(self.allocator, entry.key_ptr.*);
                }
            }

            // Poll with longer timeout (5 seconds) to avoid busy spinning
            const ready = std.posix.poll(poll_fds.items, 5000) catch |err| {
                const msg = std.fmt.allocPrint(self.allocator, "Poll error: {}", .{err}) catch "Poll error";
                return .{ .err = msg };
            };

            if (ready == 0) {
                // Timeout - just continue polling
                continue;
            }

            // Check listener for new connections
            if (poll_fds.items[0].revents & std.posix.POLL.IN != 0) {
                const connection = listener.accept() catch |err| {
                    const msg = std.fmt.allocPrint(self.allocator, "Accept error: {}", .{err}) catch "Accept error";
                    return .{ .err = msg };
                };

                const client_id = self.next_client_id;
                self.next_client_id += 1;

                try self.clients.put(client_id, .{
                    .id = client_id,
                    .stream = connection.stream,
                    .is_websocket = false,
                });

                // Handle HTTP upgrade in a separate step
                if (self.handleNewConnection(client_id)) |event| {
                    return event;
                } else |_| {
                    // Connection handling failed, remove client
                    if (self.clients.fetchRemove(client_id)) |kv| {
                        kv.value.stream.close();
                    }
                }
            }

            // Check clients for incoming data
            for (poll_fds.items[1..], 0..) |pfd, i| {
                if (pfd.revents & std.posix.POLL.IN != 0) {
                    const client_id = client_ids.items[i];
                    if (self.handleClientData(client_id)) |event| {
                        return event;
                    } else |_| {
                        // Error reading, client disconnected
                        if (self.clients.fetchRemove(client_id)) |kv| {
                            kv.value.stream.close();
                        }
                        return .{ .disconnected = client_id };
                    }
                }

                if (pfd.revents & (std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) {
                    const client_id = client_ids.items[i];
                    if (self.clients.fetchRemove(client_id)) |kv| {
                        kv.value.stream.close();
                    }
                    return .{ .disconnected = client_id };
                }
            }
            // No events this poll cycle, continue waiting
        }
    }

    fn handleNewConnection(self: *WebSocketServer, client_id: u64) !WebSocketEvent {
        const client = self.clients.getPtr(client_id) orelse return error.ClientNotFound;

        // Use an ArrayList to accumulate the request
        var request_data = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
        defer request_data.deinit(self.allocator);

        var buf: [4096]u8 = undefined;
        
        // Loop until we have the full request
        while (true) {
            const n = try client.stream.read(&buf);
            if (n == 0) return error.ConnectionClosed;
            try request_data.appendSlice(self.allocator, buf[0..n]);
            
            const data = request_data.items;
            
            // Check if headers are complete
            if (std.mem.indexOf(u8, data, "\r\n\r\n")) |headers_end| {
                const body_start = headers_end + 4;
                var content_length: usize = 0;
                
                // Parse Content-Length if present
                // We use a simple case-insensitive search
                const lower_data = try std.ascii.allocLowerString(self.allocator, data[0..headers_end]);
                defer self.allocator.free(lower_data);
                
                if (std.mem.indexOf(u8, lower_data, "content-length:")) |cl_idx| {
                    var val_idx = cl_idx + 15;
                    // Skip colon and spaces
                    while (val_idx < lower_data.len and (lower_data[val_idx] == ' ' or lower_data[val_idx] == ':')) : (val_idx += 1) {}
                    
                    if (std.mem.indexOf(u8, lower_data[val_idx..], "\r\n")) |line_end| {
                        const cl_str = lower_data[val_idx .. val_idx + line_end];
                        content_length = std.fmt.parseInt(usize, std.mem.trim(u8, cl_str, " "), 10) catch 0;
                    }
                }
                
                if (data.len >= body_start + content_length) {
                    // We have the full request
                    break;
                }
            } else if (data.len > 1024 * 1024) {
                // Header too large (1MB limit)
                return error.PayloadTooLarge;
            }
        }
        
        const request = request_data.items;

        // Parse HTTP request
        // Check for WebSocket upgrade (case-insensitive)
        const request_lower = std.ascii.allocLowerString(self.allocator, request) catch request;
        defer if (request_lower.ptr != request.ptr) self.allocator.free(request_lower);
        
        // Check for WebSocket upgrade
        // We look for Sec-WebSocket-Key directly as it's the most reliable indicator
        // and avoids issues with Upgrade header formatting (spaces, etc.)
        if (std.mem.indexOf(u8, request_lower, "sec-websocket-key:")) |_| {
            // WebSocket upgrade request
            if (try self.handleWebSocketUpgrade(client, request, request_lower)) {
                client.is_websocket = true;
                return .{ .connected = client_id };
            } else {
                const stdout = std.fs.File.stdout();
                stdout.writeAll("WebSocket upgrade failed. Request:\n") catch {};
                stdout.writeAll(request) catch {};
                stdout.writeAll("\n") catch {};
            }
        } else if (std.mem.startsWith(u8, request, "GET ") or std.mem.startsWith(u8, request, "POST ")) {
            // HTTP request - try to serve static or forward API
            _ = self.handleHttpRequest(client, request) catch |err| {
                if (err == error.ApiRequest) {
                    // API request - allocate and copy request data for Roc
                    // request_data will be freed, so we need to copy
                    const request_copy = try self.allocator.alloc(u8, request.len);
                    @memcpy(request_copy, request);
                    // API request - return as message for Roc to handle
                    client.is_websocket = false;
                    return .{ .message = .{ .client_id = client_id, .text = request_copy } };
                }
                return err;
            };

            // HTTP request was handled (either served static file or returned error)
            // Don't forward to the event loop
            client.is_closed = true;
            return error.NotWebSocket;
        }

        return error.NotWebSocket;
    }

    fn handleWebSocketUpgrade(self: *WebSocketServer, client: *WebSocketClient, request: []const u8, request_lower: []const u8) !bool {
        _ = self;

        // Find Sec-WebSocket-Key (case-insensitive search using request_lower)
        const key_header_name = "sec-websocket-key:";
        const header_start = std.mem.indexOf(u8, request_lower, key_header_name) orelse return false;
        
        var key_val_start = header_start + key_header_name.len;
        
        // Skip whitespace
        while (key_val_start < request.len and (request[key_val_start] == ' ' or request[key_val_start] == '\t')) : (key_val_start += 1) {}
        
        if (key_val_start >= request.len) return false;

        const key_end = std.mem.indexOfPos(u8, request, key_val_start, "\r\n") orelse return false;
        const key = request[key_val_start..key_end];

        // Compute accept key
        const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(key);
        hasher.update(magic);
        const hash = hasher.finalResult();

        var accept_key: [28]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&accept_key, &hash);

        // Send upgrade response
        const response = "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: ";

        _ = try client.stream.write(response);
        _ = try client.stream.write(&accept_key);
        _ = try client.stream.write("\r\n\r\n");

        return true;
    }

    fn handleHttpRequest(self: *WebSocketServer, client: *WebSocketClient, request: []const u8) !void {
        // Parse method and path
        var method_len: usize = 0;
        var path: []const u8 = "";
        
        if (std.mem.startsWith(u8, request, "GET ")) {
            method_len = 4;
        } else if (std.mem.startsWith(u8, request, "POST ")) {
            method_len = 5;
        } else {
            return;
        }
        
        const path_start = method_len;
        const path_end = std.mem.indexOfPos(u8, request, path_start, " ") orelse return;
        path = request[path_start..path_end];

        // Check if this is an API request
        if (std.mem.startsWith(u8, path, "/api/")) {
            // Don't close client - let Roc handle it
            client.is_websocket = false; // Mark as HTTP (not WebSocket)
            return error.ApiRequest; // Signal to forward to Roc
        }

        if (std.mem.eql(u8, path, "/")) {
            path = "/index.html";
        }

        // Serve static file
        const static_dir = self.static_dir orelse "static";
        var file_path_buf: [512]u8 = undefined;
        const file_path = std.fmt.bufPrint(&file_path_buf, "{s}{s}", .{ static_dir, path }) catch {
            try self.sendHttpError(client, 500, "Internal Server Error");
            return;
        };

        const file = std.fs.cwd().openFile(file_path, .{}) catch {
            try self.sendHttpError(client, 404, "Not Found");
            return;
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch {
            try self.sendHttpError(client, 500, "Internal Server Error");
            return;
        };
        defer self.allocator.free(content);

        // Determine content type
        const content_type = if (std.mem.endsWith(u8, path, ".html"))
            "text/html"
        else if (std.mem.endsWith(u8, path, ".js"))
            "application/javascript"
        else if (std.mem.endsWith(u8, path, ".css"))
            "text/css"
        else
            "application/octet-stream";

        var header_buf: [256]u8 = undefined;
        const header = std.fmt.bufPrint(&header_buf, "HTTP/1.1 200 OK\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ content_type, content.len }) catch return;

        _ = try client.stream.write(header);
        _ = try client.stream.write(content);
    }

    fn sendHttpError(self: *WebSocketServer, client: *WebSocketClient, code: u16, message: []const u8) !void {
        _ = self;
        var buf: [256]u8 = undefined;
        const response = std.fmt.bufPrint(&buf, "HTTP/1.1 {d} {s}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", .{ code, message }) catch return;
        _ = try client.stream.write(response);
    }

    fn handleClientData(self: *WebSocketServer, client_id: u64) !WebSocketEvent {
        const client = self.clients.getPtr(client_id) orelse return error.ClientNotFound;

        if (!client.is_websocket) {
            return error.NotWebSocket;
        }

        var header: [14]u8 = undefined;
        const header_read = try client.stream.read(header[0..2]);
        if (header_read < 2) return error.ConnectionClosed;

        const fin = (header[0] & 0x80) != 0;
        _ = fin;
        const opcode: WebSocketOpcode = @enumFromInt(@as(u4, @truncate(header[0] & 0x0F)));
        const masked = (header[1] & 0x80) != 0;
        var payload_len: u64 = header[1] & 0x7F;

        if (payload_len == 126) {
            _ = try client.stream.read(header[2..4]);
            payload_len = std.mem.readInt(u16, header[2..4], .big);
        } else if (payload_len == 127) {
            _ = try client.stream.read(header[2..10]);
            payload_len = std.mem.readInt(u64, header[2..10], .big);
        }

        var mask: [4]u8 = undefined;
        if (masked) {
            _ = try client.stream.read(&mask);
        }

        // Read payload
        if (payload_len > 65536) return error.PayloadTooLarge;
        const payload = try self.allocator.alloc(u8, @intCast(payload_len));

        var total_read: usize = 0;
        while (total_read < payload_len) {
            const read = try client.stream.read(payload[total_read..]);
            if (read == 0) break;
            total_read += read;
        }

        // Unmask
        if (masked) {
            for (payload, 0..) |*byte, i| {
                byte.* ^= mask[i % 4];
            }
        }

        switch (opcode) {
            .text => {
                return .{ .message = .{ .client_id = client_id, .text = payload } };
            },
            .close => {
                client.is_closed = true;
                if (self.clients.fetchRemove(client_id)) |kv| {
                    kv.value.stream.close();
                }
                self.allocator.free(payload);
                return .{ .disconnected = client_id };
            },
            .ping => {
                // Send pong
                try self.sendFrame(client, .pong, payload);
                self.allocator.free(payload);
                return error.ControlFrame;
            },
            .pong => {
                self.allocator.free(payload);
                return error.ControlFrame;
            },
            else => {
                self.allocator.free(payload);
                return error.UnsupportedOpcode;
            },
        }
    }

    fn sendFrame(self: *WebSocketServer, client: *WebSocketClient, opcode: WebSocketOpcode, payload: []const u8) !void {
        _ = self;
        var header: [10]u8 = undefined;
        var header_len: usize = 2;

        header[0] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN + opcode

        if (payload.len < 126) {
            header[1] = @intCast(payload.len);
        } else if (payload.len <= 65535) {
            header[1] = 126;
            std.mem.writeInt(u16, header[2..4], @intCast(payload.len), .big);
            header_len = 4;
        } else {
            header[1] = 127;
            std.mem.writeInt(u64, header[2..10], payload.len, .big);
            header_len = 10;
        }

        _ = try client.stream.write(header[0..header_len]);
        _ = try client.stream.write(payload);
    }

    fn send(self: *WebSocketServer, client_id: u64, message: []const u8) !void {
        const client = self.clients.getPtr(client_id) orelse return error.ClientNotFound;
        if (client.is_closed) return error.ConnectionClosed;
        
        if (client.is_websocket) {
            try self.sendFrame(client, .text, message);
        } else {
            // HTTP response - send raw
            _ = try client.stream.write(message);
        }
    }

    fn broadcast(self: *WebSocketServer, message: []const u8) !void {
        var it = self.clients.valueIterator();
        while (it.next()) |client| {
            if (client.is_websocket and !client.is_closed) {
                self.sendFrame(client, .text, message) catch {};
            }
        }
    }

    fn closeClient(self: *WebSocketServer, client_id: u64) void {
        if (self.clients.fetchRemove(client_id)) |kv| {
            // Send close frame
            self.sendFrame(@constCast(&kv.value), .close, "") catch {};
            kv.value.stream.close();
        }
    }
};

// Global server instance
var global_server: ?*WebSocketServer = null;

// ============================================================================
// Hosted Functions
// ============================================================================

fn getAsSlice(roc_str: *const RocStr) []const u8 {
    if (roc_str.len() == 0) return "";
    return roc_str.asSlice();
}

/// WebServer.listen! : U16 => Result({}, Str)
fn hostedWebServerListen(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };

    const Args = extern struct { port: u64 };
    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    if (host.server) |_| {
        const msg = "Server already running";
        result.payload = RocStr.fromSliceSmall(msg);
        result.discriminant = 0; // Err
        return;
    }

    const server = host.gpa.allocator().create(WebSocketServer) catch {
        const msg = "Failed to allocate server";
        result.payload = RocStr.fromSliceSmall(msg);
        result.discriminant = 0;
        return;
    };
    server.* = WebSocketServer.init(host.gpa.allocator());

    server.listen(@intCast(args.port)) catch |err| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Failed to listen: {}", .{err}) catch "Listen failed";
        if (RocStr.fitsInSmallStr(msg.len)) {
            result.payload = RocStr.fromSliceSmall(msg);
        } else {
            result.payload = RocStr.init(msg.ptr, msg.len, ops);
        }
        result.discriminant = 0;
        return;
    };

    host.server = server;
    global_server = server;

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

/// WebServer.run! : () => Result({}, Str)
/// Runs the event loop entirely in Zig - no Roc recursion needed
fn hostedWebServerRun(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const stderr = std.fs.File.stderr();
    const stdout = std.fs.File.stdout();
    _ = args_ptr;

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };

    const result: *Result = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    const server = host.server orelse {
        const msg = "Server not running";
        result.payload = RocStr.fromSliceSmall(msg);
        result.discriminant = 0; // Err
        return;
    };

    // Event loop runs entirely in Zig
    while (true) {
        const event = server.accept() catch |err| {
            if (err == error.ControlFrame or err == error.NotWebSocket) {
                continue;
            }
            stderr.writeAll("Accept error, continuing...\n") catch {};
            continue;
        };

        switch (event) {
            .connected => |client_id| {
                var buf: [128]u8 = undefined;
                const log_msg = std.fmt.bufPrint(&buf, "Client {} connected\n", .{client_id}) catch "Client connected\n";
                stdout.writeAll(log_msg) catch {};

                // Send welcome message
                var welcome_buf: [256]u8 = undefined;
                const welcome = std.fmt.bufPrint(&welcome_buf, "{{\"type\": \"system\", \"text\": \"Welcome to the chat! You are client #{}\"}}", .{client_id}) catch continue;
                server.send(client_id, welcome) catch {};

                // Broadcast join message
                var join_buf: [256]u8 = undefined;
                const join = std.fmt.bufPrint(&join_buf, "{{\"type\": \"system\", \"text\": \"Client #{} joined the chat\"}}", .{client_id}) catch continue;
                server.broadcast(join) catch {};
            },
            .disconnected => |client_id| {
                var buf: [128]u8 = undefined;
                const log_msg = std.fmt.bufPrint(&buf, "Client {} disconnected\n", .{client_id}) catch "Client disconnected\n";
                stdout.writeAll(log_msg) catch {};

                // Broadcast leave message
                var leave_buf: [256]u8 = undefined;
                const leave = std.fmt.bufPrint(&leave_buf, "{{\"type\": \"system\", \"text\": \"Client #{} left the chat\"}}", .{client_id}) catch continue;
                server.broadcast(leave) catch {};
            },
            .message => |msg| {
                var buf: [4096]u8 = undefined;
                const log_msg = std.fmt.bufPrint(&buf, "Client {}: {s}\n", .{ msg.client_id, msg.text }) catch "Client message\n";
                stdout.writeAll(log_msg) catch {};

                // Broadcast message - need to escape text for JSON
                var json_buf: [4096]u8 = undefined;
                var writer = std.io.fixedBufferStream(&json_buf);
                writer.writer().print("{{\"type\": \"message\", \"clientId\": {}, \"text\": \"", .{msg.client_id}) catch continue;
                for (msg.text) |c| {
                    switch (c) {
                        '"' => writer.writer().writeAll("\\\"") catch {},
                        '\\' => writer.writer().writeAll("\\\\") catch {},
                        '\n' => writer.writer().writeAll("\\n") catch {},
                        '\r' => writer.writer().writeAll("\\r") catch {},
                        '\t' => writer.writer().writeAll("\\t") catch {},
                        else => writer.writer().writeByte(c) catch {},
                    }
                }
                writer.writer().writeAll("\"}") catch continue;
                server.broadcast(json_buf[0..writer.pos]) catch {};
            },
            .err => |msg| {
                stderr.writeAll("Error: ") catch {};
                stderr.writeAll(msg) catch {};
                stderr.writeAll("\n") catch {};
            },
            .shutdown => {
                stdout.writeAll("Server shutting down\n") catch {};
                result.payload = RocStr.empty();
                result.discriminant = 1; // Ok
                return;
            },
        }
    }
}

/// WebServer.accept! : () => Event
/// Event is [Connected(U64), Disconnected(U64), Message(U64, Str), Error(Str), Shutdown]
fn hostedWebServerAccept(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = args_ptr;

    // Roc tag union layout: payload first (sized to largest), discriminant at end
    // Alphabetical order: Connected=0, Disconnected=1, Error=2, Message=3, Shutdown=4
    // Largest payload = Message(U64, Str) = 8 + 24 = 32 bytes
    // discriminant_offset = 32, total size = 40 bytes (padded to 8-byte alignment)
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
        discriminant: u8,
    };

    const result: *Event = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    const server = host.server orelse {
        result.discriminant = 4; // Shutdown
        return;
    };

    // Loop until we get a real event (skip ControlFrame and NotWebSocket errors)
    while (true) {
        const event = server.accept() catch |err| {
            if (err == error.ControlFrame or err == error.NotWebSocket) {
                // Skip these non-events and continue polling
                continue;
            }
            const msg = "Accept error";
            result.payload.err_str = RocStr.fromSliceSmall(msg);
            result.discriminant = 2; // Error
            return;
        };

        switch (event) {
            .connected => |client_id| {
                result.payload.client_id = client_id;
                result.discriminant = 0; // Connected
                return;
            },
            .disconnected => |client_id| {
                result.payload.client_id = client_id;
                result.discriminant = 1; // Disconnected
                return;
            },
            .message => |msg| {
                result.payload.message.client_id = msg.client_id;
                // Create RocStr from message text
                if (RocStr.fitsInSmallStr(msg.text.len)) {
                    result.payload.message.text = RocStr.fromSliceSmall(msg.text);
                } else {
                    result.payload.message.text = RocStr.init(msg.text.ptr, msg.text.len, ops);
                }
                result.discriminant = 3; // Message
                return;
            },
            .err => |msg| {
                if (RocStr.fitsInSmallStr(msg.len)) {
                    result.payload.err_str = RocStr.fromSliceSmall(msg);
                } else {
                    result.payload.err_str = RocStr.init(msg.ptr, msg.len, ops);
                }
                result.discriminant = 2; // Error
                return;
            },
            .shutdown => {
                result.discriminant = 4; // Shutdown
                return;
            },
        }
    }
}

/// WebServer.send! : U64, Str => Result({}, Str)
fn hostedWebServerSend(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };

    const Args = extern struct {
        client_id: u64,
        message: RocStr,
    };

    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const result: *Result = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    const server = host.server orelse {
        const msg = "Server not running";
        result.payload = RocStr.fromSliceSmall(msg);
        result.discriminant = 0;
        return;
    };

    const message = getAsSlice(&args.message);
    server.send(args.client_id, message) catch |err| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Send failed: {}", .{err}) catch "Send failed";
        if (RocStr.fitsInSmallStr(msg.len)) {
            result.payload = RocStr.fromSliceSmall(msg);
        } else {
            result.payload = RocStr.init(msg.ptr, msg.len, ops);
        }
        result.discriminant = 0;
        return;
    };

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

/// WebServer.broadcast! : Str => Result({}, Str)
fn hostedWebServerBroadcast(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };

    const Args = extern struct {
        message: RocStr,
    };

    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const result: *Result = @ptrCast(@alignCast(ret_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    const server = host.server orelse {
        const msg = "Server not running";
        result.payload = RocStr.fromSliceSmall(msg);
        result.discriminant = 0;
        return;
    };

    const message = getAsSlice(&args.message);
    server.broadcast(message) catch |err| {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Broadcast failed: {}", .{err}) catch "Broadcast failed";
        if (RocStr.fitsInSmallStr(msg.len)) {
            result.payload = RocStr.fromSliceSmall(msg);
        } else {
            result.payload = RocStr.init(msg.ptr, msg.len, ops);
        }
        result.discriminant = 0;
        return;
    };

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

/// WebServer.close! : U64 => {}
fn hostedWebServerClose(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = ret_ptr;

    const Args = extern struct {
        client_id: u64,
    };

    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const host: *HostEnv = @ptrCast(@alignCast(ops.env));

    if (host.server) |server| {
        server.closeClient(args.client_id);
    }
}

/// Stderr.line! : Str => {}
fn hostedStderrLine(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = ops;
    _ = ret_ptr;

    const Args = extern struct {
        str: RocStr,
    };
    const args: *Args = @ptrCast(@alignCast(args_ptr));
    const str = getAsSlice(&args.str);

    const stderr = std.fs.File.stderr();
    stderr.writeAll(str) catch {};
    stderr.writeAll("\n") catch {};
}

/// Stdout.line! : Str => {}
fn hostedStdoutLine(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
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

/// Array of hosted function pointers, sorted by module name alphabetically,
/// then by function name alphabetically within each module.
const hosted_function_ptrs = [_]builtins.host_abi.HostedFn{
    // SQLite: get_notes!, init!, save_notes!
    hostedSqliteGetNotes,
    hostedSqliteInit,
    hostedSqliteSaveNotes,
    // Stderr: line!
    hostedStderrLine,
    // Stdout: line!
    hostedStdoutLine,
    // Storage: delete!, exists!, list!, load!, save!
    hostedStorageDelete,
    hostedStorageExists,
    hostedStorageList,
    hostedStorageLoad,
    hostedStorageSave,
    // WebServer: accept!, broadcast!, close!, listen!, run!, send!
    hostedWebServerAccept,
    hostedWebServerBroadcast,
    hostedWebServerClose,
    hostedWebServerListen,
    hostedWebServerRun,
    hostedWebServerSend,
};

/// Platform host entrypoint
fn platform_main(argc: c_int, argv: [*][*:0]u8) c_int {
    var host_env = HostEnv{
        .gpa = std.heap.GeneralPurposeAllocator(.{}){},
        .server = null,
    };

    var roc_ops = builtins.host_abi.RocOps{
        .env = @as(*anyopaque, @ptrCast(&host_env)),
        .roc_alloc = rocAllocFn,
        .roc_dealloc = rocDeallocFn,
        .roc_realloc = rocReallocFn,
        .roc_dbg = rocDbgFn,
        .roc_expect_failed = rocExpectFailedFn,
        .roc_crashed = rocCrashedFn,
        .hosted_fns = .{
            .count = hosted_function_ptrs.len,
            .fns = @ptrCast(@constCast(&hosted_function_ptrs)),
        },
    };

    var exit_code: i32 = -99;

    // Convert argv to Roc List(Str)
    const count: usize = @intCast(argc);
    var args_list = if (count == 0) RocList.empty() else RocList.list_allocate(@alignOf(RocStr), count, @sizeOf(RocStr), true, &roc_ops);
    if (count > 0) {
        const items: [*]RocStr = @ptrCast(@alignCast(args_list.bytes));
        for (0..count) |i| {
            const arg_ptr = argv[i];
            const len = std.mem.len(arg_ptr);
            items[i] = RocStr.fromSlice(arg_ptr[0..len], &roc_ops);
        }
    }

    roc__main_for_host(&roc_ops, @as(*anyopaque, @ptrCast(&exit_code)), @as(*anyopaque, @ptrCast(&args_list)));

    // Cleanup server
    if (host_env.server) |server| {
        server.deinit();
        host_env.gpa.allocator().destroy(server);
    }

    _ = host_env.gpa.deinit();

    if (debug_or_expect_called.load(.acquire) and exit_code == 0) {
        return 1;
    }

    return exit_code;
}
// ============================================================================
// SQLite Implementation (using cImport)
// ============================================================================

const db_path = ".roc_storage/notes.db";
var db_ptr: ?*sqlite.sqlite3 = null;

/// Host environment with WebSocket server and database state
const HostEnv = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    server: ?*WebSocketServer = null,
};

fn initDatabase() !void {
    std.fs.cwd().makeDir(".roc_storage") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const rc = sqlite.sqlite3_open(db_path, @ptrCast(&db_ptr));
    if (rc != sqlite.SQLITE_OK) {
        return error.OpenFailed;
    }

    const create_table =
        \\CREATE TABLE IF NOT EXISTS notes (
        \\    id TEXT PRIMARY KEY,
        \\    content TEXT NOT NULL,
        \\    created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        \\    updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        \\);
    ;

    var stmt: ?*sqlite.sqlite3_stmt = undefined;
    const prep_rc = sqlite.sqlite3_prepare_v2(db_ptr, create_table, -1, &stmt, null);
    if (prep_rc != sqlite.SQLITE_OK) {
        return error.PrepareFailed;
    }
    defer _ = sqlite.sqlite3_finalize(stmt);

    const exec_rc = sqlite.sqlite3_step(stmt);
    if (exec_rc != sqlite.SQLITE_DONE) {
        return error.ExecFailed;
    }
}

/// Hosted function: SQLite.init!
/// Returns Result {} Str
fn hostedSqliteInit(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = args_ptr;

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    initDatabase() catch |err| {
        const msg = switch (err) {
            error.OpenFailed => "Failed to open database",
            error.PrepareFailed => "Failed to prepare statement",
            error.ExecFailed => "Failed to create table",
            else => "Failed to initialize database",
        };
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0; // Err
        return;
    };

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

/// Hosted function: SQLite.get_notes!
/// Returns Result Str Str
fn hostedSqliteGetNotes(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = args_ptr;

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    if (db_ptr == null) {
        const msg = "Database not initialized";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0; // Err
        return;
    }

    const query = "SELECT id, content FROM notes ORDER BY id DESC";
    var stmt: ?*sqlite.sqlite3_stmt = undefined;

    const prep_rc = sqlite.sqlite3_prepare_v2(db_ptr, query, -1, &stmt, null);
    if (prep_rc != sqlite.SQLITE_OK) {
        const msg = "Failed to prepare query";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    }
    defer _ = sqlite.sqlite3_finalize(stmt);

    var notes = std.ArrayListUnmanaged(struct { id: []const u8, content: []const u8 }){};
    defer {
        for (notes.items) |note| {
            c_allocator.free(note.id);
            c_allocator.free(note.content);
        }
        notes.deinit(c_allocator);
    }

    while (true) {
        const step_rc = sqlite.sqlite3_step(stmt);
        if (step_rc == sqlite.SQLITE_DONE) break;
        if (step_rc != sqlite.SQLITE_ROW) break;

        const id_ptr = sqlite.sqlite3_column_text(stmt, 0);
        const content_ptr = sqlite.sqlite3_column_text(stmt, 1);

        const id = if (id_ptr) |p| std.mem.sliceTo(p, 0) else "";
        const content = if (content_ptr) |p| std.mem.sliceTo(p, 0) else "";

        const id_dupe = c_allocator.dupe(u8, id) catch break;
        const content_dupe = c_allocator.dupe(u8, content) catch {
            c_allocator.free(id_dupe);
            break;
        };

        notes.append(c_allocator, .{
            .id = id_dupe,
            .content = content_dupe,
        }) catch {
            c_allocator.free(id_dupe);
            c_allocator.free(content_dupe);
            break;
        };
    }

    const next_id: i64 = if (notes.items.len == 0) 1 else blk: {
        var max_id: i64 = 0;
        for (notes.items) |note| {
            const id = std.fmt.parseInt(i64, note.id, 10) catch 0;
            if (id > max_id) max_id = id;
        }
        break :blk max_id + 1;
    };

    var json = std.ArrayList(u8).initCapacity(c_allocator, 1024) catch return;
    defer json.deinit(c_allocator);

    json.writer(c_allocator).print("{{\"notes\":{{", .{}) catch {};

    var first = true;
    for (notes.items) |note| {
        if (!first) json.writer(c_allocator).writeAll(",") catch {};
        first = false;

        json.writer(c_allocator).print("\"{s}\":{{\"id\":\"{s}\",\"content\":\"", .{ note.id, note.id }) catch {};

        for (note.content) |c| {
            switch (c) {
                '"' => json.writer(c_allocator).writeAll("\\\"") catch {},
                '\\' => json.writer(c_allocator).writeAll("\\\\") catch {},
                '\n' => json.writer(c_allocator).writeAll("\\n") catch {},
                '\r' => json.writer(c_allocator).writeAll("\\r") catch {},
                '\t' => json.writer(c_allocator).writeAll("\\t") catch {},
                else => json.writer(c_allocator).writeByte(c) catch {},
            }
        }

        json.writer(c_allocator).writeAll("\"}") catch {};
    }

    json.writer(c_allocator).print("}},\"nextId\":{d}}}", .{next_id}) catch {};

    result.payload = RocStr.init(json.items.ptr, json.items.len, ops);
    result.discriminant = 1; // Ok
}

/// Hosted function: SQLite.save_notes!
/// Returns Result {} Str
fn hostedSqliteSaveNotes(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const Args = extern struct { notes_json: RocStr };
    const args: *const Args = @ptrCast(@alignCast(args_ptr));
    const notes_json = getAsSlice(&args.notes_json);

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    if (db_ptr == null) {
        const msg = "Database not initialized";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0; // Err
        return;
    }

    // Delete all existing notes
    var delete_stmt: ?*sqlite.sqlite3_stmt = undefined;
    const delete_sql = "DELETE FROM notes";
    if (sqlite.sqlite3_prepare_v2(db_ptr, delete_sql, -1, &delete_stmt, null) == sqlite.SQLITE_OK) {
        defer _ = sqlite.sqlite3_finalize(delete_stmt);
        _ = sqlite.sqlite3_step(delete_stmt);
    }

    const notes_start = std.mem.indexOf(u8, notes_json, "\"notes\":{") orelse {
        const msg = "Invalid JSON format";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };

    var pos = notes_start + "\"notes\":{".len;

    const insert_sql = "INSERT INTO notes (id, content) VALUES (?, ?)";
    var insert_stmt: ?*sqlite.sqlite3_stmt = undefined;

    while (pos < notes_json.len) : (pos += 1) {
        while (pos < notes_json.len and (notes_json[pos] == ' ' or notes_json[pos] == ',' or notes_json[pos] == '\n')) : (pos += 1) {}

        if (pos >= notes_json.len or notes_json[pos] == '}') break;

        if (notes_json[pos] != '"') break;
        const id_start = pos + 1;
        const id_end = std.mem.indexOfPos(u8, notes_json, id_start, "\"") orelse break;
        const id = notes_json[id_start..id_end];
        pos = id_end + 1;

        pos = std.mem.indexOfPos(u8, notes_json, pos, "\"content\":\"") orelse break;
        pos += "\"content\":\"".len;

        const content_start = pos;
        var content_end = pos;
        while (content_end < notes_json.len) {
            if (notes_json[content_end] == '"' and (content_end == content_start or notes_json[content_end - 1] != '\\')) {
                break;
            }
            if (content_end + 1 < notes_json.len and notes_json[content_end] == '\\' and notes_json[content_end + 1] == '"') {
                content_end += 1;
            }
            content_end += 1;
        }

        if (content_end >= notes_json.len) break;

        var content = c_allocator.alloc(u8, content_end - content_start) catch break;
        errdefer c_allocator.free(content);

        var content_idx: usize = 0;
        var i = content_start;
        while (i < content_end) {
            if (notes_json[i] == '\\' and i + 1 < content_end) {
                i += 1;
                switch (notes_json[i]) {
                    '"' => content[content_idx] = '"',
                    '\\' => content[content_idx] = '\\',
                    'n' => content[content_idx] = '\n',
                    'r' => content[content_idx] = '\r',
                    't' => content[content_idx] = '\t',
                    else => content[content_idx] = notes_json[i],
                }
            } else {
                content[content_idx] = notes_json[i];
            }
            content_idx += 1;
            i += 1;
        }
        content = content[0..content_idx];

        // Prepare and execute insert statement
        const prep_rc = sqlite.sqlite3_prepare_v2(db_ptr, insert_sql, -1, &insert_stmt, null);
        if (prep_rc == sqlite.SQLITE_OK) {
            _ = sqlite.sqlite3_bind_text(insert_stmt, 1, id.ptr, @intCast(id.len), null);
            _ = sqlite.sqlite3_bind_text(insert_stmt, 2, content.ptr, @intCast(content.len), null);
            _ = sqlite.sqlite3_step(insert_stmt);
            _ = sqlite.sqlite3_finalize(insert_stmt);
            insert_stmt = null;
        }

        c_allocator.free(content);
        pos = content_end + 1;
    }

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

const storage_dir = ".roc_storage";

fn getStoragePath(key: []const u8, buf: *[4096]u8) []const u8 {
    const prefix = storage_dir ++ "/";
    @memcpy(buf[0..prefix.len], prefix);
    const copy_len = @min(key.len, buf.len - prefix.len);
    @memcpy(buf[prefix.len..][0..copy_len], key[0..copy_len]);
    return buf[0 .. prefix.len + copy_len];
}

fn hostedStorageDelete(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const Args = extern struct { key: RocStr };
    const args: *const Args = @ptrCast(@alignCast(args_ptr));
    const key = getAsSlice(&args.key);

    // Result layout: { discriminant: u8, payload: union }
    // Ok({}) = discriminant 1, Err(Str) = discriminant 0
    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    var path_buf: [4096]u8 = undefined;
    const path = getStoragePath(key, &path_buf);

    std.fs.cwd().deleteFile(path) catch |err| {
        const msg = switch (err) {
            error.FileNotFound => "File not found",
            error.AccessDenied => "Access denied",
            else => "Delete failed",
        };
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0; // Err
        return;
    };

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}

/// Hosted function: Storage.exists!
/// Returns Bool
fn hostedStorageExists(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = ops;
    const Args = extern struct { key: RocStr };
    const args: *const Args = @ptrCast(@alignCast(args_ptr));
    const key = getAsSlice(&args.key);

    const result: *bool = @ptrCast(@alignCast(ret_ptr));

    var path_buf: [4096]u8 = undefined;
    const path = getStoragePath(key, &path_buf);

    _ = std.fs.cwd().statFile(path) catch {
        result.* = false;
        return;
    };
    result.* = true;
}

/// Hosted function: Storage.list!
/// Returns List Str
fn hostedStorageList(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    _ = args_ptr;

    const result: *RocList = @ptrCast(@alignCast(ret_ptr));

    var dir = std.fs.cwd().openDir(storage_dir, .{ .iterate = true }) catch {
        result.* = RocList.empty();
        return;
    };
    defer dir.close();

    // Count entries first
    var count: usize = 0;
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .file) count += 1;
    }

    if (count == 0) {
        result.* = RocList.empty();
        return;
    }

    // Allocate list
    const list = RocList.allocateExact(@alignOf(RocStr), count, @sizeOf(RocStr), true, ops);
    const items: [*]RocStr = @ptrCast(@alignCast(list.bytes));

    // Fill entries
    var iter2 = dir.iterate();
    var i: usize = 0;
    while (iter2.next() catch null) |entry| {
        if (entry.kind == .file and i < count) {
            items[i] = RocStr.init(entry.name.ptr, entry.name.len, ops);
            i += 1;
        }
    }

    result.* = list;
}

/// Hosted function: Storage.load!
/// Returns Result Str [NotFound, PermissionDenied, Other Str]
fn hostedStorageLoad(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const Args = extern struct { key: RocStr };
    const args: *const Args = @ptrCast(@alignCast(args_ptr));
    const key = getAsSlice(&args.key);

    // Result layout for Result Str [NotFound, PermissionDenied, Other Str]
    // Tag union: NotFound=0, Other=1, PermissionDenied=2 (alphabetical)
    // Result: Ok=1 with Str payload, Err=0 with tag union payload
    const ErrPayload = extern struct {
        other_str: RocStr,
        tag: u8,
    };
    const Result = extern struct {
        payload: extern union {
            ok_str: RocStr,
            err: ErrPayload,
        },
        discriminant: u8,
    };
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    var path_buf: [4096]u8 = undefined;
    const path = getStoragePath(key, &path_buf);

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                result.payload.err = .{ .other_str = RocStr.empty(), .tag = 0 }; // NotFound
            },
            error.AccessDenied => {
                result.payload.err = .{ .other_str = RocStr.empty(), .tag = 2 }; // PermissionDenied
            },
            else => {
                const msg = "Failed to open file";
                result.payload.err = .{ .other_str = RocStr.init(msg.ptr, msg.len, ops), .tag = 1 }; // Other
            },
        }
        result.discriminant = 0; // Err
        return;
    };
    defer file.close();

    const content = file.readToEndAlloc(c_allocator, 1024 * 1024) catch {
        const msg = "Failed to read file";
        result.payload.err = .{ .other_str = RocStr.init(msg.ptr, msg.len, ops), .tag = 1 };
        result.discriminant = 0;
        return;
    };
    defer c_allocator.free(content);

    result.payload.ok_str = RocStr.init(content.ptr, content.len, ops);
    result.discriminant = 1; // Ok
}

fn ensureStorageDir() !void {
    std.fs.cwd().makeDir(storage_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

/// Hosted function: Storage.save!
/// Returns Result {} Str
fn hostedStorageSave(ops: *builtins.host_abi.RocOps, ret_ptr: *anyopaque, args_ptr: *anyopaque) callconv(.c) void {
    const Args = extern struct { key: RocStr, value: RocStr };
    const args: *const Args = @ptrCast(@alignCast(args_ptr));
    const key = getAsSlice(&args.key);
    const value = getAsSlice(&args.value);

    const Result = extern struct {
        payload: RocStr,
        discriminant: u8,
    };
    const result: *Result = @ptrCast(@alignCast(ret_ptr));

    ensureStorageDir() catch {
        const msg = "Failed to create storage directory";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };

    var path_buf: [4096]u8 = undefined;
    const path = getStoragePath(key, &path_buf);
    
    // Write to temp file first
    var temp_path_buf: [4096]u8 = undefined;
    const temp_path = std.fmt.bufPrint(&temp_path_buf, "{s}.tmp", .{path}) catch {
        const msg = "Path too long";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };

    const file = std.fs.cwd().createFile(temp_path, .{}) catch |err| {
        const msg = switch (err) {
            error.AccessDenied => "Access denied",
            else => "Failed to create file",
        };
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        return;
    };
    defer file.close();

    file.writeAll(value) catch {
        const msg = "Failed to write file";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        // Clean up temp file
        std.fs.cwd().deleteFile(temp_path) catch {};
        return;
    };
    
    // Atomic rename
    std.fs.cwd().rename(temp_path, path) catch {
        const msg = "Failed to rename file";
        result.payload = RocStr.init(msg.ptr, msg.len, ops);
        result.discriminant = 0;
        std.fs.cwd().deleteFile(temp_path) catch {};
        return;
    };

    result.payload = RocStr.empty();
    result.discriminant = 1; // Ok
}
