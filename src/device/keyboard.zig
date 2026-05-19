const platform = @import("../platform/mod.zig");
const common = @import("common.zig");
const input_code = @import("input_code.zig");

const Axis1d = common.Axis1d;
const ButtonState = common.ButtonState;
const InputCode = input_code.InputCode;

pub const KeyboardDevice = struct {
    view: common.DeviceView = .{ .id = 0, .kind = .keyboard, .connected = true, .name = common.fixedName("keyboard") },
    keys: [common.max_keys]ButtonState = @splat(.up),
    prev_keys: [common.max_keys]ButtonState = @splat(.up),

    pub fn update(self: *KeyboardDevice) !void {
        self.prev_keys = self.keys;
        try platform.updateKeyboard(self);
    }

    pub fn down(self: *const KeyboardDevice, code: InputCode) bool {
        return keyStateIs(self.keys[0..], code, .down) orelse false;
    }

    pub fn up(self: *const KeyboardDevice, code: InputCode) bool {
        return !self.down(code);
    }

    pub fn pressed(self: *const KeyboardDevice, code: InputCode) bool {
        const previous_up = keyStateIs(self.prev_keys[0..], code, .up) orelse return false;
        const current_down = keyStateIs(self.keys[0..], code, .down) orelse return false;
        return previous_up and current_down;
    }

    pub fn released(self: *const KeyboardDevice, code: InputCode) bool {
        const previous_down = keyStateIs(self.prev_keys[0..], code, .down) orelse return false;
        const current_up = keyStateIs(self.keys[0..], code, .up) orelse return false;
        return previous_down and current_up;
    }

    pub fn axis1d(self: *const KeyboardDevice, code: InputCode) ?Axis1d {
        return if (self.button(code)) |value| @as(f32, if (value) 1 else 0) else null;
    }

    pub fn button(self: *const KeyboardDevice, code: InputCode) ?bool {
        return keyStateIs(self.keys[0..], code, .down);
    }

    pub fn prevButton(self: *const KeyboardDevice, code: InputCode) ?bool {
        return keyStateIs(self.prev_keys[0..], code, .down);
    }
};

fn keyStateIs(keys: []const ButtonState, code: InputCode, state: ButtonState) ?bool {
    const idx: usize = @intFromEnum(code);
    if (idx >= keys.len) return null;
    return keys[idx] == state;
}
