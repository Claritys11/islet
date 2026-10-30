import { test } from "node:test";
import assert from "node:assert/strict";
import { clock, short, sitting, rounds, status } from "../integrations/dms/desk/common/pomo.mjs";
import { pomodoroView } from "../link/desk.mjs";

test("clock and short: the notch's formats", () => {
    assert.equal(clock(75), "1:15");
    assert.equal(clock(3700), "1:01:40");
    assert.equal(clock(-3), "0:00");
    assert.equal(short(4500), "1h 15m");
    assert.equal(short(600), "10m");
});

test("sitting: counted from the times Islet sent", () => {
    const now = 1_000_000;
    const p = { sessionStart: now - 600_000, pausedAt: now - 30_000, pausedBefore: 45, focused: 500 };
    assert.deepEqual(sitting(p, now), { pausedFor: 30, pausedTotal: 75, elapsed: 600, focused: 500 });
    assert.deepEqual(sitting({ sessionStart: 0, pausedAt: 0, pausedBefore: 0, focused: 0 }, now), { pausedFor: 0, pausedTotal: 0, elapsed: 0, focused: 0 });
    assert.deepEqual(sitting(null, now), { pausedFor: 0, pausedTotal: 0, elapsed: 0, focused: 0 });
});

test("rounds: done ones before the long break", () => {
    assert.deepEqual(rounds({ mode: "focus", round: 1, longEvery: 4 }), [false, false, false, false]);
    assert.deepEqual(rounds({ mode: "focus", round: 3, longEvery: 4 }), [true, true, false, false]);
    assert.deepEqual(rounds({ mode: "short", round: 3, longEvery: 4 }), [true, true, true, false]);
    assert.deepEqual(rounds({ mode: "long", round: 4, longEvery: 4 }), [true, true, true, true]);
});

test("status: the pause clock while paused", () => {
    const now = 1_000_000;
    assert.equal(status({ paused: true, pausedAt: now - 133_000 }, now, "id"), "Dijeda 2:13");
    assert.equal(status({ paused: false, label: "Short break" }, now), "Short break");
});

test("pomodoroView: continuous, round, tip on breaks, the sitting as times", () => {
    const P = { active: true, mode: "short", label: "Short break", clock: "4:10", running: false, paused: true, progress: 0.2,
        todayCount: 2, todayFocused: 3000, continuous: true, round: 2, tip: { icon: "water_drop", text: "Drink water" },
        sessionStart: 111, _pausedAt: 222, _pausedTotal: 33.7, focused: 1500.4 };
    const v = pomodoroView(P, { longEvery: 4, breakTips: true });
    assert.deepEqual([v.continuous, v.round, v.longEvery, v.sessionStart, v.pausedAt, v.pausedBefore, v.focused], [true, 2, 4, 111, 222, 33, 1500]);
    assert.deepEqual(v.tip, { icon: "water_drop", text: "Drink water" });
    assert.equal(pomodoroView(P, { breakTips: false }).tip, null);
    assert.equal(pomodoroView(Object.assign({}, P, { mode: "focus" }), { breakTips: true }).tip, null);
    assert.equal(pomodoroView(Object.assign({}, P, { paused: false })).pausedAt, 0);
    assert.deepEqual(JSON.parse(JSON.stringify(v)), v);
});
