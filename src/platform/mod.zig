const builtin = @import("builtin");
const device = @import("../device.zig");

const platform = switch (builtin.os.tag) {
    .windows => @import("windows.zig"),
    .linux => @import("linux.zig"),
    .macos => @import("macos.zig"),
    else => @import("unsupported.zig"),
};

pub const Backend = enum {
    x11,
    wayland,
    none,
};

pub fn selectedBackend() Backend {
    return switch (builtin.os.tag) {
        .linux => platform.selectedBackend(),
        else => .none,
    };
}

pub fn updateKeyboard(keyboard: *device.KeyboardDevice) !void {
    try platform.updateKeyboard(keyboard);
}

pub fn updateMouse(mouse: *device.MouseDevice) !void {
    try platform.updateMouse(mouse);
}

pub fn updateGamepad(gamepad: *device.GamepadDevice) !void {
    try platform.updateGamepad(gamepad);
}
