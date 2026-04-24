const builtin = @import("builtin");
const device = @import("../device.zig");

const windows = @import("windows.zig");
const linux = @import("linux.zig");
const macos = @import("macos.zig");
const unsupported = @import("unsupported.zig");

pub const BackendChoice = enum {
    auto,
    x11,
    wayland,
};

pub fn updateKeyboard(keyboard: *device.KeyboardDevice, choice: BackendChoice) !void {
    switch (builtin.os.tag) {
        .windows => try windows.updateKeyboard(keyboard),
        .linux => try linux.updateKeyboard(keyboard, choice),
        .macos => try macos.updateKeyboard(keyboard),
        else => try unsupported.updateKeyboard(keyboard),
    }
}

pub fn updateMouse(mouse: *device.MouseDevice, choice: BackendChoice) !void {
    switch (builtin.os.tag) {
        .windows => try windows.updateMouse(mouse),
        .linux => try linux.updateMouse(mouse, choice),
        .macos => try macos.updateMouse(mouse),
        else => try unsupported.updateMouse(mouse),
    }
}
