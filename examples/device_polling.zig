const std = @import("std");
const input = @import("input");

const frame_time_ns = 100 * std.time.ns_per_ms;

const Config = struct {
    frame_limit: ?usize = null,
};

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

fn render(writer: *std.Io.Writer, state: *input.InputSystem, frame_limit: ?usize) !void {
    const keyboard = state.keyboard();
    const mouse = state.mouse();
    const gamepad = state.gamepad(0) orelse unreachable;
    const raw_mouse = mouse.position(null);

    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.writeAll("device polling example\n");
    if (frame_limit) |limit| {
        try writer.print("frame limit: {d}\n\n", .{limit});
    } else {
        try writer.writeAll("frame limit: none\n");
        try writer.writeAll("ctrl+c to exit\n\n");
    }

    try writer.writeAll("keyboard\n");
    try writer.print("  space down     = {any}\n", .{keyboard.down(.key_space)});
    try writer.print("  escape pressed = {any}\n", .{keyboard.pressed(.key_escape)});
    try writer.print("  w released     = {any}\n", .{keyboard.released(.key_w)});

    try writer.writeAll("\nmouse\n");
    try writer.print("  position       = ({d:.2}, {d:.2})\n", .{ raw_mouse.x, raw_mouse.y });
    try writer.print("  delta          = ({d:.2}, {d:.2})\n", .{ mouse.delta().x, mouse.delta().y });
    try writer.print("  scroll         = ({d:.2}, {d:.2})\n", .{ mouse.scrollDelta().x, mouse.scrollDelta().y });
    try writer.print("  left down      = {any}\n", .{mouse.down(.mouse_left)});
    try writer.print("  right pressed  = {any}\n", .{mouse.pressed(.mouse_right)});

    try writer.writeAll("\ngamepad slot 0\n");
    try writer.print("  connected      = {any}\n", .{gamepad.view.connected});
    try writer.print("  south down     = {any}\n", .{gamepad.down(.gamepad_face_south)});
    try writer.print("  dpad up        = {any}\n", .{gamepad.down(.gamepad_dpad_up)});
    try writer.print("  left stick     = ({d:.2}, {d:.2})\n", .{ gamepad.leftStick().x, gamepad.leftStick().y });
    try writer.print("  right stick    = ({d:.2}, {d:.2})\n", .{ gamepad.rightStick().x, gamepad.rightStick().y });
    try writer.print("  left trigger   = {d:.2}\n", .{gamepad.leftTrigger()});
    try writer.print("  right trigger  = {d:.2}\n", .{gamepad.rightTrigger()});
}

pub fn main(init: std.process.Init) !void {
    const config = try parseConfig(init.minimal.args);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const writer = &stdout.interface;

    var state = input.InputSystem{};
    var frame_count: usize = 0;

    while (true) {
        try state.keyboard().update();
        try state.mouse().update();
        if (state.gamepad(0)) |gamepad| try gamepad.update();

        try render(writer, &state, config.frame_limit);
        try writer.flush();

        frame_count += 1;
        if (config.frame_limit) |limit| {
            if (frame_count >= limit) return;
        }

        try init.io.sleep(std.Io.Duration.fromNanoseconds(frame_time_ns), .awake);
    }
}
