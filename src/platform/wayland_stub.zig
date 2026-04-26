const std = @import("std");

pub const FocusState = struct {
    keyboard: bool,
    pointer: bool,
};

pub fn run(_: std.process.Init) !void {
    std.debug.print("Wayland is not available on this platform\n", .{});
    return;
}

pub fn runFocusedInput(
    comptime Context: type,
    _: *Context,
    _: ?usize,
    _: std.Io,
    comptime _: fn (*Context, anytype, FocusState, *std.Io.Writer, ?usize) anyerror!void,
) !void {
    @compileError("Wayland is not available on this platform");
}
