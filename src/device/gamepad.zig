const platform = @import("../platform/mod.zig");
const common = @import("common.zig");
const input_code = @import("input_code.zig");

const ButtonState = common.ButtonState;
const InputCode = input_code.InputCode;

pub const GamepadStick = common.Axis2d;

pub const GamepadIdentity = struct {
    vendor_id: u16 = 0,
    product_id: u16 = 0,
    instance_id: u64 = 0,
    guid: [16]u8 = [_]u8{0} ** 16,
};

fn gamepadButtonIndex(code: InputCode) ?usize {
    return switch (code) {
        .gamepad_face_south => 0,
        .gamepad_face_east => 1,
        .gamepad_face_west => 2,
        .gamepad_face_north => 3,
        .gamepad_dpad_up => 4,
        .gamepad_dpad_down => 5,
        .gamepad_dpad_left => 6,
        .gamepad_dpad_right => 7,
        .gamepad_left_shoulder => 8,
        .gamepad_right_shoulder => 9,
        .gamepad_left_trigger => 10,
        .gamepad_right_trigger => 11,
        .gamepad_select => 12,
        .gamepad_start => 13,
        .gamepad_home => 14,
        .gamepad_left_stick_press => 15,
        .gamepad_right_stick_press => 16,
        .gamepad_capture => 17,
        else => null,
    };
}

pub const GamepadDevice = struct {
    view: common.DeviceView,
    identity: GamepadIdentity = .{},
    buttons: [common.max_gamepad_buttons]ButtonState = [_]ButtonState{.up} ** common.max_gamepad_buttons,
    prev_buttons: [common.max_gamepad_buttons]ButtonState = [_]ButtonState{.up} ** common.max_gamepad_buttons,
    left_stick: GamepadStick = .{ .x = 0, .y = 0 },
    prev_left_stick: GamepadStick = .{ .x = 0, .y = 0 },
    right_stick: GamepadStick = .{ .x = 0, .y = 0 },
    prev_right_stick: GamepadStick = .{ .x = 0, .y = 0 },
    left_trigger_value: f32 = 0,
    prev_left_trigger_value: f32 = 0,
    right_trigger_value: f32 = 0,
    prev_right_trigger_value: f32 = 0,
    left_stick_deadzone: f32 = 0,
    right_stick_deadzone: f32 = 0,
    left_trigger_deadzone: f32 = 0,
    right_trigger_deadzone: f32 = 0,

    pub fn init(slot_index: usize) GamepadDevice {
        var name = [_]u8{0} ** common.max_name_len;
        const prefix = "gamepad ";
        @memcpy(name[0..prefix.len], prefix);
        if (slot_index < 10) {
            name[prefix.len] = @intCast('0' + slot_index);
        }

        return .{
            .view = .{
                .id = @intCast(common.first_gamepad_id + slot_index),
                .kind = .gamepad,
                .connected = false,
                .name = name,
            },
        };
    }

    pub fn update(self: *GamepadDevice) !void {
        self.prev_buttons = self.buttons;
        self.prev_left_stick = self.left_stick;
        self.prev_right_stick = self.right_stick;
        self.prev_left_trigger_value = self.left_trigger_value;
        self.prev_right_trigger_value = self.right_trigger_value;
        try platform.updateGamepad(self);
    }

    pub fn slot(self: *const GamepadDevice) ?usize {
        if (self.view.id < common.first_gamepad_id) return null;
        const out = self.view.id - common.first_gamepad_id;
        if (out >= common.max_gamepads) return null;
        return @intCast(out);
    }

    pub fn clearState(self: *GamepadDevice) void {
        @memset(self.buttons[0..], .up);
        self.left_stick = .{ .x = 0, .y = 0 };
        self.right_stick = .{ .x = 0, .y = 0 };
        self.left_trigger_value = 0;
        self.right_trigger_value = 0;
    }

    pub fn down(self: *const GamepadDevice, code: InputCode) bool {
        const idx = gamepadButtonIndex(code) orelse return false;
        return self.buttons[idx] == .down;
    }

    pub fn up(self: *const GamepadDevice, code: InputCode) bool {
        return !self.down(code);
    }

    pub fn pressed(self: *const GamepadDevice, code: InputCode) bool {
        const idx = gamepadButtonIndex(code) orelse return false;
        return self.prev_buttons[idx] == .up and self.buttons[idx] == .down;
    }

    pub fn released(self: *const GamepadDevice, code: InputCode) bool {
        const idx = gamepadButtonIndex(code) orelse return false;
        return self.prev_buttons[idx] == .down and self.buttons[idx] == .up;
    }

    pub fn axis1d(self: *const GamepadDevice, code: InputCode) ?f32 {
        return switch (code) {
            .gamepad_left_trigger => applyDeadzone(self.left_trigger_value, self.left_trigger_deadzone),
            .gamepad_right_trigger => applyDeadzone(self.right_trigger_value, self.right_trigger_deadzone),
            .gamepad_left_stick_up => positive(applyDeadzone2d(self.left_stick, self.left_stick_deadzone).y),
            .gamepad_left_stick_down => positive(-applyDeadzone2d(self.left_stick, self.left_stick_deadzone).y),
            .gamepad_left_stick_left => positive(-applyDeadzone2d(self.left_stick, self.left_stick_deadzone).x),
            .gamepad_left_stick_right => positive(applyDeadzone2d(self.left_stick, self.left_stick_deadzone).x),
            .gamepad_right_stick_up => positive(applyDeadzone2d(self.right_stick, self.right_stick_deadzone).y),
            .gamepad_right_stick_down => positive(-applyDeadzone2d(self.right_stick, self.right_stick_deadzone).y),
            .gamepad_right_stick_left => positive(-applyDeadzone2d(self.right_stick, self.right_stick_deadzone).x),
            .gamepad_right_stick_right => positive(applyDeadzone2d(self.right_stick, self.right_stick_deadzone).x),
            else => if (gamepadButtonIndex(code)) |idx| @as(f32, if (self.buttons[idx] == .down) 1 else 0) else null,
        };
    }

    pub fn axis2d(self: *const GamepadDevice, code: InputCode) ?common.Axis2d {
        return switch (code) {
            .gamepad_left_stick => self.leftStick(),
            .gamepad_right_stick => self.rightStick(),
            else => null,
        };
    }

    pub fn button(self: *const GamepadDevice, code: InputCode) ?bool {
        const idx = gamepadButtonIndex(code) orelse return null;
        return self.buttons[idx] == .down;
    }

    pub fn prevButton(self: *const GamepadDevice, code: InputCode) ?bool {
        const idx = gamepadButtonIndex(code) orelse return null;
        return self.prev_buttons[idx] == .down;
    }

    pub fn leftStick(self: *const GamepadDevice) GamepadStick {
        return applyDeadzone2d(self.left_stick, self.left_stick_deadzone);
    }

    pub fn rightStick(self: *const GamepadDevice) GamepadStick {
        return applyDeadzone2d(self.right_stick, self.right_stick_deadzone);
    }

    pub fn leftTrigger(self: *const GamepadDevice) f32 {
        return applyDeadzone(self.left_trigger_value, self.left_trigger_deadzone);
    }

    pub fn rightTrigger(self: *const GamepadDevice) f32 {
        return applyDeadzone(self.right_trigger_value, self.right_trigger_deadzone);
    }

    pub fn prevAxis1d(self: *const GamepadDevice, code: InputCode) ?f32 {
        return switch (code) {
            .gamepad_left_trigger => applyDeadzone(self.prev_left_trigger_value, self.left_trigger_deadzone),
            .gamepad_right_trigger => applyDeadzone(self.prev_right_trigger_value, self.right_trigger_deadzone),
            .gamepad_left_stick_up => positive(applyDeadzone2d(self.prev_left_stick, self.left_stick_deadzone).y),
            .gamepad_left_stick_down => positive(-applyDeadzone2d(self.prev_left_stick, self.left_stick_deadzone).y),
            .gamepad_left_stick_left => positive(-applyDeadzone2d(self.prev_left_stick, self.left_stick_deadzone).x),
            .gamepad_left_stick_right => positive(applyDeadzone2d(self.prev_left_stick, self.left_stick_deadzone).x),
            .gamepad_right_stick_up => positive(applyDeadzone2d(self.prev_right_stick, self.right_stick_deadzone).y),
            .gamepad_right_stick_down => positive(-applyDeadzone2d(self.prev_right_stick, self.right_stick_deadzone).y),
            .gamepad_right_stick_left => positive(-applyDeadzone2d(self.prev_right_stick, self.right_stick_deadzone).x),
            .gamepad_right_stick_right => positive(applyDeadzone2d(self.prev_right_stick, self.right_stick_deadzone).x),
            else => null,
        };
    }

    pub fn setLeftStickDeadzone(self: *GamepadDevice, deadzone: f32) void {
        self.left_stick_deadzone = clamp(deadzone, 0, 1);
    }

    pub fn setRightStickDeadzone(self: *GamepadDevice, deadzone: f32) void {
        self.right_stick_deadzone = clamp(deadzone, 0, 1);
    }

    pub fn setLeftTriggerDeadzone(self: *GamepadDevice, deadzone: f32) void {
        self.left_trigger_deadzone = clamp(deadzone, 0, 1);
    }

    pub fn setRightTriggerDeadzone(self: *GamepadDevice, deadzone: f32) void {
        self.right_trigger_deadzone = clamp(deadzone, 0, 1);
    }

    pub fn setDeadzone(self: *GamepadDevice, code: InputCode, deadzone: f32) !void {
        const value = clamp(deadzone, 0, 1);
        switch (code) {
            .gamepad_left_stick,
            .gamepad_left_stick_up,
            .gamepad_left_stick_down,
            .gamepad_left_stick_left,
            .gamepad_left_stick_right,
            => self.left_stick_deadzone = value,

            .gamepad_right_stick,
            .gamepad_right_stick_up,
            .gamepad_right_stick_down,
            .gamepad_right_stick_left,
            .gamepad_right_stick_right,
            => self.right_stick_deadzone = value,

            .gamepad_left_trigger => self.left_trigger_deadzone = value,
            .gamepad_right_trigger => self.right_trigger_deadzone = value,
            else => return error.NotAxisCode,
        }
    }
};

fn positive(value: f32) f32 {
    return if (value > 0) value else 0;
}

fn clamp(value: f32, min: f32, max: f32) f32 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

fn applyDeadzone(value: f32, deadzone: f32) f32 {
    if (@abs(value) < deadzone) return 0;
    return value;
}

fn applyDeadzone2d(value: GamepadStick, deadzone: f32) GamepadStick {
    return .{
        .x = applyDeadzone(value.x, deadzone),
        .y = applyDeadzone(value.y, deadzone),
    };
}
