pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Google Calendar through Dank Calendar (`dcal ipc … --json`): Dank Calendar
// is already signed in to the user's Google account, so Islet needs no
// Google login of its own. Formats: docs/superpowers/plans/2026-10-21-today-dcal-notes.md
Singleton {
    id: root

    property bool available: false
    // Signed in, no re-login needed: only then may missing events count as
    // deleted.
    property bool healthy: false
    property string account: ""
    property string error: ""
    // [{ id, name, accountName, accountKind, readOnly, supportedComponents }]
    property var calendars: []
    readonly property var writable: calendars.filter(c => !c.readOnly && (!c.supportedComponents || c.supportedComponents.includes("VEVENT")))
    // The user's Google calendar that Islet writes to when none is chosen.
    readonly property var primary: writable.find(c => c.accountKind === "google" && c.name === account) ?? writable.find(c => c.accountKind === "google") ?? null

    signal refreshed

    // One Process per call, so answers never mix.
    Component {
        id: callComponent
        Process {
            id: proc
            property var done
            stdout: StdioCollector {
                id: out
            }
            stderr: StdioCollector {
                id: err
            }
            onExited: code => {
                let reply = null;
                if (code === 0) {
                    try {
                        reply = JSON.parse(out.text);
                    } catch (e) {
                        code = 1;
                    }
                }
                // "Error: ipc error: ErrNotFound: event not found" → the message
                const msg = code === 0 ? "" : ((err.text.match(/ipc error: (.*)/) ?? [])[1] ?? (err.text.trim().split("\n")[0] || "Dank Calendar didn't answer"));
                proc.done(code === 0, code === 0 ? reply : msg);
                proc.destroy();
            }
        }
    }

    // cb(ok, reply | errorText). Values travel as separate arguments, never
    // through a shell.
    function call(method, params, cb) {
        const args = ["dcal", "ipc", method];
        for (const key in params) {
            const v = params[key];
            if (v !== undefined && v !== null)
                args.push(`${key}=${Array.isArray(v) ? v.join(",") : v}`);
        }
        args.push("--json");
        const p = callComponent.createObject(root, { command: args, done: cb ?? (() => {}) });
        p.running = true;
    }

    function refresh() {
        call("accounts.list", {}, (ok, accounts) => {
            available = ok;
            if (!ok) {
                healthy = false;
                error = accounts;
                refreshed();
                return;
            }
            const google = (Array.isArray(accounts) ? accounts : accounts.accounts ?? []).find(a => a.kind === "google");
            account = google?.displayName ?? "";
            healthy = !!google && !google.needsReauth && !google.authError;
            error = !google ? "No Google account in Dank Calendar" : healthy ? "" : "Google: perlu login ulang di Dank Calendar";
            call("calendars.list", {}, (ok2, cals) => {
                if (ok2)
                    calendars = Array.isArray(cals) ? cals : cals.calendars ?? [];
                refreshed();
            });
        });
    }

    // Events between two dates, series expanded (see the notes).
    function listEvents(from, to, query, cb) {
        call("events.list", { from: from.toISOString(), to: to.toISOString(), query: query || undefined }, (ok, r) => cb(ok, ok ? (Array.isArray(r) ? r : r.events ?? []) : r));
    }

    function show() {
        Quickshell.execDetached(["dcal", "show"]);
    }
}
