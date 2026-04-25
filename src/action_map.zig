const std = @import("std");
const device = @import("device.zig");

pub const max_actions = 64;
pub const max_action_name_len = 32;
pub const max_devices_per_map = 8;
pub const max_codes_per_action = 8;
pub const max_analog_codes_per_action = 4;

pub const ActionOptions = struct {
    axis_button_threshold: f32 = 0.5,
};

pub const Digital2dBinding = struct {
    left: ?device.InputCode = null,
    right: ?device.InputCode = null,
    up: ?device.InputCode = null,
    down: ?device.InputCode = null,
};

pub const Axis2dCompositeOptions = struct {
    normalize: bool = true,
};

const Query = enum { down, up, pressed, released };
const ActionKind = enum { codes, composite_2d };

pub const Action = struct {
    used: bool = false,
    enabled: bool = false,
    name: [max_action_name_len]u8 = [_]u8{0} ** max_action_name_len,
    kind: ActionKind = .codes,
    code_count: usize = 0,
    digital_2d: Digital2dBinding = .{},
    analog_count: usize = 0,
    analog_codes: [max_analog_codes_per_action]device.InputCode = undefined,
    composite_options: Axis2dCompositeOptions = .{},
    default_enabled: bool = false,
    default_kind: ActionKind = .codes,
    default_code_count: usize = 0,
    default_digital_2d: Digital2dBinding = .{},
    default_analog_count: usize = 0,
    default_analog_codes: [max_analog_codes_per_action]device.InputCode = undefined,
    default_composite_options: Axis2dCompositeOptions = .{},
    options: ActionOptions = .{},
    default_options: ActionOptions = .{},
    codes: [max_codes_per_action]device.InputCode = undefined,
    default_codes: [max_codes_per_action]device.InputCode = undefined,
};

pub const ActionMap = struct {
    devices: [max_devices_per_map]*const device.DeviceView = undefined,
    device_count: usize = 0,
    actions: [max_actions]Action = undefined,

    pub fn init() ActionMap {
        var out = ActionMap{};
        for (out.actions[0..]) |*action| {
            action.* = .{};
        }
        return out;
    }

    pub fn attachDevice(self: *ActionMap, input_device: anytype) !void {
        const view = deviceView(input_device);
        if (self.hasDevice(view)) return;
        if (self.device_count >= max_devices_per_map) return error.TooManyDevices;
        self.devices[self.device_count] = view;
        self.device_count += 1;
    }

    pub fn detachDevice(self: *ActionMap, input_device: anytype) bool {
        const view = deviceView(input_device);
        var i: usize = 0;
        while (i < self.device_count) : (i += 1) {
            if (self.devices[i] != view) continue;

            var j = i;
            while (j + 1 < self.device_count) : (j += 1) {
                self.devices[j] = self.devices[j + 1];
            }
            self.device_count -= 1;
            return true;
        }

        return false;
    }

    pub fn set(self: *ActionMap, name: []const u8, codes: ?[]const device.InputCode, options: ?ActionOptions) !void {
        const action = self.findByName(name) orelse try self.createSlot(name);

        if (codes) |value| {
            if (value.len == 0 or value.len > max_codes_per_action) return error.InvalidActionCodes;
            action.enabled = true;
            action.kind = .codes;
            action.code_count = value.len;
            action.options = normalizedOptions(options orelse .{});
            @memcpy(action.codes[0..value.len], value);

            action.default_enabled = true;
            action.default_kind = .codes;
            action.default_code_count = value.len;
            action.default_options = action.options;
            @memcpy(action.default_codes[0..value.len], value);
        } else {
            action.enabled = false;
            action.code_count = 0;
            if (options) |value| action.options = normalizedOptions(value);
        }
    }

    pub fn set2dComposite(
        self: *ActionMap,
        name: []const u8,
        digital: Digital2dBinding,
        analog_codes: []const device.InputCode,
        options: ?Axis2dCompositeOptions,
    ) !void {
        if (analog_codes.len > max_analog_codes_per_action) return error.InvalidActionCodes;

        const action = self.findByName(name) orelse try self.createSlot(name);
        action.enabled = true;
        action.kind = .composite_2d;
        action.digital_2d = digital;
        action.analog_count = analog_codes.len;
        action.composite_options = options orelse .{};
        if (analog_codes.len > 0) {
            @memcpy(action.analog_codes[0..analog_codes.len], analog_codes);
        }

        action.default_enabled = true;
        action.default_kind = .composite_2d;
        action.default_digital_2d = digital;
        action.default_analog_count = analog_codes.len;
        action.default_composite_options = action.composite_options;
        if (analog_codes.len > 0) {
            @memcpy(action.default_analog_codes[0..analog_codes.len], analog_codes);
        }
    }

    pub fn reset(self: *ActionMap, name: []const u8) !void {
        const action = self.findByName(name) orelse return error.ActionNotFound;
        action.enabled = action.default_enabled;
        action.kind = action.default_kind;
        action.code_count = action.default_code_count;
        action.digital_2d = action.default_digital_2d;
        action.analog_count = action.default_analog_count;
        action.composite_options = action.default_composite_options;
        action.options = action.default_options;
        if (action.default_code_count > 0) {
            @memcpy(action.codes[0..action.default_code_count], action.default_codes[0..action.default_code_count]);
        }
        if (action.default_analog_count > 0) {
            @memcpy(action.analog_codes[0..action.default_analog_count], action.default_analog_codes[0..action.default_analog_count]);
        }
    }

    pub fn resetAll(self: *ActionMap) void {
        for (self.actions[0..]) |*action| {
            if (!action.used) continue;
            action.enabled = action.default_enabled;
            action.kind = action.default_kind;
            action.code_count = action.default_code_count;
            action.digital_2d = action.default_digital_2d;
            action.analog_count = action.default_analog_count;
            action.composite_options = action.default_composite_options;
            action.options = action.default_options;
            if (action.default_code_count > 0) {
                @memcpy(action.codes[0..action.default_code_count], action.default_codes[0..action.default_code_count]);
            }
            if (action.default_analog_count > 0) {
                @memcpy(action.analog_codes[0..action.default_analog_count], action.default_analog_codes[0..action.default_analog_count]);
            }
        }
    }

    pub fn remove(self: *ActionMap, name: []const u8) bool {
        var i: usize = 0;
        while (i < self.actions.len) : (i += 1) {
            if (!self.actions[i].used) continue;
            if (!std.mem.eql(u8, cString(self.actions[i].name[0..]), name)) continue;
            self.actions[i] = .{};
            return true;
        }
        return false;
    }

    pub fn down(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .down);
    }

    pub fn up(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .up);
    }

    pub fn pressed(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .pressed);
    }

    pub fn released(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .released);
    }

    pub fn axis1d(self: *const ActionMap, input_system: anytype, name: []const u8) f32 {
        const action = self.findByNameConst(name) orelse return 0;
        if (!action.enabled) return 0;
        if (action.kind != .codes) return 0;

        var out: f32 = 0;
        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            var code_index: usize = 0;
            while (code_index < action.code_count) : (code_index += 1) {
                out += deviceAxis1d(input_system, self.devices[device_index], action.codes[code_index]) orelse 0;
            }
        }
        return clamp(out, -1, 1);
    }

    pub fn axis2d(self: *const ActionMap, input_system: anytype, name: []const u8) device.Axis2d {
        const action = self.findByNameConst(name) orelse return .{ .x = 0, .y = 0 };
        if (!action.enabled) return .{ .x = 0, .y = 0 };

        if (action.kind == .composite_2d) {
            return evalComposite2d(self, input_system, action);
        }

        var out = device.Axis2d{ .x = 0, .y = 0 };
        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            var code_index: usize = 0;
            while (code_index < action.code_count) : (code_index += 1) {
                if (deviceAxis2d(input_system, self.devices[device_index], action.codes[code_index])) |value| {
                    out.x += value.x;
                    out.y += value.y;
                }
            }
        }
        out.x = clamp(out.x, -1, 1);
        out.y = clamp(out.y, -1, 1);
        return out;
    }

    fn eval(self: *const ActionMap, input_system: anytype, name: []const u8, query: Query) bool {
        const action = self.findByNameConst(name) orelse return false;
        if (!action.enabled) return false;
        if (action.kind != .codes) return false;

        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            var code_index: usize = 0;
            while (code_index < action.code_count) : (code_index += 1) {
                if (deviceCodeQuery(input_system, self.devices[device_index], action.codes[code_index], query, action.options)) return true;
            }
        }
        return false;
    }

    fn deviceCodeQuery(input_system: anytype, view: *const device.DeviceView, code: device.InputCode, query: Query, options: ActionOptions) bool {
        const keyboard = input_system.keyboard();
        const mouse = input_system.mouse();

        if (view == &keyboard.view) {
            return buttonQuery(keyboard.button(code), keyboard.prevButton(code), query);
        }

        if (view == &mouse.view) {
            return buttonQuery(mouse.button(code), mouse.prevButton(code), query);
        }

        var slot: usize = 0;
        while (input_system.gamepad(slot)) |gamepad| : (slot += 1) {
            if (view != &gamepad.view) continue;
            if (axisButtonQuery(gamepad.axis1d(code), gamepad.prevAxis1d(code), query, options)) return true;
            return buttonQuery(gamepad.button(code), gamepad.prevButton(code), query);
        }

        return false;
    }

    fn deviceAxis1d(input_system: anytype, view: *const device.DeviceView, code: device.InputCode) ?f32 {
        const keyboard = input_system.keyboard();
        const mouse = input_system.mouse();

        if (view == &keyboard.view) return keyboard.axis1d(code);
        if (view == &mouse.view) return mouse.axis1d(code);

        var slot: usize = 0;
        while (input_system.gamepad(slot)) |gamepad| : (slot += 1) {
            if (view == &gamepad.view) return gamepad.axis1d(code);
        }

        return null;
    }

    fn deviceAxis2d(input_system: anytype, view: *const device.DeviceView, code: device.InputCode) ?device.Axis2d {
        var slot: usize = 0;
        while (input_system.gamepad(slot)) |gamepad| : (slot += 1) {
            if (view == &gamepad.view) return gamepad.axis2d(code);
        }

        return null;
    }

    fn createSlot(self: *ActionMap, name: []const u8) !*Action {
        if (name.len == 0 or name.len > max_action_name_len) return error.InvalidActionName;
        const slot = self.findFree() orelse return error.ActionMapFull;
        slot.* = .{ .used = true };
        @memcpy(slot.name[0..name.len], name);
        return slot;
    }

    fn hasDevice(self: *const ActionMap, view: *const device.DeviceView) bool {
        var i: usize = 0;
        while (i < self.device_count) : (i += 1) {
            if (self.devices[i] == view) return true;
        }
        return false;
    }

    fn findFree(self: *ActionMap) ?*Action {
        for (self.actions[0..]) |*action| {
            if (!action.used) return action;
        }
        return null;
    }

    fn findByName(self: *ActionMap, name: []const u8) ?*Action {
        for (self.actions[0..]) |*action| {
            if (!action.used) continue;
            if (std.mem.eql(u8, cString(action.name[0..]), name)) return action;
        }
        return null;
    }

    fn findByNameConst(self: *const ActionMap, name: []const u8) ?*const Action {
        for (self.actions[0..]) |*action| {
            if (!action.used) continue;
            if (std.mem.eql(u8, cString(action.name[0..]), name)) return action;
        }
        return null;
    }

    fn cString(bytes: []const u8) []const u8 {
        var end: usize = 0;
        while (end < bytes.len and bytes[end] != 0) : (end += 1) {}
        return bytes[0..end];
    }

    fn evalComposite2d(self: *const ActionMap, input_system: anytype, action: *const Action) device.Axis2d {
        var out = device.Axis2d{ .x = 0, .y = 0 };

        if (action.digital_2d.left) |code| {
            if (self.codeDown(input_system, code)) out.x -= 1;
        }
        if (action.digital_2d.right) |code| {
            if (self.codeDown(input_system, code)) out.x += 1;
        }
        if (action.digital_2d.up) |code| {
            if (self.codeDown(input_system, code)) out.y += 1;
        }
        if (action.digital_2d.down) |code| {
            if (self.codeDown(input_system, code)) out.y -= 1;
        }

        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            var analog_index: usize = 0;
            while (analog_index < action.analog_count) : (analog_index += 1) {
                if (deviceAxis2d(input_system, self.devices[device_index], action.analog_codes[analog_index])) |value| {
                    out.x += value.x;
                    out.y += value.y;
                }
            }
        }

        if (action.composite_options.normalize) {
            const len_sq = out.x * out.x + out.y * out.y;
            if (len_sq > 1) {
                const len = @sqrt(len_sq);
                out.x /= len;
                out.y /= len;
            }
        }

        return out;
    }

    fn codeDown(self: *const ActionMap, input_system: anytype, code: device.InputCode) bool {
        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            if (deviceCodeQuery(input_system, self.devices[device_index], code, .down, .{})) return true;
        }
        return false;
    }
};

fn axisButtonQuery(current: ?f32, previous: ?f32, query: Query, options: ActionOptions) bool {
    const value = current orelse return false;
    const threshold = options.axis_button_threshold;
    return switch (query) {
        .down => value > threshold,
        .up => value <= threshold,
        .pressed => blk: {
            const prev = previous orelse return false;
            break :blk prev <= threshold and value > threshold;
        },
        .released => blk: {
            const prev = previous orelse return false;
            break :blk prev > threshold and value <= threshold;
        },
    };
}

fn buttonQuery(current: ?bool, previous: ?bool, query: Query) bool {
    const value = current orelse return false;
    return switch (query) {
        .down => value,
        .up => !value,
        .pressed => blk: {
            const prev = previous orelse return false;
            break :blk !prev and value;
        },
        .released => blk: {
            const prev = previous orelse return false;
            break :blk prev and !value;
        },
    };
}

fn normalizedOptions(options: ActionOptions) ActionOptions {
    return .{
        .axis_button_threshold = clamp(options.axis_button_threshold, 0, 1),
    };
}

fn clamp(value: f32, min: f32, max: f32) f32 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

fn deviceView(input_device: anytype) *const device.DeviceView {
    const ptr = @typeInfo(@TypeOf(input_device)).pointer;
    if (ptr.child == device.DeviceView) return input_device;
    return &input_device.view;
}

test "action map set attaches devices and stores action codes" {
    const fake_keyboard = device.KeyboardDevice{};

    var map = ActionMap.init();
    try map.attachDevice(fake_keyboard);
    try map.set("jump", &.{.key_space}, null);

    const action = map.findByName("jump") orelse return error.ActionNotFound;
    try std.testing.expectEqual(@as(usize, 1), map.device_count);
    try std.testing.expect(action.enabled);
    try std.testing.expectEqual(@as(usize, 1), action.code_count);
}

test "action map evaluates codes against attached devices" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var keyboard_map = ActionMap.init();
    var gamepad_map = ActionMap.init();

    try keyboard_map.attachDevice(input_system.keyboard());
    try keyboard_map.set("jump", &.{ .key_space, .gamepad_face_south }, null);

    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try gamepad_map.attachDevice(gamepad);
    try gamepad_map.set("jump", &.{ .key_space, .gamepad_face_south }, null);

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_space)] = .down;
    gamepad.buttons[0] = .down;

    try std.testing.expect(keyboard_map.down(&input_system, "jump"));
    try std.testing.expect(gamepad_map.down(&input_system, "jump"));

    _ = keyboard_map.detachDevice(input_system.keyboard());
    try std.testing.expect(!keyboard_map.down(&input_system, "jump"));
}

test "action map set null disables reset restores and remove deletes" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    try map.set("jump", &.{.key_space}, null);
    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_space)] = .down;

    try std.testing.expect(map.down(&input_system, "jump"));
    try map.set("jump", null, null);
    try std.testing.expect(!map.down(&input_system, "jump"));

    try map.reset("jump");
    try std.testing.expect(map.down(&input_system, "jump"));

    try std.testing.expect(map.remove("jump"));
    try std.testing.expect(!map.down(&input_system, "jump"));
}

test "action map combines buttons and directional axes" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set("forward", &.{ .key_w, .gamepad_left_stick_up }, null);

    gamepad.left_stick.y = 0.75;
    try std.testing.expect(map.down(&input_system, "forward"));
    try std.testing.expectEqual(@as(f32, 0.75), map.axis1d(&input_system, "forward"));

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_w)] = .down;
    try std.testing.expectEqual(@as(f32, 1), map.axis1d(&input_system, "forward"));

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_w)] = .up;
    gamepad.prev_left_stick.y = 0.25;
    gamepad.left_stick.y = 0.75;
    try std.testing.expect(map.pressed(&input_system, "forward"));
}

test "action map combines axis2d values" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set("move", &.{ .gamepad_left_stick, .gamepad_right_stick }, null);

    gamepad.left_stick = .{ .x = 0.25, .y = 0.5 };
    gamepad.right_stick = .{ .x = 0.9, .y = -0.25 };

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, 1), move.x);
    try std.testing.expectEqual(@as(f32, 0.25), move.y);
}

test "action map composite 2d combines keyboard and stick" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set2dComposite("move", .{
        .left = .key_a,
        .right = .key_d,
        .up = .key_w,
        .down = .key_s,
    }, &.{.gamepad_left_stick}, .{ .normalize = false });

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_d)] = .down;
    gamepad.left_stick = .{ .x = -0.25, .y = 0.5 };

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, 0.75), move.x);
    try std.testing.expectEqual(@as(f32, 0.5), move.y);
}

test "action map composite 2d normalizes diagonals" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    try map.set2dComposite("move", .{
        .right = .key_d,
        .up = .key_w,
    }, &.{}, .{ .normalize = true });

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_d)] = .down;
    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_w)] = .down;

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710677), move.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710677), move.y, 0.0001);
}

test "action map axis button threshold is configurable per action" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set("forward", &.{.gamepad_left_stick_up}, .{ .axis_button_threshold = 0.25 });

    gamepad.prev_left_stick.y = 0.2;
    gamepad.left_stick.y = 0.3;

    try std.testing.expect(map.down(&input_system, "forward"));
    try std.testing.expect(map.pressed(&input_system, "forward"));
}

test "action map up ignores incompatible codes" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    try map.set("move", &.{.gamepad_left_stick}, null);

    try std.testing.expect(!map.up(&input_system, "move"));
}

test "gamepad deadzone clips axis query values" {
    var gamepad = device.GamepadDevice.init(0);
    gamepad.left_stick = .{ .x = 0.1, .y = 0.3 };
    gamepad.right_stick = .{ .x = 0.1, .y = 0.3 };
    gamepad.left_trigger_value = 0.1;
    gamepad.right_trigger_value = 0.1;
    try gamepad.setDeadzone(.gamepad_left_stick, 0.2);
    gamepad.setRightStickDeadzone(0.05);
    gamepad.setLeftTriggerDeadzone(0.2);
    try gamepad.setDeadzone(.gamepad_right_trigger, 0.05);

    const left = gamepad.leftStick();
    const right = gamepad.rightStick();
    try std.testing.expectEqual(@as(f32, 0), left.x);
    try std.testing.expectEqual(@as(f32, 0.3), left.y);
    try std.testing.expectEqual(@as(f32, 0.1), right.x);
    try std.testing.expectEqual(@as(f32, 0.3), right.y);
    try std.testing.expectEqual(@as(f32, 0), gamepad.leftTrigger());
    try std.testing.expectEqual(@as(f32, 0.1), gamepad.rightTrigger());
}
