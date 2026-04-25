# input-zig

`input-zig` is a pull-based input library with a shared device model.

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
  - `press`
  - `release`

`press`/`release` are computed from previous vs current frame state.

## Binding model

Bindings now use:

- pointer to a `DeviceView`
- `InputCode` enum value

`InputCode` is shared across device kinds and each device interprets the numeric value based on its own semantics.

Keyboard entries are shift-agnostic (for example `key_a` covers both `a` and `A`). Modifier keys are explicit enum values (`key_shift_left/right`, `key_control_left/right`, `key_alt_left/right`, `key_super_left/right`, `key_escape`).

Backends now translate native platform keycodes into canonical `InputCode` values before updating key state, so bindings use one key namespace across OSes.

## API shape

- `keyboard.update()` updates the keyboard device
- `mouse.update()` updates the mouse device
- `gamepad.update()` updates one stable logical gamepad slot
- `input.keyboard()` and `input.mouse()`
- `input.mouse().position(window_rect)` for raw or window-relative coordinates
- `input.listDevices(kind, out)` to fetch devices by type in stable order

## Mouse position

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

`ActionMap` supports keybind-style bindings with fixed action names (`32` chars).

- action creation requires a default binding (device pointer + code)
- multiple bindings per action are supported
- functions:
  - `createAction`
  - `bind`
  - `unbind`
  - `reset`
  - `resetAll`
  - `down`
  - `up`
  - `press`
  - `release`

## Example

```zig
const input_lib = @import("input_zig");

var input = input_lib.InputSystem{};
var actions = input_lib.ActionMap.init();

try actions.createAction("jump", .{ .device = &input.keyboard().view, .code = @enumFromInt(32) });
try actions.bind("jump", .{ .device = &input.mouse().view, .code = .mouse_left });

try input.keyboard().update();
try input.mouse().update();

const window_rect = input_lib.WindowRect{
    .x = 100,
    .y = 50,
    .width = 1280,
    .height = 720,
};
const mouse_pos = input.mouse().position(&window_rect);

if (actions.press(&input, "jump")) {
    // pressed this update cycle
}
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
- mouse button `down` / `press` / `release`
- a fixed set of common keyboard probes
- gamepad connected state, buttons, sticks, and triggers

For Wayland desktops, `zig build debug-input` now creates a native Wayland
window and reports keyboard and mouse state only while that window has focus.

When both `DISPLAY` and `WAYLAND_DISPLAY` are set, input-zig prefers Wayland,
which matches the actual desktop session more closely on compositors such as
Hyprland.

## Platform notes

- Linux uses runtime detection and cached backend selection.
- Wayland global polling currently returns `error.WaylandGlobalPollingUnsupported`;
  the debug viewer uses a focused Wayland window instead.
- Windows gamepad polling uses XInput slots.
- Linux gamepad polling uses `/dev/input/jsN` when the current user can open the
  joystick device. It does not require root and treats inaccessible devices as
  disconnected.
- The Linux joystick API may not expose newer controls such as Xbox
  screenshot/share or PlayStation Create buttons. `gamepad_capture` is therefore
  optional and may remain up even when the physical button exists.
- input-zig does not use `/dev/input/event*` by default because those devices are
  commonly unreadable without elevated permissions or udev/group changes.
- macOS gamepad polling currently reports disconnected slots until a proper
  GameController/IOKit bridge is added.

## Source layout

- `src/device/common.zig` shared device view/state types
- `src/device/input_code.zig` canonical input codes
- `src/device/keyboard.zig` keyboard device
- `src/device/mouse.zig` mouse device
- `src/device/gamepad.zig` gamepad device
- `src/device.zig` public device facade
