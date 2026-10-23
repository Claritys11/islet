import { test } from "node:test";
import assert from "node:assert/strict";
import { nudge, pickStreams } from "../media/volume.mjs";

test("nudge: 5% a step, kept within 0–100%, on the 5% grid", () => {
    assert.equal(nudge(0.5, 1), 0.55);
    assert.equal(nudge(0.5, -2), 0.4);
    assert.equal(nudge(0.98, 1), 1);
    assert.equal(nudge(0.03, -1), 0);
    // Spotify's own 0.727 snaps onto the grid rather than drifting.
    assert.equal(nudge(0.727, 1), 0.75);
    assert.equal(nudge(0.727, -1), 0.7);
    // Float noise (0.55 * 20 = 11.000000000000002) is on the grid.
    assert.equal(nudge(0.55, -1), 0.5);
    assert.equal(nudge(0.1 + 0.2, 1), 0.35);
    // PipeWire keeps volumes as 32-bit floats: just off the grid is on it.
    assert.equal(nudge(0.70000454, -1), 0.65);
    assert.equal(nudge(0.69999546, 1), 0.75);
});

const streams = [
    { id: 86, app: "Spotify", binary: "spotify", media: "Spotify" },
    { id: 121, app: undefined, binary: undefined, media: "Spotify" },
    { id: 100, app: "vesktop", binary: "electron", media: "Playback" },
    { id: 120, app: "Google Chrome", binary: "chrome", media: "YouTube Music" },
];
const ids = player => pickStreams(streams, player).map(s => s.id);

test("pickStreams: every stream of the player's app, by name, binary or desktop entry", () => {
    assert.deepEqual(ids({ identity: "Spotify", desktopEntry: "spotify" }), [86, 121]);
    assert.deepEqual(ids({ identity: "Google Chrome", desktopEntry: "google-chrome" }), [120]);
    assert.deepEqual(ids({ identity: "Chromium", desktopEntry: "chrome" }), [120]);
});

test("pickStreams: nothing that fits, or no player, is none", () => {
    assert.deepEqual(ids({ identity: "mpv", desktopEntry: "mpv" }), []);
    assert.deepEqual(ids(null), []);
    assert.deepEqual(pickStreams([], { identity: "Spotify", desktopEntry: "spotify" }), []);
});
