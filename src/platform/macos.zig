const device = @import("../device.zig");

const c = @cImport({
    @cInclude("ApplicationServices/ApplicationServices.h");
    @cInclude("Carbon/Carbon.h");
});

fn mapMacKeycode(keycode: usize) ?device.InputCode {
    return switch (keycode) {
        c.kVK_ANSI_A => .key_a,
        c.kVK_ANSI_B => .key_b,
        c.kVK_ANSI_C => .key_c,
        c.kVK_ANSI_D => .key_d,
        c.kVK_ANSI_E => .key_e,
        c.kVK_ANSI_F => .key_f,
        c.kVK_ANSI_G => .key_g,
        c.kVK_ANSI_H => .key_h,
        c.kVK_ANSI_I => .key_i,
        c.kVK_ANSI_J => .key_j,
        c.kVK_ANSI_K => .key_k,
        c.kVK_ANSI_L => .key_l,
        c.kVK_ANSI_M => .key_m,
        c.kVK_ANSI_N => .key_n,
        c.kVK_ANSI_O => .key_o,
        c.kVK_ANSI_P => .key_p,
        c.kVK_ANSI_Q => .key_q,
        c.kVK_ANSI_R => .key_r,
        c.kVK_ANSI_S => .key_s,
        c.kVK_ANSI_T => .key_t,
        c.kVK_ANSI_U => .key_u,
        c.kVK_ANSI_V => .key_v,
        c.kVK_ANSI_W => .key_w,
        c.kVK_ANSI_X => .key_x,
        c.kVK_ANSI_Y => .key_y,
        c.kVK_ANSI_Z => .key_z,
        c.kVK_ANSI_0 => .key_0,
        c.kVK_ANSI_1 => .key_1,
        c.kVK_ANSI_2 => .key_2,
        c.kVK_ANSI_3 => .key_3,
        c.kVK_ANSI_4 => .key_4,
        c.kVK_ANSI_5 => .key_5,
        c.kVK_ANSI_6 => .key_6,
        c.kVK_ANSI_7 => .key_7,
        c.kVK_ANSI_8 => .key_8,
        c.kVK_ANSI_9 => .key_9,
        c.kVK_Return => .key_enter,
        c.kVK_Tab => .key_tab,
        c.kVK_Space => .key_space,
        c.kVK_Delete => .key_backspace,
        c.kVK_Escape => .key_escape,
        c.kVK_Home => .key_home,
        c.kVK_End => .key_end,
        c.kVK_PageUp => .key_page_up,
        c.kVK_PageDown => .key_page_down,
        c.kVK_LeftArrow => .key_left,
        c.kVK_RightArrow => .key_right,
        c.kVK_UpArrow => .key_up,
        c.kVK_DownArrow => .key_down,
        c.kVK_Shift => .key_shift_left,
        c.kVK_RightShift => .key_shift_right,
        c.kVK_Control => .key_control_left,
        c.kVK_RightControl => .key_control_right,
        c.kVK_Option => .key_alt_left,
        c.kVK_RightOption => .key_alt_right,
        c.kVK_Command => .key_super_left,
        c.kVK_RightCommand => .key_super_right,
        c.kVK_F1 => .key_f1,
        c.kVK_F2 => .key_f2,
        c.kVK_F3 => .key_f3,
        c.kVK_F4 => .key_f4,
        c.kVK_F5 => .key_f5,
        c.kVK_F6 => .key_f6,
        c.kVK_F7 => .key_f7,
        c.kVK_F8 => .key_f8,
        c.kVK_F9 => .key_f9,
        c.kVK_F10 => .key_f10,
        c.kVK_F11 => .key_f11,
        c.kVK_F12 => .key_f12,
        c.kVK_Help => .key_insert,
        c.kVK_ForwardDelete => .key_delete,
        else => null,
    };
}

pub fn updateKeyboard(keyboard: *device.KeyboardDevice) !void {
    @memset(keyboard.keys[0..], .up);

    var keycode: usize = 0;
    while (keycode < 128) : (keycode += 1) {
        const down = c.CGEventSourceKeyState(c.kCGEventSourceStateCombinedSessionState, @intCast(keycode));
        if (down == 0) continue;

        const code = mapMacKeycode(keycode) orelse continue;
        const idx: usize = @intFromEnum(code);
        if (idx < device.max_keys) {
            keyboard.keys[idx] = .down;
        }
    }
}

pub fn updateMouse(mouse: *device.MouseDevice) !void {
    const event = c.CGEventCreate(null);
    if (event == null) return error.EventCreateFailed;
    defer c.CFRelease(event);

    const point = c.CGEventGetLocation(event);
    mouse.setRawPosition(.{
        .x = @floatCast(point.x),
        .y = @floatCast(point.y),
    }, .global);

    @memset(mouse.buttons[0..], .up);

    var button_index: usize = 0;
    while (button_index < device.max_mouse_buttons) : (button_index += 1) {
        const down = c.CGEventSourceButtonState(c.kCGEventSourceStateCombinedSessionState, @intCast(button_index));
        mouse.buttons[button_index] = if (down != 0) .down else .up;
    }
}

pub fn updateGamepad(gamepad: *device.GamepadDevice) !void {
    gamepad.view.connected = false;
    gamepad.clearState();
}
