# Architecture Notes

`input` is intentionally small and pull-based. Most code falls into four
layers:

- `src/lib.zig` and `src/input.zig` expose the public import surface and the
  `InputSystem` owner for keyboard, mouse, and stable gamepad slots.
- `src/device/` stores device state and device-local query helpers. These files
  should stay free of platform APIs except through `platform/mod.zig`.
- `src/platform/` translates OS polling APIs into device state. Backend code
  should avoid action-map policy and should only update the concrete device it
  receives.
- `src/action_map.zig` stores user-facing bindings, snapshots them for JSON,
  and evaluates actions against devices attached to an `ActionMap`.

## Refactor Boundaries

When changing code without controller hardware available, prefer changes that
are visible to tests and docs:

- Keep public type names, action names, `InputCode` values, and JSON field names
  stable.
- Do not change button, axis, deadzone, threshold, or slot semantics unless a
  test can describe the new behavior.
- Keep platform-specific polling isolated inside `src/platform/`.
- Treat examples as user documentation. Shared helpers are useful when they
  remove repeated setup, but examples should still read like complete recipes.

## Validation

Run these before publishing functional changes:

```sh
zig build test
zig build example-device-polling
zig build example-player
zig build example-save-action-map
zig build example-action-map-round-trip
zig build example-load-action-map-debug
```

Hardware-dependent changes also need a manual pass with at least one keyboard,
mouse, and controller on the target backend. When that is not available, keep
the patch limited to composition, documentation, or test-covered pure logic.
