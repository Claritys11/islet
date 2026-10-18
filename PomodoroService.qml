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

    readonly property real total: duration(mode)
    readonly property real remaining: running ? Math.max(0, (_endAt - now) / 1000) : _pausedLeft
    readonly property real progress: total > 0 ? 1 - remaining / total : 0
    // Shown in the pill once you've started a session, until you reset.
    readonly property bool active: running || _pausedLeft < total - 0.5
    readonly property string label: mode === "focus" ? "Focus" : mode === "short" ? "Short break" : "Long break"
    readonly property string clock: {
        const s = Math.ceil(remaining);
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    readonly property string today: Qt.formatDate(new Date(now), "yyyy-MM-dd")
    readonly property int todayCount: Store.db.focusLog[today] ?? 0

    function duration(m) {
        return 60 * (m === "focus" ? o.focusMinutes : m === "short" ? o.shortBreakMinutes : o.longBreakMinutes);
    }

    function start() {
        if (running)
            return;
        _endAt = Date.now() + _pausedLeft * 1000;
        now = Date.now();
        running = true;
    }

    function pause() {
        if (!running)
            return;
        _pausedLeft = remaining;
        running = false;
    }

    function toggle() {
        running ? pause() : start();
    }

    function reset() {
        running = false;
        _pausedLeft = duration(mode);
    }

    function setMode(m) {
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
            root.now = Date.now();
            if (root.remaining <= 0)
                root.finish();
        }
    }

    // Keep "today" fresh across midnight.
    Timer {
        running: !root.running
        repeat: true
        interval: 60000
        onTriggered: root.now = Date.now()
    }
}
