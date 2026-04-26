const std = @import("std");
const input = @import("input");
const cli_compat = @import("cli_compat");

pub const file_name = "action_bindings.json";

const max_file_size = 64 * 1024;

pub fn buildDefaultActions(actions: *input.ActionMap) !void {
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
}

pub fn attachDefaultDevices(state: *input.InputSystem, actions: *input.ActionMap) !void {
    try actions.attachDevices(state, .{
        .keyboard = true,
        .mouse = true,
        .gamepad_slot = 0,
    });
}

pub fn updateDefaultDevices(state: *input.InputSystem) !void {
    try state.keyboard().update();
    try state.mouse().update();
    if (state.gamepad(0)) |gamepad| try gamepad.update();
}

pub fn save(runtime: *cli_compat.Runtime, path: []const u8, actions: *const input.ActionMap) !void {
    const bindings = actions.snapshot();

    const file = try runtime.createFile(path);
    defer runtime.closeFile(file);

    var buffer: [4096]u8 = undefined;
    var writer = runtime.fileWriter(file, &buffer);
    const out = &writer.interface;

    try std.json.Stringify.value(bindings.slice(), .{
        .emit_null_optional_fields = false,
    }, out);
    try out.writeByte('\n');
    try out.flush();
}

pub fn load(runtime: *cli_compat.Runtime, path: []const u8, allocator: std.mem.Allocator, actions: *input.ActionMap) !bool {
    const contents = runtime.readFileAlloc(
        allocator,
        path,
        max_file_size,
    ) catch |err| switch (err) {
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

    if (parsed.value.len > input.max_actions) return error.ActionMapFull;
    try actions.importBindings(parsed.value);
    return true;
}
