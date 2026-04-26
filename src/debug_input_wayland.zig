const std = @import("std");
const input = @import("input");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
    @cInclude("wayland-client.h");
    @cInclude("wayland-client-protocol.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("xdg-shell-client-protocol.h");
});

const frame_time_ns = 100 * std.time.ns_per_ms;
const window_width = 640;
const window_height = 360;
const buffer_stride = window_width * 4;
const buffer_size = buffer_stride * window_height;
const max_focused_keys = 256;
const max_focused_mouse_buttons = 16;

const KeyProbe = struct {
    label: []const u8,
    keysym: u32,
    code: input.InputCode,
};

const MouseProbe = struct {
    label: []const u8,
    button: u32,
    code: input.InputCode,
};

const GamepadProbe = struct {
    label: []const u8,
    code: input.InputCode,
};

const key_probes = [_]KeyProbe{
    .{ .label = "W", .keysym = c.XKB_KEY_w, .code = .key_w },
    .{ .label = "A", .keysym = c.XKB_KEY_a, .code = .key_a },
    .{ .label = "S", .keysym = c.XKB_KEY_s, .code = .key_s },
    .{ .label = "D", .keysym = c.XKB_KEY_d, .code = .key_d },
    .{ .label = "Space", .keysym = c.XKB_KEY_space, .code = .key_space },
    .{ .label = "Escape", .keysym = c.XKB_KEY_Escape, .code = .key_escape },
    .{ .label = "Left Shift", .keysym = c.XKB_KEY_Shift_L, .code = .key_shift_left },
    .{ .label = "Right Shift", .keysym = c.XKB_KEY_Shift_R, .code = .key_shift_right },
    .{ .label = "Left Ctrl", .keysym = c.XKB_KEY_Control_L, .code = .key_control_left },
    .{ .label = "Right Ctrl", .keysym = c.XKB_KEY_Control_R, .code = .key_control_right },
    .{ .label = "Left Alt", .keysym = c.XKB_KEY_Alt_L, .code = .key_alt_left },
    .{ .label = "Right Alt", .keysym = c.XKB_KEY_Alt_R, .code = .key_alt_right },
    .{ .label = "Left", .keysym = c.XKB_KEY_Left, .code = .key_left },
    .{ .label = "Right", .keysym = c.XKB_KEY_Right, .code = .key_right },
    .{ .label = "Up", .keysym = c.XKB_KEY_Up, .code = .key_up },
    .{ .label = "Down", .keysym = c.XKB_KEY_Down, .code = .key_down },
};

const mouse_probes = [_]MouseProbe{
    .{ .label = "Left", .button = 0x110, .code = .mouse_left },
    .{ .label = "Right", .button = 0x111, .code = .mouse_right },
    .{ .label = "Middle", .button = 0x112, .code = .mouse_middle },
    .{ .label = "Button4", .button = 0x113, .code = .mouse_button4 },
    .{ .label = "Button5", .button = 0x114, .code = .mouse_button5 },
};

const gamepad_probes = [_]GamepadProbe{
    .{ .label = "Face North", .code = .gamepad_face_north },
    .{ .label = "Face East", .code = .gamepad_face_east },
    .{ .label = "Face South", .code = .gamepad_face_south },
    .{ .label = "Face West", .code = .gamepad_face_west },
    .{ .label = "Dpad Up", .code = .gamepad_dpad_up },
    .{ .label = "Dpad Right", .code = .gamepad_dpad_right },
    .{ .label = "Dpad Down", .code = .gamepad_dpad_down },
    .{ .label = "Dpad Left", .code = .gamepad_dpad_left },
    .{ .label = "L Shoulder", .code = .gamepad_left_shoulder },
    .{ .label = "R Shoulder", .code = .gamepad_right_shoulder },
    .{ .label = "L Trigger", .code = .gamepad_left_trigger },
    .{ .label = "R Trigger", .code = .gamepad_right_trigger },
    .{ .label = "Select", .code = .gamepad_select },
    .{ .label = "Start", .code = .gamepad_start },
    .{ .label = "Home", .code = .gamepad_home },
    .{ .label = "Capture", .code = .gamepad_capture },
    .{ .label = "L Stick", .code = .gamepad_left_stick_press },
    .{ .label = "R Stick", .code = .gamepad_right_stick_press },
};

const KeyState = struct {
    down: bool = false,
    prev_down: bool = false,
};

const ButtonState = struct {
    down: bool = false,
    prev_down: bool = false,
};

const Config = struct {
    frame_limit: ?usize = null,
};

pub const FocusState = struct {
    keyboard: bool,
    pointer: bool,
};

const App = struct {
    display: ?*c.wl_display = null,
    registry: ?*c.wl_registry = null,
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    seat: ?*c.wl_seat = null,
    pointer: ?*c.wl_pointer = null,
    keyboard: ?*c.wl_keyboard = null,
    wm_base: ?*c.xdg_wm_base = null,
    surface: ?*c.wl_surface = null,
    xdg_surface: ?*c.xdg_surface = null,
    toplevel: ?*c.xdg_toplevel = null,
    pool: ?*c.wl_shm_pool = null,
    buffer: ?*c.wl_buffer = null,
    shm_fd: ?std.posix.fd_t = null,
    shm_map: ?[]align(std.heap.page_size_min) u8 = null,
    xkb_context: ?*c.xkb_context = null,
    xkb_keymap: ?*c.xkb_keymap = null,
    xkb_state: ?*c.xkb_state = null,
    configured: bool = false,
    running: bool = true,
    pointer_focus: bool = false,
    keyboard_focus: bool = false,
    pointer_x: f64 = 0,
    pointer_y: f64 = 0,
    pointer_delta_x: f64 = 0,
    pointer_delta_y: f64 = 0,
    pointer_position_initialized: bool = false,
    scroll_delta_x: f64 = 0,
    scroll_delta_y: f64 = 0,
    focused_keys: [max_focused_keys]bool = [_]bool{false} ** max_focused_keys,
    focused_mouse_buttons: [max_focused_mouse_buttons]bool = [_]bool{false} ** max_focused_mouse_buttons,
    key_states: [key_probes.len]KeyState = [_]KeyState{.{}} ** key_probes.len,
    button_states: [mouse_probes.len]ButtonState = [_]ButtonState{.{}} ** mouse_probes.len,
    input_state: input.InputSystem = .{},

    /// Connect to Wayland globals and prepare the window objects.
    fn init(self: *App) !void {
        self.display = c.wl_display_connect(null) orelse {
            return error.WaylandConnectFailed;
        };

        self.registry = c.wl_display_get_registry(self.display);
        if (self.registry == null) return error.WaylandRegistryUnavailable;

        if (c.wl_registry_add_listener(self.registry, &registry_listener, self) != 0) {
            return error.WaylandListenerInstallFailed;
        }

        if (c.wl_display_roundtrip(self.display) < 0) {
            return error.WaylandRoundtripFailed;
        }

        if (self.compositor == null) return error.WaylandCompositorUnavailable;
        if (self.shm == null) return error.WaylandShmUnavailable;
        if (self.wm_base == null) return error.WaylandXdgUnavailable;

        try self.createWindow();

        if (self.seat != null and c.wl_display_roundtrip(self.display) < 0) {
            return error.WaylandRoundtripFailed;
        }
    }

    /// Release all Wayland and xkb resources.
    fn deinit(self: *App) void {
        if (self.keyboard) |keyboard| c.wl_keyboard_release(keyboard);
        if (self.pointer) |pointer| c.wl_pointer_release(pointer);
        if (self.seat) |seat| c.wl_seat_release(seat);
        if (self.buffer) |buffer| c.wl_buffer_destroy(buffer);
        if (self.pool) |pool| c.wl_shm_pool_destroy(pool);
        if (self.toplevel) |toplevel| c.xdg_toplevel_destroy(toplevel);
        if (self.xdg_surface) |xdg_surface| c.xdg_surface_destroy(xdg_surface);
        if (self.surface) |surface| c.wl_surface_destroy(surface);
        if (self.wm_base) |wm_base| c.xdg_wm_base_destroy(wm_base);
        if (self.shm) |shm| c.wl_shm_release(shm);
        if (self.registry) |registry| c.wl_registry_destroy(registry);
        if (self.xkb_state) |state| c.xkb_state_unref(state);
        if (self.xkb_keymap) |keymap| c.xkb_keymap_unref(keymap);
        if (self.xkb_context) |context| c.xkb_context_unref(context);

        if (self.shm_map) |mapping| std.posix.munmap(mapping);
        if (self.shm_fd) |fd| _ = c.close(fd);
        if (self.display) |display| _ = c.wl_display_disconnect(display);
    }

    /// Create a tiny visible toplevel surface so the compositor can focus it.
    fn createWindow(self: *App) !void {
        self.surface = c.wl_compositor_create_surface(self.compositor);
        self.xdg_surface = c.xdg_wm_base_get_xdg_surface(self.wm_base, self.surface);
        self.toplevel = c.xdg_surface_get_toplevel(self.xdg_surface);

        if (self.surface == null or self.xdg_surface == null or self.toplevel == null) {
            return error.WaylandWindowCreateFailed;
        }

        if (c.xdg_wm_base_add_listener(self.wm_base, &wm_base_listener, self) != 0) {
            return error.WaylandListenerInstallFailed;
        }
        if (c.xdg_surface_add_listener(self.xdg_surface, &xdg_surface_listener, self) != 0) {
            return error.WaylandListenerInstallFailed;
        }
        if (c.xdg_toplevel_add_listener(self.toplevel, &xdg_toplevel_listener, self) != 0) {
            return error.WaylandListenerInstallFailed;
        }

        c.xdg_toplevel_set_title(self.toplevel, "input wayland debug");
        c.xdg_toplevel_set_app_id(self.toplevel, "input-debug");
        c.wl_surface_commit(self.surface);

        if (c.wl_display_roundtrip(self.display) < 0) {
            return error.WaylandRoundtripFailed;
        }

        if (!self.configured) return error.WaylandConfigureMissing;
        try self.createBuffer();
        self.attachBuffer();
    }

    /// Create a shared-memory buffer so the surface can be mapped.
    fn createBuffer(self: *App) !void {
        const fd = try std.posix.memfd_create("input-wayland", 0);
        errdefer _ = c.close(fd);

        if (c.ftruncate(fd, buffer_size) != 0) return error.WaylandBufferCreateFailed;
        const mapping = try std.posix.mmap(
            null,
            buffer_size,
            .{ .READ = true, .WRITE = true },
            .{ .TYPE = .SHARED },
            fd,
            0,
        );
        errdefer std.posix.munmap(mapping);

        @memset(mapping, 0x20);

        self.pool = c.wl_shm_create_pool(self.shm, @intCast(fd), buffer_size);
        self.buffer = c.wl_shm_pool_create_buffer(
            self.pool,
            0,
            window_width,
            window_height,
            buffer_stride,
            c.WL_SHM_FORMAT_XRGB8888,
        );

        if (self.pool == null or self.buffer == null) {
            return error.WaylandBufferCreateFailed;
        }

        self.shm_fd = fd;
        self.shm_map = mapping;
    }

    /// Attach the window buffer and damage the full surface.
    fn attachBuffer(self: *App) void {
        c.wl_surface_attach(self.surface, self.buffer, 0, 0);
        c.wl_surface_damage_buffer(self.surface, 0, 0, window_width, window_height);
        c.wl_surface_commit(self.surface);
    }

    /// Pump pending Wayland events without blocking forever.
    fn pumpEvents(self: *App) !void {
        if (c.wl_display_flush(self.display) < 0) {
            return error.WaylandFlushFailed;
        }

        var fds = [_]std.posix.pollfd{.{
            .fd = c.wl_display_get_fd(self.display),
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        _ = try std.posix.poll(fds[0..], 0);

        if (c.wl_display_dispatch_pending(self.display) < 0) {
            return error.WaylandDispatchFailed;
        }

        if (fds[0].revents & std.posix.POLL.IN != 0) {
            if (c.wl_display_dispatch(self.display) < 0) {
                return error.WaylandDispatchFailed;
            }
        }
    }

    /// Advance previous-state snapshots before the next event pump.
    fn beginFrame(self: *App) void {
        for (&self.key_states) |*state| {
            state.prev_down = state.down;
        }
        for (&self.button_states) |*state| {
            state.prev_down = state.down;
        }

        const keyboard = self.input_state.keyboard();
        keyboard.prev_keys = keyboard.keys;

        const mouse = self.input_state.mouse();
        mouse.prev_buttons = mouse.buttons;
        mouse.raw_delta = .{ .x = 0, .y = 0 };
        mouse.scroll_delta = .{ .x = 0, .y = 0 };

        self.pointer_delta_x = 0;
        self.pointer_delta_y = 0;
        self.scroll_delta_x = 0;
        self.scroll_delta_y = 0;
    }

    fn syncFocusedDevices(self: *App) void {
        const keyboard = self.input_state.keyboard();
        @memset(keyboard.keys[0..], .up);
        for (self.focused_keys, 0..) |down, index| {
            if (!down or index >= keyboard.keys.len) continue;
            keyboard.keys[index] = .down;
        }

        const mouse = self.input_state.mouse();
        @memset(mouse.buttons[0..], .up);
        for (self.focused_mouse_buttons, 0..) |down, index| {
            if (!down or index >= mouse.buttons.len) continue;
            mouse.buttons[index] = .down;
        }

        mouse.setRawPosition(.{
            .x = @floatCast(self.pointer_x),
            .y = @floatCast(self.pointer_y),
        }, .window_local);
        mouse.raw_delta = .{
            .x = @floatCast(self.pointer_delta_x),
            .y = @floatCast(self.pointer_delta_y),
        };
        mouse.addScrollDelta(.{
            .x = @floatCast(self.scroll_delta_x),
            .y = @floatCast(self.scroll_delta_y),
        });
    }

    fn updateGamepads(self: *App) !void {
        var slot: usize = 0;
        while (self.input_state.gamepad(slot)) |gamepad| : (slot += 1) {
            try gamepad.update();
        }
    }

    /// Render the current focused input state to stdout.
    fn render(self: *App, writer: *std.Io.Writer, frame_limit: ?usize) !void {
        try writer.writeAll("\x1b[2J\x1b[H");
        try writer.writeAll("input debug viewer\n");

        if (frame_limit) |limit| {
            try writer.print("frame limit: {d}\n", .{limit});
        } else {
            try writer.writeAll("frame limit: none\n");
        }

        try writer.print("window focus: keyboard={any} pointer={any}\n\n", .{
            self.keyboard_focus,
            self.pointer_focus,
        });

        try writer.writeAll("mouse position: ");
        try writeFixed(writer, @floatCast(self.pointer_x), 10);
        try writer.writeAll(", ");
        try writeFixed(writer, @floatCast(self.pointer_y), 10);
        try writer.writeByte('\n');
        try writer.writeAll("mouse delta:    ");
        try writeFixed(writer, @floatCast(self.pointer_delta_x), 10);
        try writer.writeAll(", ");
        try writeFixed(writer, @floatCast(self.pointer_delta_y), 10);
        try writer.writeByte('\n');
        try writer.writeAll("scroll delta:   ");
        try writeFixed(writer, @floatCast(self.scroll_delta_x), 10);
        try writer.writeAll(", ");
        try writeFixed(writer, @floatCast(self.scroll_delta_y), 10);
        try writer.writeByte('\n');
        try writer.writeAll("mouse buttons:\n");

        for (mouse_probes, 0..) |probe, idx| {
            const state = self.button_states[idx];
            try writer.print(
                "  {s: <11} down={any} pressed={any} released={any}\n",
                .{
                    probe.label,
                    state.down,
                    !state.prev_down and state.down,
                    state.prev_down and !state.down,
                },
            );
        }

        try writer.writeByte('\n');
        try writer.writeAll("keyboard keys:\n");

        for (key_probes, 0..) |probe, idx| {
            const state = self.key_states[idx];
            try writer.print(
                "  {s: <11} down={any} pressed={any} released={any}\n",
                .{
                    probe.label,
                    state.down,
                    !state.prev_down and state.down,
                    state.prev_down and !state.down,
                },
            );
        }

        try writer.writeByte('\n');
        try self.renderGamepads(writer);
    }

    fn renderGamepads(self: *const App, writer: *std.Io.Writer) !void {
        try writer.writeAll("gamepads:\n");

        var slot: usize = 0;
        while (self.input_state.gamepad(slot)) |gamepad| : (slot += 1) {
            try writer.print("  slot {d} connected={any} name={s}\n", .{
                slot,
                gamepad.view.connected,
                gamepad.view.nameSlice(),
            });

            if (!gamepad.view.connected) continue;

            const left = gamepad.leftStick();
            const right = gamepad.rightStick();
            try writer.writeAll("    left=(");
            try writeFixed(writer, left.x, 100);
            try writer.writeAll(", ");
            try writeFixed(writer, left.y, 100);
            try writer.writeAll(") right=(");
            try writeFixed(writer, right.x, 100);
            try writer.writeAll(", ");
            try writeFixed(writer, right.y, 100);
            try writer.writeAll(") lt=");
            try writeFixed(writer, gamepad.leftTrigger(), 100);
            try writer.writeAll(" rt=");
            try writeFixed(writer, gamepad.rightTrigger(), 100);
            try writer.writeByte('\n');
            try self.renderRawGamepadButtons(writer, gamepad);

            for (gamepad_probes) |probe| {
                try writer.print(
                    "    {s: <11} down={any} pressed={any} released={any}\n",
                    .{
                        probe.label,
                        gamepad.down(probe.code),
                        gamepad.pressed(probe.code),
                        gamepad.released(probe.code),
                    },
                );
            }
        }
    }

    fn renderRawGamepadButtons(_: *const App, writer: *std.Io.Writer, gamepad: *const input.GamepadDevice) !void {
        try writer.writeAll("    raw buttons:");
        for (gamepad.buttons[0..18], 0..) |button, index| {
            if (button == .down) {
                try writer.print(" {d}=1", .{index});
            }
        }
        try writer.writeByte('\n');
    }
};

fn mouseIndex(code: input.InputCode) ?usize {
    return switch (code) {
        .mouse_left => 0,
        .mouse_right => 1,
        .mouse_middle => 2,
        .mouse_button4 => 3,
        .mouse_button5 => 4,
        else => null,
    };
}

fn keysymToInputCode(sym: u32) ?input.InputCode {
    return switch (sym) {
        c.XKB_KEY_BackSpace => .key_backspace,
        c.XKB_KEY_Tab => .key_tab,
        c.XKB_KEY_Return => .key_enter,
        c.XKB_KEY_Pause => .key_pause,
        c.XKB_KEY_Caps_Lock => .key_caps_lock,
        c.XKB_KEY_Escape => .key_escape,
        c.XKB_KEY_space => .key_space,
        c.XKB_KEY_Page_Up => .key_page_up,
        c.XKB_KEY_Page_Down => .key_page_down,
        c.XKB_KEY_End => .key_end,
        c.XKB_KEY_Home => .key_home,
        c.XKB_KEY_Left => .key_left,
        c.XKB_KEY_Up => .key_up,
        c.XKB_KEY_Right => .key_right,
        c.XKB_KEY_Down => .key_down,
        c.XKB_KEY_Print => .key_print_screen,
        c.XKB_KEY_Insert => .key_insert,
        c.XKB_KEY_Delete => .key_delete,
        c.XKB_KEY_Super_L => .key_super_left,
        c.XKB_KEY_Super_R => .key_super_right,
        c.XKB_KEY_Menu => .key_menu,
        c.XKB_KEY_Num_Lock => .key_num_lock,
        c.XKB_KEY_Scroll_Lock => .key_scroll_lock,
        c.XKB_KEY_Shift_L => .key_shift_left,
        c.XKB_KEY_Shift_R => .key_shift_right,
        c.XKB_KEY_Control_L => .key_control_left,
        c.XKB_KEY_Control_R => .key_control_right,
        c.XKB_KEY_Alt_L => .key_alt_left,
        c.XKB_KEY_Alt_R => .key_alt_right,
        c.XKB_KEY_F1 => .key_f1,
        c.XKB_KEY_F2 => .key_f2,
        c.XKB_KEY_F3 => .key_f3,
        c.XKB_KEY_F4 => .key_f4,
        c.XKB_KEY_F5 => .key_f5,
        c.XKB_KEY_F6 => .key_f6,
        c.XKB_KEY_F7 => .key_f7,
        c.XKB_KEY_F8 => .key_f8,
        c.XKB_KEY_F9 => .key_f9,
        c.XKB_KEY_F10 => .key_f10,
        c.XKB_KEY_F11 => .key_f11,
        c.XKB_KEY_F12 => .key_f12,
        c.XKB_KEY_F13 => .key_f13,
        c.XKB_KEY_F14 => .key_f14,
        c.XKB_KEY_F15 => .key_f15,
        c.XKB_KEY_F16 => .key_f16,
        c.XKB_KEY_F17 => .key_f17,
        c.XKB_KEY_F18 => .key_f18,
        c.XKB_KEY_F19 => .key_f19,
        c.XKB_KEY_F20 => .key_f20,
        c.XKB_KEY_F21 => .key_f21,
        c.XKB_KEY_F22 => .key_f22,
        c.XKB_KEY_F23 => .key_f23,
        c.XKB_KEY_F24 => .key_f24,
        c.XKB_KEY_KP_0 => .key_numpad_0,
        c.XKB_KEY_KP_1 => .key_numpad_1,
        c.XKB_KEY_KP_2 => .key_numpad_2,
        c.XKB_KEY_KP_3 => .key_numpad_3,
        c.XKB_KEY_KP_4 => .key_numpad_4,
        c.XKB_KEY_KP_5 => .key_numpad_5,
        c.XKB_KEY_KP_6 => .key_numpad_6,
        c.XKB_KEY_KP_7 => .key_numpad_7,
        c.XKB_KEY_KP_8 => .key_numpad_8,
        c.XKB_KEY_KP_9 => .key_numpad_9,
        c.XKB_KEY_KP_Multiply => .key_numpad_multiply,
        c.XKB_KEY_KP_Add => .key_numpad_add,
        c.XKB_KEY_KP_Subtract => .key_numpad_subtract,
        c.XKB_KEY_KP_Decimal => .key_numpad_decimal,
        c.XKB_KEY_KP_Divide => .key_numpad_divide,
        c.XKB_KEY_0 => .key_0,
        c.XKB_KEY_1 => .key_1,
        c.XKB_KEY_2 => .key_2,
        c.XKB_KEY_3 => .key_3,
        c.XKB_KEY_4 => .key_4,
        c.XKB_KEY_5 => .key_5,
        c.XKB_KEY_6 => .key_6,
        c.XKB_KEY_7 => .key_7,
        c.XKB_KEY_8 => .key_8,
        c.XKB_KEY_9 => .key_9,
        c.XKB_KEY_a, c.XKB_KEY_A => .key_a,
        c.XKB_KEY_b, c.XKB_KEY_B => .key_b,
        c.XKB_KEY_c, c.XKB_KEY_C => .key_c,
        c.XKB_KEY_d, c.XKB_KEY_D => .key_d,
        c.XKB_KEY_e, c.XKB_KEY_E => .key_e,
        c.XKB_KEY_f, c.XKB_KEY_F => .key_f,
        c.XKB_KEY_g, c.XKB_KEY_G => .key_g,
        c.XKB_KEY_h, c.XKB_KEY_H => .key_h,
        c.XKB_KEY_i, c.XKB_KEY_I => .key_i,
        c.XKB_KEY_j, c.XKB_KEY_J => .key_j,
        c.XKB_KEY_k, c.XKB_KEY_K => .key_k,
        c.XKB_KEY_l, c.XKB_KEY_L => .key_l,
        c.XKB_KEY_m, c.XKB_KEY_M => .key_m,
        c.XKB_KEY_n, c.XKB_KEY_N => .key_n,
        c.XKB_KEY_o, c.XKB_KEY_O => .key_o,
        c.XKB_KEY_p, c.XKB_KEY_P => .key_p,
        c.XKB_KEY_q, c.XKB_KEY_Q => .key_q,
        c.XKB_KEY_r, c.XKB_KEY_R => .key_r,
        c.XKB_KEY_s, c.XKB_KEY_S => .key_s,
        c.XKB_KEY_t, c.XKB_KEY_T => .key_t,
        c.XKB_KEY_u, c.XKB_KEY_U => .key_u,
        c.XKB_KEY_v, c.XKB_KEY_V => .key_v,
        c.XKB_KEY_w, c.XKB_KEY_W => .key_w,
        c.XKB_KEY_x, c.XKB_KEY_X => .key_x,
        c.XKB_KEY_y, c.XKB_KEY_Y => .key_y,
        c.XKB_KEY_z, c.XKB_KEY_Z => .key_z,
        else => null,
    };
}

fn waylandPointerButtonIndex(button: u32) ?usize {
    if (button < 0x110) return null;
    const index: usize = @intCast(button - 0x110);
    if (index >= max_focused_mouse_buttons) return null;
    return index;
}

fn writeFixed(writer: *std.Io.Writer, value: f32, comptime scale: i32) !void {
    var scaled: i32 = @intFromFloat(value * @as(f32, @floatFromInt(scale)));
    if (scaled < 0) {
        try writer.writeByte('-');
        scaled = -scaled;
    }

    const whole = @divTrunc(scaled, scale);
    const fraction: u32 = @intCast(@rem(scaled, scale));
    if (scale == 10) {
        try writer.print("{d}.{d}", .{ whole, fraction });
    } else {
        try writer.print("{d}.{d:0>2}", .{ whole, fraction });
    }
}

/// Run a native Wayland focused-window debug viewer.
pub fn run(frame_limit: ?usize, io: std.Io) !void {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
    var stderr = std.Io.File.stderr().writer(io, &stderr_buffer);
    var stdout_writer = &stdout.interface;
    var stderr_writer = &stderr.interface;
    var app = App{};
    var frame_count: usize = 0;

    app.init() catch |err| {
        try renderError(stderr_writer, err);
        try stderr_writer.flush();
        return err;
    };
    defer app.deinit();

    while (app.running) {
        app.beginFrame();
        app.pumpEvents() catch |err| {
            try stdout_writer.flush();
            try renderError(stderr_writer, err);
            try stderr_writer.flush();
            return err;
        };
        app.syncFocusedDevices();
        app.updateGamepads() catch |err| {
            try stdout_writer.flush();
            try renderError(stderr_writer, err);
            try stderr_writer.flush();
            return err;
        };

        try app.render(stdout_writer, frame_limit);
        try stdout_writer.flush();

        frame_count += 1;
        if (frame_limit) |limit| {
            if (frame_count >= limit) return;
        }

        try io.sleep(std.Io.Duration.fromNanoseconds(frame_time_ns), .awake);
    }
}

pub fn runFocusedInput(
    comptime Context: type,
    context: *Context,
    frame_limit: ?usize,
    io: std.Io,
    comptime render: fn (*Context, *input.InputSystem, FocusState, *std.Io.Writer, ?usize) anyerror!void,
) !void {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buffer);
    var stderr = std.Io.File.stderr().writer(io, &stderr_buffer);
    var stdout_writer = &stdout.interface;
    var stderr_writer = &stderr.interface;
    var app = App{};
    var frame_count: usize = 0;

    app.init() catch |err| {
        try renderError(stderr_writer, err);
        try stderr_writer.flush();
        return err;
    };
    defer app.deinit();

    while (app.running) {
        app.beginFrame();
        app.pumpEvents() catch |err| {
            try stdout_writer.flush();
            try renderError(stderr_writer, err);
            try stderr_writer.flush();
            return err;
        };
        app.syncFocusedDevices();
        app.updateGamepads() catch |err| {
            try stdout_writer.flush();
            try renderError(stderr_writer, err);
            try stderr_writer.flush();
            return err;
        };

        try render(context, &app.input_state, .{
            .keyboard = app.keyboard_focus,
            .pointer = app.pointer_focus,
        }, stdout_writer, frame_limit);
        try stdout_writer.flush();

        frame_count += 1;
        if (frame_limit) |limit| {
            if (frame_count >= limit) return;
        }

        try io.sleep(std.Io.Duration.fromNanoseconds(frame_time_ns), .awake);
    }
}

/// Print setup or runtime failures in plain language.
fn renderError(writer: *std.Io.Writer, err: anyerror) !void {
    try writer.print("wayland focused input failed with {s}\n", .{@errorName(err)});

    switch (err) {
        error.WaylandConnectFailed => {
            try writer.writeAll("Could not connect to the Wayland compositor.\n");
        },
        error.WaylandCompositorUnavailable,
        error.WaylandShmUnavailable,
        error.WaylandXdgUnavailable,
        => {
            try writer.writeAll(
                "Required Wayland globals were not advertised by the compositor.\n",
            );
        },
        error.XkbKeymapCreateFailed,
        error.XkbStateCreateFailed,
        => {
            try writer.writeAll("Could not initialize xkb keyboard state.\n");
        },
        else => {},
    }
}

/// Bind compositor globals needed by the focused-window debug app.
fn registryGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    const iface = std.mem.span(interface);

    if (std.mem.eql(u8, iface, "wl_compositor")) {
        app.compositor = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_compositor_interface,
            @min(version, 4),
        ));
        return;
    }

    if (std.mem.eql(u8, iface, "wl_shm")) {
        app.shm = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_shm_interface,
            @min(version, 1),
        ));
        return;
    }

    if (std.mem.eql(u8, iface, "wl_seat")) {
        app.seat = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.wl_seat_interface,
            @min(version, 5),
        ));
        _ = c.wl_seat_add_listener(app.seat, &seat_listener, app);
        return;
    }

    if (std.mem.eql(u8, iface, "xdg_wm_base")) {
        app.wm_base = @ptrCast(c.wl_registry_bind(
            registry,
            name,
            &c.xdg_wm_base_interface,
            @min(version, 1),
        ));
    }
}

/// Ignore removed globals for the debug app lifetime.
fn registryGlobalRemove(_: ?*anyopaque, _: ?*c.wl_registry, _: u32) callconv(.c) void {}

/// Create or destroy pointer/keyboard objects to match seat capabilities.
fn seatCapabilities(data: ?*anyopaque, seat: ?*c.wl_seat, capabilities: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    const has_pointer = (capabilities & c.WL_SEAT_CAPABILITY_POINTER) != 0;
    const has_keyboard = (capabilities & c.WL_SEAT_CAPABILITY_KEYBOARD) != 0;

    if (has_pointer and app.pointer == null) {
        app.pointer = c.wl_seat_get_pointer(seat);
        _ = c.wl_pointer_add_listener(app.pointer, &pointer_listener, app);
    }

    if (!has_pointer and app.pointer != null) {
        c.wl_pointer_release(app.pointer);
        app.pointer = null;
        app.pointer_focus = false;
    }

    if (has_keyboard and app.keyboard == null) {
        app.keyboard = c.wl_seat_get_keyboard(seat);
        _ = c.wl_keyboard_add_listener(app.keyboard, &keyboard_listener, app);
    }

    if (!has_keyboard and app.keyboard != null) {
        c.wl_keyboard_release(app.keyboard);
        app.keyboard = null;
        app.keyboard_focus = false;
    }
}

/// Ignore seat names for now.
fn seatName(_: ?*anyopaque, _: ?*c.wl_seat, _: [*c]const u8) callconv(.c) void {}

/// Reply to compositor liveness checks.
fn wmBasePing(_: ?*anyopaque, wm_base: ?*c.xdg_wm_base, serial: u32) callconv(.c) void {
    c.xdg_wm_base_pong(wm_base, serial);
}

/// Acknowledge configure and map the surface once it is ready.
fn xdgSurfaceConfigure(data: ?*anyopaque, xdg_surface: ?*c.xdg_surface, serial: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    c.xdg_surface_ack_configure(xdg_surface, serial);
    app.configured = true;

    if (app.buffer != null) {
        app.attachBuffer();
    }
}

/// Ignore toplevel size hints in the fixed debug window.
fn xdgToplevelConfigure(_: ?*anyopaque, _: ?*c.xdg_toplevel, _: i32, _: i32, _: ?*c.wl_array) callconv(.c) void {}

/// Exit when the compositor asks to close the debug window.
fn xdgToplevelClose(data: ?*anyopaque, _: ?*c.xdg_toplevel) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.running = false;
}

/// Ignore optional bounds hints.
fn xdgToplevelConfigureBounds(_: ?*anyopaque, _: ?*c.xdg_toplevel, _: i32, _: i32) callconv(.c) void {}

/// Ignore optional wm capability hints.
fn xdgToplevelWmCapabilities(_: ?*anyopaque, _: ?*c.xdg_toplevel, _: ?*c.wl_array) callconv(.c) void {}

/// Track pointer focus entry and surface-local position.
fn pointerEnter(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: ?*c.wl_surface, surface_x: c.wl_fixed_t, surface_y: c.wl_fixed_t) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.pointer_focus = true;
    app.pointer_x = c.wl_fixed_to_double(surface_x);
    app.pointer_y = c.wl_fixed_to_double(surface_y);
    app.pointer_position_initialized = true;
}

/// Clear pointer focus when the compositor leaves the debug surface.
fn pointerLeave(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: ?*c.wl_surface) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.pointer_focus = false;
    @memset(app.focused_mouse_buttons[0..], false);

    for (&app.button_states) |*state| {
        state.down = false;
    }
}

/// Update the pointer coordinates within the focused surface.
fn pointerMotion(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, surface_x: c.wl_fixed_t, surface_y: c.wl_fixed_t) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    const x = c.wl_fixed_to_double(surface_x);
    const y = c.wl_fixed_to_double(surface_y);

    if (app.pointer_position_initialized) {
        app.pointer_delta_x += x - app.pointer_x;
        app.pointer_delta_y += y - app.pointer_y;
    } else {
        app.pointer_position_initialized = true;
    }

    app.pointer_x = x;
    app.pointer_y = y;
}

/// Record mouse button transitions while the window has pointer focus.
fn pointerButton(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: u32, button: u32, state: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    const down = state == c.WL_POINTER_BUTTON_STATE_PRESSED;

    if (waylandPointerButtonIndex(button)) |index| {
        app.focused_mouse_buttons[index] = down;
    }

    for (mouse_probes, 0..) |probe, idx| {
        if (probe.button != button) continue;
        app.button_states[idx].down = down;
        return;
    }
}

/// Accumulate scroll axes for quick visual confirmation.
fn pointerAxis(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, axis: u32, value: c.wl_fixed_t) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    const delta = c.wl_fixed_to_double(value);

    switch (axis) {
        c.WL_POINTER_AXIS_VERTICAL_SCROLL => app.scroll_delta_y += delta,
        c.WL_POINTER_AXIS_HORIZONTAL_SCROLL => app.scroll_delta_x += delta,
        else => {},
    }
}

/// Ignore pointer event grouping.
fn pointerFrame(_: ?*anyopaque, _: ?*c.wl_pointer) callconv(.c) void {}

/// Ignore scroll source details.
fn pointerAxisSource(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32) callconv(.c) void {}

/// Ignore axis stop notifications.
fn pointerAxisStop(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: u32) callconv(.c) void {}

/// Ignore discrete wheel clicks because continuous axis values are enough here.
fn pointerAxisDiscrete(_: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: i32) callconv(.c) void {}

/// Build the xkb keymap and state from the compositor-provided fd.
fn keyboardKeymap(data: ?*anyopaque, _: ?*c.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    defer _ = c.close(fd);

    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) return;

    const mapping = std.posix.mmap(
        null,
        size,
        .{ .READ = true },
        .{ .TYPE = .PRIVATE },
        fd,
        0,
    ) catch return;
    defer std.posix.munmap(mapping);

    if (app.xkb_context == null) {
        app.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
        if (app.xkb_context == null) return;
    }

    if (app.xkb_state) |state| c.xkb_state_unref(state);
    if (app.xkb_keymap) |keymap| c.xkb_keymap_unref(keymap);

    app.xkb_keymap = c.xkb_keymap_new_from_string(
        app.xkb_context,
        @ptrCast(mapping.ptr),
        c.XKB_KEYMAP_FORMAT_TEXT_V1,
        c.XKB_KEYMAP_COMPILE_NO_FLAGS,
    );
    if (app.xkb_keymap == null) return;

    app.xkb_state = c.xkb_state_new(app.xkb_keymap);
}

/// Note keyboard focus and seed any currently-held keys from the enter array.
fn keyboardEnter(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface, keys: ?*c.wl_array) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.keyboard_focus = true;

    @memset(app.focused_keys[0..], false);
    for (&app.key_states) |*state| {
        state.down = false;
    }

    const key_array = keys orelse return;
    const count = key_array.*.size / @sizeOf(u32);
    const pressed: [*]u32 = @ptrCast(@alignCast(key_array.*.data));

    for (pressed[0..count]) |keycode| {
        updateKeyProbeStates(app, keycode + 8, true);
    }
}

/// Clear logical key state when the window loses keyboard focus.
fn keyboardLeave(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.keyboard_focus = false;

    @memset(app.focused_keys[0..], false);
    for (&app.key_states) |*state| {
        state.down = false;
    }
}

/// Update the tracked probe keys from compositor key events.
fn keyboardKey(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: u32, key: u32, state: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    updateKeyProbeStates(app, key + 8, state != c.WL_KEYBOARD_KEY_STATE_RELEASED);
}

/// Keep xkb modifier state in sync for symbol lookup.
fn keyboardModifiers(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    if (app.xkb_state == null) return;

    _ = c.xkb_state_update_mask(
        app.xkb_state,
        mods_depressed,
        mods_latched,
        mods_locked,
        0,
        0,
        group,
    );
}

/// Ignore repeat metadata for the simple state viewer.
fn keyboardRepeatInfo(_: ?*anyopaque, _: ?*c.wl_keyboard, _: i32, _: i32) callconv(.c) void {}

/// Update tracked key probes from an xkb keycode.
fn updateKeyProbeStates(app: *App, keycode: u32, down: bool) void {
    if (app.xkb_state == null) return;

    const sym = c.xkb_state_key_get_one_sym(app.xkb_state, keycode);
    if (keysymToInputCode(sym)) |code| {
        const index: usize = @intFromEnum(code);
        if (index < app.focused_keys.len) app.focused_keys[index] = down;
    }

    for (key_probes, 0..) |probe, idx| {
        if (probe.keysym == sym) {
            app.key_states[idx].down = down;
        }
    }
}

const registry_listener = c.wl_registry_listener{
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

const seat_listener = c.wl_seat_listener{
    .capabilities = seatCapabilities,
    .name = seatName,
};

const wm_base_listener = c.xdg_wm_base_listener{
    .ping = wmBasePing,
};

const xdg_surface_listener = c.xdg_surface_listener{
    .configure = xdgSurfaceConfigure,
};

const xdg_toplevel_listener = c.xdg_toplevel_listener{
    .configure = xdgToplevelConfigure,
    .close = xdgToplevelClose,
    .configure_bounds = xdgToplevelConfigureBounds,
    .wm_capabilities = xdgToplevelWmCapabilities,
};

const pointer_listener = c.wl_pointer_listener{
    .enter = pointerEnter,
    .leave = pointerLeave,
    .motion = pointerMotion,
    .button = pointerButton,
    .axis = pointerAxis,
    .frame = pointerFrame,
    .axis_source = pointerAxisSource,
    .axis_stop = pointerAxisStop,
    .axis_discrete = pointerAxisDiscrete,
    .axis_value120 = null,
    .axis_relative_direction = null,
};

const keyboard_listener = c.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeatInfo,
};
