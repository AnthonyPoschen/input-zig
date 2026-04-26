# Input code legend

`InputCode` is the shared token namespace used by devices, action maps, JSON
bindings, and tooling.

Use these helpers instead of hard-coding display text:

- `inputCodeName(code)` for stable config tokens such as `key_space`
- `inputCodeLabel(code)` for user-facing labels such as `Space`
- `parseInputCode(name)` to turn config tokens back into `InputCode`

## Mouse codes

- `mouse_left`
- `mouse_right`
- `mouse_middle`
- `mouse_button4`
- `mouse_button5`
- `mouse_button6`
- `mouse_button7`
- `mouse_button8`
- `mouse_button9`
- `mouse_button10`
- `mouse_button11`
- `mouse_button12`
- `mouse_button13`
- `mouse_button14`
- `mouse_button15`
- `mouse_button16`

## Gamepad codes

Buttons:

- `gamepad_face_south`
- `gamepad_face_east`
- `gamepad_face_west`
- `gamepad_face_north`
- `gamepad_dpad_up`
- `gamepad_dpad_down`
- `gamepad_dpad_left`
- `gamepad_dpad_right`
- `gamepad_left_shoulder`
- `gamepad_right_shoulder`
- `gamepad_left_trigger`
- `gamepad_right_trigger`
- `gamepad_select`
- `gamepad_start`
- `gamepad_home`
- `gamepad_left_stick_press`
- `gamepad_right_stick_press`
- `gamepad_capture`

Vector and directional analog codes:

- `gamepad_left_stick`
- `gamepad_right_stick`
- `gamepad_left_stick_up`
- `gamepad_left_stick_down`
- `gamepad_left_stick_left`
- `gamepad_left_stick_right`
- `gamepad_right_stick_up`
- `gamepad_right_stick_down`
- `gamepad_right_stick_left`
- `gamepad_right_stick_right`

## Keyboard codes

Editing and control:

- `key_backspace`
- `key_tab`
- `key_enter`
- `key_pause`
- `key_caps_lock`
- `key_escape`
- `key_space`

Navigation:

- `key_page_up`
- `key_page_down`
- `key_end`
- `key_home`
- `key_left`
- `key_up`
- `key_right`
- `key_down`
- `key_print_screen`
- `key_insert`
- `key_delete`

Digits:

- `key_0`
- `key_1`
- `key_2`
- `key_3`
- `key_4`
- `key_5`
- `key_6`
- `key_7`
- `key_8`
- `key_9`

Letters:

- `key_a`
- `key_b`
- `key_c`
- `key_d`
- `key_e`
- `key_f`
- `key_g`
- `key_h`
- `key_i`
- `key_j`
- `key_k`
- `key_l`
- `key_m`
- `key_n`
- `key_o`
- `key_p`
- `key_q`
- `key_r`
- `key_s`
- `key_t`
- `key_u`
- `key_v`
- `key_w`
- `key_x`
- `key_y`
- `key_z`

System keys:

- `key_super_left`
- `key_super_right`
- `key_menu`

Numpad:

- `key_numpad_0`
- `key_numpad_1`
- `key_numpad_2`
- `key_numpad_3`
- `key_numpad_4`
- `key_numpad_5`
- `key_numpad_6`
- `key_numpad_7`
- `key_numpad_8`
- `key_numpad_9`
- `key_numpad_multiply`
- `key_numpad_add`
- `key_numpad_subtract`
- `key_numpad_decimal`
- `key_numpad_divide`

Function keys:

- `key_f1`
- `key_f2`
- `key_f3`
- `key_f4`
- `key_f5`
- `key_f6`
- `key_f7`
- `key_f8`
- `key_f9`
- `key_f10`
- `key_f11`
- `key_f12`
- `key_f13`
- `key_f14`
- `key_f15`
- `key_f16`
- `key_f17`
- `key_f18`
- `key_f19`
- `key_f20`
- `key_f21`
- `key_f22`
- `key_f23`
- `key_f24`

Locks and modifiers:

- `key_num_lock`
- `key_scroll_lock`
- `key_shift_left`
- `key_shift_right`
- `key_control_left`
- `key_control_right`
- `key_alt_left`
- `key_alt_right`

## Notes

- keyboard bindings are layout-level and shift-agnostic
- gamepad face buttons use physical-position names, not vendor labels
- directional stick codes can be used as button-like bindings with
  `activation_threshold`

For the authoritative source, see
[src/device/input_code.zig](../src/device/input_code.zig).
