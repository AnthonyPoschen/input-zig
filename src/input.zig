const std = @import("std");
const device = @import("device.zig");
pub const action_map = @import("action_map.zig");

pub const DeviceKind = device.DeviceKind;
pub const DeviceView = device.DeviceView;
pub const KeyboardDevice = device.KeyboardDevice;
pub const MousePosition = device.MousePosition;
pub const MouseDevice = device.MouseDevice;
pub const WindowRect = device.WindowRect;
pub const InputCode = device.InputCode;
pub const BackendChoice = @import("platform/mod.zig").BackendChoice;
pub const selectedBackend = @import("platform/mod.zig").selectedBackend;
pub const ActionMap = action_map.ActionMap;
pub const Binding = action_map.Binding;

pub const InputSystem = struct {
    keyboard_device: KeyboardDevice = .{},
    mouse_device: MouseDevice = .{},

    pub fn update(self: *InputSystem, backend_choice: BackendChoice) !void {
        try self.keyboard_device.update(backend_choice);
        try self.mouse_device.update(backend_choice);
    }

    pub fn keyboard(self: *const InputSystem) *const KeyboardDevice {
        return &self.keyboard_device;
    }

    pub fn mouse(self: *const InputSystem) *const MouseDevice {
        return &self.mouse_device;
    }

    pub fn listDevices(self: *const InputSystem, kind: DeviceKind, out: []DeviceView) usize {
        var count: usize = 0;

        if (kind == .keyboard and count < out.len) {
            out[count] = self.keyboard_device.view;
            count += 1;
        }

        if (kind == .mouse and count < out.len) {
            out[count] = self.mouse_device.view;
            count += 1;
        }

        return count;
    }
};

test "list devices by kind returns stable order" {
    var input = InputSystem{};
    var out: [4]DeviceView = undefined;

    const count = input.listDevices(.keyboard, out[0..]);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u32, 0), out[0].id);
    try std.testing.expectEqual(DeviceKind.keyboard, out[0].kind);
}
