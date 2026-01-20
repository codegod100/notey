const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    // Get roc dependency
    const roc = b.dependency("roc", .{});
    const builtins = roc.module("builtins");

    // Native step: build only for the current platform
    const native_step = b.step("native", "Build host library for native platform only");

    const native_target = b.standardTargetOptions(.{});

    // x64musl step: build for Linux with musl libc
    const x64musl_step = b.step("x64musl", "Build host library for x64musl target");
    const x64musl_target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl });

    // Native target configuration
    const host_module_native = b.createModule(.{
        .root_source_file = b.path("platform/host.zig"),
        .optimize = optimize,
        .target = native_target,
        .imports = &.{
            .{ .name = "builtins", .module = builtins },
        },
    });

    const host_lib_native = b.addLibrary(.{
        .name = "host",
        .linkage = .static,
        .root_module = host_module_native,
    });
    host_lib_native.linkLibC();
    b.installArtifact(host_lib_native);
    native_step.dependOn(&host_lib_native.step);

    // x64musl target configuration
    const host_module_x64musl = b.createModule(.{
        .root_source_file = b.path("platform/host.zig"),
        .optimize = optimize,
        .target = x64musl_target,
        .imports = &.{
            .{ .name = "builtins", .module = builtins },
        },
    });

    const host_lib_x64musl = b.addLibrary(.{
        .name = "host",
        .linkage = .static,
        .root_module = host_module_x64musl,
    });
    host_lib_x64musl.linkLibC();
    
    // Install to platform/targets/x64musl/
    const install_x64musl = b.addInstallArtifact(host_lib_x64musl, .{
        .dest_dir = .{ .override = .{ .custom = "platform/targets/x64musl" } },
    });
    x64musl_step.dependOn(&install_x64musl.step);
}
