# Device polling

This path is for games or tools that want direct device state without an
`ActionMap`.

The model is simple:

1. get the device from `InputSystem`
2. call `update()` each loop
3. read the state
4. print or consume it

## Keyboard

```zig
const input = @import("input");

var state = input.InputSystem{};

while (true) {
    try state.keyboard().update();

    const keyboard = state.keyboard();
    const jump_down = keyboard.down(.key_space);
    const pause_pressed = keyboard.pressed(.key_escape);
    const move_left = keyboard.down(.key_a);

    std.debug.print(
        "space={any} escape_pressed={any} a={any}\n",
        .{ jump_down, pause_pressed, move_left },
    );
}
```

## Mouse

```zig
const input = @import("input");

var state = input.InputSystem{};

while (true) {
    try state.mouse().update();

    const mouse = state.mouse();
    const position = mouse.position(null);
    const delta = mouse.delta();
    const wheel = mouse.scrollDelta();

    std.debug.print(
        "mouse pos=({d:.2}, {d:.2}) delta=({d:.2}, {d:.2}) wheel=({d:.2}, {d:.2}) left={any}\n",
        .{
            position.x, position.y,
            delta.x, delta.y,
            wheel.x, wheel.y,
            mouse.down(.mouse_left),
        },
    );
}
```

When you have a window rect and want window-relative coordinates:

```zig
const rect = input.WindowRect{
    .x = 100,
    .y = 50,
    .width = 1280,
    .height = 720,
};
const local = state.mouse().position(&rect);
```

## Gamepad

Gamepads use stable logical slots. Slot `0` always means player one’s assigned
slot, even if that slot is currently disconnected.

```zig
const input = @import("input");

var state = input.InputSystem{};

while (true) {
    const pad = state.gamepad(0) orelse unreachable;
    try pad.update();

    std.debug.print(
        "connected={any} south={any} dpad_up={any} left=({d:.2}, {d:.2}) right_trigger={d:.2}\n",
        .{
            pad.view.connected,
            pad.down(.gamepad_face_south),
            pad.down(.gamepad_dpad_up),
            pad.leftStick().x,
            pad.leftStick().y,
            pad.rightTrigger(),
        },
    );
}
```

Triggers are analog values in `[0, 1]`. Sticks are normalized `[-1, 1]`.

Direct gamepad button queries also work with 1D axis codes:

```zig
const pressed = pad.down(.gamepad_left_trigger);
```

The default activation threshold is `0.5`. Override it per device when needed:

```zig
pad.setActivationThreshold(0.35);
```

## Combined loop

This is the typical direct-polling loop:

```zig
const input = @import("input");

var state = input.InputSystem{};

while (true) {
    try state.keyboard().update();
    try state.mouse().update();
    if (state.gamepad(0)) |pad| try pad.update();

    const keyboard = state.keyboard();
    const mouse = state.mouse();
    const pad = state.gamepad(0) orelse unreachable;

    std.debug.print(
        "space={any} mouse_left={any} mouse_pos=({d:.2}, {d:.2}) pad_south={any}\n",
        .{
            keyboard.down(.key_space),
            mouse.down(.mouse_left),
            mouse.position(null).x,
            mouse.position(null).y,
            pad.down(.gamepad_face_south),
        },
    );
}
```

## Runnable example

See [examples/device_polling.zig](../examples/device_polling.zig).

Build:

```sh
zig build example-device-polling
./zig-out/bin/device-polling --frames 10
```
