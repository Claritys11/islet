pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Looks for a newer Islet on GitHub now and then (`islet update --check`),
// and runs the update when asked. Settings shows what's new; a notification
// says so once per new version.
Singleton {
    id: root

    readonly property string script: Qt.resolvedUrl("bin/islet").toString().replace(/^file:\/\//, "")
    readonly property string log: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/islet-update.log`

    // "idle" | "checking" | "current" | "available" | "updating" | "error"
    property string status: "idle"
    property string current: ""
    property string latest: ""
    property var changes: []
    property string message: ""
    property var _out: []

    function check() {
        if (checker.running)
            return;
        _out = [];
        status = "checking";
        checker.running = true;
    }

    // The update restarts Islet, so it runs on its own and reports back with
    // a notification.
    function update() {
        status = "updating";
        Quickshell.execDetached(["sh", "-c", '"$0" update >"$1" 2>&1; notify-send -a Islet -i software-update-available "Islet" "$(grep -v -e "^  •" -e "^Update available" "$1" | tail -n 3)"', script, log]);
    }

    Process {
        id: checker
        command: ["sh", root.script, "update", "--check"]
        stdout: SplitParser {
            onRead: line => root._out.push(line)
        }
        stderr: SplitParser {
            onRead: line => root.message = line
        }
        onExited: code => {
            const out = root._out;
            const head = out.find(l => l.startsWith("Update available:")) ?? "";
            const m = head.match(/^Update available: (.*) → (.*)$/);
            if (code !== 0) {
                root.status = "error";
            } else if (m) {
                root.current = m[1];
                root.latest = m[2];
                root.changes = out.filter(l => l.startsWith("  • ")).map(l => l.slice(4));
                root.status = "available";
                if (Store.db.updateNotified !== root.latest) {
                    Store.db.updateNotified = root.latest;
                    Quickshell.execDetached(["notify-send", "-a", "Islet", "-i", "software-update-available", "Islet update available", `${root.latest} — open Islet Settings or run 'islet update'.`]);
                }
            } else {
                root.current = (out.find(l => l.startsWith("Islet is up to date")) ?? "").replace(/^.*\((.*)\)\.$/, "$1");
                root.status = "current";
            }
        }
    }

    // A minute after start, then every six hours.
    Timer {
        running: Config.opts.checkUpdates
        interval: root.status === "idle" ? 60 * 1000 : 6 * 3600 * 1000
        repeat: true
        onTriggered: root.check()
    }
}
