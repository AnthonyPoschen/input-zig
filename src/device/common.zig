pub const max_name_len = 32;
pub const max_keys = 256;
pub const max_mouse_buttons = 16;
pub const max_gamepads = 4;
pub const max_gamepad_buttons = 32;
pub const first_gamepad_id = 100;

pub const ButtonState = enum { up, down };

pub const Axis1d = f32;

pub const Axis2d = struct {
    x: f32,
    y: f32,

    /// Convert into a consumer vector with `x` and `y` fields.
    pub fn as(self: Axis2d, comptime T: type) T {
        return .{ .x = self.x, .y = self.y };
    }

    /// Convert into an array for array-based math APIs.
    pub fn array(self: Axis2d) [2]f32 {
        return .{ self.x, self.y };
    }
};

pub const WindowRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
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

pub fn fixedName(comptime text: []const u8) [max_name_len]u8 {
    var out = [_]u8{0} ** max_name_len;
    const count = if (text.len < max_name_len) text.len else max_name_len;
    @memcpy(out[0..count], text[0..count]);
    return out;
}
