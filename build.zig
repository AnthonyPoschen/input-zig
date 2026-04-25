const std = @import("std");

fn configurePlatformLinking(step: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    switch (os_tag) {
        .windows => {
            step.linkSystemLibrary("user32");
            step.linkSystemLibrary("kernel32");
            step.linkSystemLibrary("xinput1_4");
        },
        .linux => {
            step.linkSystemLibrary("X11");
        },
        .macos => {
            step.linkFramework("ApplicationServices");
            step.linkFramework("Carbon");
        },
        else => {},
    }
}

fn configureWaylandDebugLinking(step: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    if (os_tag != .linux) return;

    step.linkSystemLibrary("wayland-client");
    step.linkSystemLibrary("wayland-cursor");
    step.linkSystemLibrary("xkbcommon");
    step.linkSystemLibrary("m");
    step.root_module.addIncludePath(step.step.owner.path("src/platform"));
    step.root_module.addCSourceFile(.{
        .file = step.step.owner.path("src/platform/xdg-shell-protocol.c"),
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("input", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const debug_module = b.createModule(.{
        .root_source_file = b.path("src/debug_input.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const example_module = b.createModule(.{
        .root_source_file = b.path("examples/player_action_map.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const save_action_map_module = b.createModule(.{
        .root_source_file = b.path("examples/save_action_map.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const load_action_map_debug_module = b.createModule(.{
        .root_source_file = b.path("examples/load_action_map_debug.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const debug_wayland_module = b.createModule(.{
        .root_source_file = b.path("src/debug_input_wayland.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    debug_wayland_module.addIncludePath(b.path("src/platform"));
    const tests = b.addTest(.{
        .root_module = test_module,
    });

    const debug_exe = b.addExecutable(.{
        .name = "debug-input",
        .root_module = debug_module,
    });
    const example_exe = b.addExecutable(.{
        .name = "player-action-map",
        .root_module = example_module,
    });
    const save_action_map_exe = b.addExecutable(.{
        .name = "save-action-map",
        .root_module = save_action_map_module,
    });
    const load_action_map_debug_exe = b.addExecutable(.{
        .name = "load-action-map-debug",
        .root_module = load_action_map_debug_module,
    });
    debug_module.addImport("input", module);
    example_module.addImport("input", module);
    save_action_map_module.addImport("input", module);
    load_action_map_debug_module.addImport("input", module);
    load_action_map_debug_module.addImport("debug_input_wayland", debug_wayland_module);
    debug_wayland_module.addImport("input", module);

    configurePlatformLinking(tests, target.result.os.tag);
    configurePlatformLinking(debug_exe, target.result.os.tag);
    configurePlatformLinking(example_exe, target.result.os.tag);
    configurePlatformLinking(save_action_map_exe, target.result.os.tag);
    configurePlatformLinking(load_action_map_debug_exe, target.result.os.tag);
    configureWaylandDebugLinking(debug_exe, target.result.os.tag);
    configureWaylandDebugLinking(load_action_map_debug_exe, target.result.os.tag);

    const run_tests = b.addRunArtifact(tests);
    const run_debug = b.addRunArtifact(debug_exe);
    const install_example = b.addInstallArtifact(example_exe, .{});
    const install_save_action_map = b.addInstallArtifact(save_action_map_exe, .{});
    const install_load_action_map_debug = b.addInstallArtifact(load_action_map_debug_exe, .{});

    if (b.args) |args| {
        run_debug.addArgs(args);
    }

    const test_step = b.step("test", "Run library tests");
    const debug_step = b.step(
        "debug-input",
        "Run terminal input debug viewer",
    );
    const example_step = b.step(
        "example-player",
        "Build the player action map example",
    );
    const save_action_map_step = b.step(
        "example-save-action-map",
        "Build the action map JSON save example",
    );
    const load_action_map_debug_step = b.step(
        "example-load-action-map-debug",
        "Build the action map JSON load debug viewer",
    );

    test_step.dependOn(&run_tests.step);
    debug_step.dependOn(&run_debug.step);
    example_step.dependOn(&install_example.step);
    save_action_map_step.dependOn(&install_save_action_map.step);
    load_action_map_debug_step.dependOn(&install_load_action_map_debug.step);
}
