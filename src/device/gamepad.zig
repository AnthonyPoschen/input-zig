const platform = @import("../platform/mod.zig");
const common = @import("common.zig");
const input_code = @import("input_code.zig");

const ButtonState = common.ButtonState;
const InputCode = input_code.InputCode;

pub const GamepadStick = struct {
    x: f32,
    y: f32,

    /// Convert into a consumer vector with `x` and `y` fields.
    pub fn as(self: GamepadStick, comptime T: type) T {
        return .{ .x = self.x, .y = self.y };
    }

    /// Convert into an array for array-based math APIs.
    pub fn array(self: GamepadStick) [2]f32 {
        return .{ self.x, self.y };
    }
};

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
    right_stick: GamepadStick = .{ .x = 0, .y = 0 },
    left_trigger_value: f32 = 0,
    right_trigger_value: f32 = 0,

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

    pub fn press(self: *const GamepadDevice, code: InputCode) bool {
        const idx = gamepadButtonIndex(code) orelse return false;
        return self.prev_buttons[idx] == .up and self.buttons[idx] == .down;
    }

    pub fn release(self: *const GamepadDevice, code: InputCode) bool {
        const idx = gamepadButtonIndex(code) orelse return false;
        return self.prev_buttons[idx] == .down and self.buttons[idx] == .up;
    }

    pub fn leftStick(self: *const GamepadDevice) GamepadStick {
        return self.left_stick;
    }

    pub fn rightStick(self: *const GamepadDevice) GamepadStick {
        return self.right_stick;
    }

    pub fn leftTrigger(self: *const GamepadDevice) f32 {
        return self.left_trigger_value;
    }

    pub fn rightTrigger(self: *const GamepadDevice) f32 {
        return self.right_trigger_value;
    }
};
