// Pure helpers shared by the plasmoid and its test suite.
//
// QML loads this with `import "../code/litra.mjs" as Litra` (Qt 6 treats .mjs
// as an ECMAScript module) and `node --test` loads the exact same file. Keep
// it free of Qt, QML and Plasma references so both runtimes accept it, and
// keep every function pure so the tests never need a device or a compositor.

/** Lowest value `litra brightness --percentage` accepts. */
export const MIN_BRIGHTNESS_PERCENT = 1;
/** Highest value `litra brightness --percentage` accepts. */
export const MAX_BRIGHTNESS_PERCENT = 100;

/** `litra devices --json` produced something that was not JSON. */
export const ERROR_BAD_JSON = "bad-json";
/** The JSON parsed but was not the array of device objects we expect. */
export const ERROR_UNEXPECTED_SHAPE = "unexpected-shape";

function clamp(value, lower, upper) {
    return Math.max(lower, Math.min(upper, value));
}

function isFiniteNumber(value) {
    return typeof value === "number" && Number.isFinite(value);
}

/**
 * Convert a raw lumen reading into the percentage scale the CLI accepts.
 *
 * This is the inverse of the CLI's own `percentage_within_range`, which maps
 * p onto `p / 100 * (max - min) + min`. Devices differ: a Litra Glow runs
 * 20-250 lumens, so a fixed scale would misreport every model but one.
 */
export function lumenToPercent(lumen, minLumen, maxLumen) {
    if (!isFiniteNumber(lumen) || !isFiniteNumber(minLumen) || !isFiniteNumber(maxLumen)) {
        return MAX_BRIGHTNESS_PERCENT;
    }
    if (maxLumen <= minLumen) {
        return MAX_BRIGHTNESS_PERCENT;
    }
    const percent = Math.round(((lumen - minLumen) / (maxLumen - minLumen)) * 100);
    return clamp(percent, MIN_BRIGHTNESS_PERCENT, MAX_BRIGHTNESS_PERCENT);
}

/**
 * Turn the stdout of `litra devices --json` into the state the widget renders.
 *
 * Returns `{ok: false, error}` for unreadable output, `{ok: true, present:
 * false}` when no device is plugged in, and the full state otherwise. Errors
 * are returned as codes rather than sentences so the caller owns translation.
 */
export function deviceStateFromJson(stdout) {
    let parsed;
    try {
        parsed = JSON.parse(stdout);
    } catch (error) {
        return { ok: false, error: ERROR_BAD_JSON };
    }

    if (!Array.isArray(parsed)) {
        return { ok: false, error: ERROR_UNEXPECTED_SHAPE };
    }

    if (parsed.length === 0) {
        return { ok: true, present: false, count: 0 };
    }

    const first = parsed[0];
    if (first === null || typeof first !== "object") {
        return { ok: false, error: ERROR_UNEXPECTED_SHAPE };
    }

    return {
        ok: true,
        present: true,
        count: parsed.length,
        name: typeof first.device_type_display === "string" ? first.device_type_display : "",
        // `litra on` and `litra off` target every connected device, so the
        // icon answers "is any light lit", not "is device zero lit".
        on: parsed.some((device) => device !== null && typeof device === "object" && device.is_on === true),
        brightnessPercent: lumenToPercent(
            first.brightness_in_lumen,
            first.minimum_brightness_in_lumen,
            first.maximum_brightness_in_lumen,
        ),
        temperature: isFiniteNumber(first.temperature_in_kelvin) ? first.temperature_in_kelvin : 4500,
        minTemperature: isFiniteNumber(first.minimum_temperature_in_kelvin)
            ? first.minimum_temperature_in_kelvin
            : 2700,
        maxTemperature: isFiniteNumber(first.maximum_temperature_in_kelvin)
            ? first.maximum_temperature_in_kelvin
            : 6500,
    };
}
