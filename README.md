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
- `input.listDevices(kind, out)` to fetch devices by type in stable order

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

if (actions.press(&input, "jump")) {
    // pressed this update cycle
}
```

## Platform notes

- Linux `.auto` uses runtime detection and cached backend selection.
- Wayland global polling currently returns `error.WaylandGlobalPollingUnsupported`.
