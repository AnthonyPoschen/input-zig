const std = @import("std");
const device = @import("device.zig");

pub const max_actions = 64;
pub const max_action_name_len = 32;
pub const max_devices_per_map = 8;
pub const max_codes_per_action = 8;
pub const max_codes_per_2d_direction = 4;
pub const max_vectors_per_action = 4;

pub const ActionOptions = struct {
    axis_button_threshold: f32 = 0.5,
};

pub const AttachOptions = struct {
    keyboard: bool = false,
    mouse: bool = false,
    gamepad_slot: ?usize = null,
};

pub const Action2dBinding = struct {
    left: ?[]const device.InputCode = null,
    right: ?[]const device.InputCode = null,
    up: ?[]const device.InputCode = null,
    down: ?[]const device.InputCode = null,
    vectors: ?[]const device.InputCode = null,
};

const Query = enum { down, up, pressed, released };
pub const ActionKind = enum { codes, axis_2d };

pub const BindingSlot = enum {
    code,
    left,
    right,
    up,
    down,
    vector,
};

pub const BindingConflict = struct {
    action_name: []const u8,
    slot: BindingSlot,
    index: usize = 0,
};

pub const ActionBinding = struct {
    name: []const u8,
    enabled: bool = true,
    kind: ActionKind = .codes,
    options: ActionOptions = .{},
    codes: ?[]const device.InputCode = null,
    left: ?[]const device.InputCode = null,
    right: ?[]const device.InputCode = null,
    up: ?[]const device.InputCode = null,
    down: ?[]const device.InputCode = null,
    vectors: ?[]const device.InputCode = null,
};

pub const Action = struct {
    used: bool = false,
    enabled: bool = false,
    name: [max_action_name_len]u8 = [_]u8{0} ** max_action_name_len,
    kind: ActionKind = .codes,
    code_count: usize = 0,
    left_count: usize = 0,
    right_count: usize = 0,
    up_count: usize = 0,
    down_count: usize = 0,
    vector_count: usize = 0,
    left_codes: [max_codes_per_2d_direction]device.InputCode = undefined,
    right_codes: [max_codes_per_2d_direction]device.InputCode = undefined,
    up_codes: [max_codes_per_2d_direction]device.InputCode = undefined,
    down_codes: [max_codes_per_2d_direction]device.InputCode = undefined,
    vector_codes: [max_vectors_per_action]device.InputCode = undefined,
    options: ActionOptions = .{},
    codes: [max_codes_per_action]device.InputCode = undefined,
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

    pub fn attachDevices(self: *ActionMap, input_system: anytype, options: AttachOptions) !void {
        if (options.keyboard) try self.attachDevice(input_system.keyboard());
        if (options.mouse) try self.attachDevice(input_system.mouse());
        if (options.gamepad_slot) |slot| {
            const gamepad = input_system.gamepad(slot) orelse return error.InvalidGamepadSlot;
            try self.attachDevice(gamepad);
        }
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
        } else {
            action.enabled = false;
            action.code_count = 0;
            if (options) |value| action.options = normalizedOptions(value);
        }
    }

    pub fn set2d(self: *ActionMap, name: []const u8, binding: Action2dBinding, options: ?ActionOptions) !void {
        const action = self.findByName(name) orelse try self.createSlot(name);

        action.left_count = try copyBindingCodes(
            action.left_codes[0..],
            binding.left,
        );
        action.right_count = try copyBindingCodes(
            action.right_codes[0..],
            binding.right,
        );
        action.up_count = try copyBindingCodes(
            action.up_codes[0..],
            binding.up,
        );
        action.down_count = try copyBindingCodes(
            action.down_codes[0..],
            binding.down,
        );
        action.vector_count = try copyBindingCodes(
            action.vector_codes[0..],
            binding.vectors,
        );

        if (action.left_count == 0 and
            action.right_count == 0 and
            action.up_count == 0 and
            action.down_count == 0 and
            action.vector_count == 0)
        {
            return error.InvalidActionCodes;
        }

        action.enabled = true;
        action.kind = .axis_2d;
        action.options = normalizedOptions(options orelse .{});
    }

    pub fn reset(self: *ActionMap, name: []const u8, defaults: *const ActionMap) !void {
        const default_action = defaults.findByNameConst(name) orelse return error.ActionNotFound;
        const action = self.findByName(name) orelse try self.createSlot(name);
        copyAction(action, default_action);
    }

    pub fn resetAll(self: *ActionMap, defaults: *const ActionMap) !void {
        if (self == defaults) return;

        for (&self.actions) |*action| {
            action.* = .{};
        }

        for (defaults.actions[0..]) |*default_action| {
            if (!default_action.used) continue;
            const action = self.findByName(cString(default_action.name[0..])) orelse try self.createSlot(cString(default_action.name[0..]));
            copyAction(action, default_action);
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

    pub fn actionCount(self: *const ActionMap) usize {
        var count: usize = 0;
        for (self.actions[0..]) |*action| {
            if (action.used) count += 1;
        }
        return count;
    }

    pub fn copyBindings(self: *const ActionMap, out: []ActionBinding) usize {
        var count: usize = 0;
        for (self.actions[0..]) |*action| {
            if (!action.used) continue;
            if (count >= out.len) break;
            out[count] = actionBinding(action);
            count += 1;
        }
        return count;
    }

    pub fn exportBindings(self: *const ActionMap, out: []ActionBinding) usize {
        return self.copyBindings(out);
    }

    pub fn replaceBindings(self: *ActionMap, bindings: []const ActionBinding) !void {
        if (bindings.len > max_actions) return error.ActionMapFull;

        for (&self.actions) |*action| {
            action.* = .{};
        }

        for (bindings) |binding| {
            try self.applyBinding(binding);
        }
    }

    pub fn importBindings(self: *ActionMap, bindings: []const ActionBinding) !void {
        try self.replaceBindings(bindings);
    }

    pub fn actionCodes(self: *const ActionMap, name: []const u8) ?[]const device.InputCode {
        const action = self.findByNameConst(name) orelse return null;
        if (!action.enabled or action.kind != .codes) return null;
        return action.codes[0..action.code_count];
    }

    pub fn action2d(self: *const ActionMap, name: []const u8) ?Action2dBinding {
        const action = self.findByNameConst(name) orelse return null;
        if (!action.enabled or action.kind != .axis_2d) return null;
        return .{
            .left = sliceIfAny(action.left_codes[0..], action.left_count),
            .right = sliceIfAny(action.right_codes[0..], action.right_count),
            .up = sliceIfAny(action.up_codes[0..], action.up_count),
            .down = sliceIfAny(action.down_codes[0..], action.down_count),
            .vectors = sliceIfAny(
                action.vector_codes[0..],
                action.vector_count,
            ),
        };
    }

    pub fn findConflict(self: *const ActionMap, code: device.InputCode, ignore_action: ?[]const u8) ?BindingConflict {
        for (self.actions[0..]) |*action| {
            if (!action.used or !action.enabled) continue;
            const action_name = cString(action.name[0..]);
            if (ignore_action) |ignored| {
                if (std.mem.eql(u8, action_name, ignored)) continue;
            }

            switch (action.kind) {
                .codes => {
                    for (action.codes[0..action.code_count], 0..) |bound_code, index| {
                        if (bound_code == code) return .{ .action_name = action_name, .slot = .code, .index = index };
                    }
                },
                .axis_2d => {
                    if (findCode(action.left_codes[0..action.left_count], code)) |index| {
                        return .{ .action_name = action_name, .slot = .left, .index = index };
                    }
                    if (findCode(action.right_codes[0..action.right_count], code)) |index| {
                        return .{ .action_name = action_name, .slot = .right, .index = index };
                    }
                    if (findCode(action.up_codes[0..action.up_count], code)) |index| {
                        return .{ .action_name = action_name, .slot = .up, .index = index };
                    }
                    if (findCode(action.down_codes[0..action.down_count], code)) |index| {
                        return .{ .action_name = action_name, .slot = .down, .index = index };
                    }
                    if (findCode(action.vector_codes[0..action.vector_count], code)) |index| {
                        return .{ .action_name = action_name, .slot = .vector, .index = index };
                    }
                },
            }
        }
        return null;
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

    pub fn axis1d(self: *const ActionMap, input_system: anytype, name: []const u8) device.Axis1d {
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

        if (action.kind == .axis_2d) {
            return evalAction2d(self, input_system, action);
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
            return buttonQuery(
                gamepad.buttonWithThreshold(code, options.axis_button_threshold),
                gamepad.prevButtonWithThreshold(code, options.axis_button_threshold),
                query,
            );
        }

        return false;
    }

    fn deviceAxis1d(input_system: anytype, view: *const device.DeviceView, code: device.InputCode) ?device.Axis1d {
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

    fn applyBinding(self: *ActionMap, binding: ActionBinding) !void {
        if (binding.name.len == 0 or binding.name.len > max_action_name_len) return error.InvalidActionName;
        const action = self.findByName(binding.name) orelse try self.createSlot(binding.name);
        action.enabled = binding.enabled;
        action.kind = binding.kind;
        action.options = normalizedOptions(binding.options);
        action.code_count = 0;
        action.left_count = 0;
        action.right_count = 0;
        action.up_count = 0;
        action.down_count = 0;
        action.vector_count = 0;

        switch (binding.kind) {
            .codes => {
                if (binding.enabled) {
                    const codes = binding.codes orelse return error.InvalidActionCodes;
                    if (codes.len == 0 or codes.len > max_codes_per_action) return error.InvalidActionCodes;
                    action.code_count = codes.len;
                    @memcpy(action.codes[0..codes.len], codes);
                }
            },
            .axis_2d => {
                if (binding.enabled) {
                    action.left_count = try copyBindingCodes(action.left_codes[0..], binding.left);
                    action.right_count = try copyBindingCodes(action.right_codes[0..], binding.right);
                    action.up_count = try copyBindingCodes(action.up_codes[0..], binding.up);
                    action.down_count = try copyBindingCodes(action.down_codes[0..], binding.down);
                    action.vector_count = try copyBindingCodes(action.vector_codes[0..], binding.vectors);
                    if (action.left_count == 0 and
                        action.right_count == 0 and
                        action.up_count == 0 and
                        action.down_count == 0 and
                        action.vector_count == 0)
                    {
                        return error.InvalidActionCodes;
                    }
                }
            },
        }
    }

    fn evalAction2d(self: *const ActionMap, input_system: anytype, action: *const Action) device.Axis2d {
        var out = device.Axis2d{ .x = 0, .y = 0 };

        out.x -= activeCodeValue(
            self,
            input_system,
            action.left_codes[0..action.left_count],
            action.options,
        );
        out.x += activeCodeValue(
            self,
            input_system,
            action.right_codes[0..action.right_count],
            action.options,
        );
        out.y += activeCodeValue(
            self,
            input_system,
            action.up_codes[0..action.up_count],
            action.options,
        );
        out.y -= activeCodeValue(
            self,
            input_system,
            action.down_codes[0..action.down_count],
            action.options,
        );

        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            var vector_index: usize = 0;
            while (vector_index < action.vector_count) : (vector_index += 1) {
                if (deviceAxis2d(input_system, self.devices[device_index], action.vector_codes[vector_index])) |value| {
                    out.x += value.x;
                    out.y += value.y;
                }
            }
        }

        out.x = clamp(out.x, -1, 1);
        out.y = clamp(out.y, -1, 1);

        return out;
    }

    fn codeDown(
        self: *const ActionMap,
        input_system: anytype,
        code: device.InputCode,
        options: ActionOptions,
    ) bool {
        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            if (deviceCodeQuery(
                input_system,
                self.devices[device_index],
                code,
                .down,
                options,
            )) return true;
        }
        return false;
    }

    fn codeValue(
        self: *const ActionMap,
        input_system: anytype,
        code: device.InputCode,
        options: ActionOptions,
    ) device.Axis1d {
        var out: device.Axis1d = 0;
        var device_index: usize = 0;
        while (device_index < self.device_count) : (device_index += 1) {
            const value = deviceAxis1d(
                input_system,
                self.devices[device_index],
                code,
            ) orelse continue;

            if (value > out) out = value;
        }

        if (out <= options.axis_button_threshold) return 0;
        return clamp(out, 0, 1);
    }
};

fn cString(bytes: []const u8) []const u8 {
    var end: usize = 0;
    while (end < bytes.len and bytes[end] != 0) : (end += 1) {}
    return bytes[0..end];
}

fn copyAction(out: *Action, source: *const Action) void {
    const name = cString(source.name[0..]);
    out.* = .{ .used = true };
    @memcpy(out.name[0..name.len], name);
    out.enabled = source.enabled;
    out.kind = source.kind;
    out.code_count = source.code_count;
    out.left_count = source.left_count;
    out.right_count = source.right_count;
    out.up_count = source.up_count;
    out.down_count = source.down_count;
    out.vector_count = source.vector_count;
    out.options = source.options;
    if (source.code_count > 0) {
        @memcpy(out.codes[0..source.code_count], source.codes[0..source.code_count]);
    }
    if (source.left_count > 0) {
        @memcpy(
            out.left_codes[0..source.left_count],
            source.left_codes[0..source.left_count],
        );
    }
    if (source.right_count > 0) {
        @memcpy(
            out.right_codes[0..source.right_count],
            source.right_codes[0..source.right_count],
        );
    }
    if (source.up_count > 0) {
        @memcpy(
            out.up_codes[0..source.up_count],
            source.up_codes[0..source.up_count],
        );
    }
    if (source.down_count > 0) {
        @memcpy(
            out.down_codes[0..source.down_count],
            source.down_codes[0..source.down_count],
        );
    }
    if (source.vector_count > 0) {
        @memcpy(
            out.vector_codes[0..source.vector_count],
            source.vector_codes[0..source.vector_count],
        );
    }
}

fn actionBinding(action: *const Action) ActionBinding {
    return .{
        .name = cString(action.name[0..]),
        .enabled = action.enabled,
        .kind = action.kind,
        .options = action.options,
        .codes = if (action.kind == .codes) sliceIfAny(action.codes[0..], action.code_count) else null,
        .left = if (action.kind == .axis_2d) sliceIfAny(action.left_codes[0..], action.left_count) else null,
        .right = if (action.kind == .axis_2d) sliceIfAny(action.right_codes[0..], action.right_count) else null,
        .up = if (action.kind == .axis_2d) sliceIfAny(action.up_codes[0..], action.up_count) else null,
        .down = if (action.kind == .axis_2d) sliceIfAny(action.down_codes[0..], action.down_count) else null,
        .vectors = if (action.kind == .axis_2d) sliceIfAny(action.vector_codes[0..], action.vector_count) else null,
    };
}

fn copyBindingCodes(dst: []device.InputCode, src: ?[]const device.InputCode) !usize {
    const codes = src orelse return 0;
    if (codes.len == 0 or codes.len > dst.len) return error.InvalidActionCodes;
    @memcpy(dst[0..codes.len], codes);
    return codes.len;
}

fn sliceIfAny(codes: []const device.InputCode, count: usize) ?[]const device.InputCode {
    if (count == 0) return null;
    return codes[0..count];
}

fn findCode(codes: []const device.InputCode, needle: device.InputCode) ?usize {
    for (codes, 0..) |code, index| {
        if (code == needle) return index;
    }
    return null;
}

fn activeCodeValue(self: *const ActionMap, input_system: anytype, codes: []const device.InputCode, options: ActionOptions) f32 {
    var out: f32 = 0;
    for (codes) |code| {
        const value = self.codeValue(input_system, code, options);
        if (value > out) out = value;
    }
    return out;
}

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
    var defaults = ActionMap.init();
    var map = ActionMap.init();

    try defaults.set("jump", &.{.key_space}, null);
    try map.attachDevice(input_system.keyboard());
    try map.reset("jump", &defaults);
    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_space)] = .down;

    try std.testing.expect(map.down(&input_system, "jump"));
    try map.set("jump", null, null);
    try std.testing.expect(!map.down(&input_system, "jump"));

    try map.reset("jump", &defaults);
    try std.testing.expect(map.down(&input_system, "jump"));

    try std.testing.expect(map.remove("jump"));
    try std.testing.expect(!map.down(&input_system, "jump"));
}

test "action map reset all copies actions from default map" {
    var defaults = ActionMap.init();
    var map = ActionMap.init();

    try defaults.set("jump", &.{.key_space}, null);
    try defaults.set2d("move", .{
        .left = &.{.key_a},
        .right = &.{.key_d},
        .vectors = &.{.gamepad_left_stick},
    }, null);

    try map.set("jump", &.{.key_j}, null);
    try map.set("extra", &.{.key_escape}, null);
    try map.resetAll(&defaults);

    try std.testing.expectEqual(@as(usize, 2), map.actionCount());
    try std.testing.expectEqual(device.InputCode.key_space, map.actionCodes("jump").?[0]);
    try std.testing.expect(map.actionCodes("extra") == null);
    try std.testing.expectEqual(device.InputCode.key_a, map.action2d("move").?.left.?[0]);
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

test "action map 2d action combines keyboard and stick" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set2d("move", .{
        .left = &.{.key_a},
        .right = &.{.key_d},
        .up = &.{.key_w},
        .down = &.{.key_s},
        .vectors = &.{.gamepad_left_stick},
    }, null);

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_d)] = .down;
    gamepad.left_stick = .{ .x = -0.5, .y = 0.5 };

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, 0.5), move.x);
    try std.testing.expectEqual(@as(f32, 0.5), move.y);
}

test "action map 2d action keeps analog directional magnitude" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set2d("move", .{
        .left = &.{.gamepad_right_stick_left},
        .right = &.{.gamepad_right_stick_right},
        .up = &.{.gamepad_left_stick_up},
        .down = &.{.gamepad_left_stick_down},
    }, .{ .axis_button_threshold = 0.1 });

    gamepad.left_stick = .{ .x = 0, .y = 0.6 };
    gamepad.right_stick = .{ .x = -0.25, .y = 0 };

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, -0.25), move.x);
    try std.testing.expectEqual(@as(f32, 0.6), move.y);
}

test "action map 2d action uses strongest code per direction" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set2d("move", .{
        .up = &.{ .key_w, .gamepad_left_stick_up },
    }, .{ .axis_button_threshold = 0.1 });

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_w)] = .down;
    gamepad.left_stick = .{ .x = 0, .y = 0.4 };

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, 1), move.y);
}

test "action map 2d action threshold zeros weak directional axis" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);
    try map.set2d("move", .{
        .up = &.{.gamepad_left_stick_up},
    }, .{ .axis_button_threshold = 0.35 });

    gamepad.left_stick = .{ .x = 0, .y = 0.3 };

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, 0), move.y);
}

test "action map 2d action preserves digital diagonals" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();

    try map.attachDevice(input_system.keyboard());
    try map.set2d("move", .{
        .right = &.{.key_d},
        .up = &.{.key_w},
    }, null);

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_d)] = .down;
    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_w)] = .down;

    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, 1), move.x);
    try std.testing.expectEqual(@as(f32, 1), move.y);
}

test "action map exports bindings for save load" {
    var map = ActionMap.init();
    var out: [max_actions]ActionBinding = undefined;

    try map.set("jump", &.{ .key_space, .gamepad_face_south }, null);
    try map.set2d("move", .{
        .left = &.{.key_a},
        .right = &.{.key_d},
        .up = &.{.key_w},
        .down = &.{.key_s},
        .vectors = &.{.gamepad_left_stick},
    }, null);

    const count = map.exportBindings(out[0..]);
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("jump", out[0].name);
    try std.testing.expectEqual(ActionKind.codes, out[0].kind);
    try std.testing.expectEqual(device.InputCode.gamepad_face_south, out[0].codes.?[1]);
    try std.testing.expectEqual(ActionKind.axis_2d, out[1].kind);
    try std.testing.expectEqual(device.InputCode.key_s, out[1].down.?[0]);
}

test "action map imports bindings from saved data" {
    const input = @import("input.zig");

    var input_system = input.InputSystem{};
    var map = ActionMap.init();
    const bindings = [_]ActionBinding{
        .{
            .name = "jump",
            .kind = .codes,
            .codes = &.{ .key_space, .gamepad_face_south },
        },
        .{
            .name = "move",
            .kind = .axis_2d,
            .left = &.{.key_a},
            .right = &.{.key_d},
            .up = &.{.key_w},
            .down = &.{.key_s},
            .vectors = &.{.gamepad_left_stick},
        },
    };

    try map.importBindings(bindings[0..]);
    try map.attachDevice(input_system.keyboard());
    const gamepad = input_system.gamepad(0) orelse return error.MissingGamepadSlot;
    try map.attachDevice(gamepad);

    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_space)] = .down;
    input_system.keyboard_device.keys[@intFromEnum(device.InputCode.key_d)] = .down;
    gamepad.left_stick = .{ .x = -0.25, .y = 0.5 };

    try std.testing.expect(map.down(&input_system, "jump"));
    const move = map.axis2d(&input_system, "move");
    try std.testing.expectEqual(@as(f32, 0.75), move.x);
    try std.testing.expectEqual(@as(f32, 0.5), move.y);
}

test "action map finds binding conflicts" {
    var map = ActionMap.init();

    try map.set("jump", &.{ .key_space, .gamepad_face_south }, null);
    try map.set2d("move", .{
        .left = &.{.key_a},
        .right = &.{.key_d},
        .vectors = &.{.gamepad_left_stick},
    }, null);

    const jump_conflict = map.findConflict(.key_space, null) orelse return error.MissingConflict;
    try std.testing.expectEqualStrings("jump", jump_conflict.action_name);
    try std.testing.expectEqual(BindingSlot.code, jump_conflict.slot);
    try std.testing.expectEqual(@as(usize, 0), jump_conflict.index);

    const move_conflict = map.findConflict(.key_a, null) orelse return error.MissingConflict;
    try std.testing.expectEqualStrings("move", move_conflict.action_name);
    try std.testing.expectEqual(BindingSlot.left, move_conflict.slot);

    try std.testing.expect(map.findConflict(.key_space, "jump") == null);
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
