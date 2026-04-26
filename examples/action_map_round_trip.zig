const std = @import("std");
const input = @import("input");

const frame_time_ns = 100 * std.time.ns_per_ms;
const file_name = "action_bindings_round_trip.json";
const max_file_size = 64 * 1024;

const Config = struct {
    frame_limit: ?usize = null,
};

const Status = struct {
    loaded_from_disk: bool = false,
    last_event: []const u8 = "none",
};

fn buildDefaults(actions: *input.ActionMap) !void {
    try actions.set2d("move", .{
        .left = &.{.{ .code = .key_a }},
        .right = &.{.{ .code = .key_d }},
        .up = &.{.{ .code = .key_w }},
        .down = &.{.{ .code = .key_s }},
        .vectors = &.{.{ .code = .gamepad_left_stick }},
    });
    try actions.set("jump", &.{
        .{ .code = .key_space },
        .{ .code = .gamepad_face_south },
    });
    try actions.set("save_bindings", &.{
        .{ .code = .key_f5 },
        .{ .code = .gamepad_start },
    });
    try actions.set("reset_bindings", &.{
        .{ .code = .key_f9 },
        .{ .code = .gamepad_select },
    });
}

fn attachDevices(state: *input.InputSystem, actions: *input.ActionMap) !void {
    try actions.attachDevices(state, .{
        .keyboard = true,
        .gamepad_slot = 0,
    });
}

fn save(io: std.Io, path: []const u8, actions: *const input.ActionMap) !void {
    const bindings = actions.snapshot();
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    const out = &writer.interface;

    try std.json.Stringify.value(bindings.slice(), .{
        .emit_null_optional_fields = false,
    }, out);
    try out.writeByte('\n');
    try out.flush();
}

fn load(io: std.Io, path: []const u8, allocator: std.mem.Allocator, actions: *input.ActionMap) !bool {
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(contents);

    var parsed = try std.json.parseFromSlice(
        []input.ActionBinding,
        allocator,
        contents,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    try actions.importBindings(parsed.value);
    return true;
}

fn parseConfig(process_args: std.process.Args) !Config {
    var args = std.process.Args.Iterator.init(process_args);
    defer args.deinit();
    var config = Config{};

    _ = args.next();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameLimit;
            config.frame_limit = try parseUsize(value);
            continue;
        }
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

fn maybeHandleCommands(io: std.Io, actions: *input.ActionMap, defaults: *const input.ActionMap, state: *input.InputSystem, status: *Status) !void {
    if (actions.pressed(state, "save_bindings")) {
        try save(io, file_name, actions);
        status.last_event = "saved to disk";
    }

    if (actions.pressed(state, "reset_bindings")) {
        try actions.resetAll(defaults);
        status.last_event = "reset to defaults";
    }
}

fn renderBindings(writer: *std.Io.Writer, actions: *const input.ActionMap) !void {
    const bindings = actions.snapshot();
    for (bindings.slice()) |binding| {
        try writer.print("{s: <16} {s}", .{ binding.name, @tagName(binding.kind) });
        if (binding.codes) |codes| {
            try writer.writeAll(" = ");
            for (codes, 0..) |code, index| {
                if (index > 0) try writer.writeAll(", ");
                try writer.writeAll(input.inputCodeName(code.code) orelse "unknown");
                if (code.activation_threshold) |threshold| {
                    try writer.print(">{d:.2}", .{threshold});
                }
            }
            try writer.writeByte('\n');
            continue;
        }

        try writer.writeByte('\n');
        try renderDirectionalCodes(writer, "left", binding.left);
        try renderDirectionalCodes(writer, "right", binding.right);
        try renderDirectionalCodes(writer, "up", binding.up);
        try renderDirectionalCodes(writer, "down", binding.down);
        try renderDirectionalCodes(writer, "vectors", binding.vectors);
    }
}

fn renderDirectionalCodes(writer: *std.Io.Writer, name: []const u8, maybe_codes: ?[]const input.BoundInput) !void {
    const codes = maybe_codes orelse return;
    try writer.print("  {s: <8}= ", .{name});
    for (codes, 0..) |code, index| {
        if (index > 0) try writer.writeAll(", ");
        try writer.writeAll(input.inputCodeName(code.code) orelse "unknown");
        if (code.activation_threshold) |threshold| {
            try writer.print(">{d:.2}", .{threshold});
        }
    }
    try writer.writeByte('\n');
}

fn render(writer: *std.Io.Writer, actions: *const input.ActionMap, state: *input.InputSystem, status: Status, frame_limit: ?usize) !void {
    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.writeAll("action map json round-trip example\n");
    try writer.print("config file: {s}\n", .{file_name});
    try writer.print("source: {s}\n", .{if (status.loaded_from_disk) "loaded from disk" else "built-in defaults"});
    try writer.print("last event: {s}\n", .{status.last_event});
    if (frame_limit) |limit| {
        try writer.print("frame limit: {d}\n", .{limit});
    } else {
        try writer.writeAll("frame limit: none\n");
    }
    try writer.writeAll("press save_bindings to write json, reset_bindings to restore defaults\n\n");

    const move = actions.axis2d(state, "move");
    try writer.print("move         = ({d:.2}, {d:.2})\n", .{ move.x, move.y });
    try writer.print("jump down    = {any}\n", .{actions.down(state, "jump")});
    try writer.print("save pressed = {any}\n", .{actions.pressed(state, "save_bindings")});
    try writer.print("reset pressed= {any}\n\n", .{actions.pressed(state, "reset_bindings")});

    try renderBindings(writer, actions);
}

pub fn main(init: std.process.Init) !void {
    const config = try parseConfig(init.minimal.args);

    var stdout_buffer: [8192]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const writer = &stdout.interface;

    var state = input.InputSystem{};
    var defaults = input.ActionMap.init();
    try buildDefaults(&defaults);

    var actions = defaults;
    var status = Status{};
    status.loaded_from_disk = try load(
        init.io,
        file_name,
        std.heap.page_allocator,
        &actions,
    );
    try attachDevices(&state, &actions);

    var frame_count: usize = 0;
    while (true) {
        try state.keyboard().update();
        if (state.gamepad(0)) |gamepad| try gamepad.update();

        try maybeHandleCommands(init.io, &actions, &defaults, &state, &status);
        try render(writer, &actions, &state, status, config.frame_limit);
        try writer.flush();

        frame_count += 1;
        if (config.frame_limit) |limit| {
            if (frame_count >= limit) return;
        }

        try init.io.sleep(std.Io.Duration.fromNanoseconds(frame_time_ns), .awake);
    }
}
