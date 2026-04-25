const std = @import("std");
const input = @import("input_zig");

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

const KeyProbe = struct {
    label: []const u8,
    keysym: u32,
};

const MouseProbe = struct {
    label: []const u8,
    button: u32,
};

const GamepadProbe = struct {
    label: []const u8,
    code: input.InputCode,
};

const key_probes = [_]KeyProbe{
    .{ .label = "W", .keysym = c.XKB_KEY_w },
    .{ .label = "A", .keysym = c.XKB_KEY_a },
    .{ .label = "S", .keysym = c.XKB_KEY_s },
    .{ .label = "D", .keysym = c.XKB_KEY_d },
    .{ .label = "Space", .keysym = c.XKB_KEY_space },
    .{ .label = "Escape", .keysym = c.XKB_KEY_Escape },
    .{ .label = "Left Shift", .keysym = c.XKB_KEY_Shift_L },
    .{ .label = "Right Shift", .keysym = c.XKB_KEY_Shift_R },
    .{ .label = "Left Ctrl", .keysym = c.XKB_KEY_Control_L },
    .{ .label = "Right Ctrl", .keysym = c.XKB_KEY_Control_R },
    .{ .label = "Left Alt", .keysym = c.XKB_KEY_Alt_L },
    .{ .label = "Right Alt", .keysym = c.XKB_KEY_Alt_R },
    .{ .label = "Left", .keysym = c.XKB_KEY_Left },
    .{ .label = "Right", .keysym = c.XKB_KEY_Right },
    .{ .label = "Up", .keysym = c.XKB_KEY_Up },
    .{ .label = "Down", .keysym = c.XKB_KEY_Down },
};

const mouse_probes = [_]MouseProbe{
    .{ .label = "Left", .button = 0x110 },
    .{ .label = "Right", .button = 0x111 },
    .{ .label = "Middle", .button = 0x112 },
    .{ .label = "Button4", .button = 0x113 },
    .{ .label = "Button5", .button = 0x114 },
};

const gamepad_probes = [_]GamepadProbe{
    .{ .label = "Face South", .code = .gamepad_face_south },
    .{ .label = "Face East", .code = .gamepad_face_east },
    .{ .label = "Face West", .code = .gamepad_face_west },
    .{ .label = "Face North", .code = .gamepad_face_north },
    .{ .label = "Dpad Up", .code = .gamepad_dpad_up },
    .{ .label = "Dpad Down", .code = .gamepad_dpad_down },
    .{ .label = "Dpad Left", .code = .gamepad_dpad_left },
    .{ .label = "Dpad Right", .code = .gamepad_dpad_right },
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
    scroll_x: f64 = 0,
    scroll_y: f64 = 0,
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
        if (self.shm_fd) |fd| std.posix.close(fd);
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

        c.xdg_toplevel_set_title(self.toplevel, "input-zig wayland debug");
        c.xdg_toplevel_set_app_id(self.toplevel, "input-zig-debug");
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
        const fd = try std.posix.memfd_create("input-zig-wayland", 0);
        errdefer std.posix.close(fd);

        try std.posix.ftruncate(fd, buffer_size);
        const mapping = try std.posix.mmap(
            null,
            buffer_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
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
        try writer.writeAll("input-zig debug viewer\n");

        if (frame_limit) |limit| {
            try writer.print("frame limit: {d}\n", .{limit});
        } else {
            try writer.writeAll("frame limit: none\n");
        }

        try writer.print("window focus: keyboard={any} pointer={any}\n\n", .{
            self.keyboard_focus,
            self.pointer_focus,
        });

        try writer.print("mouse position: {d:.1}, {d:.1}\n", .{
            self.pointer_x,
            self.pointer_y,
        });
        try writer.print("scroll accum: {d:.1}, {d:.1}\n", .{
            self.scroll_x,
            self.scroll_y,
        });
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
            try writer.print(
                "    left=({d:.2}, {d:.2}) right=({d:.2}, {d:.2}) lt={d:.2} rt={d:.2}\n",
                .{
                    left.x,
                    left.y,
                    right.x,
                    right.y,
                    gamepad.leftTrigger(),
                    gamepad.rightTrigger(),
                },
            );
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

/// Run a native Wayland focused-window debug viewer.
pub fn run(frame_limit: ?usize) !void {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [1024]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buffer);
    var stderr = std.fs.File.stderr().writer(&stderr_buffer);
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

        std.Thread.sleep(frame_time_ns);
    }
}

/// Run as a standalone entrypoint for direct Wayland debugging.
pub fn main() !void {
    const config = try parseConfig();
    return run(config.frame_limit);
}

/// Parse the optional bounded-run arguments.
fn parseConfig() !Config {
    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    var config = Config{};

    _ = args.next();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--frames")) {
            const value = args.next() orelse return error.MissingFrameLimit;
            config.frame_limit = try std.fmt.parseInt(usize, value, 10);
            continue;
        }

        std.debug.print(
            "unknown arg '{s}', expected only --frames N\n",
            .{arg},
        );
        return error.InvalidArgument;
    }

    return config;
}

/// Print setup or runtime failures in plain language.
fn renderError(writer: *std.Io.Writer, err: anyerror) !void {
    try writer.print("debug-input-wayland failed with {s}\n", .{@errorName(err)});

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
}

/// Clear pointer focus when the compositor leaves the debug surface.
fn pointerLeave(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: ?*c.wl_surface) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.pointer_focus = false;
}

/// Update the pointer coordinates within the focused surface.
fn pointerMotion(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, surface_x: c.wl_fixed_t, surface_y: c.wl_fixed_t) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.pointer_x = c.wl_fixed_to_double(surface_x);
    app.pointer_y = c.wl_fixed_to_double(surface_y);
}

/// Record mouse button transitions while the window has pointer focus.
fn pointerButton(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, _: u32, button: u32, state: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));

    for (mouse_probes, 0..) |probe, idx| {
        if (probe.button != button) continue;
        app.button_states[idx].down = state == c.WL_POINTER_BUTTON_STATE_PRESSED;
        return;
    }
}

/// Accumulate scroll axes for quick visual confirmation.
fn pointerAxis(data: ?*anyopaque, _: ?*c.wl_pointer, _: u32, axis: u32, value: c.wl_fixed_t) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    const delta = c.wl_fixed_to_double(value);

    switch (axis) {
        c.WL_POINTER_AXIS_VERTICAL_SCROLL => app.scroll_y += delta,
        c.WL_POINTER_AXIS_HORIZONTAL_SCROLL => app.scroll_x += delta,
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
    defer std.posix.close(fd);

    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) return;

    const mapping = std.posix.mmap(
        null,
        size,
        std.posix.PROT.READ,
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
