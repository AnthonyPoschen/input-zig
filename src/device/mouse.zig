const platform = @import("../platform/mod.zig");
const common = @import("common.zig");
const input_code = @import("input_code.zig");

const ButtonState = common.ButtonState;
const InputCode = input_code.InputCode;
const WindowRect = common.WindowRect;

pub const MousePosition = struct {
    x: f32,
    y: f32,

    /// Convert into a consumer vector with `x` and `y` fields.
    pub fn as(self: MousePosition, comptime T: type) T {
        return .{ .x = self.x, .y = self.y };
    }

    /// Convert into an array for array-based math APIs.
    pub fn array(self: MousePosition) [2]f32 {
        return .{ self.x, self.y };
    }
};

pub const MouseCoordinateSpace = enum {
    global,
    window_local,
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
    view: common.DeviceView = .{ .id = 1, .kind = .mouse, .connected = true, .name = common.fixedName("mouse") },
    buttons: [common.max_mouse_buttons]ButtonState = [_]ButtonState{.up} ** common.max_mouse_buttons,
    prev_buttons: [common.max_mouse_buttons]ButtonState = [_]ButtonState{.up} ** common.max_mouse_buttons,
    raw_position: MousePosition = .{ .x = 0, .y = 0 },
    coordinate_space: MouseCoordinateSpace = .global,

    /// Refresh the raw mouse state from the selected platform backend.
    pub fn update(self: *MouseDevice) !void {
        self.prev_buttons = self.buttons;
        try platform.updateMouse(self);
    }

    /// Return whether the requested mouse button is currently held down.
    pub fn down(self: *const MouseDevice, code: InputCode) bool {
        const idx = mouseIndex(code) orelse return false;
        return self.buttons[idx] == .down;
    }

    /// Return whether the requested mouse button is currently up.
    pub fn up(self: *const MouseDevice, code: InputCode) bool {
        return !self.down(code);
    }

    /// Return whether the button transitioned to down this update.
    pub fn pressed(self: *const MouseDevice, code: InputCode) bool {
        const idx = mouseIndex(code) orelse return false;
        return self.prev_buttons[idx] == .up and self.buttons[idx] == .down;
    }

    /// Return whether the button transitioned to up this update.
    pub fn released(self: *const MouseDevice, code: InputCode) bool {
        const idx = mouseIndex(code) orelse return false;
        return self.prev_buttons[idx] == .down and self.buttons[idx] == .up;
    }

    pub fn axis1d(self: *const MouseDevice, code: InputCode) ?f32 {
        return if (self.button(code)) |value| @as(f32, if (value) 1 else 0) else null;
    }

    pub fn button(self: *const MouseDevice, code: InputCode) ?bool {
        const idx = mouseIndex(code) orelse return null;
        return self.buttons[idx] == .down;
    }

    pub fn prevButton(self: *const MouseDevice, code: InputCode) ?bool {
        const idx = mouseIndex(code) orelse return null;
        return self.prev_buttons[idx] == .down;
    }

    /// Return raw or window-relative mouse coordinates.
    pub fn position(self: *const MouseDevice, window_rect: ?*const WindowRect) MousePosition {
        if (window_rect) |rect| {
            if (self.coordinate_space == .global) {
                return .{
                    .x = self.raw_position.x - rect.x,
                    .y = self.raw_position.y - rect.y,
                };
            }
        }

        return self.raw_position;
    }
};
