# Action maps

Use `ActionMap` when you want gameplay actions instead of raw device reads.

That gives you:

- one action name for mixed keyboard, mouse, and gamepad input
- direct polling with `down`, `pressed`, `released`, `axis1d`, and `axis2d`
- plain-data save/load with `ActionBinding`

## Typical player setup

```zig
const input = @import("input");

var state = input.InputSystem{};
var actions = input.ActionMap.init();

try actions.attachDevices(&state, .{
    .keyboard = true,
    .mouse = true,
    .gamepad_slot = 0,
});

try actions.set2d("move", .{
    .left = &.{.{ .code = .key_a }},
    .right = &.{.{ .code = .key_d }},
    .up = &.{.{ .code = .key_w }},
    .down = &.{.{ .code = .key_s }},
    .vectors = &.{.{ .code = .gamepad_left_stick }},
});
try actions.set("jump", &.{
    .{ .code = .key_space },
    .{ .code = .gamepad_face_south },
});
try actions.set("fire", &.{
    .{ .code = .mouse_left },
    .{ .code = .gamepad_right_trigger, .activation_threshold = 0.1 },
});
try actions.set("aim", &.{
    .{ .code = .mouse_right },
    .{ .code = .gamepad_left_trigger, .activation_threshold = 0.1 },
});
try actions.set("pause", &.{
    .{ .code = .key_escape },
    .{ .code = .gamepad_start },
});
try actions.set("look", &.{.{ .code = .gamepad_right_stick }});
```

## Reading actions in a loop

```zig
while (true) {
    try state.keyboard().update();
    try state.mouse().update();
    if (state.gamepad(0)) |pad| try pad.update();

    const move = actions.axis2d(&state, "move");
    const look_stick = actions.axis2d(&state, "look");
    const look_mouse = state.mouse().delta();
    const jump_pressed = actions.pressed(&state, "jump");
    const fire_down = actions.down(&state, "fire");
    const aim_down = actions.down(&state, "aim");
    const pause_pressed = actions.pressed(&state, "pause");

    std.debug.print(
        "move=({d:.2}, {d:.2}) look=({d:.2}, {d:.2}) mouse=({d:.2}, {d:.2}) jump={any} fire={any} aim={any} pause={any}\n",
        .{
            move.x, move.y,
            look_stick.x, look_stick.y,
            look_mouse.x, look_mouse.y,
            jump_pressed,
            fire_down,
            aim_down,
            pause_pressed,
        },
    );
}
```

## BoundInput

Each bound entry is a `BoundInput`:

```zig
pub const BoundInput = struct {
    code: input.InputCode,
    activation_threshold: ?f32 = null,
};
```

For digital buttons, `activation_threshold` is usually unnecessary.

For analog-capable inputs used like buttons, set it where the action should
become active:

```zig
try actions.set("forward", &.{
    .{ .code = .key_w },
    .{ .code = .gamepad_left_stick_up, .activation_threshold = 0.35 },
});
```

That same action can then be queried both ways:

```zig
const forward_down = actions.down(&state, "forward");
const forward_value = actions.axis1d(&state, "forward");
```

## Editing one action

Read one action as an `ActionBinding`, modify it, then write it back:

```zig
if (actions.binding("jump")) |current| {
    var edited = current;
    edited.codes = &.{
        .{ .code = .key_enter },
        .{ .code = .gamepad_face_south },
    };
    try actions.setBinding(edited);
}
```

`setBinding` validates the payload. Invalid mixed shapes are rejected:

- `.kind = .codes` cannot also fill `left/right/up/down/vectors`
- `.kind = .axis_2d` cannot also fill `codes`

## Reset and conflict helpers

Keep a default map and a mutable map:

```zig
var defaults = input.ActionMap.init();
try defaults.set("jump", &.{.{ .code = .key_space }});

var bindings = defaults;
```

Reset one action:

```zig
try bindings.reset("jump", &defaults);
```

Reset the whole map:

```zig
try bindings.resetAll(&defaults);
```

Check conflicts before rebinding:

```zig
if (bindings.findConflict(.key_f, "interact")) |conflict| {
    std.debug.print("already used by {s}\n", .{conflict.action_name});
}
```

## Runnable example

See [examples/player_action_map.zig](../examples/player_action_map.zig).

Build:

```sh
zig build example-player
./zig-out/bin/player-action-map --frames 10
```
