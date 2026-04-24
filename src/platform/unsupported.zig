const device = @import("../device.zig");

pub fn updateKeyboard(_: *device.KeyboardDevice) !void {
    return error.UnsupportedPlatform;
}

pub fn updateMouse(_: *device.MouseDevice) !void {
    return error.UnsupportedPlatform;
}
