# JSON save and load

The intended flow is:

1. build a small default `ActionMap`
2. load a user-edited JSON file when it exists
3. run the game with the loaded bindings
4. save back to disk when the user asks
5. reset to defaults when the user asks

`ActionBinding` is plain data, so the JSON is directly editable.

## Build defaults

```zig
fn buildDefaults(actions: *input.ActionMap) !void {
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
    try actions.set("save_bindings", &.{
        .{ .code = .key_f5 },
        .{ .code = .gamepad_start },
    });
    try actions.set("reset_bindings", &.{
        .{ .code = .key_f9 },
        .{ .code = .gamepad_select },
    });
}
```

## Save

```zig
const snapshot = actions.snapshot();
try std.json.Stringify.value(snapshot.slice(), .{
    .emit_null_optional_fields = false,
}, writer);
```

## Load

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

## Loop with save and reset actions

```zig
while (true) {
    try state.keyboard().update();
    if (state.gamepad(0)) |pad| try pad.update();

    if (actions.pressed(&state, "save_bindings")) {
        try save(io, "action_bindings_round_trip.json", &actions);
    }

    if (actions.pressed(&state, "reset_bindings")) {
        try actions.resetAll(&defaults);
    }

    const move = actions.axis2d(&state, "move");
    const jump = actions.down(&state, "jump");

    std.debug.print(
        "move=({d:.2}, {d:.2}) jump={any} save={any} reset={any}\n",
        .{
            move.x,
            move.y,
            jump,
            actions.pressed(&state, "save_bindings"),
            actions.pressed(&state, "reset_bindings"),
        },
    );
}
```

## Example JSON

```json
[
  {
    "name": "jump",
    "enabled": true,
    "kind": "codes",
    "codes": [
      { "code": "key_space" },
      { "code": "gamepad_face_south" }
    ]
  }
]
```

The stable values that matter for disk are the `InputCode` names such as
`key_space` and `gamepad_face_south`. Use:

- `inputCodeName(code)` when writing human-readable tools
- `parseInputCode(name)` when converting from custom formats
- `inputCodeLabel(code)` when rendering GUI labels

## Runnable example

See [examples/action_map_round_trip.zig](../examples/action_map_round_trip.zig).

Build:

```sh
zig build example-action-map-round-trip
./zig-out/bin/action-map-round-trip --frames 10
```

That example:

- starts with a tiny default map
- loads `action_bindings_round_trip.json` when present
- prints current live action state every frame
- saves to disk on `save_bindings`
- resets to defaults on `reset_bindings`

You can edit the JSON file manually, relaunch the example, and immediately see
the changed bindings being used.
