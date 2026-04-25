const input_lib = @import("input_zig");

const PlayerInput = struct {
    move_x: f32,
    move_y: f32,
    jump_pressed: bool,
    fire_down: bool,
    aim_down: bool,
    pause_pressed: bool,
    look_stick: input_lib.Axis2d,
};

/// Configure one player-facing action map across keyboard, mouse, and gamepad.
fn setupPlayerActions(input: *input_lib.InputSystem, actions: *input_lib.ActionMap) !void {
    const gamepad = input.gamepad(0) orelse unreachable;

    try actions.attachDevice(input.keyboard());
    try actions.attachDevice(input.mouse());
    try actions.attachDevice(gamepad);

    try actions.set("move_forward", &.{
        .key_w,
        .gamepad_left_stick_up,
    }, null);
    try actions.set("move_back", &.{
        .key_s,
        .gamepad_left_stick_down,
    }, null);
    try actions.set("move_left", &.{
        .key_a,
        .gamepad_left_stick_left,
    }, null);
    try actions.set("move_right", &.{
        .key_d,
        .gamepad_left_stick_right,
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
    // Build movement from four 1D actions because ActionMap cannot currently
    // express a keyboard+gamepad 2D composite like WASD plus left stick.
    const move_x = actions.axis1d(input, "move_right") -
        actions.axis1d(input, "move_left");
    const move_y = actions.axis1d(input, "move_forward") -
        actions.axis1d(input, "move_back");

    return .{
        .move_x = move_x,
        .move_y = move_y,
        .jump_pressed = actions.pressed(input, "jump"),
        .fire_down = actions.down(input, "fire"),
        .aim_down = actions.down(input, "aim"),
        .pause_pressed = actions.pressed(input, "pause"),
        .look_stick = actions.axis2d(input, "look_stick"),
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

    // TODO: Mouse look wants delta, not absolute position, but ActionMap has no
    // mouse-motion binding yet. A future example could map raw delta here.
    // const look_mouse = input.mouse().delta();

    _ = sampleFrame;
}
