import { test } from "node:test";
import assert from "node:assert/strict";
import { fillKeys, fillAt, clockAt, needsAnchor } from "../link/fill.mjs";

const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} ≠ ${b}`);

test("syllables fill from start to end and hold between them (Spicy Lyrics)", () => {
    const line = { time: 10, syl: [{ s: 10.2, e: 10.6, from: 0, to: 0.4 }, { s: 11, e: 11.5, from: 0.4, to: 1 }] };
    const k = fillKeys(line, 0);
    near(fillAt(k, 9), 0);
    near(fillAt(k, 10.1), 0);
    near(fillAt(k, 10.4), 0.2);
    near(fillAt(k, 10.8), 0.4); // the pause between syllables holds
    near(fillAt(k, 11.25), 0.7);
    near(fillAt(k, 12), 1);
});

test("a first syllable that starts part-filled jumps there, as before", () => {
    const k = fillKeys({ time: 0, syl: [{ s: 1, e: 2, from: 0.3, to: 1 }] }, 0);
    near(fillAt(k, 0.5), 0);
    near(fillAt(k, 1), 0.3);
    near(fillAt(k, 1.5), 0.65);
});

test("a line that knows its end fills evenly to it", () => {
    const k = fillKeys({ time: 4, end: 6 }, 0);
    near(fillAt(k, 3), 0);
    near(fillAt(k, 5), 0.5);
    near(fillAt(k, 7), 1);
});

test("word timings: nothing before the first word, then word by word, full after the last", () => {
    const k = fillKeys({ time: 0, words: [{ time: 1, frac: 0 }, { time: 2, frac: 0.5 }, { time: 3, frac: 0.8 }] }, 0);
    near(fillAt(k, 0.5), 0);
    near(fillAt(k, 1.5), 0.25);
    near(fillAt(k, 2.5), 0.65);
    near(fillAt(k, 3), 1);
});

test("plain lines fill over the sung length (at least 0.1 s)", () => {
    const k = fillKeys({ time: 20 }, 2);
    near(fillAt(k, 21), 0.5);
    near(fillAt(k, 25), 1);
    near(fillAt(fillKeys({ time: 0 }, 0), 0.05), 0.5);
});

test("no line, no keys: nothing filled", () => {
    assert.deepEqual(fillKeys(null, 1), []);
    near(fillAt([], 3), 0);
});

test("the clock runs from its anchor while playing and stands still when paused", () => {
    near(clockAt({ t: 10, at: 1000, playing: true, rate: 1 }, 2500), 11.5);
    near(clockAt({ t: 10, at: 1000, playing: true, rate: 2 }, 2000), 12);
    near(clockAt({ t: 10, at: 1000, playing: false, rate: 1 }, 9000), 10);
});

test("a new anchor only when the clients' guess has drifted, or play state changed", () => {
    const sent = { t: 10, at: 1000, playing: true, rate: 1 };
    assert.equal(needsAnchor(sent, 11.03, true, 1, 2000), false);
    assert.equal(needsAnchor(sent, 11.2, true, 1, 2000), true); // a seek, or drift
    assert.equal(needsAnchor(sent, 11, false, 1, 2000), true);
    assert.equal(needsAnchor(sent, 11, true, 1.5, 2000), true);
    assert.equal(needsAnchor(null, 11, true, 1, 2000), true);
});
