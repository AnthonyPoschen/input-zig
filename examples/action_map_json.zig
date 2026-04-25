const std = @import("std");
const input = @import("input");

pub const file_name = "action_bindings.json";

const max_file_size = 64 * 1024;

pub fn buildDefaultActions(actions: *input.ActionMap) !void {
    try actions.set2d("move", .{
        .left = &.{.key_a},
        .right = &.{.key_d},
        .up = &.{.key_w},
        .down = &.{.key_s},
        .vectors = &.{.gamepad_left_stick},
    }, null);
    try actions.set("jump", &.{
        .key_space,
        .gamepad_face_south,
    }, null);
    try actions.set("fire", &.{
        .mouse_left,
        .gamepad_right_trigger,
    }, .{ .axis_button_threshold = 0.1 });
    try actions.set("aim", &.{
        .mouse_right,
        .gamepad_left_trigger,
    }, .{ .axis_button_threshold = 0.1 });
    try actions.set("pause", &.{
        .key_escape,
        .gamepad_start,
    }, null);
    try actions.set("look", &.{.gamepad_right_stick}, null);
}

pub fn attachDefaultDevices(state: *input.InputSystem, actions: *input.ActionMap) !void {
    try actions.attachDevice(state.keyboard());
    try actions.attachDevice(state.mouse());
    if (state.gamepad(0)) |gamepad| try actions.attachDevice(gamepad);
}

pub fn updateDefaultDevices(state: *input.InputSystem) !void {
    try state.keyboard().update();
    try state.mouse().update();
    if (state.gamepad(0)) |gamepad| try gamepad.update();
}

pub fn save(path: []const u8, actions: *const input.ActionMap) !void {
    var bindings: [input.action_map.max_actions]input.ActionBinding = undefined;
    const count = actions.exportBindings(bindings[0..]);

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    const out = &writer.interface;

    try std.json.Stringify.value(bindings[0..count], .{
        .emit_null_optional_fields = false,
    }, out);
    try out.writeByte('\n');
    try out.flush();
}

pub fn load(path: []const u8, allocator: std.mem.Allocator, actions: *input.ActionMap) !bool {
    const contents = std.fs.cwd().readFileAlloc(allocator, path, max_file_size) catch |err| switch (err) {
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

    if (parsed.value.len > input.action_map.max_actions) return error.ActionMapFull;
    try actions.importBindings(parsed.value);
    return true;
}
