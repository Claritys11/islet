pragma Singleton
import QtQuick
import Quickshell

// Pomodoro timer: focus → short break → … → long break every N sessions.
// Tracks an end timestamp instead of counting ticks, so it stays exact even
// if the shell is busy or the machine sleeps.
Singleton {
    id: root

    readonly property var o: Config.opts

    // "focus" | "short" | "long"
    property string mode: "focus"
    property bool running: false
    // Session currently being worked towards the long break (1-based).
    property int round: 1
    property real _endAt: 0
    property real _pausedLeft: duration(mode)
    property real now: Date.now()

    // The whole sitting, from the first start until reset: wall-clock time
    // (breaks and pauses included), time actually spent in focus, and time
    // spent paused. Pauses are timed too, so an emergency doesn't vanish
    // from the record.
    property real sessionStart: 0
    property real _focused: 0
    property real _pausedTotal: 0
    property real _pausedAt: 0
    property real _lastTick: 0
    property bool _reminded: false

    readonly property real total: duration(mode)
    readonly property real remaining: running ? Math.max(0, (_endAt - now) / 1000) : _pausedLeft
    readonly property real progress: total > 0 ? 1 - remaining / total : 0
    // Shown in the pill once you've started a session, until you reset.
    readonly property bool active: running || _pausedLeft < total - 0.5
    readonly property string label: mode === "focus" ? "Focus" : mode === "short" ? "Short break" : "Long break"
    readonly property string clock: format(Math.ceil(remaining))

    readonly property bool paused: !running && _pausedAt > 0
    readonly property real pausedFor: paused ? (now - _pausedAt) / 1000 : 0
    readonly property real elapsed: sessionStart > 0 ? (now - sessionStart) / 1000 : 0
    readonly property real focused: _focused
    readonly property real pausedTotal: _pausedTotal + pausedFor
    // Focus and break follow each other without waiting for a click.
    readonly property bool continuous: o.autoStartBreaks && o.autoStartFocus

    readonly property string today: Qt.formatDate(new Date(now), "yyyy-MM-dd")
    readonly property int todayCount: Store.db.focusLog[today] ?? 0
    // Seconds focused today, including the part of this session not yet saved.
    readonly property real todayFocused: (Store.db.focusTime[today] ?? 0) + _focused - _savedFocus
    property real _savedFocus: 0

    // 75 → "1:15", 3700 → "1:01:40"
    function format(s) {
        s = Math.max(0, Math.floor(s));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = String(s % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${sec}` : `${m}:${sec}`;
    }

    // 4500 → "1h 15m", 600 → "10m"
    function formatShort(s) {
        const m = Math.floor(s / 60);
        return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`;
    }

    function setContinuous(on) {
        Config.set("autoStartBreaks", on, on ? "Continuous focus on" : "Continuous focus off");
        Config.set("autoStartFocus", on, on ? "Continuous focus on" : "Continuous focus off");
    }

    function duration(m) {
        return 60 * (m === "focus" ? o.focusMinutes : m === "short" ? o.shortBreakMinutes : o.longBreakMinutes);
    }

    function start() {
        if (running)
            return;
        const t = Date.now();
        if (sessionStart === 0)
            sessionStart = t;
        if (_pausedAt > 0)
            _pausedTotal += (t - _pausedAt) / 1000;
        _pausedAt = 0;
        _reminded = false;
        _endAt = t + _pausedLeft * 1000;
        _lastTick = t;
        now = t;
        running = true;
    }

    function pause() {
        if (!running)
            return;
        tick();
        _pausedLeft = remaining;
        _pausedAt = Date.now();
        running = false;
        saveFocus();
    }

    function toggle() {
        running ? pause() : start();
    }

    // Back to a fresh timer; also ends the session and its tallies.
    function reset() {
        if (running)
            tick();
        saveFocus();
        running = false;
        _pausedLeft = duration(mode);
        sessionStart = 0;
        _focused = 0;
        _savedFocus = 0;
        _pausedTotal = 0;
        _pausedAt = 0;
    }

    // Count the focus time since the last tick.
    function tick() {
        const t = Date.now();
        if (running && mode === "focus" && _lastTick > 0)
            _focused += Math.min(Math.max(0, t - _lastTick) / 1000, total);
        _lastTick = t;
        now = t;
    }

    // Store today's focused time (state.json is written on changes, so not
    // every tick).
    function saveFocus() {
        const unsaved = _focused - _savedFocus;
        if (unsaved < 1)
            return;
        const log = Object.assign({}, Store.db.focusTime);
        log[today] = Math.round((log[today] ?? 0) + unsaved);
        Store.db.focusTime = log;
        _savedFocus = _focused;
    }

    function setMode(m) {
        if (running)
            tick();
        saveFocus();
        running = false;
        mode = m;
        _pausedLeft = duration(m);
    }

    // Jump to the next phase without finishing this one.
    function skip() {
        advance(false);
    }

    function advance(completed) {
        const wasRunning = running;
        if (mode === "focus") {
            if (completed) {
                const log = Object.assign({}, Store.db.focusLog);
                log[today] = (log[today] ?? 0) + 1;
                Store.db.focusLog = log;
            }
            const longNext = round >= o.longBreakEvery;
            setMode(longNext ? "long" : "short");
            round = longNext ? 1 : round + 1;
            if (completed ? o.autoStartBreaks : wasRunning)
                start();
        } else {
            setMode("focus");
            if (completed ? o.autoStartFocus : wasRunning)
                start();
        }
    }

    function finish() {
        const ended = label;
        advance(true);
        notify(`${ended} finished`, mode === "focus" ? "Back to focus." : `Time for a ${label.toLowerCase()}.`);
    }

    // A pause that drags on (the emergency is over, or forgotten) gets one
    // nudge.
    function checkPause() {
        const limit = o.pauseReminderMinutes * 60;
        if (!paused || _reminded || limit <= 0 || pausedFor < limit)
            return;
        _reminded = true;
        notify(`Paused for ${formatShort(pausedFor)}`, `${label} is waiting: ${clock} left.`);
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-i", "alarm-symbolic", title, body]);
        if (o.pomodoroSound)
            Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"]);
    }

    // Durations changed in settings apply to a timer that hasn't started yet.
    onTotalChanged: if (!running)
        _pausedLeft = total

    Timer {
        running: root.running
        repeat: true
        interval: 250
        onTriggered: {
            root.tick();
            if (root.remaining <= 0)
                root.finish();
        }
    }

    // While paused the pause clock counts up; otherwise keep "today" fresh
    // across midnight.
    Timer {
        running: !root.running
        repeat: true
        interval: root.paused ? 1000 : 60000
        onTriggered: {
            root.now = Date.now();
            root.checkPause();
        }
    }
}
