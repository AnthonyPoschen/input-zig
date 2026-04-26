const std = @import("std");

const common = @import("device/common.zig");
const gamepad = @import("device/gamepad.zig");
const input_code = @import("device/input_code.zig");
const keyboard = @import("device/keyboard.zig");
const mouse = @import("device/mouse.zig");

pub const max_name_len = common.max_name_len;
pub const max_keys = common.max_keys;
pub const max_mouse_buttons = common.max_mouse_buttons;
pub const max_gamepads = common.max_gamepads;
pub const max_gamepad_buttons = common.max_gamepad_buttons;
pub const first_gamepad_id = common.first_gamepad_id;

pub const Axis1d = common.Axis1d;
pub const Axis2d = common.Axis2d;
pub const ButtonState = common.ButtonState;
pub const DeviceKind = common.DeviceKind;
pub const DeviceView = common.DeviceView;
pub const WindowRect = common.WindowRect;

pub const GamepadDevice = gamepad.GamepadDevice;
pub const GamepadIdentity = gamepad.GamepadIdentity;
pub const GamepadStick = gamepad.GamepadStick;
pub const InputCode = input_code.InputCode;
pub const inputCodeLabel = input_code.inputCodeLabel;
pub const inputCodeName = input_code.inputCodeName;
pub const parseInputCode = input_code.parseInputCode;
pub const KeyboardDevice = keyboard.KeyboardDevice;
pub const MouseCoordinateSpace = mouse.MouseCoordinateSpace;
pub const MouseDevice = mouse.MouseDevice;
pub const MousePosition = mouse.MousePosition;

test "mouse position subtracts window origin for global coordinates" {
    const device = MouseDevice{
        .raw_position = .{ .x = 320, .y = 180 },
        .coordinate_space = .global,
    };
    const rect = WindowRect{ .x = 100, .y = 40, .width = 640, .height = 480 };
    const pos = device.position(&rect);

    try std.testing.expectEqual(@as(f32, 220), pos.x);
    try std.testing.expectEqual(@as(f32, 140), pos.y);
}

test "input code helpers provide stable names labels and parsing" {
    try std.testing.expectEqualStrings("key_space", inputCodeName(.key_space).?);
    try std.testing.expectEqualStrings("Space", inputCodeLabel(.key_space).?);
    try std.testing.expectEqual(InputCode.key_space, parseInputCode("key_space").?);
    try std.testing.expect(parseInputCode("space") == null);
}

test "mouse position returns raw global coordinates without window rect" {
    const device = MouseDevice{
        .raw_position = .{ .x = 320, .y = 180 },
        .coordinate_space = .global,
    };
    const pos = device.position(null);

    try std.testing.expectEqual(@as(f32, 320), pos.x);
    try std.testing.expectEqual(@as(f32, 180), pos.y);
}

test "mouse position keeps window local coordinates unchanged" {
    const device = MouseDevice{
        .raw_position = .{ .x = 45, .y = 90 },
        .coordinate_space = .window_local,
    };
    const rect = WindowRect{ .x = 100, .y = 40, .width = 640, .height = 480 };
    const pos = device.position(&rect);

    try std.testing.expectEqual(@as(f32, 45), pos.x);
    try std.testing.expectEqual(@as(f32, 90), pos.y);
}

test "mouse position keeps window local coordinates without rect" {
    const device = MouseDevice{
        .raw_position = .{ .x = 45, .y = 90 },
        .coordinate_space = .window_local,
    };
    const pos = device.position(null);

    try std.testing.expectEqual(@as(f32, 45), pos.x);
    try std.testing.expectEqual(@as(f32, 90), pos.y);
}

test "mouse position converts into consumer vector type" {
    const pos = MousePosition{ .x = 12, .y = 24 };
    const Vec2 = struct { x: f32, y: f32 };
    const vec = pos.as(Vec2);

    try std.testing.expectEqual(@as(f32, 12), vec.x);
    try std.testing.expectEqual(@as(f32, 24), vec.y);
}

test "mouse position converts into array form" {
    const pos = MousePosition{ .x = 12, .y = 24 };
    const out = pos.array();

    try std.testing.expectEqual(@as(f32, 12), out[0]);
    try std.testing.expectEqual(@as(f32, 24), out[1]);
}

test "mouse delta is zero for first raw position sample" {
    var device = MouseDevice{};

    device.setRawPosition(.{ .x = 320, .y = 180 }, .global);
    const movement = device.delta();

    try std.testing.expectEqual(@as(f32, 0), movement.x);
    try std.testing.expectEqual(@as(f32, 0), movement.y);
}

test "mouse delta tracks raw position change" {
    var device = MouseDevice{};

    device.setRawPosition(.{ .x = 320, .y = 180 }, .global);
    device.setRawPosition(.{ .x = 300, .y = 220 }, .global);
    const movement = device.delta();

    try std.testing.expectEqual(@as(f32, -20), movement.x);
    try std.testing.expectEqual(@as(f32, 40), movement.y);
}

test "mouse scroll delta accumulates per update" {
    var device = MouseDevice{};

    device.addScrollDelta(.{ .x = 1, .y = -2 });
    device.addScrollDelta(.{ .x = 0.5, .y = 3 });
    const scroll = device.scrollDelta();

    try std.testing.expectEqual(@as(f32, 1.5), scroll.x);
    try std.testing.expectEqual(@as(f32, 1), scroll.y);
}

test "gamepad button transitions use canonical button codes" {
    var pad = GamepadDevice.init(0);

    try std.testing.expect(pad.up(.gamepad_face_south));
    try std.testing.expect(!pad.down(.gamepad_face_south));

    pad.buttons[0] = .down;
    try std.testing.expect(pad.down(.gamepad_face_south));
    try std.testing.expect(pad.pressed(.gamepad_face_south));
    try std.testing.expect(!pad.released(.gamepad_face_south));

    pad.prev_buttons = pad.buttons;
    try std.testing.expect(pad.down(.gamepad_face_south));
    try std.testing.expect(!pad.pressed(.gamepad_face_south));

    pad.buttons[0] = .up;
    try std.testing.expect(pad.released(.gamepad_face_south));
}

test "gamepad 1d axes can be queried as buttons" {
    var pad = GamepadDevice.init(0);

    pad.prev_left_trigger_value = 0.25;
    pad.left_trigger_value = 0.75;
    try std.testing.expect(pad.down(.gamepad_left_trigger));
    try std.testing.expect(pad.pressed(.gamepad_left_trigger));
    try std.testing.expect(!pad.released(.gamepad_left_trigger));

    pad.prev_left_trigger_value = 0.75;
    pad.left_trigger_value = 0.25;
    try std.testing.expect(!pad.down(.gamepad_left_trigger));
    try std.testing.expect(!pad.pressed(.gamepad_left_trigger));
    try std.testing.expect(pad.released(.gamepad_left_trigger));

    pad.left_stick.y = 0.6;
    try std.testing.expect(pad.down(.gamepad_left_stick_up));
}

test "gamepad axis button threshold is configurable" {
    var pad = GamepadDevice.init(0);

    pad.left_trigger_value = 0.4;
    try std.testing.expect(!pad.down(.gamepad_left_trigger));

    pad.setAxisButtonThreshold(0.3);
    try std.testing.expect(pad.down(.gamepad_left_trigger));
    try std.testing.expect(pad.buttonWithThreshold(.gamepad_left_trigger, 0.5) == false);
}

test "gamepad ignores non-gamepad button codes" {
    const pad = GamepadDevice.init(0);

    try std.testing.expect(!pad.down(.key_space));
    try std.testing.expect(pad.up(.key_space));
    try std.testing.expect(!pad.pressed(.mouse_left));
    try std.testing.expect(!pad.released(.mouse_left));
}

test "gamepad exposes normalized analog values" {
    const pad = GamepadDevice{
        .view = GamepadDevice.init(0).view,
        .left_stick = .{ .x = -1, .y = 0.5 },
        .right_stick = .{ .x = 0.25, .y = 1 },
        .left_trigger_value = 0.75,
        .right_trigger_value = 1,
    };

    const left = pad.leftStick();
    const right = pad.rightStick().array();

    try std.testing.expectEqual(@as(f32, -1), left.x);
    try std.testing.expectEqual(@as(f32, 0.5), left.y);
    try std.testing.expectEqual(@as(f32, 0.25), right[0]);
    try std.testing.expectEqual(@as(f32, 1), right[1]);
    try std.testing.expectEqual(@as(f32, 0.75), pad.leftTrigger());
    try std.testing.expectEqual(@as(f32, 1), pad.rightTrigger());
}
