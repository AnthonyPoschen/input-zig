# input-zig

`input-zig` is a pull-based input library with a shared device model.

## Core concepts

- Every input source is a **device view** with:
  - `id: number`
  - `kind: enum`
  - `connected: bool`
  - fixed-size `name` (`32` chars)
- Keyboard and mouse are singleton devices today.
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

- `InputSystem.update(backend_choice)`
  - internally calls each device update (`keyboard.update`, `mouse.update`)
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

## Device listing guarantees

- stable IDs for built-ins:
  - keyboard id = `0`
  - mouse id = `1`
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

try input.update(.auto);

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

- Run with automatic backend selection:

```sh
zig build debug-input
```

- Force a backend explicitly:

```sh
zig build debug-input -- x11
zig build debug-input -- wayland
```

- Run for a fixed number of frames, then exit:

```sh
zig build debug-input -- --frames 10
zig build debug-input -- x11 --frames 10
```

`--frames N` is only a test convenience flag. It redraws `N` times and exits
instead of running forever.

The viewer redraws with:

- mouse position via `MouseDevice.position(null)`
- mouse button `down` / `press` / `release`
- a fixed set of common keyboard probes

On Linux, global polling currently works through X11 only. Wayland returns
`error.WaylandGlobalPollingUnsupported`.

For Wayland desktops, `zig build debug-input` now creates a native Wayland
window and reports keyboard and mouse state only while that window has focus.

When both `DISPLAY` and `WAYLAND_DISPLAY` are set, `.auto` now prefers
Wayland, which matches the actual desktop session more closely on compositors
such as Hyprland.

On a Wayland session, `zig build debug-input -- x11` still forces the old X11
polling path. `zig build debug-input -- wayland` or plain
`zig build debug-input` use the focused-window Wayland path instead.

## Platform notes

- Linux `.auto` uses runtime detection and cached backend selection.
- Wayland global polling currently returns `error.WaylandGlobalPollingUnsupported`.
