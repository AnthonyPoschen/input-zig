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
    step.root_module.addCSourceFile(.{
        .file = step.step.owner.path("src/platform/wayland_shm_wrapper.c"),
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ---------- 创建唯一的共享 C 翻译模块 ----------
    const c_module: ?*std.Build.Module = if (target.result.os.tag == .linux) blk: {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/linux_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        translate_c.addIncludePath(b.path("src/platform"));
        break :blk translate_c.createModule();
    } else if (target.result.os.tag == .windows) blk: {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("src/platform/windows_headers.h"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        break :blk translate_c.createModule();
    } else null;

    // ---------- 主模块 module (input) ----------
    const module = b.addModule("input", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (c_module) |cm| module.addImport("c", cm);

    // ---------- 测试模块 ----------
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (c_module) |cm| test_module.addImport("c", cm);

    // ---------- debug 模块 ----------
    const debug_module = b.createModule(.{
        .root_source_file = b.path("src/debug_input.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (c_module) |cm| debug_module.addImport("c", cm);

    // ---------- wayland 调试模块 (独立的 C 头文件，可保留) ----------
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

    // ---------- 其他示例模块 (无需 C 导入，按原样) ----------
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

    // ---------- 可执行文件和测试 ----------
    const tests = b.addTest(.{ .root_module = test_module });
    const debug_exe = b.addExecutable(.{ .name = "debug-input", .root_module = debug_module });
    const example_exe = b.addExecutable(.{ .name = "player-action-map", .root_module = example_module });
    const save_action_map_exe = b.addExecutable(.{ .name = "save-action-map", .root_module = save_action_map_module });
    const load_action_map_debug_exe = b.addExecutable(.{ .name = "load-action-map-debug", .root_module = load_action_map_debug_module });

    // 模块之间的导入关系
    debug_module.addImport("debug_input_wayland", debug_wayland_module);
    debug_module.addImport("input", module);
    example_module.addImport("input", module);
    save_action_map_module.addImport("input", module);
    load_action_map_debug_module.addImport("input", module);
    load_action_map_debug_module.addImport("debug_input_wayland", debug_wayland_module);
    debug_wayland_module.addImport("input", module);

    // 平台链接
    configurePlatformLinking(tests, target.result.os.tag);
    configurePlatformLinking(debug_exe, target.result.os.tag);
    configurePlatformLinking(example_exe, target.result.os.tag);
    configurePlatformLinking(save_action_map_exe, target.result.os.tag);
    configurePlatformLinking(load_action_map_debug_exe, target.result.os.tag);
    configureWaylandDebugLinking(debug_exe, target.result.os.tag);
    configureWaylandDebugLinking(load_action_map_debug_exe, target.result.os.tag);

    // 安装与运行步骤
    const run_tests = b.addRunArtifact(tests);
    const run_debug = b.addRunArtifact(debug_exe);
    const install_example = b.addInstallArtifact(example_exe, .{});
    const install_save_action_map = b.addInstallArtifact(save_action_map_exe, .{});
    const install_load_action_map_debug = b.addInstallArtifact(load_action_map_debug_exe, .{});

    if (b.args) |args| run_debug.addArgs(args);

    const test_step = b.step("test", "Run library tests");
    const debug_step = b.step("debug-input", "Run terminal input debug viewer");
    const example_step = b.step("example-player", "Build the player action map example");
    const save_action_map_step = b.step("example-save-action-map", "Build the action map JSON save example");
    const load_action_map_debug_step = b.step("example-load-action-map-debug", "Build the action map JSON load debug viewer");

    test_step.dependOn(&run_tests.step);
    debug_step.dependOn(&run_debug.step);
    example_step.dependOn(&install_example.step);
    save_action_map_step.dependOn(&install_save_action_map.step);
    load_action_map_debug_step.dependOn(&install_load_action_map_debug.step);
}
