const std = @import("std");
const input_lib = @import("input");

const frame_time_ns = 100 * std.time.ns_per_ms;

const Config = struct {
    frame_limit: ?usize = null,
};

const PlayerInput = struct {
    move: input_lib.Axis2d,
    jump_pressed: bool,
    fire_down: bool,
    aim_down: bool,
    pause_pressed: bool,
    look_stick: input_lib.Axis2d,
    look_mouse: input_lib.Axis2d,
};

fn setupPlayerActions(input: *input_lib.InputSystem, actions: *input_lib.ActionMap) !void {
    const gamepad = input.gamepad(0) orelse unreachable;

    try actions.attachDevices(input, .{
        .keyboard = true,
        .mouse = true,
        .gamepad_slot = 0,
    });

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
    try actions.set("fire", &.{
        .{ .code = .mouse_left },
        .{ .code = .gamepad_right_trigger, .activation_threshold = 0.1 },
    });
    try actions.set("aim", &.{
        .{ .code = .mouse_right },
        .{ .code = .gamepad_left_trigger, .activation_threshold = 0.1 },
    });
    try actions.set("pause", &.{
        .{ .code = .key_escape },
        .{ .code = .gamepad_start },
    });
    try actions.set("look", &.{.{ .code = .gamepad_right_stick }});

    try gamepad.setDeadzone(.gamepad_left_stick, 0.05);
    try gamepad.setDeadzone(.gamepad_right_stick, 0.05);
}

fn samplePlayerInput(input: *input_lib.InputSystem, actions: *const input_lib.ActionMap) PlayerInput {
    return .{
        .move = actions.axis2d(input, "move"),
        .jump_pressed = actions.pressed(input, "jump"),
        .fire_down = actions.down(input, "fire"),
        .aim_down = actions.down(input, "aim"),
        .pause_pressed = actions.pressed(input, "pause"),
        .look_stick = actions.axis2d(input, "look"),
        .look_mouse = input.mouse().delta(),
    };
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

fn render(writer: *std.Io.Writer, player_input: PlayerInput, frame_limit: ?usize) !void {
    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.writeAll("player action map example\n");
    if (frame_limit) |limit| {
        try writer.print("frame limit: {d}\n\n", .{limit});
    } else {
        try writer.writeAll("frame limit: none\n");
        try writer.writeAll("ctrl+c to exit\n\n");
    }

    try writer.print("move        = ({d:.2}, {d:.2})\n", .{ player_input.move.x, player_input.move.y });
    try writer.print("look_stick  = ({d:.2}, {d:.2})\n", .{ player_input.look_stick.x, player_input.look_stick.y });
    try writer.print("look_mouse  = ({d:.2}, {d:.2})\n", .{ player_input.look_mouse.x, player_input.look_mouse.y });
    try writer.print("jump_pressed= {any}\n", .{player_input.jump_pressed});
    try writer.print("fire_down   = {any}\n", .{player_input.fire_down});
    try writer.print("aim_down    = {any}\n", .{player_input.aim_down});
    try writer.print("pause_press = {any}\n", .{player_input.pause_pressed});
}

pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    runMain(@intCast(argc), argv) catch |err| {
        std.debug.print("player-action-map failed with {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn runMain(argc: usize, argv: [*][*:0]u8) !void {
    const config = try parseConfigArgv(argv[0..argc]);
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var stdout_buffer: [2048]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
    const writer = &stdout.interface;

    var input = input_lib.InputSystem{};
    var actions = input_lib.ActionMap.init();
    try setupPlayerActions(&input, &actions);

    var frame_count: usize = 0;
    while (true) {
        try input.keyboard().update();
        try input.mouse().update();
        if (input.gamepad(0)) |pad| try pad.update();

        const player_input = samplePlayerInput(&input, &actions);
        try render(writer, player_input, config.frame_limit);
        try writer.flush();

        frame_count += 1;
        if (config.frame_limit) |limit| {
            if (frame_count >= limit) return;
        }

        try io.sleep(std.Io.Duration.fromNanoseconds(frame_time_ns), .awake);
    }
}
