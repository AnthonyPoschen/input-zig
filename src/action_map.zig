const std = @import("std");
const device = @import("device.zig");

pub const max_actions = 64;
pub const max_action_name_len = 32;
pub const max_bindings_per_action = 8;

pub const Binding = struct {
    device: *const device.DeviceView,
    code: device.InputCode,
};

pub const Action = struct {
    used: bool = false,
    name: [max_action_name_len]u8 = [_]u8{0} ** max_action_name_len,
    binding_count: usize = 0,
    default_binding: Binding,
    bindings: [max_bindings_per_action]Binding,
};

pub const ActionMap = struct {
    actions: [max_actions]Action = undefined,

    pub fn init() ActionMap {
        var out = ActionMap{};
        for (out.actions[0..]) |*action| {
            action.* = .{
                .default_binding = undefined,
                .bindings = undefined,
            };
        }
        return out;
    }

    pub fn createAction(self: *ActionMap, name: []const u8, default_binding: Binding) !void {
        const slot = self.findFree() orelse return error.ActionMapFull;
        if (name.len == 0 or name.len > max_action_name_len) return error.InvalidActionName;

        slot.used = true;
        @memset(slot.name[0..], 0);
        @memcpy(slot.name[0..name.len], name);
        slot.default_binding = default_binding;
        slot.binding_count = 1;
        slot.bindings[0] = default_binding;
    }

    pub fn bind(self: *ActionMap, name: []const u8, binding: Binding) !void {
        const action = self.findByName(name) orelse return error.ActionNotFound;
        if (action.binding_count >= max_bindings_per_action) return error.TooManyBindings;
        action.bindings[action.binding_count] = binding;
        action.binding_count += 1;
    }

    pub fn unbind(self: *ActionMap, name: []const u8, index: usize) !void {
        const action = self.findByName(name) orelse return error.ActionNotFound;
        if (index >= action.binding_count) return error.BindingNotFound;

        var i = index;
        while (i + 1 < action.binding_count) : (i += 1) {
            action.bindings[i] = action.bindings[i + 1];
        }
        action.binding_count -= 1;
    }

    pub fn reset(self: *ActionMap, name: []const u8) !void {
        const action = self.findByName(name) orelse return error.ActionNotFound;
        action.binding_count = 1;
        action.bindings[0] = action.default_binding;
    }

    pub fn resetAll(self: *ActionMap) void {
        for (self.actions[0..]) |*action| {
            if (!action.used) continue;
            action.binding_count = 1;
            action.bindings[0] = action.default_binding;
        }
    }

    pub fn down(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .down);
    }

    pub fn up(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .up);
    }

    pub fn press(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .press);
    }

    pub fn release(self: *const ActionMap, input_system: anytype, name: []const u8) bool {
        return self.eval(input_system, name, .release);
    }

    const Query = enum { down, up, press, release };

    fn eval(self: *const ActionMap, input_system: anytype, name: []const u8, query: Query) bool {
        const action = self.findByNameConst(name) orelse return false;
        var i: usize = 0;
        while (i < action.binding_count) : (i += 1) {
            if (bindingQuery(input_system, action.bindings[i], query)) return true;
        }
        return false;
    }

    fn bindingQuery(input_system: anytype, binding: Binding, query: Query) bool {
        const keyboard = input_system.keyboard();
        const mouse = input_system.mouse();

        if (binding.device == &keyboard.view) {
            return switch (query) {
                .down => keyboard.down(binding.code),
                .up => keyboard.up(binding.code),
                .press => keyboard.press(binding.code),
                .release => keyboard.release(binding.code),
            };
        }

        if (binding.device == &mouse.view) {
            return switch (query) {
                .down => mouse.down(binding.code),
                .up => mouse.up(binding.code),
                .press => mouse.press(binding.code),
                .release => mouse.release(binding.code),
            };
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
};

test "action map supports device pointers and press/release queries" {
    const fake_keyboard_view = device.DeviceView{ .id = 0, .kind = .keyboard, .connected = true, .name = [_]u8{0} ** device.max_name_len };

    var map = ActionMap.init();
    try map.createAction("jump", .{ .device = &fake_keyboard_view, .code = @enumFromInt(32) });
    try std.testing.expect(map.findByName("jump") != null);
}
