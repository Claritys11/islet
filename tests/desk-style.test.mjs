import { test } from "node:test";
import assert from "node:assert/strict";
import { styleFrom } from "../integrations/dms/desk/common/style.mjs";

test("defaults: solid, and glass values ready for when it's turned on", () => {
    assert.deepEqual(styleFrom(null), { glass: false, opacity: 0.55, blur: true, border: true });
    assert.deepEqual(styleFrom({}), { glass: false, opacity: 0.55, blur: true, border: true });
});

test("reads deskwStyle from DMS's plugin_settings.json", () => {
    const s = styleFrom({ deskwStyle: { style: "glass", opacity: 40, blur: false, border: false }, deskwNotes: {} });
    assert.deepEqual(s, { glass: true, opacity: 0.4, blur: false, border: false });
});

test("opacity: percent from the slider, kept between 10 and 100", () => {
    assert.equal(styleFrom({ deskwStyle: { opacity: 5 } }).opacity, 0.1);
    assert.equal(styleFrom({ deskwStyle: { opacity: 250 } }).opacity, 1);
    assert.equal(styleFrom({ deskwStyle: { opacity: "x" } }).opacity, 0.55);
});
