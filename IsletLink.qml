pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Lets other shells show Islet: a Unix socket at $XDG_RUNTIME_DIR/islet.sock
// streams Islet's state as JSON lines and accepts commands back. The
// DankMaterialShell bar widget (integrations/dms) uses it.
//
//   → {"v":1,"hasTrack":true,"title":…,"line":…,"progress":0.42,"timer":{…},…}
//   ← {"cmd":"toggle","tab":"media","x":812,"y":44,"width":300}
//   ← {"cmd":"play-pause"} | {"cmd":"next"} | {"cmd":"previous"}
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/islet.sock`
    property var clients: []
    readonly property bool hasClients: clients.length > 0
    // Set by shell.qml so the state can say whether the island is open.
    property bool notchOpen: false
    property string _last: ""

    // Commands that need the notch window are handled by shell.qml.
    signal notchCommand(var msg)

    function state() {
        const L = LyricsService;
        const l = L.lines[L.currentIndex];
        const singing = L.status === "ready" && L.synced && l && !l.interlude;
        const o = Config.opts;
        const P = PomodoroService;
        return JSON.stringify({
            v: 1,
            hasTrack: L.hasTrack,
            title: L.title,
            artist: L.artist,
            art: L.artUrl,
            playing: L.isPlaying,
            line: singing ? l.main : "",
            progress: singing ? Math.round(L.progress * 1000) / 1000 : 0,
            source: L.source,
            viz: CavaService.values.map(v => Math.round(v * 100) / 100),
            timer: P.active ? { clock: P.clock, mode: P.mode, running: P.running, paused: P.paused, pausedFor: P.paused ? P.format(P.pausedFor) : "", progress: Math.round(P.progress * 1000) / 1000 } : null,
            bar: { width: o.barPillWidth, text: o.notchPillText, viz: o.barShowVisualizer, timer: o.barShowTimer, accent: Theme.primary.toString() },
            notchOpen: root.notchOpen
        });
    }

    function broadcast(force) {
        const s = state();
        if (!force && s === _last)
            return;
        _last = s;
        for (const c of clients) {
            c.write(s + "\n");
            c.flush();
        }
    }

    function handle(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        const player = LyricsService.player;
        switch (msg.cmd) {
        case "play-pause":
            player?.togglePlaying();
            break;
        case "next":
            player?.next();
            break;
        case "previous":
            player?.previous();
            break;
        default:
            notchCommand(msg);
        }
    }

    // Fast while something moves (lyrics, timer), slow when idle.
    Timer {
        running: root.hasClients
        repeat: true
        interval: LyricsService.isPlaying || PomodoroService.running ? 50 : 1000
        onTriggered: root.broadcast(false)
    }

    // The visualizer only runs while someone shows it.
    Binding {
        target: CavaService
        property: "wanted"
        value: true
        when: root.hasClients && Config.opts.barShowVisualizer
    }

    SocketServer {
        active: true
        path: root.path
        handler: Socket {
            id: client
            parser: SplitParser {
                onRead: line => root.handle(line)
            }
            Component.onCompleted: {
                root.clients = root.clients.concat([client]);
                // Greet newcomers with the current state right away.
                Qt.callLater(() => {
                    client.write(root.state() + "\n");
                    client.flush();
                });
            }
            Component.onDestruction: root.clients = root.clients.filter(c => c !== client)
            onConnectedChanged: if (!connected)
                root.clients = root.clients.filter(c => c !== client)
        }
    }
}
