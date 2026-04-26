const std = @import("std");

fn configurePlatformLinking(step: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    switch (os_tag) {
        .windows => {
            step.root_module.linkSystemLibrary("user32", .{});
            step.root_module.linkSystemLibrary("kernel32", .{});
            step.root_module.linkSystemLibrary("xinput1_4", .{});
        },
        .linux => {
            step.root_module.linkSystemLibrary("X11", .{});
        },
        .macos => {
            step.root_module.linkFramework("CoreFoundation", .{});
            step.root_module.linkFramework("CoreGraphics", .{});
            step.root_module.linkFramework("Foundation", .{});
            step.root_module.linkFramework("GameController", .{});
            step.root_module.linkFramework("IOKit", .{});
            step.root_module.addCSourceFile(.{
                .file = step.step.owner.path("src/platform/macos_shim.m"),
                .flags = &.{ "-fblocks", "-fobjc-arc" },
                .language = .objective_c,
            });
        },
        else => {},
    }
}

fn configureWaylandDebugLinking(step: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    if (os_tag != .linux) return;

    step.root_module.linkSystemLibrary("wayland-client", .{});
    step.root_module.linkSystemLibrary("wayland-cursor", .{});
    step.root_module.linkSystemLibrary("xkbcommon", .{});
    step.root_module.linkSystemLibrary("m", .{});
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

    if (target.result.os.tag == .linux) {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/linux_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        translate_c.addIncludePath(b.path("src/platform"));
        const c_module = translate_c.createModule();
        module.addImport("c", c_module);
    } else if (target.result.os.tag == .windows) {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/windows_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const c_module = translate_c.createModule();
        module.addImport("c", c_module);
    }

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (target.result.os.tag == .linux) {
        const translate_c_2 = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/linux_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        translate_c_2.addIncludePath(b.path("src/platform"));
        const c_module_2 = translate_c_2.createModule();
        test_module.addImport("c", c_module_2);
    } else if (target.result.os.tag == .windows) {
        const translate_c_2 = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/windows_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const c_module_2 = translate_c_2.createModule();
        test_module.addImport("c", c_module_2);
    }
    const debug_module = b.createModule(.{
        .root_source_file = b.path("src/debug_input.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    if (target.result.os.tag == .linux) {
        const translate_c_debug = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/linux_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        translate_c_debug.addIncludePath(b.path("src/platform"));
        const c_module_debug = translate_c_debug.createModule();
        debug_module.addImport("c", c_module_debug);
    } else if (target.result.os.tag == .windows) {
        const translate_c_debug = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/windows_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const c_module_debug = translate_c_debug.createModule();
        debug_module.addImport("c", c_module_debug);
    }
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
    const debug_wayland_module = if (target.result.os.tag == .linux) blk: {
        const translate_c_wl = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/wayland_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        translate_c_wl.addIncludePath(b.path("src/platform"));
        const c_module_wl = translate_c_wl.createModule();

        const mod = b.createModule(.{
            .root_source_file = b.path("src/debug_input_wayland.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        mod.addImport("c", c_module_wl);
        mod.addIncludePath(b.path("src/platform"));
        break :blk mod;
    } else blk: {
        const mod = b.createModule(.{
            .root_source_file = b.path("src/platform/wayland_stub.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        break :blk mod;
    };
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
