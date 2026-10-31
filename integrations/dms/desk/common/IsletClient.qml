pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "slices.mjs" as Slices

// One connection to islet's socket ($XDG_RUNTIME_DIR/islet.sock) shared by
// every deskw desktop widget: the latest state, fire-and-forget commands,
// and request/reply calls (notes, calendar). While islet isn't there it
// tries again after 2 s, then waits twice as long each time up to 8 s: soon
// back after Islet restarts (an update, `islet dms`), without a
// "ConnectionRefused" in the journal every second while it's gone (M5).
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/islet.sock`
    readonly property bool connected: socket.connected
    // The last raw state line (changes every tick while music plays — don't
    // build models from it).
    property var state: null
    // The parts widgets draw; each reassigned only when it really changes.
    property var track: null
    property var lyrics: null
    property var tasks: null
    property var pomodoro: null
    property var day: null
    property var shelf: null
    property var checklist: null
    property var _json: ({})
    // Islet's language (Settings → Notch): "en" or "id". Words are written
    // as both: IsletClient.t("No classes", "Tidak ada jadwal").
    readonly property string lang: state?.lang === "id" ? "id" : "en"
    // The Islet tab shows this page when it can ("shelf": files were dragged
    // onto the pill), then clears it.
    property string panelPage: ""
    function t(en, id) {
        return lang === "id" ? id : en;
    }

    function _take(msg) {
        root.state = msg;
        const parts = Slices.splitState(msg);
        const json = {};
        for (const key of ["track", "lyrics", "tasks", "pomodoro", "day", "shelf", "checklist"]) {
            json[key] = JSON.stringify(parts[key]);
            if (json[key] !== root._json[key])
                root[key] = parts[key];
        }
        root._json = json;
    }

    function _clear() {
        root.state = null;
        root.track = null;
        root.lyrics = null;
        root.tasks = null;
        root.pomodoro = null;
        root.day = null;
        root.shelf = null;
        root.checklist = null;
        root._json = {};
    }

    property int _next: 1
    property var _pending: ({})

    function send(obj): void {
        if (!socket.connected)
            return;
        socket.write(JSON.stringify(obj) + "\n");
        socket.flush();
    }

    // cb(ok, data, error); fails at once when islet isn't connected and after
    // `timeoutMs` (20 s) without an answer. Writes to Notion pass a longer
    // one than islet's own retries (30 s × up to 4) so a slow save isn't
    // reported as failed while it still happens (review I1). Returns the
    // request's number for cancel(), or 0 when it already failed. Widgets
    // go through Requester, which cancels what's left when they're gone.
    function request(cmd, args, cb, timeoutMs): int {
        if (!socket.connected) {
            cb(false, null, "islet isn't running");
            return 0;
        }
        const req = root._next++;
        const pending = Object.assign({}, root._pending);
        pending[req] = { cb, at: Date.now(), timeout: timeoutMs ?? 20000 };
        root._pending = pending;
        root.send(Object.assign({}, args ?? {}, { cmd, req }));
        return req;
    }

    // Forget a request: its answer, if it comes, calls nobody.
    function cancel(req): void {
        if (!root._pending[req])
            return;
        const pending = Object.assign({}, root._pending);
        delete pending[req];
        root._pending = pending;
    }

    function _settle(req, ok, data, error) {
        const p = root._pending[req];
        if (!p)
            return;
        const pending = Object.assign({}, root._pending);
        delete pending[req];
        root._pending = pending;
        p.cb(ok, data, error);
    }

    Socket {
        id: socket

        path: root.path
        connected: true
        parser: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (typeof msg.reply === "number")
                    root._settle(msg.reply, msg.ok === true, msg.data ?? null, msg.error ?? "");
                else
                    root._take(msg);
            }
        }
        onConnectedChanged: {
            if (connected) {
                root._retry = 2000;
                return;
            }
            root._clear();
            for (const req of Object.keys(root._pending))
                root._settle(Number(req), false, null, "islet isn't running");
        }
    }

    property int _retry: 2000

    // Reconnect while islet is away, waiting longer each time.
    Timer {
        interval: root._retry
        repeat: true
        running: !socket.connected
        onTriggered: {
            socket.connected = true;
            root._retry = Math.min(root._retry * 2, 8000);
        }
    }

    // Time out requests nobody answered.
    Timer {
        interval: 5000
        repeat: true
        running: Object.keys(root._pending).length > 0
        onTriggered: {
            const now = Date.now();
            for (const [req, p] of Object.entries(root._pending)) {
                if (now - p.at > p.timeout)
                    root._settle(Number(req), false, null, "islet didn't answer");
            }
        }
    }
}
