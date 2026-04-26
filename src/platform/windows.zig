const device = @import("../device.zig");

const c = @import("c");

const mouse_vks = [_]c_int{ c.VK_LBUTTON, c.VK_RBUTTON, c.VK_MBUTTON, c.VK_XBUTTON1, c.VK_XBUTTON2 };

fn isVirtualKeyDown(vk: c_int) bool {
    return c.GetAsyncKeyState(vk) < 0;
}

fn mapVirtualKey(vk: usize) ?device.InputCode {
    return switch (vk) {
        c.VK_BACK => .key_backspace,
        c.VK_TAB => .key_tab,
        c.VK_RETURN => .key_enter,
        c.VK_PAUSE => .key_pause,
        c.VK_CAPITAL => .key_caps_lock,
        c.VK_ESCAPE => .key_escape,
        c.VK_SPACE => .key_space,
        c.VK_PRIOR => .key_page_up,
        c.VK_NEXT => .key_page_down,
        c.VK_END => .key_end,
        c.VK_HOME => .key_home,
        c.VK_LEFT => .key_left,
        c.VK_UP => .key_up,
        c.VK_RIGHT => .key_right,
        c.VK_DOWN => .key_down,
        c.VK_SNAPSHOT => .key_print_screen,
        c.VK_INSERT => .key_insert,
        c.VK_DELETE => .key_delete,
        c.VK_LWIN => .key_super_left,
        c.VK_RWIN => .key_super_right,
        c.VK_APPS => .key_menu,
        c.VK_NUMLOCK => .key_num_lock,
        c.VK_SCROLL => .key_scroll_lock,
        c.VK_LSHIFT => .key_shift_left,
        c.VK_RSHIFT => .key_shift_right,
        c.VK_LCONTROL => .key_control_left,
        c.VK_RCONTROL => .key_control_right,
        c.VK_LMENU => .key_alt_left,
        c.VK_RMENU => .key_alt_right,
        c.VK_F1 => .key_f1,
        c.VK_F2 => .key_f2,
        c.VK_F3 => .key_f3,
        c.VK_F4 => .key_f4,
        c.VK_F5 => .key_f5,
        c.VK_F6 => .key_f6,
        c.VK_F7 => .key_f7,
        c.VK_F8 => .key_f8,
        c.VK_F9 => .key_f9,
        c.VK_F10 => .key_f10,
        c.VK_F11 => .key_f11,
        c.VK_F12 => .key_f12,
        c.VK_F13 => .key_f13,
        c.VK_F14 => .key_f14,
        c.VK_F15 => .key_f15,
        c.VK_F16 => .key_f16,
        c.VK_F17 => .key_f17,
        c.VK_F18 => .key_f18,
        c.VK_F19 => .key_f19,
        c.VK_F20 => .key_f20,
        c.VK_F21 => .key_f21,
        c.VK_F22 => .key_f22,
        c.VK_F23 => .key_f23,
        c.VK_F24 => .key_f24,
        c.VK_NUMPAD0 => .key_numpad_0,
        c.VK_NUMPAD1 => .key_numpad_1,
        c.VK_NUMPAD2 => .key_numpad_2,
        c.VK_NUMPAD3 => .key_numpad_3,
        c.VK_NUMPAD4 => .key_numpad_4,
        c.VK_NUMPAD5 => .key_numpad_5,
        c.VK_NUMPAD6 => .key_numpad_6,
        c.VK_NUMPAD7 => .key_numpad_7,
        c.VK_NUMPAD8 => .key_numpad_8,
        c.VK_NUMPAD9 => .key_numpad_9,
        c.VK_MULTIPLY => .key_numpad_multiply,
        c.VK_ADD => .key_numpad_add,
        c.VK_SUBTRACT => .key_numpad_subtract,
        c.VK_DECIMAL => .key_numpad_decimal,
        c.VK_DIVIDE => .key_numpad_divide,
        '0' => .key_0,
        '1' => .key_1,
        '2' => .key_2,
        '3' => .key_3,
        '4' => .key_4,
        '5' => .key_5,
        '6' => .key_6,
        '7' => .key_7,
        '8' => .key_8,
        '9' => .key_9,
        'A' => .key_a,
        'B' => .key_b,
        'C' => .key_c,
        'D' => .key_d,
        'E' => .key_e,
        'F' => .key_f,
        'G' => .key_g,
        'H' => .key_h,
        'I' => .key_i,
        'J' => .key_j,
        'K' => .key_k,
        'L' => .key_l,
        'M' => .key_m,
        'N' => .key_n,
        'O' => .key_o,
        'P' => .key_p,
        'Q' => .key_q,
        'R' => .key_r,
        'S' => .key_s,
        'T' => .key_t,
        'U' => .key_u,
        'V' => .key_v,
        'W' => .key_w,
        'X' => .key_x,
        'Y' => .key_y,
        'Z' => .key_z,
        else => null,
    };
}

pub fn updateKeyboard(keyboard: *device.KeyboardDevice) !void {
    @memset(keyboard.keys[0..], .up);

    var vk: usize = 0;
    while (vk < 256) : (vk += 1) {
        if (!isVirtualKeyDown(@intCast(vk))) continue;
        const code = mapVirtualKey(vk) orelse continue;
        const idx: usize = @intFromEnum(code);
        if (idx < device.max_keys) {
            keyboard.keys[idx] = .down;
        }
    }
}

pub fn updateMouse(mouse: *device.MouseDevice) !void {
    var point: c.POINT = undefined;
    if (c.GetCursorPos(&point) != 0) {
        mouse.setRawPosition(.{
            .x = @floatFromInt(point.x),
            .y = @floatFromInt(point.y),
        }, .global);
    }

    @memset(mouse.buttons[0..], .up);

    var i: usize = 0;
    while (i < mouse_vks.len and i < device.max_mouse_buttons) : (i += 1) {
        mouse.buttons[i] = if (isVirtualKeyDown(mouse_vks[i])) .down else .up;
    }
}

fn setGamepadButton(gamepad: *device.GamepadDevice, index: usize, down: bool) void {
    gamepad.buttons[index] = if (down) .down else .up;
}

fn normalizeThumb(value: c.SHORT, deadzone: c.SHORT) f32 {
    if (value > -deadzone and value < deadzone) return 0;
    if (value < 0) {
        return @as(f32, @floatFromInt(value)) / 32768.0;
    }
    return @as(f32, @floatFromInt(value)) / 32767.0;
}

fn normalizeTrigger(value: c.BYTE) f32 {
    if (value <= c.XINPUT_GAMEPAD_TRIGGER_THRESHOLD) return 0;
    return @as(f32, @floatFromInt(value)) / 255.0;
}

pub fn updateGamepad(gamepad: *device.GamepadDevice) !void {
    const slot = gamepad.slot() orelse return;
    if (slot >= c.XUSER_MAX_COUNT) return;

    var state: c.XINPUT_STATE = undefined;
    if (c.XInputGetState(@intCast(slot), &state) != c.ERROR_SUCCESS) {
        gamepad.view.connected = false;
        gamepad.clearState();
        return;
    }

    gamepad.view.connected = true;
    gamepad.identity.instance_id = slot;
    gamepad.identity.guid[0] = 'x';
    gamepad.identity.guid[1] = 'i';
    gamepad.identity.guid[2] = 'n';
    gamepad.identity.guid[3] = 'p';
    gamepad.identity.guid[4] = 'u';
    gamepad.identity.guid[5] = 't';
    @memset(gamepad.buttons[0..], .up);

    const buttons = state.Gamepad.wButtons;
    setGamepadButton(gamepad, 0, (buttons & c.XINPUT_GAMEPAD_A) != 0);
    setGamepadButton(gamepad, 1, (buttons & c.XINPUT_GAMEPAD_B) != 0);
    setGamepadButton(gamepad, 2, (buttons & c.XINPUT_GAMEPAD_X) != 0);
    setGamepadButton(gamepad, 3, (buttons & c.XINPUT_GAMEPAD_Y) != 0);
    setGamepadButton(gamepad, 4, (buttons & c.XINPUT_GAMEPAD_DPAD_UP) != 0);
    setGamepadButton(gamepad, 5, (buttons & c.XINPUT_GAMEPAD_DPAD_DOWN) != 0);
    setGamepadButton(gamepad, 6, (buttons & c.XINPUT_GAMEPAD_DPAD_LEFT) != 0);
    setGamepadButton(gamepad, 7, (buttons & c.XINPUT_GAMEPAD_DPAD_RIGHT) != 0);
    setGamepadButton(gamepad, 8, (buttons & c.XINPUT_GAMEPAD_LEFT_SHOULDER) != 0);
    setGamepadButton(gamepad, 9, (buttons & c.XINPUT_GAMEPAD_RIGHT_SHOULDER) != 0);
    setGamepadButton(gamepad, 12, (buttons & c.XINPUT_GAMEPAD_BACK) != 0);
    setGamepadButton(gamepad, 13, (buttons & c.XINPUT_GAMEPAD_START) != 0);
    setGamepadButton(gamepad, 15, (buttons & c.XINPUT_GAMEPAD_LEFT_THUMB) != 0);
    setGamepadButton(gamepad, 16, (buttons & c.XINPUT_GAMEPAD_RIGHT_THUMB) != 0);

    gamepad.left_stick = .{
        .x = normalizeThumb(state.Gamepad.sThumbLX, c.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE),
        .y = normalizeThumb(state.Gamepad.sThumbLY, c.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE),
    };
    gamepad.right_stick = .{
        .x = normalizeThumb(state.Gamepad.sThumbRX, c.XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE),
        .y = normalizeThumb(state.Gamepad.sThumbRY, c.XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE),
    };
    gamepad.left_trigger_value = normalizeTrigger(state.Gamepad.bLeftTrigger);
    gamepad.right_trigger_value = normalizeTrigger(state.Gamepad.bRightTrigger);
}
