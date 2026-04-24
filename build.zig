const std = @import("std");

fn configurePlatformLinking(step: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    switch (os_tag) {
        .windows => {
            step.linkSystemLibrary("user32");
            step.linkSystemLibrary("kernel32");
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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("input_zig", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    configurePlatformLinking(tests, target.result.os.tag);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    _ = module;
}
