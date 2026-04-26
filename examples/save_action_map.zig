const std = @import("std");
const input = @import("input");
const action_map_json = @import("action_map_json.zig");

pub export fn main(argc: c_int, argv: [*][*:0]u8) c_int {
    _ = argc;
    _ = argv;
    runMain() catch |err| {
        std.debug.print("save-action-map failed with {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn runMain() !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
    const writer = &stdout.interface;

    var actions = input.ActionMap.init();
    try action_map_json.buildDefaultActions(&actions);
    try action_map_json.save(io, action_map_json.file_name, &actions);

    try writer.print("saved {d} actions to {s}\n", .{
        actions.actionCount(),
        action_map_json.file_name,
    });
    try writer.flush();
}
