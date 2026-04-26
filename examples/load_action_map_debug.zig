const std = @import("std");
const input = @import("input");
const builtin = @import("builtin");
const action_map_json = @import("action_map_json.zig");
const cli_compat = @import("cli_compat");
const debug_input_wayland = @import("debug_input_wayland");

const frame_time_ns = 100 * std.time.ns_per_ms;

const Config = struct {
    frame_limit: ?usize = null,
};

const ActionDebugContext = struct {
    actions: *input.ActionMap,
    loaded: bool,
    devices_attached: bool = false,
};

pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    runMain(@intCast(argc), argv) catch |err| {
        std.debug.print("load-action-map-debug failed with {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn runMain(argc: usize, argv: [*][*:0]u8) !void {
    const config = try parseConfigArgv(argv[0..argc]);
    var runtime = cli_compat.Runtime.init();
    defer runtime.deinit();

    var stdout_buffer: [8192]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout = runtime.stdoutWriter(&stdout_buffer);
    var stderr = runtime.stderrWriter(&stderr_buffer);
    const stdout_writer = &stdout.interface;
    const stderr_writer = &stderr.interface;

    var state = input.InputSystem{};
    var defaults = input.ActionMap.init();
    try action_map_json.buildDefaultActions(&defaults);

    var actions = defaults;
    const loaded = action_map_json.load(
        &runtime,
        action_map_json.file_name,
        std.heap.page_allocator,
        &actions,
    ) catch |err| {
        try renderError(stderr_writer, err);
        try stderr_writer.flush();
        return err;
    };

    if (builtin.os.tag == .linux and input.selectedBackend() == .wayland) {
        var context = ActionDebugContext{
            .actions = &actions,
            .loaded = loaded,
        };
        return debug_input_wayland.runFocusedInput(
            ActionDebugContext,
            &context,
            config.frame_limit,
            renderWaylandActionMap,
        );
    }

    try action_map_json.attachDefaultDevices(&state, &actions);

    var frame_count: usize = 0;
    while (true) {
        updateAndRender(
            &state,
            &actions,
            loaded,
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

        try runtime.sleep(frame_time_ns);
    }
}

fn parseConfigArgv(argv: []const [*:0]u8) !Config {
    var config = Config{};

    var index: usize = 1;
    while (index < argv.len) : (index += 1) {
        const arg = std.mem.span(argv[index]);
        if (std.mem.eql(u8, arg, "--frames")) {
            index += 1;
            if (index >= argv.len) return error.MissingFrameLimit;
            const value = std.mem.span(argv[index]);
            config.frame_limit = try parseUsize(value);
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

fn parseUsize(text: []const u8) !usize {
    if (text.len == 0) return error.InvalidFrameLimit;
    var out: usize = 0;
    for (text) |byte| {
        if (byte < '0' or byte > '9') return error.InvalidFrameLimit;
        out = out * 10 + (byte - '0');
    }
    return out;
}

fn renderWaylandActionMap(
    context: *ActionDebugContext,
    state: *input.InputSystem,
    focus: debug_input_wayland.FocusState,
    writer: *std.Io.Writer,
    frame_limit: ?usize,
) !void {
    if (!context.devices_attached) {
        try action_map_json.attachDefaultDevices(state, context.actions);
        context.devices_attached = true;
    }

    try renderActionMap(
        state,
        context.actions,
        context.loaded,
        frame_limit,
        focus,
        writer,
    );
}

fn updateAndRender(
    state: *input.InputSystem,
    actions: *const input.ActionMap,
    loaded: bool,
    frame_limit: ?usize,
    writer: *std.Io.Writer,
) !void {
    try action_map_json.updateDefaultDevices(state);

    try renderActionMap(
        state,
        actions,
        loaded,
        frame_limit,
        null,
        writer,
    );
}

fn renderActionMap(
    state: *input.InputSystem,
    actions: *const input.ActionMap,
    loaded: bool,
    frame_limit: ?usize,
    focus: ?debug_input_wayland.FocusState,
    writer: *std.Io.Writer,
) !void {
    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.writeAll("action map debug viewer\n");
    try writer.print("bindings: {s}\n", .{if (loaded) action_map_json.file_name else "built-in defaults"});

    if (frame_limit) |limit| {
        try writer.print("frame limit: {d}\n\n", .{limit});
    } else {
        try writer.writeAll("frame limit: none\n");
        try writer.writeAll("ctrl+c to exit\n\n");
    }

    if (focus) |value| {
        try writer.print("window focus: keyboard={any} pointer={any}\n\n", .{
            value.keyboard,
            value.pointer,
        });
    }

    const bindings = actions.snapshot();

    for (bindings.slice()) |binding| {
        switch (binding.kind) {
            .codes => try renderCodeAction(writer, state, actions, binding),
            .axis_2d => try renderAxis2dAction(writer, state, actions, binding),
        }
    }
}

fn renderCodeAction(
    writer: *std.Io.Writer,
    state: *input.InputSystem,
    actions: *const input.ActionMap,
    binding: input.ActionBinding,
) !void {
    try writer.print(
        "{s: <12} enabled={any} down={any} pressed={any} released={any} bindings=",
        .{
            binding.name,
            binding.enabled,
            actions.down(state, binding.name),
            actions.pressed(state, binding.name),
            actions.released(state, binding.name),
        },
    );
    try renderCodeList(writer, binding.codes orelse &.{});
    try writer.writeByte('\n');
}

fn renderAxis2dAction(
    writer: *std.Io.Writer,
    state: *input.InputSystem,
    actions: *const input.ActionMap,
    binding: input.ActionBinding,
) !void {
    const value = actions.axis2d(state, binding.name);
    try writer.print("{s: <12} enabled={any} axis=(", .{
        binding.name,
        binding.enabled,
    });
    try writeFixed(writer, value.x, 100);
    try writer.writeAll(", ");
    try writeFixed(writer, value.y, 100);
    try writer.writeAll(")\n");
    try renderNamedCodeList(writer, "left", binding.left);
    try renderNamedCodeList(writer, "right", binding.right);
    try renderNamedCodeList(writer, "up", binding.up);
    try renderNamedCodeList(writer, "down", binding.down);
    try renderNamedCodeList(writer, "vectors", binding.vectors);
}

fn writeFixed(writer: *std.Io.Writer, value: f32, comptime scale: i32) !void {
    var scaled: i32 = @intFromFloat(value * @as(f32, @floatFromInt(scale)));
    if (scaled < 0) {
        try writer.writeByte('-');
        scaled = -scaled;
    }

    const whole = @divTrunc(scaled, scale);
    const fraction: u32 = @intCast(@rem(scaled, scale));
    if (scale == 10) {
        try writer.print("{d}.{d}", .{ whole, fraction });
    } else {
        try writer.print("{d}.{d:0>2}", .{ whole, fraction });
    }
}

fn renderNamedCodeList(
    writer: *std.Io.Writer,
    label: []const u8,
    codes: ?[]const input.BoundInput,
) !void {
    if (codes == null) return;
    try writer.print("  {s: <8} ", .{label});
    try renderCodeList(writer, codes.?);
    try writer.writeByte('\n');
}

fn renderCodeList(writer: *std.Io.Writer, codes: []const input.BoundInput) !void {
    try writer.writeByte('[');
    for (codes, 0..) |code, index| {
        if (index > 0) try writer.writeAll(", ");
        try writer.writeAll(input.inputCodeLabel(code.code) orelse input.inputCodeName(code.code) orelse "Unknown");
    }
    try writer.writeByte(']');
}

fn renderError(writer: *std.Io.Writer, err: anyerror) !void {
    try writer.print("load-action-map-debug failed with {s}\n", .{@errorName(err)});

    switch (err) {
        error.FileNotFound => {
            try writer.writeAll("No saved action map was found; defaults should be used instead.\n");
        },
        error.NoDisplayServer => {
            try writer.writeAll("No supported display server was detected for global polling.\n");
        },
        error.DisplayOpenFailed => {
            try writer.writeAll("The X11 display could not be opened. Check DISPLAY and X access.\n");
        },
        error.InvalidActionBindingJson => {
            try writer.writeAll("The JSON action map did not match the expected shape.\n");
        },
        error.InvalidInputCode => {
            try writer.writeAll("The JSON action map contains an unknown input code name.\n");
        },
        else => {},
    }
}
