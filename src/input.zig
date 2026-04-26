const std = @import("std");
const device = @import("device.zig");
pub const action_map = @import("action_map.zig");

pub const Axis1d = device.Axis1d;
pub const Axis2d = device.Axis2d;
pub const DeviceKind = device.DeviceKind;
pub const DeviceView = device.DeviceView;
pub const GamepadDevice = device.GamepadDevice;
pub const GamepadIdentity = device.GamepadIdentity;
pub const GamepadStick = device.GamepadStick;
pub const KeyboardDevice = device.KeyboardDevice;
pub const MousePosition = device.MousePosition;
pub const MouseDevice = device.MouseDevice;
pub const WindowRect = device.WindowRect;
pub const InputCode = device.InputCode;
pub const Backend = @import("platform/mod.zig").Backend;
pub const selectedBackend = @import("platform/mod.zig").selectedBackend;
pub const ActionBinding = action_map.ActionBinding;
pub const ActionKind = action_map.ActionKind;
pub const ActionMap = action_map.ActionMap;
pub const Action2dBinding = action_map.Action2dBinding;
pub const AttachOptions = action_map.AttachOptions;
pub const BindingConflict = action_map.BindingConflict;
pub const BindingSlot = action_map.BindingSlot;
pub const inputCodeLabel = device.inputCodeLabel;
pub const inputCodeName = device.inputCodeName;
pub const parseInputCode = device.parseInputCode;

pub const InputSystem = struct {
    keyboard_device: KeyboardDevice = .{},
    mouse_device: MouseDevice = .{},
    gamepad_devices: [device.max_gamepads]GamepadDevice = initGamepads(),

    pub fn keyboard(self: anytype) if (@typeInfo(@TypeOf(self)).pointer.is_const) *const KeyboardDevice else *KeyboardDevice {
        return &self.keyboard_device;
    }

    pub fn mouse(self: anytype) if (@typeInfo(@TypeOf(self)).pointer.is_const) *const MouseDevice else *MouseDevice {
        return &self.mouse_device;
    }

    pub fn gamepad(self: anytype, slot: usize) if (@typeInfo(@TypeOf(self)).pointer.is_const) ?*const GamepadDevice else ?*GamepadDevice {
        if (slot >= self.gamepad_devices.len) return null;
        return &self.gamepad_devices[slot];
    }

    pub fn gamepadCount(self: *const InputSystem) usize {
        var count: usize = 0;
        for (self.gamepad_devices[0..]) |*gamepad_device| {
            if (gamepad_device.view.connected) count += 1;
        }
        return count;
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

        if (kind == .gamepad) {
            for (self.gamepad_devices[0..]) |*gamepad_device| {
                if (!gamepad_device.view.connected) continue;
                if (count >= out.len) break;
                out[count] = gamepad_device.view;
                count += 1;
            }
        }

        return count;
    }
};

fn initGamepads() [device.max_gamepads]GamepadDevice {
    var out: [device.max_gamepads]GamepadDevice = undefined;
    for (out[0..], 0..) |*gamepad_device, slot| {
        gamepad_device.* = GamepadDevice.init(slot);
    }
    return out;
}

test "list devices by kind returns stable order" {
    var input = InputSystem{};
    var out: [4]DeviceView = undefined;

    const count = input.listDevices(.keyboard, out[0..]);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u32, 0), out[0].id);
    try std.testing.expectEqual(DeviceKind.keyboard, out[0].kind);
}

test "gamepad slots are stable and disconnected by default" {
    const input = InputSystem{};

    try std.testing.expectEqual(@as(usize, 0), input.gamepadCount());
    const first = input.gamepad(0) orelse return error.MissingGamepadSlot;
    const second = input.gamepad(1) orelse return error.MissingGamepadSlot;

    try std.testing.expectEqual(@as(u32, device.first_gamepad_id), first.view.id);
    try std.testing.expectEqual(@as(u32, device.first_gamepad_id + 1), second.view.id);
    try std.testing.expectEqual(DeviceKind.gamepad, first.view.kind);
    try std.testing.expect(!first.view.connected);
}

test "list devices omits disconnected gamepad slots" {
    var input = InputSystem{};
    var out: [device.max_gamepads]DeviceView = undefined;

    try std.testing.expectEqual(@as(usize, 0), input.listDevices(.gamepad, out[0..]));

    input.gamepad_devices[1].view.connected = true;
    const count = input.listDevices(.gamepad, out[0..]);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u32, device.first_gamepad_id + 1), out[0].id);
}
