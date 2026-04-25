const std = @import("std");
const input = @import("input_zig");
const builtin = @import("builtin");
const debug_input_wayland = @import("debug_input_wayland.zig");

const frame_time_ns = 100 * std.time.ns_per_ms;

const Config = struct {
    backend: input.BackendChoice = .auto,
    frame_limit: ?usize = null,
};

const KeyProbe = struct {
    label: []const u8,
    code: input.InputCode,
};

const MouseProbe = struct {
    label: []const u8,
    code: input.InputCode,
};

const key_probes = [_]KeyProbe{
    .{ .label = "W", .code = .key_w },
    .{ .label = "A", .code = .key_a },
    .{ .label = "S", .code = .key_s },
    .{ .label = "D", .code = .key_d },
    .{ .label = "Space", .code = .key_space },
    .{ .label = "Escape", .code = .key_escape },
    .{ .label = "Left Shift", .code = .key_shift_left },
    .{ .label = "Right Shift", .code = .key_shift_right },
    .{ .label = "Left Ctrl", .code = .key_control_left },
    .{ .label = "Right Ctrl", .code = .key_control_right },
    .{ .label = "Left Alt", .code = .key_alt_left },
    .{ .label = "Right Alt", .code = .key_alt_right },
    .{ .label = "Left", .code = .key_left },
    .{ .label = "Right", .code = .key_right },
    .{ .label = "Up", .code = .key_up },
    .{ .label = "Down", .code = .key_down },
};

const mouse_probes = [_]MouseProbe{
    .{ .label = "Left", .code = .mouse_left },
    .{ .label = "Right", .code = .mouse_right },
    .{ .label = "Middle", .code = .mouse_middle },
    .{ .label = "Button4", .code = .mouse_button4 },
    .{ .label = "Button5", .code = .mouse_button5 },
};

/// Run a terminal debug viewer that polls and prints input state.
pub fn main() !void {
    if (builtin.os.tag == .linux) {
        const linux_config = try parseConfig();
        if (input.selectedBackend(linux_config.backend) == .wayland) {
            return debug_input_wayland.run(linux_config.frame_limit);
        }
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr = std.fs.File.stderr().writer(&stderr_buffer);
    var stdout_writer = &stdout.interface;
    var stderr_writer = &stderr.interface;
    const config = try parseConfig();
    const effective_backend = input.selectedBackend(config.backend);
    var state = input.InputSystem{};
    var frame_count: usize = 0;

    while (true) {
        updateAndRender(
            &state,
            config.backend,
            effective_backend,
            config.frame_limit,
            stdout_writer,
        ) catch |err| {
            try stdout_writer.flush();
            try renderError(
                stderr_writer,
                err,
                config.backend,
                effective_backend,
            );
            try stderr_writer.flush();
            return err;
        };

        frame_count += 1;
        try stdout_writer.flush();

        if (config.frame_limit) |limit| {
            if (frame_count >= limit) return;
        }

        std.Thread.sleep(frame_time_ns);
    }
}

/// Parse optional backend and frame limit arguments passed after `--`.
fn parseConfig() !Config {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    var config = Config{};

    _ = args.next();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "auto")) {
            config.backend = .auto;
            continue;
        }

        if (std.mem.eql(u8, arg, "x11")) {
            config.backend = .x11;
            continue;
        }

        if (std.mem.eql(u8, arg, "wayland")) {
            config.backend = .wayland;
            continue;
        }

        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameLimit;
            config.frame_limit = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        std.debug.print(
            "unknown arg '{s}', expected auto|x11|wayland or --frames N\n",
            .{arg},
        );
        return error.InvalidBackendChoice;
    }

    return config;
}

/// Poll the library state and redraw the terminal view.
fn updateAndRender(state: *input.InputSystem, requested_backend: input.BackendChoice, effective_backend: input.BackendChoice, frame_limit: ?usize, writer: anytype) !void {
    try state.update(requested_backend);

    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.print("input-zig debug viewer\n", .{});
    try writer.print("backend requested: {s}\n", .{backendName(requested_backend)});
    try writer.print("backend effective: {s}\n", .{backendName(effective_backend)});

    if (frame_limit) |limit| {
        try writer.print("frame limit: {d}\n\n", .{limit});
    } else {
        try writer.writeAll("frame limit: none\n");
        try writer.writeAll("ctrl+c to exit\n\n");
    }

    try renderMouse(writer, state.mouse());
    try writer.writeByte('\n');
    try renderKeyboard(writer, state.keyboard());
}

/// Render mouse position and button transitions.
fn renderMouse(writer: anytype, mouse: *const input.MouseDevice) !void {
    const position = mouse.position(null);
    try writer.print("mouse position: {d:.1}, {d:.1}\n", .{
        position.x,
        position.y,
    });
    try writer.writeAll("mouse buttons:\n");

    for (mouse_probes) |probe| {
        try renderButtonState(writer, probe.label, mouse, probe.code);
    }
}

/// Render a fixed probe set of keyboard keys and transitions.
fn renderKeyboard(writer: anytype, keyboard: *const input.KeyboardDevice) !void {
    try writer.writeAll("keyboard keys:\n");

    for (key_probes) |probe| {
        try renderKeyState(writer, probe.label, keyboard, probe.code);
    }
}

/// Print a single keyboard probe in a compact, scan-friendly row.
fn renderKeyState(writer: anytype, label: []const u8, keyboard: *const input.KeyboardDevice, code: input.InputCode) !void {
    try writer.print(
        "  {s: <11} down={any} press={any} release={any}\n",
        .{
            label,
            keyboard.down(code),
            keyboard.press(code),
            keyboard.release(code),
        },
    );
}

/// Print a single mouse probe in a compact, scan-friendly row.
fn renderButtonState(writer: anytype, label: []const u8, mouse: *const input.MouseDevice, code: input.InputCode) !void {
    try writer.print(
        "  {s: <11} down={any} press={any} release={any}\n",
        .{
            label,
            mouse.down(code),
            mouse.press(code),
            mouse.release(code),
        },
    );
}

/// Describe backend-specific setup problems in plain terms.
fn renderError(writer: anytype, err: anyerror, requested_backend: input.BackendChoice, effective_backend: input.BackendChoice) !void {
    try writer.print("debug-input failed with {s}\n", .{@errorName(err)});

    switch (err) {
        error.WaylandGlobalPollingUnsupported => {
            try writer.writeAll(
                "Wayland global input polling is not implemented yet.\n",
            );
            try writer.writeAll(
                "Run under X11 or pass `-- x11` if an X11 session is available.\n",
            );
        },
        error.NoDisplayServer => {
            try writer.writeAll(
                "No supported display server was detected for global polling.\n",
            );
            try writer.writeAll(
                "Set DISPLAY for X11 or pass `-- x11` in an X11 session.\n",
            );
        },
        error.DisplayOpenFailed => {
            try writer.writeAll(
                "The X11 display could not be opened. Check DISPLAY and X access.\n",
            );
        },
        error.InvalidBackendChoice => {
            try writer.writeAll("Expected backend argument: auto, x11, or wayland.\n");
        },
        else => {},
    }

    try writer.print(
        "backend requested: {s}\n",
        .{backendName(requested_backend)},
    );
    try writer.print(
        "backend effective: {s}\n",
        .{backendName(effective_backend)},
    );
}

/// Convert the backend enum into a stable printable name.
fn backendName(choice: input.BackendChoice) []const u8 {
    return switch (choice) {
        .auto => "auto",
        .x11 => "x11",
        .wayland => "wayland",
    };
}
