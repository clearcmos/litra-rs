// Unit tests for the plasmoid's pure helpers. No Qt, no Plasma, no device:
// `node --test tray-plasmoid/tests/` runs these anywhere, including CI.
//
// The fixture below is real `litra devices --json` output from a Litra Glow,
// with the serial number replaced. Keep it that way: the conversion maths is
// only worth testing against the shape the CLI actually emits.

import test from "node:test";
import assert from "node:assert/strict";

import {
    ERROR_BAD_JSON,
    ERROR_UNEXPECTED_SHAPE,
    deviceStateFromJson,
    lumenToPercent,
} from "../package/contents/code/litra.mjs";

const GLOW = {
    device_type: "glow",
    device_type_display: "Litra Glow",
    has_back_side: false,
    serial_number: "0000AA000000",
    device_path: "/dev/hidraw5",
    status_display: "Off",
    brightness_display: "250/250",
    temperature_display: "4500/6500",
    back_status_display: "N/A",
    back_brightness_display: "N/A",
    is_on: false,
    brightness_in_lumen: 250,
    temperature_in_kelvin: 4500,
    minimum_brightness_in_lumen: 20,
    maximum_brightness_in_lumen: 250,
    minimum_temperature_in_kelvin: 2700,
    maximum_temperature_in_kelvin: 6500,
    is_back_on: null,
    back_brightness_percentage: null,
};

function json(devices) {
    return JSON.stringify(devices);
}

test("lumenToPercent inverts the CLI's own percentage mapping", () => {
    // The CLI maps p onto p/100 * (max - min) + min, so 50% of a Glow's
    // 20-250 range is 135 lumens. Verified against the device itself.
    assert.equal(lumenToPercent(135, 20, 250), 50);
    assert.equal(lumenToPercent(250, 20, 250), 100);
});

test("lumenToPercent never reports a percentage the CLI would reject", () => {
    // `litra brightness --percentage` has value_parser range 1..=100, so the
    // floor is 1 rather than 0 even at the device's minimum brightness.
    assert.equal(lumenToPercent(20, 20, 250), 1);
    assert.equal(lumenToPercent(-5, 20, 250), 1);
    assert.equal(lumenToPercent(9999, 20, 250), 100);
});

test("lumenToPercent falls back to 100 on a degenerate or absent range", () => {
    assert.equal(lumenToPercent(100, 250, 250), 100);
    assert.equal(lumenToPercent(100, 250, 20), 100);
    assert.equal(lumenToPercent(undefined, 20, 250), 100);
    assert.equal(lumenToPercent(135, null, 250), 100);
});

test("deviceStateFromJson reads a real Litra Glow payload", () => {
    const state = deviceStateFromJson(json([GLOW]));
    assert.equal(state.ok, true);
    assert.equal(state.present, true);
    assert.equal(state.count, 1);
    assert.equal(state.name, "Litra Glow");
    assert.equal(state.on, false);
    assert.equal(state.brightnessPercent, 100);
    assert.equal(state.temperature, 4500);
    assert.equal(state.minTemperature, 2700);
    assert.equal(state.maxTemperature, 6500);
});

test("deviceStateFromJson reports an unplugged device rather than failing", () => {
    const state = deviceStateFromJson(json([]));
    assert.equal(state.ok, true);
    assert.equal(state.present, false);
    assert.equal(state.count, 0);
});

test("deviceStateFromJson treats any lit device as on", () => {
    // Regression pin: the tray icon showed lit while the light was off,
    // because the widget tracked its own guess instead of reading the device.
    // `litra on`/`off` target every device, so the icon answers "is any light
    // lit", and a single unlit device must never read as on.
    assert.equal(deviceStateFromJson(json([{ ...GLOW, is_on: true }])).on, true);
    assert.equal(deviceStateFromJson(json([GLOW])).on, false);
    assert.equal(deviceStateFromJson(json([GLOW, { ...GLOW, is_on: true }])).on, true);
    assert.equal(deviceStateFromJson(json([GLOW, GLOW])).on, false);
});

test("deviceStateFromJson only counts a literal true as on", () => {
    // hidapi reports the back light as null on devices without one; nothing
    // truthy-but-not-true may be allowed to light the icon.
    for (const value of [null, undefined, 1, "true", "Off"]) {
        assert.equal(deviceStateFromJson(json([{ ...GLOW, is_on: value }])).on, false);
    }
});

test("deviceStateFromJson surfaces unreadable output as an error code", () => {
    assert.deepEqual(deviceStateFromJson(""), { ok: false, error: ERROR_BAD_JSON });
    assert.deepEqual(deviceStateFromJson("litra: not found"), { ok: false, error: ERROR_BAD_JSON });
    assert.deepEqual(deviceStateFromJson("{}"), { ok: false, error: ERROR_UNEXPECTED_SHAPE });
    assert.deepEqual(deviceStateFromJson("[null]"), { ok: false, error: ERROR_UNEXPECTED_SHAPE });
});

test("deviceStateFromJson tolerates a device missing optional fields", () => {
    const state = deviceStateFromJson(json([{ is_on: true }]));
    assert.equal(state.ok, true);
    assert.equal(state.present, true);
    assert.equal(state.on, true);
    assert.equal(state.name, "");
    assert.equal(state.brightnessPercent, 100);
    assert.equal(state.temperature, 4500);
    assert.equal(state.minTemperature, 2700);
    assert.equal(state.maxTemperature, 6500);
});
