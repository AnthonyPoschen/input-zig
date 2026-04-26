# input

`input` is a pull-based input library for Zig with:

- direct keyboard, mouse, and gamepad polling
- stable gamepad slots
- a shared `InputCode` namespace
- `ActionMap` bindings for mixed-device gameplay input
- plain JSON save/load for user-editable bindings

## Documentation

- [Device polling guide](docs/device-polling.md)
- [Action map guide](docs/action-maps.md)
- [JSON save/load guide](docs/action-map-json.md)
- [Input code legend](docs/input-codes.md)

## Quick start

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
    .up = &.{.{ .code = .key_w }},
    .down = &.{.{ .code = .key_s }},
    .left = &.{.{ .code = .key_a }},
    .right = &.{.{ .code = .key_d }},
    .vectors = &.{.{ .code = .gamepad_left_stick }},
});
try actions.set("jump", &.{
    .{ .code = .key_space },
    .{ .code = .gamepad_face_south },
});

while (true) {
    try state.keyboard().update();
    try state.mouse().update();
    if (state.gamepad(0)) |pad| try pad.update();

    const move = actions.axis2d(&state, "move");
    const jump_pressed = actions.pressed(&state, "jump");
    _ = move;
    _ = jump_pressed;
}
```

## Example programs

Build the examples:

```sh
zig build example-device-polling
zig build example-player
zig build example-save-action-map
zig build example-action-map-round-trip
zig build example-load-action-map-debug
```

Then run the installed binaries from `zig-out/bin`:

- `device-polling`
  - updates each device directly and prints keyboard, mouse, and gamepad state
- `player-action-map`
  - builds a typical player action map and prints sampled gameplay input
- `save-action-map`
  - writes a plain JSON array of `ActionBinding` entries
- `action-map-round-trip`
  - loads bindings from disk when present, lets you save and reset in a loop, and prints the active bindings every frame
- `load-action-map-debug`
  - renders all configured actions and their live state in a debug viewer

Most examples accept `--frames N` so you can run a bounded number of updates.

## Core concepts

- `InputSystem.keyboard()` returns the singleton keyboard device
- `InputSystem.mouse()` returns the singleton mouse device
- `InputSystem.gamepad(slot)` returns a stable logical gamepad slot
- buttons expose:
  - `down`
  - `up`
  - `pressed`
  - `released`
- analog queries expose:
  - `axis1d`
  - `axis2d`
  - `leftStick`
  - `rightStick`
  - `leftTrigger`
  - `rightTrigger`

Gamepads use physical-position names:

- `gamepad_face_south` = Xbox `A` / PlayStation Cross
- `gamepad_face_east` = Xbox `B` / PlayStation Circle
- `gamepad_face_west` = Xbox `X` / PlayStation Square
- `gamepad_face_north` = Xbox `Y` / PlayStation Triangle

Action maps use structured `BoundInput` entries:

```zig
try actions.set("fire", &.{
    .{ .code = .mouse_left },
    .{ .code = .gamepad_right_trigger, .activation_threshold = 0.1 },
});
```

`activation_threshold` controls when analog-capable inputs become active for
button-style queries such as `down`, `pressed`, and `released`.

## Persistence

Take a snapshot and write the slice directly as JSON:

```zig
const saved = actions.snapshot();
try std.json.Stringify.value(saved.slice(), .{
    .emit_null_optional_fields = false,
}, writer);
```

Load by parsing `[]ActionBinding` and passing it back:

```zig
var parsed = try std.json.parseFromSlice(
    []input.ActionBinding,
    allocator,
    contents,
    .{ .ignore_unknown_fields = true },
);
defer parsed.deinit();

try actions.importBindings(parsed.value);
```

For editing one action at a time:

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

## Debug viewer

Run the input debugger with:

```sh
zig build debug-input
```

Optional bounded run:

```sh
zig build debug-input -- --frames 10
```

The viewer prints:

- mouse position, delta, and scroll
- mouse button state
- a small keyboard probe set
- gamepad buttons, sticks, triggers, and connection state

On Wayland, `debug-input` opens a focused helper window so keyboard and mouse
state can be read normally.

## Platform notes

- Linux uses runtime backend detection and cached backend selection
- Wayland does not allow global keyboard/mouse polling; the default polling path
  is a no-op there unless you use a focused window
- Windows gamepad polling uses XInput slots
- Linux gamepad polling uses `/dev/input/jsN`
- macOS gamepad polling uses GameController first and falls back to IOKit HID

## Source layout

- `src/device/input_code.zig`
- `src/device/keyboard.zig`
- `src/device/mouse.zig`
- `src/device/gamepad.zig`
- `src/action_map.zig`
- `examples/`
