const std = @import("std");
const input = @import("input");
const action_map_json = @import("action_map_json.zig");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    const writer = &stdout.interface;

    var actions = input.ActionMap.init();
    try action_map_json.buildDefaultActions(&actions);
    try action_map_json.save(action_map_json.file_name, &actions);

    try writer.print("saved {d} actions to {s}\n", .{
        actions.actionCount(),
        action_map_json.file_name,
    });
    try writer.flush();
}
