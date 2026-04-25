const device = @import("../device.zig");

const CGPoint = extern struct {
    x: f64,
    y: f64,
};

const MacEventState = extern struct {
    scroll_x: f32,
    scroll_y: f32,
    buttons: [device.max_mouse_buttons]u8,
    key_down: [128]u8,
    has_key_state: u8,
};

const MacGamepadState = extern struct {
    connected: u8,
    name: [device.max_name_len]u8,
    instance_id: u64,
    left_x: f32,
    left_y: f32,
    right_x: f32,
    right_y: f32,
    left_trigger: f32,
    right_trigger: f32,
    buttons: [device.max_gamepad_buttons]u8,
    raw_report_id: u8,
    raw_report_len: u8,
    raw_report: [32]u8,
};

extern fn CFRelease(cf: ?*const anyopaque) void;
extern fn CGEventCreate(source: ?*anyopaque) ?*anyopaque;
extern fn CGEventGetLocation(event: ?*anyopaque) CGPoint;
extern fn CGEventSourceKeyState(state_id: i32, key: u16) bool;
extern fn CGEventSourceButtonState(state_id: i32, button: u32) bool;
extern fn input_zig_macos_poll_events(state: *MacEventState) void;
extern fn input_zig_macos_poll_gamepad(slot: u32, state: *MacGamepadState) u8;

const kCGEventSourceStateCombinedSessionState = 0;

const kVK_ANSI_A = 0x00;
const kVK_ANSI_S = 0x01;
const kVK_ANSI_D = 0x02;
const kVK_ANSI_F = 0x03;
const kVK_ANSI_H = 0x04;
const kVK_ANSI_G = 0x05;
const kVK_ANSI_Z = 0x06;
const kVK_ANSI_X = 0x07;
const kVK_ANSI_C = 0x08;
const kVK_ANSI_V = 0x09;
const kVK_ANSI_B = 0x0B;
const kVK_ANSI_Q = 0x0C;
const kVK_ANSI_W = 0x0D;
const kVK_ANSI_E = 0x0E;
const kVK_ANSI_R = 0x0F;
const kVK_ANSI_Y = 0x10;
const kVK_ANSI_T = 0x11;
const kVK_ANSI_1 = 0x12;
const kVK_ANSI_2 = 0x13;
const kVK_ANSI_3 = 0x14;
const kVK_ANSI_4 = 0x15;
const kVK_ANSI_6 = 0x16;
const kVK_ANSI_5 = 0x17;
const kVK_ANSI_9 = 0x19;
const kVK_ANSI_7 = 0x1A;
const kVK_ANSI_8 = 0x1C;
const kVK_ANSI_0 = 0x1D;
const kVK_ANSI_O = 0x1F;
const kVK_ANSI_U = 0x20;
const kVK_ANSI_I = 0x22;
const kVK_ANSI_P = 0x23;
const kVK_ANSI_L = 0x25;
const kVK_ANSI_J = 0x26;
const kVK_ANSI_K = 0x28;
const kVK_ANSI_N = 0x2D;
const kVK_ANSI_M = 0x2E;
const kVK_Return = 0x24;
const kVK_Tab = 0x30;
const kVK_Space = 0x31;
const kVK_Delete = 0x33;
const kVK_Escape = 0x35;
const kVK_RightCommand = 0x36;
const kVK_Command = 0x37;
const kVK_Shift = 0x38;
const kVK_Option = 0x3A;
const kVK_Control = 0x3B;
const kVK_RightShift = 0x3C;
const kVK_RightOption = 0x3D;
const kVK_RightControl = 0x3E;
const kVK_F5 = 0x60;
const kVK_F6 = 0x61;
const kVK_F7 = 0x62;
const kVK_F3 = 0x63;
const kVK_F8 = 0x64;
const kVK_F9 = 0x65;
const kVK_F11 = 0x67;
const kVK_F10 = 0x6D;
const kVK_F12 = 0x6F;
const kVK_Help = 0x72;
const kVK_Home = 0x73;
const kVK_PageUp = 0x74;
const kVK_ForwardDelete = 0x75;
const kVK_F4 = 0x76;
const kVK_End = 0x77;
const kVK_F2 = 0x78;
const kVK_PageDown = 0x79;
const kVK_F1 = 0x7A;
const kVK_LeftArrow = 0x7B;
const kVK_RightArrow = 0x7C;
const kVK_DownArrow = 0x7D;
const kVK_UpArrow = 0x7E;

fn setKey(keyboard: *device.KeyboardDevice, code: device.InputCode, down: bool) void {
    const idx: usize = @intFromEnum(code);
    if (idx < device.max_keys) {
        keyboard.keys[idx] = if (down) .down else .up;
    }
}

fn mapMacModifierKeycode(keycode: usize) ?device.InputCode {
    return switch (keycode) {
        kVK_Shift => .key_shift_left,
        kVK_RightShift => .key_shift_right,
        kVK_Control => .key_control_left,
        kVK_RightControl => .key_control_right,
        kVK_Option => .key_alt_left,
        kVK_RightOption => .key_alt_right,
        kVK_Command => .key_super_left,
        kVK_RightCommand => .key_super_right,
        else => null,
    };
}

fn mapMacKeycode(keycode: usize) ?device.InputCode {
    return switch (keycode) {
        kVK_ANSI_A => .key_a,
        kVK_ANSI_B => .key_b,
        kVK_ANSI_C => .key_c,
        kVK_ANSI_D => .key_d,
        kVK_ANSI_E => .key_e,
        kVK_ANSI_F => .key_f,
        kVK_ANSI_G => .key_g,
        kVK_ANSI_H => .key_h,
        kVK_ANSI_I => .key_i,
        kVK_ANSI_J => .key_j,
        kVK_ANSI_K => .key_k,
        kVK_ANSI_L => .key_l,
        kVK_ANSI_M => .key_m,
        kVK_ANSI_N => .key_n,
        kVK_ANSI_O => .key_o,
        kVK_ANSI_P => .key_p,
        kVK_ANSI_Q => .key_q,
        kVK_ANSI_R => .key_r,
        kVK_ANSI_S => .key_s,
        kVK_ANSI_T => .key_t,
        kVK_ANSI_U => .key_u,
        kVK_ANSI_V => .key_v,
        kVK_ANSI_W => .key_w,
        kVK_ANSI_X => .key_x,
        kVK_ANSI_Y => .key_y,
        kVK_ANSI_Z => .key_z,
        kVK_ANSI_0 => .key_0,
        kVK_ANSI_1 => .key_1,
        kVK_ANSI_2 => .key_2,
        kVK_ANSI_3 => .key_3,
        kVK_ANSI_4 => .key_4,
        kVK_ANSI_5 => .key_5,
        kVK_ANSI_6 => .key_6,
        kVK_ANSI_7 => .key_7,
        kVK_ANSI_8 => .key_8,
        kVK_ANSI_9 => .key_9,
        kVK_Return => .key_enter,
        kVK_Tab => .key_tab,
        kVK_Space => .key_space,
        kVK_Delete => .key_backspace,
        kVK_Escape => .key_escape,
        kVK_Home => .key_home,
        kVK_End => .key_end,
        kVK_PageUp => .key_page_up,
        kVK_PageDown => .key_page_down,
        kVK_LeftArrow => .key_left,
        kVK_RightArrow => .key_right,
        kVK_UpArrow => .key_up,
        kVK_DownArrow => .key_down,
        kVK_Shift => .key_shift_left,
        kVK_RightShift => .key_shift_right,
        kVK_Control => .key_control_left,
        kVK_RightControl => .key_control_right,
        kVK_Option => .key_alt_left,
        kVK_RightOption => .key_alt_right,
        kVK_Command => .key_super_left,
        kVK_RightCommand => .key_super_right,
        kVK_F1 => .key_f1,
        kVK_F2 => .key_f2,
        kVK_F3 => .key_f3,
        kVK_F4 => .key_f4,
        kVK_F5 => .key_f5,
        kVK_F6 => .key_f6,
        kVK_F7 => .key_f7,
        kVK_F8 => .key_f8,
        kVK_F9 => .key_f9,
        kVK_F10 => .key_f10,
        kVK_F11 => .key_f11,
        kVK_F12 => .key_f12,
        kVK_Help => .key_insert,
        kVK_ForwardDelete => .key_delete,
        else => null,
    };
}

pub fn updateKeyboard(keyboard: *device.KeyboardDevice) !void {
    @memset(keyboard.keys[0..], .up);

    var keycode: usize = 0;
    while (keycode < 128) : (keycode += 1) {
        const down = CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, @intCast(keycode));
        if (!down) continue;

        const code = mapMacKeycode(keycode) orelse continue;
        setKey(keyboard, code, true);
    }

    var events: MacEventState = undefined;
    input_zig_macos_poll_events(&events);
    if (events.has_key_state != 0) {
        setKey(keyboard, .key_shift_left, false);
        setKey(keyboard, .key_shift_right, false);
        setKey(keyboard, .key_control_left, false);
        setKey(keyboard, .key_control_right, false);
        setKey(keyboard, .key_alt_left, false);
        setKey(keyboard, .key_alt_right, false);
        setKey(keyboard, .key_super_left, false);
        setKey(keyboard, .key_super_right, false);

        keycode = 0;
        while (keycode < events.key_down.len) : (keycode += 1) {
            const code = mapMacModifierKeycode(keycode) orelse continue;
            setKey(keyboard, code, events.key_down[keycode] != 0);
        }
    }
}

pub fn updateMouse(mouse: *device.MouseDevice) !void {
    const event = CGEventCreate(null);
    if (event == null) return error.EventCreateFailed;
    defer CFRelease(event);

    const point = CGEventGetLocation(event);
    mouse.setRawPosition(.{
        .x = @floatCast(point.x),
        .y = @floatCast(point.y),
    }, .global);

    @memset(mouse.buttons[0..], .up);

    var button_index: usize = 0;
    while (button_index < 3 and button_index < device.max_mouse_buttons) : (button_index += 1) {
        const down = CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, @intCast(button_index));
        mouse.buttons[button_index] = if (down) .down else .up;
    }

    var events: MacEventState = undefined;
    input_zig_macos_poll_events(&events);
    mouse.addScrollDelta(.{ .x = events.scroll_x, .y = events.scroll_y });

    button_index = 3;
    while (button_index < device.max_mouse_buttons) : (button_index += 1) {
        mouse.buttons[button_index] = if (events.buttons[button_index] != 0) .down else .up;
    }
}

pub fn updateGamepad(gamepad: *device.GamepadDevice) !void {
    const slot = gamepad.slot() orelse return;

    var state: MacGamepadState = undefined;
    if (input_zig_macos_poll_gamepad(@intCast(slot), &state) == 0 or state.connected == 0) {
        gamepad.view.connected = false;
        gamepad.clearState();
        return;
    }

    gamepad.view.connected = true;
    gamepad.view.name = state.name;
    gamepad.identity.instance_id = state.instance_id;
    gamepad.identity.guid[0] = 'g';
    gamepad.identity.guid[1] = 'c';
    if (slot < 10) {
        gamepad.identity.guid[2] = @intCast('0' + slot);
    }

    @memset(gamepad.buttons[0..], .up);
    var button_index: usize = 0;
    while (button_index < device.max_gamepad_buttons) : (button_index += 1) {
        gamepad.buttons[button_index] = if (state.buttons[button_index] != 0) .down else .up;
    }

    gamepad.left_stick = .{ .x = state.left_x, .y = state.left_y };
    gamepad.right_stick = .{ .x = state.right_x, .y = state.right_y };
    gamepad.left_trigger_value = state.left_trigger;
    gamepad.right_trigger_value = state.right_trigger;
    gamepad.debug_report_id = state.raw_report_id;
    gamepad.debug_report_len = state.raw_report_len;
    gamepad.debug_report = state.raw_report;
}
