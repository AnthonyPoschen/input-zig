const platform = @import("platform/mod.zig");

pub const max_name_len = 32;
pub const max_keys = 256;
pub const max_mouse_buttons = 16;

pub const ButtonState = enum { up, down };

pub const InputCode = enum(u16) {
    // Mouse buttons (interpreted by mouse device)
    mouse_left = 1000,
    mouse_right = 1001,
    mouse_middle = 1002,
    mouse_button4 = 1003,
    mouse_button5 = 1004,
    mouse_button6 = 1005,
    mouse_button7 = 1006,
    mouse_button8 = 1007,
    mouse_button9 = 1008,
    mouse_button10 = 1009,
    mouse_button11 = 1010,
    mouse_button12 = 1011,
    mouse_button13 = 1012,
    mouse_button14 = 1013,
    mouse_button15 = 1014,
    mouse_button16 = 1015,

    // Keyboard keys (layout-level, shift-agnostic)
    key_backspace = 8,
    key_tab = 9,
    key_enter = 13,
    key_pause = 19,
    key_caps_lock = 20,
    key_escape = 27,
    key_space = 32,
    key_page_up = 33,
    key_page_down = 34,
    key_end = 35,
    key_home = 36,
    key_left = 37,
    key_up = 38,
    key_right = 39,
    key_down = 40,
    key_print_screen = 44,
    key_insert = 45,
    key_delete = 46,

    key_0 = 48,
    key_1 = 49,
    key_2 = 50,
    key_3 = 51,
    key_4 = 52,
    key_5 = 53,
    key_6 = 54,
    key_7 = 55,
    key_8 = 56,
    key_9 = 57,

    key_a = 65,
    key_b = 66,
    key_c = 67,
    key_d = 68,
    key_e = 69,
    key_f = 70,
    key_g = 71,
    key_h = 72,
    key_i = 73,
    key_j = 74,
    key_k = 75,
    key_l = 76,
    key_m = 77,
    key_n = 78,
    key_o = 79,
    key_p = 80,
    key_q = 81,
    key_r = 82,
    key_s = 83,
    key_t = 84,
    key_u = 85,
    key_v = 86,
    key_w = 87,
    key_x = 88,
    key_y = 89,
    key_z = 90,

    key_super_left = 91,
    key_super_right = 92,
    key_menu = 93,

    key_numpad_0 = 96,
    key_numpad_1 = 97,
    key_numpad_2 = 98,
    key_numpad_3 = 99,
    key_numpad_4 = 100,
    key_numpad_5 = 101,
    key_numpad_6 = 102,
    key_numpad_7 = 103,
    key_numpad_8 = 104,
    key_numpad_9 = 105,
    key_numpad_multiply = 106,
    key_numpad_add = 107,
    key_numpad_subtract = 109,
    key_numpad_decimal = 110,
    key_numpad_divide = 111,

    key_f1 = 112,
    key_f2 = 113,
    key_f3 = 114,
    key_f4 = 115,
    key_f5 = 116,
    key_f6 = 117,
    key_f7 = 118,
    key_f8 = 119,
    key_f9 = 120,
    key_f10 = 121,
    key_f11 = 122,
    key_f12 = 123,
    key_f13 = 124,
    key_f14 = 125,
    key_f15 = 126,
    key_f16 = 127,
    key_f17 = 128,
    key_f18 = 129,
    key_f19 = 130,
    key_f20 = 131,
    key_f21 = 132,
    key_f22 = 133,
    key_f23 = 134,
    key_f24 = 135,

    key_num_lock = 144,
    key_scroll_lock = 145,

    key_shift_left = 160,
    key_shift_right = 161,
    key_control_left = 162,
    key_control_right = 163,
    key_alt_left = 164,
    key_alt_right = 165,

    // Keep enum open for additional backend-specific values.
    _,
};

pub const DeviceKind = enum {
    keyboard,
    mouse,
    gamepad,
    wheel,
    joystick,
};

pub const DeviceView = struct {
    id: u32,
    kind: DeviceKind,
    connected: bool,
    name: [max_name_len]u8,

    pub fn nameSlice(self: *const DeviceView) []const u8 {
        var end: usize = 0;
        while (end < self.name.len and self.name[end] != 0) : (end += 1) {}
        return self.name[0..end];
    }
};

fn fixedName(comptime text: []const u8) [max_name_len]u8 {
    var out = [_]u8{0} ** max_name_len;
    const count = if (text.len < max_name_len) text.len else max_name_len;
    @memcpy(out[0..count], text[0..count]);
    return out;
}

pub const KeyboardDevice = struct {
    view: DeviceView = .{ .id = 0, .kind = .keyboard, .connected = true, .name = fixedName("keyboard") },
    keys: [max_keys]ButtonState = [_]ButtonState{.up} ** max_keys,
    prev_keys: [max_keys]ButtonState = [_]ButtonState{.up} ** max_keys,

    pub fn update(self: *KeyboardDevice, backend_choice: platform.BackendChoice) !void {
        self.prev_keys = self.keys;
        try platform.updateKeyboard(self, backend_choice);
    }

    pub fn down(self: *const KeyboardDevice, code: InputCode) bool {
        const idx: usize = @intFromEnum(code);
        return idx < max_keys and self.keys[idx] == .down;
    }

    pub fn up(self: *const KeyboardDevice, code: InputCode) bool {
        return !self.down(code);
    }

    pub fn press(self: *const KeyboardDevice, code: InputCode) bool {
        const idx: usize = @intFromEnum(code);
        return idx < max_keys and self.prev_keys[idx] == .up and self.keys[idx] == .down;
    }

    pub fn release(self: *const KeyboardDevice, code: InputCode) bool {
        const idx: usize = @intFromEnum(code);
        return idx < max_keys and self.prev_keys[idx] == .down and self.keys[idx] == .up;
    }
};

fn mouseIndex(code: InputCode) ?usize {
    return switch (code) {
        .mouse_left => 0,
        .mouse_right => 1,
        .mouse_middle => 2,
        .mouse_button4 => 3,
        .mouse_button5 => 4,
        .mouse_button6 => 5,
        .mouse_button7 => 6,
        .mouse_button8 => 7,
        .mouse_button9 => 8,
        .mouse_button10 => 9,
        .mouse_button11 => 10,
        .mouse_button12 => 11,
        .mouse_button13 => 12,
        .mouse_button14 => 13,
        .mouse_button15 => 14,
        .mouse_button16 => 15,
        else => null,
    };
}

pub const MouseDevice = struct {
    view: DeviceView = .{ .id = 1, .kind = .mouse, .connected = true, .name = fixedName("mouse") },
    buttons: [max_mouse_buttons]ButtonState = [_]ButtonState{.up} ** max_mouse_buttons,
    prev_buttons: [max_mouse_buttons]ButtonState = [_]ButtonState{.up} ** max_mouse_buttons,
    x: f32 = 0,
    y: f32 = 0,

    pub fn update(self: *MouseDevice, backend_choice: platform.BackendChoice) !void {
        self.prev_buttons = self.buttons;
        try platform.updateMouse(self, backend_choice);
    }

    pub fn down(self: *const MouseDevice, code: InputCode) bool {
        const idx = mouseIndex(code) orelse return false;
        return self.buttons[idx] == .down;
    }

    pub fn up(self: *const MouseDevice, code: InputCode) bool {
        return !self.down(code);
    }

    pub fn press(self: *const MouseDevice, code: InputCode) bool {
        const idx = mouseIndex(code) orelse return false;
        return self.prev_buttons[idx] == .up and self.buttons[idx] == .down;
    }

    pub fn release(self: *const MouseDevice, code: InputCode) bool {
        const idx = mouseIndex(code) orelse return false;
        return self.prev_buttons[idx] == .down and self.buttons[idx] == .up;
    }
};
