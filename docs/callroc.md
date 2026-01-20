 If you use the built-in host helpers from the test fixtures:

   zig
     const std = @import("std");
     const str = @import("glue/str.zig");
     const RocStr = str.RocStr;

     extern fn roc__main_for_host_1_caller([*]u8, *const RocStr, [*]u8, *RocStr) void;

     pub export fn main() c_int {
         // Call Roc with input "hello"
         const input = RocStr.fromSlice("hello");
         defer input.decref(null);  // cleanup

         var result: RocStr = undefined;
         roc__main_for_host_1_caller(null, &input, null, &result);
         defer result.decref(null);

         // Print "HELLO PROCESSED"
         std.debug.print("{s}\n", .{result.asSlice()});

         return 0;
     }

   This demonstrates: Platform (Zig) → Roc (string processing) → Platform (printing result). The key is _caller function
   that Roc automatically generates for exposed functions.