#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDLib.h>
#include <stdint.h>
#include <string.h>

#define INPUT_ZIG_MAX_KEYS 128
#define INPUT_ZIG_MAX_MOUSE_BUTTONS 16
#define INPUT_ZIG_MAX_GAMEPAD_BUTTONS 32
#define INPUT_ZIG_MAX_NAME_LEN 32

typedef struct {
    float scroll_x;
    float scroll_y;
    uint8_t buttons[INPUT_ZIG_MAX_MOUSE_BUTTONS];
    uint8_t key_down[INPUT_ZIG_MAX_KEYS];
    uint8_t has_key_state;
} InputZigMacEventState;

typedef struct {
    uint8_t connected;
    char name[INPUT_ZIG_MAX_NAME_LEN];
    uint64_t instance_id;
    float left_x;
    float left_y;
    float right_x;
    float right_y;
    float left_trigger;
    float right_trigger;
    uint8_t buttons[INPUT_ZIG_MAX_GAMEPAD_BUTTONS];
    uint8_t raw_report_id;
    uint8_t raw_report_len;
    uint8_t raw_report[32];
} InputZigMacGamepadState;

static CFMachPortRef input_zig_event_tap = NULL;
static CFRunLoopSourceRef input_zig_event_source = NULL;
static uint8_t input_zig_mouse_buttons[INPUT_ZIG_MAX_MOUSE_BUTTONS];
static uint8_t input_zig_key_down[INPUT_ZIG_MAX_KEYS];
static float input_zig_scroll_x = 0;
static float input_zig_scroll_y = 0;
static IOHIDManagerRef input_zig_hid_manager = NULL;
static IOHIDDeviceRef input_zig_raw_xbox_device = NULL;
static uint8_t input_zig_raw_xbox_report_buffer[64];
static uint8_t input_zig_raw_xbox_report_id = 0;
static uint8_t input_zig_raw_xbox_report_len = 0;
static uint8_t input_zig_raw_xbox_report[32];
static uint8_t input_zig_raw_xbox_home_down = 0;

static void input_zig_set_key(CGKeyCode keycode, uint8_t down) {
    if (keycode < INPUT_ZIG_MAX_KEYS) {
        input_zig_key_down[keycode] = down;
    }
}

static CGEventRef input_zig_event_callback(
    CGEventTapProxy proxy,
    CGEventType type,
    CGEventRef event,
    void *user_info
) {
    (void)proxy;
    (void)user_info;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (input_zig_event_tap != NULL) {
            CGEventTapEnable(input_zig_event_tap, true);
        }
        return event;
    }

    switch (type) {
        case kCGEventScrollWheel:
            input_zig_scroll_y += (float)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
            input_zig_scroll_x += (float)CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2);
            break;
        case kCGEventOtherMouseDown:
        case kCGEventOtherMouseUp: {
            const int64_t button = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
            if (button >= 0 && button < INPUT_ZIG_MAX_MOUSE_BUTTONS) {
                input_zig_mouse_buttons[button] = (type == kCGEventOtherMouseDown);
            }
            break;
        }
        case kCGEventKeyDown:
        case kCGEventKeyUp: {
            const CGKeyCode keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            input_zig_set_key(keycode, type == kCGEventKeyDown);
            break;
        }
        case kCGEventFlagsChanged: {
            const CGKeyCode keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            if (keycode < INPUT_ZIG_MAX_KEYS) {
                input_zig_key_down[keycode] = !input_zig_key_down[keycode];
            }
            break;
        }
        default:
            break;
    }

    return event;
}

static void input_zig_init_event_tap(void) {
    if (input_zig_event_tap != NULL) return;

    const CGEventMask mask =
        CGEventMaskBit(kCGEventScrollWheel) |
        CGEventMaskBit(kCGEventOtherMouseDown) |
        CGEventMaskBit(kCGEventOtherMouseUp) |
        CGEventMaskBit(kCGEventKeyDown) |
        CGEventMaskBit(kCGEventKeyUp) |
        CGEventMaskBit(kCGEventFlagsChanged);

    input_zig_event_tap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionListenOnly,
        mask,
        input_zig_event_callback,
        NULL
    );
    if (input_zig_event_tap == NULL) return;

    input_zig_event_source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, input_zig_event_tap, 0);
    if (input_zig_event_source == NULL) {
        CFRelease(input_zig_event_tap);
        input_zig_event_tap = NULL;
        return;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), input_zig_event_source, kCFRunLoopDefaultMode);
    CGEventTapEnable(input_zig_event_tap, true);
}

void input_zig_macos_poll_events(InputZigMacEventState *state) {
    if (state == NULL) return;

    input_zig_init_event_tap();
    if (input_zig_event_tap != NULL) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    }

    state->scroll_x = input_zig_scroll_x;
    state->scroll_y = input_zig_scroll_y;
    memcpy(state->buttons, input_zig_mouse_buttons, sizeof(input_zig_mouse_buttons));
    memcpy(state->key_down, input_zig_key_down, sizeof(input_zig_key_down));
    state->has_key_state = input_zig_event_tap != NULL;

    input_zig_scroll_x = 0;
    input_zig_scroll_y = 0;
}

static void input_zig_set_gamepad_button(InputZigMacGamepadState *state, uint32_t index, BOOL down) {
    if (index < INPUT_ZIG_MAX_GAMEPAD_BUTTONS) {
        state->buttons[index] = down ? 1 : 0;
    }
}

static void input_zig_copy_name(InputZigMacGamepadState *state, NSString *name) {
    memset(state->name, 0, INPUT_ZIG_MAX_NAME_LEN);
    if (name == nil) return;

    const char *utf8 = [name UTF8String];
    if (utf8 == NULL) return;

    const size_t len = strnlen(utf8, INPUT_ZIG_MAX_NAME_LEN);
    memcpy(state->name, utf8, len);
}

static int32_t input_zig_number_property(IOHIDDeviceRef device, CFStringRef key, int32_t fallback) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) return fallback;

    int32_t out = fallback;
    CFNumberGetValue((CFNumberRef)value, kCFNumberSInt32Type, &out);
    return out;
}

static void input_zig_copy_hid_name(InputZigMacGamepadState *state, IOHIDDeviceRef device) {
    memset(state->name, 0, INPUT_ZIG_MAX_NAME_LEN);

    CFTypeRef product = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (product == NULL || CFGetTypeID(product) != CFStringGetTypeID()) {
        memcpy(state->name, "gamepad", 7);
        return;
    }

    CFStringGetCString((CFStringRef)product, state->name, INPUT_ZIG_MAX_NAME_LEN, kCFStringEncodingUTF8);
}

static float input_zig_normalize_axis(long value, long min, long max) {
    if (max <= min) return 0;

    const float span = (float)(max - min);
    float normalized = (((float)(value - min) / span) * 2.0f) - 1.0f;
    if (normalized < -1.0f) normalized = -1.0f;
    if (normalized > 1.0f) normalized = 1.0f;
    return normalized;
}

static float input_zig_normalize_trigger(long value, long min, long max) {
    if (max <= min) return 0;

    float normalized = (float)(value - min) / (float)(max - min);
    if (normalized < 0.0f) normalized = 0.0f;
    if (normalized > 1.0f) normalized = 1.0f;
    return normalized;
}

static void input_zig_apply_hat(InputZigMacGamepadState *state, long value) {
    if (value < 0 || value > 7) return;

    const uint8_t up = value == 0 || value == 1 || value == 7;
    const uint8_t right = value == 1 || value == 2 || value == 3;
    const uint8_t down = value == 3 || value == 4 || value == 5;
    const uint8_t left = value == 5 || value == 6 || value == 7;

    state->buttons[4] = up;
    state->buttons[5] = down;
    state->buttons[6] = left;
    state->buttons[7] = right;
}

static void input_zig_apply_hid_button(InputZigMacGamepadState *state, uint32_t usage, BOOL down) {
    switch (usage) {
        case 1: input_zig_set_gamepad_button(state, 0, down); break;
        case 2: input_zig_set_gamepad_button(state, 1, down); break;
        case 3: input_zig_set_gamepad_button(state, 2, down); break;
        case 4: input_zig_set_gamepad_button(state, 3, down); break;
        case 5: input_zig_set_gamepad_button(state, 8, down); break;
        case 6: input_zig_set_gamepad_button(state, 9, down); break;
        case 7: input_zig_set_gamepad_button(state, 12, down); break;
        case 8: input_zig_set_gamepad_button(state, 13, down); break;
        case 9: input_zig_set_gamepad_button(state, 15, down); break;
        case 10: input_zig_set_gamepad_button(state, 16, down); break;
        case 11: input_zig_set_gamepad_button(state, 14, down); break;
        case 12: break;
        case 13: input_zig_set_gamepad_button(state, 14, down); break;
        case 14: break;
        default:
            if (usage < INPUT_ZIG_MAX_GAMEPAD_BUTTONS) {
                input_zig_set_gamepad_button(state, usage, down);
            }
            break;
    }
}

static void input_zig_apply_raw_xbox_report(uint32_t report_id, const uint8_t *report, CFIndex report_length) {
    if (report == NULL || report_length <= 0) return;

    const CFIndex offset = (report[0] == report_id) ? 1 : 0;
    const CFIndex payload_length = report_length - offset;
    if (payload_length <= 0) return;

    // macOS does not expose Xbox Home reliably through GameController, but
    // wired Xbox controllers report it through vendor report 7. Wireless
    // controllers have only shown ambiguous input report 1 data here, so avoid
    // guessing from that report. Capture/Share also appears in vendor reports,
    // but those reports are ambiguous with normal button telemetry, so macOS
    // intentionally leaves Capture up.
    if (report_id == 7 && payload_length >= 4) {
        input_zig_raw_xbox_home_down = report[offset + 3] != 0;
    }
}

static void input_zig_apply_raw_xbox_buttons(InputZigMacGamepadState *state) {
    input_zig_set_gamepad_button(state, 14, input_zig_raw_xbox_home_down);
}

static void input_zig_disable_system_gesture(GCControllerElement *element) {
    if (element == nil) return;

    if (@available(macOS 11.0, *)) {
        element.preferredSystemGestureState = GCSystemGestureStateDisabled;
    }
}

static GCControllerButtonInput *input_zig_physical_button(GCController *controller, NSString *name) {
    if (controller == nil || name == nil) return nil;

    if (@available(macOS 11.0, *)) {
        return [controller.physicalInputProfile.buttons objectForKey:name];
    }
    return nil;
}

static void input_zig_init_hid_manager(void) {
    if (input_zig_hid_manager != NULL) return;

    input_zig_hid_manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (input_zig_hid_manager == NULL) return;

    IOHIDManagerSetDeviceMatching(input_zig_hid_manager, NULL);
    IOHIDManagerScheduleWithRunLoop(input_zig_hid_manager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(input_zig_hid_manager, kIOHIDOptionsTypeNone);
}

static BOOL input_zig_is_gamepad_device(IOHIDDeviceRef device) {
    const int32_t page = input_zig_number_property(device, CFSTR(kIOHIDPrimaryUsagePageKey), 0);
    const int32_t usage = input_zig_number_property(device, CFSTR(kIOHIDPrimaryUsageKey), 0);

    return page == kHIDPage_GenericDesktop &&
        (usage == kHIDUsage_GD_GamePad || usage == kHIDUsage_GD_Joystick);
}

static BOOL input_zig_is_synthetic_gamepad_device(IOHIDDeviceRef device) {
    if (!input_zig_is_gamepad_device(device)) return false;

    CFTypeRef synthetic = IOHIDDeviceGetProperty(device, CFSTR("GCSyntheticDevice"));
    if (synthetic != NULL && CFGetTypeID(synthetic) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)synthetic)) {
        return true;
    }

    CFTypeRef product = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    if (product != NULL && CFGetTypeID(product) == CFStringGetTypeID()) {
        return CFStringHasPrefix((CFStringRef)product, CFSTR("GamePad-"));
    }

    return false;
}

static BOOL input_zig_is_xbox_device(IOHIDDeviceRef device) {
    const int32_t vendor_id = input_zig_number_property(device, CFSTR(kIOHIDVendorIDKey), 0);
    const int32_t usage_page = input_zig_number_property(device, CFSTR(kIOHIDPrimaryUsagePageKey), 0);
    const int32_t usage = input_zig_number_property(device, CFSTR(kIOHIDPrimaryUsageKey), 0);

    return vendor_id == 1118 && usage_page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_GamePad;
}

static void input_zig_raw_xbox_report_callback(
    void *context,
    IOReturn result,
    void *sender,
    IOHIDReportType type,
    uint32_t report_id,
    uint8_t *report,
    CFIndex report_length
) {
    (void)context;
    (void)result;
    (void)sender;
    (void)type;

    input_zig_raw_xbox_report_id = (uint8_t)report_id;
    input_zig_raw_xbox_report_len = (uint8_t)((report_length < 32) ? report_length : 32);
    memcpy(input_zig_raw_xbox_report, report, input_zig_raw_xbox_report_len);
    input_zig_apply_raw_xbox_report(report_id, report, report_length);
}

static void input_zig_register_raw_xbox_device(IOHIDDeviceRef device) {
    if (device == NULL || input_zig_raw_xbox_device == device) return;
    if (!input_zig_is_xbox_device(device)) return;

    if (input_zig_raw_xbox_device != NULL) {
        IOHIDDeviceUnscheduleFromRunLoop(input_zig_raw_xbox_device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(input_zig_raw_xbox_device);
    }

    input_zig_raw_xbox_device = (IOHIDDeviceRef)CFRetain(device);
    IOHIDDeviceScheduleWithRunLoop(input_zig_raw_xbox_device, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(
        input_zig_raw_xbox_device,
        input_zig_raw_xbox_report_buffer,
        sizeof(input_zig_raw_xbox_report_buffer),
        input_zig_raw_xbox_report_callback,
        NULL
    );
}

static void input_zig_read_raw_xbox_reports(IOHIDDeviceRef device) {
    if (device == NULL || !input_zig_is_xbox_device(device)) return;

    const uint32_t report_ids[] = { 1, 5, 7, 32 };
    for (size_t i = 0; i < sizeof(report_ids) / sizeof(report_ids[0]); i += 1) {
        uint8_t report[64] = {0};
        CFIndex report_len = sizeof(report);
        const IOReturn result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeInput,
            report_ids[i],
            report,
            &report_len
        );
        if (result != kIOReturnSuccess || report_len == 0) continue;

        input_zig_raw_xbox_report_id = (uint8_t)report_ids[i];
        input_zig_raw_xbox_report_len = (uint8_t)((report_len < 32) ? report_len : 32);
        memcpy(input_zig_raw_xbox_report, report, input_zig_raw_xbox_report_len);
        input_zig_apply_raw_xbox_report(report_ids[i], report, report_len);
    }
}

static uint8_t input_zig_poll_hid_gamepad(uint32_t slot, InputZigMacGamepadState *state) {
    input_zig_init_hid_manager();
    if (input_zig_hid_manager == NULL) return 0;

    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);

    CFSetRef devices = IOHIDManagerCopyDevices(input_zig_hid_manager);
    if (devices == NULL) return 0;
    const CFIndex count = CFSetGetCount(devices);
    IOHIDDeviceRef *device_list = calloc((size_t)count, sizeof(IOHIDDeviceRef));
    if (device_list == NULL) {
        CFRelease(devices);
        return 0;
    }

    CFSetGetValues(devices, (const void **)device_list);

    IOHIDDeviceRef selected = NULL;
    uint32_t found_slot = 0;
    for (CFIndex pass = 0; pass < 2 && selected == NULL; pass += 1) {
        found_slot = 0;
        for (CFIndex i = 0; i < count; i += 1) {
            IOHIDDeviceRef device = device_list[i];
            if (pass == 0) {
                if (!input_zig_is_synthetic_gamepad_device(device)) continue;
            } else {
                if (!input_zig_is_gamepad_device(device) || input_zig_is_synthetic_gamepad_device(device)) continue;
                input_zig_register_raw_xbox_device(device);
            }

            if (found_slot == slot) {
                selected = device;
                break;
            }
            found_slot += 1;
        }
    }

    if (selected == NULL) {
        free(device_list);
        CFRelease(devices);
        return 0;
    }

    state->connected = 1;
    state->instance_id = ((uint64_t)input_zig_number_property(selected, CFSTR(kIOHIDVendorIDKey), 0) << 32) |
        (uint32_t)input_zig_number_property(selected, CFSTR(kIOHIDProductIDKey), 0);
    input_zig_copy_hid_name(state, selected);
    input_zig_register_raw_xbox_device(selected);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    input_zig_read_raw_xbox_reports(selected);

    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(selected, NULL, kIOHIDOptionsTypeNone);
    if (elements != NULL) {
        const CFIndex element_count = CFArrayGetCount(elements);
        for (CFIndex i = 0; i < element_count; i += 1) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, i);
            const IOHIDElementType type = IOHIDElementGetType(element);
            if (type != kIOHIDElementTypeInput_Misc &&
                type != kIOHIDElementTypeInput_Button &&
                type != kIOHIDElementTypeInput_Axis) {
                continue;
            }

            IOHIDValueRef value_ref = NULL;
            if (IOHIDDeviceGetValue(selected, element, &value_ref) != kIOReturnSuccess || value_ref == NULL) {
                continue;
            }

            const uint32_t page = IOHIDElementGetUsagePage(element);
            const uint32_t usage = IOHIDElementGetUsage(element);
            const long value = IOHIDValueGetIntegerValue(value_ref);
            const long min = IOHIDElementGetLogicalMin(element);
            const long max = IOHIDElementGetLogicalMax(element);

            if (page == kHIDPage_Button) {
                input_zig_apply_hid_button(state, usage, value != 0);
            } else if (page == kHIDPage_GenericDesktop) {
                switch (usage) {
                    case kHIDUsage_GD_X:
                        state->left_x = input_zig_normalize_axis(value, min, max);
                        break;
                    case kHIDUsage_GD_Y:
                        state->left_y = -input_zig_normalize_axis(value, min, max);
                        break;
                    case kHIDUsage_GD_Rx:
                        state->right_x = input_zig_normalize_axis(value, min, max);
                        break;
                    case kHIDUsage_GD_Ry:
                        state->right_y = -input_zig_normalize_axis(value, min, max);
                        break;
                    case kHIDUsage_GD_Z:
                        state->left_trigger = input_zig_normalize_trigger(value, min, max);
                        break;
                    case kHIDUsage_GD_Rz:
                        state->right_trigger = input_zig_normalize_trigger(value, min, max);
                        break;
                    case kHIDUsage_GD_Hatswitch:
                        input_zig_apply_hat(state, value);
                        break;
                    default:
                        break;
                }
            }
        }
        CFRelease(elements);
    }

    input_zig_set_gamepad_button(state, 10, state->left_trigger > 0.05f);
    input_zig_set_gamepad_button(state, 11, state->right_trigger > 0.05f);
    input_zig_apply_raw_xbox_buttons(state);

    state->raw_report_id = input_zig_raw_xbox_report_id;
    state->raw_report_len = input_zig_raw_xbox_report_len;
    memcpy(state->raw_report, input_zig_raw_xbox_report, sizeof(state->raw_report));

    free(device_list);
    CFRelease(devices);
    return 1;
}

uint8_t input_zig_macos_poll_gamepad(uint32_t slot, InputZigMacGamepadState *state) {
    if (state == NULL) return 0;
    memset(state, 0, sizeof(*state));

    @autoreleasepool {
        if ([GCController respondsToSelector:@selector(setShouldMonitorBackgroundEvents:)]) {
            GCController.shouldMonitorBackgroundEvents = YES;
        }

        if ([GCController respondsToSelector:@selector(startWirelessControllerDiscoveryWithCompletionHandler:)]) {
            [GCController startWirelessControllerDiscoveryWithCompletionHandler:nil];
        }

        NSArray<GCController *> *controllers = [GCController controllers];
        if (slot < [controllers count]) {
            GCController *controller = [controllers objectAtIndex:slot];
            GCExtendedGamepad *pad = controller.extendedGamepad;
            if (pad != nil) {
                state->connected = 1;
                state->instance_id = slot;
                input_zig_copy_name(state, controller.vendorName);

                input_zig_set_gamepad_button(state, 0, pad.buttonA.pressed);
                input_zig_set_gamepad_button(state, 1, pad.buttonB.pressed);
                input_zig_set_gamepad_button(state, 2, pad.buttonX.pressed);
                input_zig_set_gamepad_button(state, 3, pad.buttonY.pressed);
                input_zig_set_gamepad_button(state, 4, pad.dpad.up.pressed);
                input_zig_set_gamepad_button(state, 5, pad.dpad.down.pressed);
                input_zig_set_gamepad_button(state, 6, pad.dpad.left.pressed);
                input_zig_set_gamepad_button(state, 7, pad.dpad.right.pressed);
                input_zig_set_gamepad_button(state, 8, pad.leftShoulder.pressed);
                input_zig_set_gamepad_button(state, 9, pad.rightShoulder.pressed);
                input_zig_set_gamepad_button(state, 10, pad.leftTrigger.pressed);
                input_zig_set_gamepad_button(state, 11, pad.rightTrigger.pressed);

                if (@available(macOS 10.15, *)) {
                    input_zig_disable_system_gesture(pad.buttonOptions);
                    input_zig_disable_system_gesture(pad.buttonMenu);
                    input_zig_set_gamepad_button(state, 12, pad.buttonOptions != nil && pad.buttonOptions.pressed);
                    input_zig_set_gamepad_button(state, 13, pad.buttonMenu.pressed);
                }
                if (@available(macOS 11.0, *)) {
                    input_zig_disable_system_gesture(pad.buttonHome);
                    input_zig_set_gamepad_button(state, 14, pad.buttonHome != nil && pad.buttonHome.pressed);

                    GCControllerButtonInput *physical_home = input_zig_physical_button(controller, GCInputButtonHome);
                    input_zig_disable_system_gesture(physical_home);
                    if (physical_home != nil && physical_home.pressed) {
                        input_zig_set_gamepad_button(state, 14, true);
                    }
                }
                if (@available(macOS 10.14.1, *)) {
                    input_zig_set_gamepad_button(state, 15, pad.leftThumbstickButton != nil && pad.leftThumbstickButton.pressed);
                    input_zig_set_gamepad_button(state, 16, pad.rightThumbstickButton != nil && pad.rightThumbstickButton.pressed);
                }
                if (@available(macOS 12.0, *)) {
                    if ([pad isKindOfClass:[GCXboxGamepad class]]) {
                        GCXboxGamepad *xbox = (GCXboxGamepad *)pad;
                        input_zig_disable_system_gesture(xbox.buttonShare);
                    }
                }

                state->left_x = pad.leftThumbstick.xAxis.value;
                state->left_y = pad.leftThumbstick.yAxis.value;
        state->right_x = pad.rightThumbstick.xAxis.value;
        state->right_y = pad.rightThumbstick.yAxis.value;
        state->left_trigger = pad.leftTrigger.value;
        state->right_trigger = pad.rightTrigger.value;
        input_zig_set_gamepad_button(state, 10, state->left_trigger > 0.05f);
        input_zig_set_gamepad_button(state, 11, state->right_trigger > 0.05f);
    }
        }
    }

    if (state->connected) {
        InputZigMacGamepadState hid_state;
        memset(&hid_state, 0, sizeof(hid_state));
        if (input_zig_poll_hid_gamepad(slot, &hid_state)) {
            if (hid_state.buttons[14]) state->buttons[14] = 1;
            state->raw_report_id = hid_state.raw_report_id;
            state->raw_report_len = hid_state.raw_report_len;
            memcpy(state->raw_report, hid_state.raw_report, sizeof(state->raw_report));
        }
        return 1;
    }

    return input_zig_poll_hid_gamepad(slot, state);
}
