const std = @import("std");
const input = @import("input");
const builtin = @import("builtin");
const debug_input_wayland = @import("debug_input_wayland.zig");

const frame_time_ns = 100 * std.time.ns_per_ms;

const Config = struct {
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

const GamepadProbe = struct {
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

const gamepad_probes = [_]GamepadProbe{
    .{ .label = "Face South", .code = .gamepad_face_south },
    .{ .label = "Face East", .code = .gamepad_face_east },
    .{ .label = "Face West", .code = .gamepad_face_west },
    .{ .label = "Face North", .code = .gamepad_face_north },
    .{ .label = "Dpad Up", .code = .gamepad_dpad_up },
    .{ .label = "Dpad Down", .code = .gamepad_dpad_down },
    .{ .label = "Dpad Left", .code = .gamepad_dpad_left },
    .{ .label = "Dpad Right", .code = .gamepad_dpad_right },
    .{ .label = "L Shoulder", .code = .gamepad_left_shoulder },
    .{ .label = "R Shoulder", .code = .gamepad_right_shoulder },
    .{ .label = "L Trigger", .code = .gamepad_left_trigger },
    .{ .label = "R Trigger", .code = .gamepad_right_trigger },
    .{ .label = "Select", .code = .gamepad_select },
    .{ .label = "Start", .code = .gamepad_start },
    .{ .label = "Home", .code = .gamepad_home },
    .{ .label = "Capture", .code = .gamepad_capture },
    .{ .label = "L Stick", .code = .gamepad_left_stick_press },
    .{ .label = "R Stick", .code = .gamepad_right_stick_press },
};

/// Run a terminal debug viewer that polls and prints input state.
pub fn main() !void {
    const config = try parseConfig();

    if (builtin.os.tag == .linux) {
        if (input.selectedBackend() == .wayland) {
            return debug_input_wayland.run(config.frame_limit);
        }
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr = std.fs.File.stderr().writer(&stderr_buffer);
    var stdout_writer = &stdout.interface;
    var stderr_writer = &stderr.interface;
    var state = input.InputSystem{};
    var frame_count: usize = 0;

    while (true) {
        updateAndRender(
            &state,
            config.frame_limit,
            stdout_writer,
        ) catch |err| {
            try stdout_writer.flush();
            try renderError(stderr_writer, err);
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

/// Parse optional frame limit arguments passed after `--`.
fn parseConfig() !Config {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    var config = Config{};

    _ = args.next();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameLimit;
            config.frame_limit = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        std.debug.print(
            "unknown arg '{s}', expected only --frames N\n",
            .{arg},
        );
        return error.InvalidArgument;
    }

    return config;
}

/// Poll the library state and redraw the terminal view.
fn updateAndRender(state: *input.InputSystem, frame_limit: ?usize, writer: anytype) !void {
    try state.mouse().update();
    try state.keyboard().update();
    var gamepad_slot: usize = 0;
    while (state.gamepad(gamepad_slot)) |gamepad| : (gamepad_slot += 1) {
        try gamepad.update();
    }

    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.print("input debug viewer\n", .{});

    if (frame_limit) |limit| {
        try writer.print("frame limit: {d}\n\n", .{limit});
    } else {
        try writer.writeAll("frame limit: none\n");
        try writer.writeAll("ctrl+c to exit\n\n");
    }

    try renderMouse(writer, state.mouse());
    try writer.writeByte('\n');
    try renderKeyboard(writer, state.keyboard());
    try writer.writeByte('\n');
    try renderGamepads(writer, state);
}

/// Render mouse position and button transitions.
fn renderMouse(writer: anytype, mouse: *const input.MouseDevice) !void {
    const position = mouse.position(null);
    const delta = mouse.delta();
    const scroll_delta = mouse.scrollDelta();
    try writer.print("mouse position: {d:.1}, {d:.1}\n", .{
        position.x,
        position.y,
    });
    try writer.print("mouse delta:    {d:.1}, {d:.1}\n", .{
        delta.x,
        delta.y,
    });
    try writer.print("scroll delta:   {d:.1}, {d:.1}\n", .{
        scroll_delta.x,
        scroll_delta.y,
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

fn renderGamepads(writer: anytype, state: *const input.InputSystem) !void {
    try writer.writeAll("gamepads:\n");

    var slot: usize = 0;
    while (state.gamepad(slot)) |gamepad| : (slot += 1) {
        try writer.print("  slot {d} connected={any} name={s}\n", .{
            slot,
            gamepad.view.connected,
            gamepad.view.nameSlice(),
        });

        if (!gamepad.view.connected) continue;

        const left = gamepad.leftStick();
        const right = gamepad.rightStick();
        try writer.print(
            "    left=({d:.2}, {d:.2}) right=({d:.2}, {d:.2}) lt={d:.2} rt={d:.2}\n",
            .{
                left.x,
                left.y,
                right.x,
                right.y,
                gamepad.leftTrigger(),
                gamepad.rightTrigger(),
            },
        );
        try renderRawGamepadButtons(writer, gamepad);

        for (gamepad_probes) |probe| {
            try writer.print(
                "    {s: <11} down={any} pressed={any} released={any}\n",
                .{
                    probe.label,
                    gamepad.down(probe.code),
                    gamepad.pressed(probe.code),
                    gamepad.released(probe.code),
                },
            );
        }
    }
}

fn renderRawGamepadButtons(writer: anytype, gamepad: *const input.GamepadDevice) !void {
    try writer.writeAll("    raw buttons:");
    for (gamepad.buttons[0..18], 0..) |button, index| {
        if (button == .down) {
            try writer.print(" {d}=1", .{index});
        }
    }
    try writer.writeByte('\n');
}

/// Print a single keyboard probe in a compact, scan-friendly row.
fn renderKeyState(writer: anytype, label: []const u8, keyboard: *const input.KeyboardDevice, code: input.InputCode) !void {
    try writer.print(
        "  {s: <11} down={any} pressed={any} released={any}\n",
        .{
            label,
            keyboard.down(code),
            keyboard.pressed(code),
            keyboard.released(code),
        },
    );
}

/// Print a single mouse probe in a compact, scan-friendly row.
fn renderButtonState(writer: anytype, label: []const u8, mouse: *const input.MouseDevice, code: input.InputCode) !void {
    try writer.print(
        "  {s: <11} down={any} pressed={any} released={any}\n",
        .{
            label,
            mouse.down(code),
            mouse.pressed(code),
            mouse.released(code),
        },
    );
}

/// Describe backend-specific setup problems in plain terms.
fn renderError(writer: anytype, err: anyerror) !void {
    try writer.print("debug-input failed with {s}\n", .{@errorName(err)});

    switch (err) {
        error.NoDisplayServer => {
            try writer.writeAll(
                "No supported display server was detected for global polling.\n",
            );
            try writer.writeAll(
                "Set DISPLAY for X11 or WAYLAND_DISPLAY for Wayland.\n",
            );
        },
        error.DisplayOpenFailed => {
            try writer.writeAll(
                "The X11 display could not be opened. Check DISPLAY and X access.\n",
            );
        },
        error.InvalidArgument => {
            try writer.writeAll("Expected only --frames N.\n");
        },
        else => {},
    }
}
