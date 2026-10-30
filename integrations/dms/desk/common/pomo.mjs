// The focus timer's sitting as the widgets show it, counted from the times
// Islet sends (link/desk.mjs pomodoroView), so a paused timer needs no line
// from Islet every second. Same words and formats as the notch's Focus tab.

// 75 → "1:15", 3700 → "1:01:40"
export function clock(s) {
    s = Math.max(0, Math.floor(s));
    const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = String(s % 60).padStart(2, "0");
    return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
}

// 4500 → "1h 15m", 600 → "10m"
export function short(s) {
    const m = Math.floor(Math.max(0, s) / 60);
    return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;
}

// { pausedFor, pausedTotal, elapsed, focused } in seconds at `now` (ms).
export function sitting(p, now = Date.now()) {
    const pausedFor = p?.pausedAt > 0 ? Math.max(0, (now - p.pausedAt) / 1000) : 0;
    return {
        pausedFor,
        pausedTotal: (p?.pausedBefore ?? 0) + pausedFor,
        elapsed: p?.sessionStart > 0 ? Math.max(0, (now - p.sessionStart) / 1000) : 0,
        focused: p?.focused ?? 0
    };
}

// Dots towards the long break: which of `longEvery` are done.
export function rounds(p) {
    const n = Math.max(1, Math.min(12, p?.longEvery ?? 4));
    const done = p?.mode === "long" ? n : (p?.round ?? 1) - (p?.mode === "focus" ? 1 : 0);
    return Array.from({ length: n }, (_, i) => i < done);
}

// Under the clock: "Paused 2:13" while paused, else what it's timing.
export function status(p, now = Date.now(), lang = "en") {
    if (p?.paused)
        return `${lang === "id" ? "Dijeda" : "Paused"} ${clock(sitting(p, now).pausedFor)}`;
    return p?.label ?? (lang === "id" ? "Fokus" : "Focus");
}
