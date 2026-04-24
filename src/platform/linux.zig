const device = @import("../device.zig");
const platform = @import("mod.zig");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/keysym.h");
});

const LinuxBackend = enum { x11, wayland, none };

var display: ?*c.Display = null;
var cached_detected_backend: ?LinuxBackend = null;

fn detectBackendOnce() LinuxBackend {
    if (cached_detected_backend) |backend| return backend;

    const detected: LinuxBackend = blk: {
        const display_env = c.getenv("DISPLAY");
        const wayland_env = c.getenv("WAYLAND_DISPLAY");
        if (display_env != null) break :blk .x11;
        if (wayland_env != null) break :blk .wayland;
        break :blk .none;
    };

    cached_detected_backend = detected;
    return detected;
}

fn effectiveBackend(choice: platform.BackendChoice) LinuxBackend {
    return switch (choice) {
        .auto => detectBackendOnce(),
        .x11 => .x11,
        .wayland => .wayland,
    };
}

fn getDisplay() ?*c.Display {
    if (display == null) {
        display = c.XOpenDisplay(null);
    }
    return display;
}

fn mapKeysym(sym: c.KeySym) ?device.InputCode {
    return switch (sym) {
        c.XK_BackSpace => .key_backspace,
        c.XK_Tab => .key_tab,
        c.XK_Return => .key_enter,
        c.XK_Pause => .key_pause,
        c.XK_Caps_Lock => .key_caps_lock,
        c.XK_Escape => .key_escape,
        c.XK_space => .key_space,
        c.XK_Page_Up => .key_page_up,
        c.XK_Page_Down => .key_page_down,
        c.XK_End => .key_end,
        c.XK_Home => .key_home,
        c.XK_Left => .key_left,
        c.XK_Up => .key_up,
        c.XK_Right => .key_right,
        c.XK_Down => .key_down,
        c.XK_Print => .key_print_screen,
        c.XK_Insert => .key_insert,
        c.XK_Delete => .key_delete,
        c.XK_Super_L => .key_super_left,
        c.XK_Super_R => .key_super_right,
        c.XK_Menu => .key_menu,
        c.XK_Num_Lock => .key_num_lock,
        c.XK_Scroll_Lock => .key_scroll_lock,
        c.XK_Shift_L => .key_shift_left,
        c.XK_Shift_R => .key_shift_right,
        c.XK_Control_L => .key_control_left,
        c.XK_Control_R => .key_control_right,
        c.XK_Alt_L => .key_alt_left,
        c.XK_Alt_R => .key_alt_right,
        c.XK_F1 => .key_f1,
        c.XK_F2 => .key_f2,
        c.XK_F3 => .key_f3,
        c.XK_F4 => .key_f4,
        c.XK_F5 => .key_f5,
        c.XK_F6 => .key_f6,
        c.XK_F7 => .key_f7,
        c.XK_F8 => .key_f8,
        c.XK_F9 => .key_f9,
        c.XK_F10 => .key_f10,
        c.XK_F11 => .key_f11,
        c.XK_F12 => .key_f12,
        c.XK_F13 => .key_f13,
        c.XK_F14 => .key_f14,
        c.XK_F15 => .key_f15,
        c.XK_F16 => .key_f16,
        c.XK_F17 => .key_f17,
        c.XK_F18 => .key_f18,
        c.XK_F19 => .key_f19,
        c.XK_F20 => .key_f20,
        c.XK_F21 => .key_f21,
        c.XK_F22 => .key_f22,
        c.XK_F23 => .key_f23,
        c.XK_F24 => .key_f24,
        c.XK_KP_0 => .key_numpad_0,
        c.XK_KP_1 => .key_numpad_1,
        c.XK_KP_2 => .key_numpad_2,
        c.XK_KP_3 => .key_numpad_3,
        c.XK_KP_4 => .key_numpad_4,
        c.XK_KP_5 => .key_numpad_5,
        c.XK_KP_6 => .key_numpad_6,
        c.XK_KP_7 => .key_numpad_7,
        c.XK_KP_8 => .key_numpad_8,
        c.XK_KP_9 => .key_numpad_9,
        c.XK_KP_Multiply => .key_numpad_multiply,
        c.XK_KP_Add => .key_numpad_add,
        c.XK_KP_Subtract => .key_numpad_subtract,
        c.XK_KP_Decimal => .key_numpad_decimal,
        c.XK_KP_Divide => .key_numpad_divide,
        c.XK_0 => .key_0,
        c.XK_1 => .key_1,
        c.XK_2 => .key_2,
        c.XK_3 => .key_3,
        c.XK_4 => .key_4,
        c.XK_5 => .key_5,
        c.XK_6 => .key_6,
        c.XK_7 => .key_7,
        c.XK_8 => .key_8,
        c.XK_9 => .key_9,
        c.XK_a, c.XK_A => .key_a,
        c.XK_b, c.XK_B => .key_b,
        c.XK_c, c.XK_C => .key_c,
        c.XK_d, c.XK_D => .key_d,
        c.XK_e, c.XK_E => .key_e,
        c.XK_f, c.XK_F => .key_f,
        c.XK_g, c.XK_G => .key_g,
        c.XK_h, c.XK_H => .key_h,
        c.XK_i, c.XK_I => .key_i,
        c.XK_j, c.XK_J => .key_j,
        c.XK_k, c.XK_K => .key_k,
        c.XK_l, c.XK_L => .key_l,
        c.XK_m, c.XK_M => .key_m,
        c.XK_n, c.XK_N => .key_n,
        c.XK_o, c.XK_O => .key_o,
        c.XK_p, c.XK_P => .key_p,
        c.XK_q, c.XK_Q => .key_q,
        c.XK_r, c.XK_R => .key_r,
        c.XK_s, c.XK_S => .key_s,
        c.XK_t, c.XK_T => .key_t,
        c.XK_u, c.XK_U => .key_u,
        c.XK_v, c.XK_V => .key_v,
        c.XK_w, c.XK_W => .key_w,
        c.XK_x, c.XK_X => .key_x,
        c.XK_y, c.XK_Y => .key_y,
        c.XK_z, c.XK_Z => .key_z,
        else => null,
    };
}

pub fn updateKeyboard(keyboard: *device.KeyboardDevice, choice: platform.BackendChoice) !void {
    switch (effectiveBackend(choice)) {
        .x11 => {
            const d = getDisplay() orelse return error.DisplayOpenFailed;

            @memset(keyboard.keys[0..], .up);

            var keymap: [32]u8 = [_]u8{0} ** 32;
            c.XQueryKeymap(d, @ptrCast(&keymap));

            var keycode: usize = 8;
            while (keycode < 256) : (keycode += 1) {
                const idx = keycode / 8;
                const shift: u3 = @intCast(keycode % 8);
                const down = (keymap[idx] & (@as(u8, 1) << shift)) != 0;
                if (!down) continue;

                const sym = c.XkbKeycodeToKeysym(d, @intCast(keycode), 0, 0);
                const code = mapKeysym(sym) orelse continue;
                const out_idx: usize = @intFromEnum(code);
                if (out_idx < device.max_keys) {
                    keyboard.keys[out_idx] = .down;
                }
            }
        },
        .wayland => return error.WaylandGlobalPollingUnsupported,
        .none => return error.NoDisplayServer,
    }
}

pub fn updateMouse(mouse: *device.MouseDevice, choice: platform.BackendChoice) !void {
    switch (effectiveBackend(choice)) {
        .x11 => {
            const d = getDisplay() orelse return error.DisplayOpenFailed;

            var root: c.Window = 0;
            var child: c.Window = 0;
            var root_x: c_int = 0;
            var root_y: c_int = 0;
            var win_x: c_int = 0;
            var win_y: c_int = 0;
            var mask: c_uint = 0;

            if (c.XQueryPointer(d, c.XDefaultRootWindow(d), &root, &child, &root_x, &root_y, &win_x, &win_y, &mask) != 0) {
                mouse.x = @floatFromInt(root_x);
                mouse.y = @floatFromInt(root_y);

                @memset(mouse.buttons[0..], .up);
                mouse.buttons[0] = if ((mask & c.Button1Mask) != 0) .down else .up;
                mouse.buttons[1] = if ((mask & c.Button3Mask) != 0) .down else .up;
                mouse.buttons[2] = if ((mask & c.Button2Mask) != 0) .down else .up;
                mouse.buttons[3] = if ((mask & c.Button4Mask) != 0) .down else .up;
                mouse.buttons[4] = if ((mask & c.Button5Mask) != 0) .down else .up;
            }
        },
        .wayland => return error.WaylandGlobalPollingUnsupported,
        .none => return error.NoDisplayServer,
    }
}
