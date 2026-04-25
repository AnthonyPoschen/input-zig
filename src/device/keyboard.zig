const platform = @import("../platform/mod.zig");
const common = @import("common.zig");
const input_code = @import("input_code.zig");

const ButtonState = common.ButtonState;
const InputCode = input_code.InputCode;

pub const KeyboardDevice = struct {
    view: common.DeviceView = .{ .id = 0, .kind = .keyboard, .connected = true, .name = common.fixedName("keyboard") },
    keys: [common.max_keys]ButtonState = [_]ButtonState{.up} ** common.max_keys,
    prev_keys: [common.max_keys]ButtonState = [_]ButtonState{.up} ** common.max_keys,

    pub fn update(self: *KeyboardDevice) !void {
        self.prev_keys = self.keys;
        try platform.updateKeyboard(self);
    }

    pub fn down(self: *const KeyboardDevice, code: InputCode) bool {
        const idx: usize = @intFromEnum(code);
        return idx < common.max_keys and self.keys[idx] == .down;
    }

    pub fn up(self: *const KeyboardDevice, code: InputCode) bool {
        return !self.down(code);
    }

    pub fn pressed(self: *const KeyboardDevice, code: InputCode) bool {
        const idx: usize = @intFromEnum(code);
        return idx < common.max_keys and self.prev_keys[idx] == .up and self.keys[idx] == .down;
    }

    pub fn released(self: *const KeyboardDevice, code: InputCode) bool {
        const idx: usize = @intFromEnum(code);
        return idx < common.max_keys and self.prev_keys[idx] == .down and self.keys[idx] == .up;
    }

    pub fn axis1d(self: *const KeyboardDevice, code: InputCode) ?f32 {
        return if (self.button(code)) |value| @as(f32, if (value) 1 else 0) else null;
    }

    pub fn button(self: *const KeyboardDevice, code: InputCode) ?bool {
        const idx: usize = @intFromEnum(code);
        if (idx >= common.max_keys) return null;
        return self.keys[idx] == .down;
    }

    pub fn prevButton(self: *const KeyboardDevice, code: InputCode) ?bool {
        const idx: usize = @intFromEnum(code);
        if (idx >= common.max_keys) return null;
        return self.prev_keys[idx] == .down;
    }
};
