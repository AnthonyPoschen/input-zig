const std = @import("std");
const input = @import("input");
const action_map_json = @import("action_map_json.zig");
const cli_compat = @import("cli_compat");

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
    var runtime = cli_compat.Runtime.init();
    defer runtime.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout = runtime.stdoutWriter(&stdout_buffer);
    const writer = &stdout.interface;

    var actions = input.ActionMap.init();
    try action_map_json.buildDefaultActions(&actions);
    try action_map_json.save(&runtime, action_map_json.file_name, &actions);

    try writer.print("saved {d} actions to {s}\n", .{
        actions.actionCount(),
        action_map_json.file_name,
    });
    try writer.flush();
}
