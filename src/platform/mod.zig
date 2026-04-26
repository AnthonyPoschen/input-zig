const builtin = @import("builtin");
const device = @import("../device.zig");

const windows = if (builtin.os.tag == .windows) @import("windows.zig") else struct {};
const linux = if (builtin.os.tag == .linux) @import("linux.zig") else struct {};
const macos = if (builtin.os.tag == .macos) @import("macos.zig") else struct {};
const unsupported = @import("unsupported.zig");

pub const Backend = enum {
    x11,
    wayland,
    none,
};

pub fn selectedBackend() Backend {
    return switch (builtin.os.tag) {
        .linux => linux.selectedBackend(),
        else => .none,
    };
}

pub fn updateKeyboard(keyboard: *device.KeyboardDevice) !void {
    switch (builtin.os.tag) {
        .windows => try windows.updateKeyboard(keyboard),
        .linux => try linux.updateKeyboard(keyboard),
        .macos => try macos.updateKeyboard(keyboard),
        else => try unsupported.updateKeyboard(keyboard),
    }
}

pub fn updateMouse(mouse: *device.MouseDevice) !void {
    switch (builtin.os.tag) {
        .windows => try windows.updateMouse(mouse),
        .linux => try linux.updateMouse(mouse),
        .macos => try macos.updateMouse(mouse),
        else => try unsupported.updateMouse(mouse),
    }
}

pub fn updateGamepad(gamepad: *device.GamepadDevice) !void {
    switch (builtin.os.tag) {
        .windows => try windows.updateGamepad(gamepad),
        .linux => try linux.updateGamepad(gamepad),
        .macos => try macos.updateGamepad(gamepad),
        else => try unsupported.updateGamepad(gamepad),
    }
}
