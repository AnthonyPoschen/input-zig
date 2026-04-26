const input_lib = @import("input");

const PlayerInput = struct {
    move: input_lib.Axis2d,
    jump_pressed: bool,
    fire_down: bool,
    aim_down: bool,
    pause_pressed: bool,
    look_stick: input_lib.Axis2d,
    look_mouse: input_lib.Axis2d,
};

/// Configure one player-facing action map across keyboard, mouse, and gamepad.
fn setupPlayerActions(input: *input_lib.InputSystem, actions: *input_lib.ActionMap) !void {
    const gamepad = input.gamepad(0) orelse unreachable;

    try actions.attachDevices(input, .{
        .keyboard = true,
        .mouse = true,
        .gamepad_slot = 0,
    });

    try actions.set2d("move", .{
        .left = &.{.key_a},
        .right = &.{.key_d},
        .up = &.{.key_w},
        .down = &.{.key_s},
        .vectors = &.{.gamepad_left_stick},
    }, null);
    try actions.set("jump", &.{
        .key_space,
        .gamepad_face_south,
    }, null);
    try actions.set("fire", &.{
        .mouse_left,
        .gamepad_right_trigger,
    }, .{ .axis_button_threshold = 0.1 });
    try actions.set("aim", &.{
        .mouse_right,
        .gamepad_left_trigger,
    }, .{ .axis_button_threshold = 0.1 });
    try actions.set("pause", &.{
        .key_escape,
        .gamepad_start,
    }, null);
    try actions.set("look", &.{.gamepad_right_stick}, null);

    try gamepad.setDeadzone(.gamepad_left_stick, 0.05);
    try gamepad.setDeadzone(.gamepad_right_stick, 0.05);
    try gamepad.setDeadzone(.gamepad_left_trigger, 0.00);
    try gamepad.setDeadzone(.gamepad_right_trigger, 0.00);
}

/// Read a player frame from the configured action map.
fn samplePlayerInput(input: *input_lib.InputSystem, actions: *const input_lib.ActionMap) PlayerInput {
    return .{
        .move = actions.axis2d(input, "move"),
        .jump_pressed = actions.pressed(input, "jump"),
        .fire_down = actions.down(input, "fire"),
        .aim_down = actions.down(input, "aim"),
        .pause_pressed = actions.pressed(input, "pause"),
        .look_stick = actions.axis2d(input, "look"),
        .look_mouse = input.mouse().delta(),
    };
}

/// Show the per-frame update shape a consumer would typically use.
fn sampleFrame(input: *input_lib.InputSystem, actions: *const input_lib.ActionMap) !PlayerInput {
    const gamepad = input.gamepad(0) orelse unreachable;

    try input.keyboard().update();
    try input.mouse().update();
    try gamepad.update();

    return samplePlayerInput(input, actions);
}

/// Build-check a complete player action map example without needing a demo app.
pub fn main() !void {
    var input = input_lib.InputSystem{};
    var actions = input_lib.ActionMap.init();

    try setupPlayerActions(&input, &actions);

    const player_input = samplePlayerInput(&input, &actions);
    _ = player_input;

    _ = sampleFrame;
}
