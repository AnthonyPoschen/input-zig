# input

`input` is a pull-based input library with a shared device model.

## Core concepts

- Every input source is a **device view** with:
  - `id: number`
  - `kind: enum`
  - `connected: bool`
  - fixed-size `name` (`32` chars)
- Keyboard and mouse are singleton devices today.
- Gamepads use stable logical slots. A gamepad slot can exist while disconnected
  so player assignment does not have to follow current enumeration order.
- Devices expose local state functions:
  - `down`
  - `up`
  - `pressed`
  - `released`

`pressed`/`released` are computed from previous vs current frame state.

## Binding model

Action maps now use:

- attached `DeviceView` pointers
- per-action arrays of `InputCode` enum values

`InputCode` is shared across device kinds and each device interprets the numeric value based on its own semantics.

Keyboard entries are shift-agnostic (for example `key_a` covers both `a` and `A`). Modifier keys are explicit enum values (`key_shift_left/right`, `key_control_left/right`, `key_alt_left/right`, `key_super_left/right`, `key_escape`).

Backends now translate native platform keycodes into canonical `InputCode` values before updating key state, so bindings use one key namespace across OSes.

## API shape

- `keyboard.update()` updates the keyboard device
- `mouse.update()` updates the mouse device
- `gamepad.update()` updates one stable logical gamepad slot
- `input.keyboard()` and `input.mouse()`
- `input.mouse().position(window_rect)` for raw or window-relative coordinates
- `input.mouse().delta()` for raw per-update movement
- `input.mouse().scrollDelta()` for per-update wheel movement
- `input.listDevices(kind, out)` to fetch devices by type in stable order

## Mouse position and movement

`MouseDevice.position(window_rect)` returns a `MousePosition` value:

```zig
pub const MousePosition = struct {
    x: f32,
    y: f32,
};
```

- Pass `null` to get raw backend coordinates
- Pass `?*const WindowRect` to get application-window-relative coordinates when
  the backend stores global mouse coordinates
- If the backend already reports window-local coordinates, `position(rect)`
  returns those coordinates unchanged

Mouse coordinates are exposed through `MouseDevice.position(...)`; there are no
public `mouse.x` or `mouse.y` fields.

`MouseDevice.delta()` returns an `Axis2d` with raw movement since the previous
successful `mouse.update()`. The first position sample reports `0, 0`, then
later samples report positive or negative movement as `current - previous`.

`MouseDevice.scrollDelta()` returns an `Axis2d` with scroll wheel movement
reported during the latest `mouse.update()`. Backends that cannot observe wheel
events through polling report `0, 0`.

`WindowRect` is a plain value type:

```zig
pub const WindowRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};
```

`MousePosition` includes convenience helpers for math-library interop:

```zig
const pos = input.mouse().position(null);
const movement = input.mouse().delta();
const wheel = input.mouse().scrollDelta();
const arr = pos.array();
const vec = pos.as(struct { x: f32, y: f32 });
```

## Gamepads

Gamepad controls use physical-position names instead of controller-specific
labels:

- `gamepad_face_south` for Xbox `A` / PlayStation Cross
- `gamepad_face_east` for Xbox `B` / PlayStation Circle
- `gamepad_face_west` for Xbox `X` / PlayStation Square
- `gamepad_face_north` for Xbox `Y` / PlayStation Triangle
- `gamepad_capture` for capture/share-style center buttons when a backend
  exposes one
- `gamepad_left_stick` / `gamepad_right_stick` for full 2D stick values
- directional stick codes such as `gamepad_left_stick_up` and
  `gamepad_left_stick_right` for button-like or 1D-axis actions

Gamepad slots have stable logical ids starting at `100`. `input.gamepad(slot)`
looks up a logical slot, while `input.gamepadCount()` counts currently connected
gamepads. `input.listDevices(.gamepad, out)` returns connected gamepads in slot
order.

Analog controls are exposed separately from button queries:

```zig
const pad = input.gamepad(0) orelse return;
const move = pad.leftStick();
const aim = pad.rightStick();
const brake = pad.leftTrigger();
const throttle = pad.rightTrigger();
```

Sticks use normalized `[-1, 1]` values. Triggers use normalized `[0, 1]`
values.

Action maps can also read action values:

```zig
try actions.set("forward", &.{ .key_w, .gamepad_left_stick_up }, .{
    .axis_button_threshold = 0.35,
});
try actions.set2d("move", .{
    .left = &.{.key_a},
    .right = &.{.key_d},
    .up = &.{.key_w},
    .down = &.{.key_s},
    .vectors = &.{.gamepad_left_stick},
}, null);

if (actions.down(&input, "forward")) {
    // W is held or the stick is pushed forward past the button threshold.
}

const forward = actions.axis1d(&input, "forward");
const move = actions.axis2d(&input, "move");
```

`axis1d` returns `Axis1d` and `axis2d` returns `Axis2d`. They ignore
incompatible codes and add compatible values together, clamping the final result
to `[-1, 1]`.

`set2d` is the cleaner path for movement-style actions that combine one or more
four-way digital sources such as `WASD` with vector sources such as
`.gamepad_left_stick`. It merges them into one `Axis2d` and clamps each final
component to `[-1, 1]`.

When `down`, `pressed`, or `released` checks an axis code, it uses the action's
`axis_button_threshold`. The default threshold is `0.5`.

Direct gamepad button queries also treat 1D axis codes as buttons. For example,
`pad.down(.gamepad_left_trigger)` becomes true when the left trigger is above
the gamepad's axis button threshold. Use `pad.setAxisButtonThreshold(...)` to
change the default `0.5` threshold, or `buttonWithThreshold` /
`prevButtonWithThreshold` when a caller has its own threshold.

Gamepads also have per-axis deadzones for axis queries:

```zig
if (input.gamepad(0)) |pad| {
    pad.setLeftStickDeadzone(0.2);
    pad.setRightStickDeadzone(0.15);
    pad.setLeftTriggerDeadzone(0.05);
    pad.setRightTriggerDeadzone(0.05);

    try pad.setDeadzone(.gamepad_left_stick_up, 0.25);
}
```

Axis values smaller than their deadzone are reported as `0`. Directional stick
codes share the deadzone of their parent stick.

Gamepad slots are updated per device. A local multiplayer game can update only
the slots assigned to active players:

```zig
try input.keyboard().update();
try input.mouse().update();
if (input.gamepad(0)) |pad| try pad.update();
if (input.gamepad(1)) |pad| try pad.update();
```

## Device listing guarantees

- stable IDs for built-ins:
  - keyboard id = `0`
  - mouse id = `1`
  - gamepad slots start at id = `100`
- deterministic order for the same kind

## ActionMap

`ActionMap` supports keybind-style actions with fixed action names (`32` chars).

- action maps attach one or more devices
- `set(name, codes, options)` creates or replaces an action
- `set2d(name, binding, options)` creates or replaces a 2D action
- `set(name, null, options)` disables/unbinds an action
- `reset(name, defaults)` restores one action from a separate default map
- `resetAll(defaults)` replaces all actions with a separate default map
- `findConflict(code, ignore_action)` finds the first action already using an
  `InputCode`
- `inputCodeName(code)` returns a stable config token such as `key_space`
- `inputCodeLabel(code)` returns a GUI label such as `Space`
- `parseInputCode(name)` parses stable config tokens back into `InputCode`
- `remove(name)` deletes the action
- functions:
  - `attachDevice`
  - `detachDevice`
  - `set`
  - `set2d`
  - `reset`
  - `resetAll`
  - `remove`
  - `actionCount`
  - `exportBindings`
  - `importBindings`
  - `actionCodes`
  - `action2d`
  - `findConflict`
  - `down`
  - `up`
  - `pressed`
  - `released`

A game can keep hard-coded defaults separate from user-editable bindings:

```zig
var defaults = input_lib.ActionMap.init();
try defaults.set("jump", &.{ .key_space, .gamepad_face_south }, null);
try defaults.set2d("move", .{
    .left = &.{.key_a},
    .right = &.{.key_d},
    .up = &.{.key_w},
    .down = &.{.key_s},
    .vectors = &.{.gamepad_left_stick},
}, null);

var bindings = defaults;
try bindings.attachDevice(input.keyboard());
try bindings.attachDevice(input.mouse());
if (input.gamepad(0)) |pad| try bindings.attachDevice(pad);

try bindings.set("jump", &.{ .key_j, .gamepad_face_south }, null);
try bindings.reset("jump", &defaults);
```

For save/load, export the current bindings into plain `ActionBinding` values.
The examples below serialize those values to JSON:

```zig
var saved: [input_lib.action_map.max_actions]input_lib.ActionBinding = undefined;
const count = bindings.exportBindings(saved[0..]);

var i: usize = 0;
while (i < count) : (i += 1) {
    const binding = saved[i];

    if (binding.codes) |codes| {
        for (codes) |code| {
            const token = input_lib.inputCodeName(code) orelse "unknown";
            _ = token;
        }
    }

    if (binding.left) |codes| {
        for (codes) |code| {
            const token = input_lib.inputCodeName(code) orelse "unknown";
            _ = token;
        }
    }

    _ = binding.name;
}
```

Load by parsing saved data back into `ActionBinding` values:

```zig
var loaded = [_]input_lib.ActionBinding{ /* parsed from disk */ };
try bindings.importBindings(loaded[0..]);
```

For a keybinding GUI, inspect one action by name:

```zig
if (bindings.actionCodes("jump")) |codes| {
    for (codes) |code| {
        const label = input_lib.inputCodeLabel(code) orelse "Unknown";
        _ = label;
    }
}

if (bindings.action2d("move")) |binding| {
    if (binding.left) |codes| {
        for (codes) |code| {
            const label = input_lib.inputCodeLabel(code) orelse "Unknown";
            _ = label;
        }
    }
}

if (bindings.findConflict(.key_f, "interact")) |conflict| {
    // conflict.action_name and conflict.slot identify where it is already used.
    _ = conflict;
}
```

## Example

```zig
const input_lib = @import("input");

var input = input_lib.InputSystem{};
var actions = input_lib.ActionMap.init();

try actions.attachDevice(input.keyboard());
try actions.attachDevice(input.mouse());
try actions.set("jump", &.{ .key_space, .mouse_left }, null);

try input.keyboard().update();
try input.mouse().update();

const window_rect = input_lib.WindowRect{
    .x = 100,
    .y = 50,
    .width = 1280,
    .height = 720,
};
const mouse_pos = input.mouse().position(&window_rect);

if (actions.pressed(&input, "jump")) {
    // pressed this update cycle
}
```

For a larger consumer-facing setup, see
`examples/player_action_map.zig` and build it with:

```sh
zig build example-player
```

Two save/load examples use JSON on disk:

- `examples/save_action_map.zig` writes the current action map to
  `action_bindings.json` as a plain JSON array of `ActionBinding` objects.
- `examples/load_action_map_debug.zig` loads `action_bindings.json` when it
  exists, otherwise uses hard-coded defaults, then displays every action and
  its current state. On Wayland it opens the same focused helper window as
  `debug-input` so keyboard and mouse actions can be tested normally.

```sh
zig build example-save-action-map
./zig-out/bin/save-action-map

zig build example-load-action-map-debug
./zig-out/bin/load-action-map-debug
```

## Debug viewer

There is one debug viewer executable:

- `debug-input`

- Run with environment-based backend selection:

```sh
zig build debug-input
```

- Run for a fixed number of frames, then exit:

```sh
zig build debug-input -- --frames 10
```

`--frames N` is only a test convenience flag. It redraws `N` times and exits
instead of running forever.

The viewer redraws with:

- mouse position via `MouseDevice.position(null)`
- mouse movement via `MouseDevice.delta()`
- scroll wheel movement via `MouseDevice.scrollDelta()`
- mouse button `down` / `pressed` / `released`
- a fixed set of common keyboard probes
- gamepad connected state, buttons, sticks, and triggers

For Wayland desktops, `zig build debug-input` now creates a native Wayland
window and reports keyboard and mouse state only while that window has focus.

When both `DISPLAY` and `WAYLAND_DISPLAY` are set, input prefers Wayland,
which matches the actual desktop session more closely on compositors such as
Hyprland.

## Platform notes

- Linux uses runtime detection and cached backend selection.
- Wayland does not allow global keyboard/mouse polling. The default keyboard and
  mouse update path is a no-op on Wayland; `debug-input` uses a focused Wayland
  window when it needs live keyboard and mouse state.
- Windows gamepad polling uses XInput slots.
- Linux gamepad polling uses `/dev/input/jsN` when the current user can open the
  joystick device. It does not require root and treats inaccessible devices as
  disconnected.
- The Linux joystick API may not expose newer controls such as Xbox
  screenshot/share or PlayStation Create buttons. `gamepad_capture` is therefore
  optional and may remain up even when the physical button exists.
- input does not use `/dev/input/event*` by default because those devices are
  commonly unreadable without elevated permissions or udev/group changes.
- macOS gamepad polling uses GameController first and falls back to IOKit HID
  devices for wired controllers. Xbox Home is decoded from wired-controller
  vendor reports when needed, but may remain up when the same controller is
  connected wirelessly. Xbox Capture/Share reports are ambiguous with normal
  button telemetry, so `gamepad_capture` may remain up on macOS too.

## Source layout

- `src/device/common.zig` shared device view/state types
- `src/device/input_code.zig` canonical input codes
- `src/device/keyboard.zig` keyboard device
- `src/device/mouse.zig` mouse device
- `src/device/gamepad.zig` gamepad device
- `src/device.zig` public device facade
