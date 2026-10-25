pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "link/desk.mjs" as Desk

// Lets other shells show Islet: a Unix socket at $XDG_RUNTIME_DIR/islet.sock
// streams Islet's state as JSON lines and accepts commands back. The
// DankMaterialShell bar widget (integrations/dms) uses it.
//
//   → {"v":1,"hasTrack":true,"title":…,"line":…,"progress":0.42,"timer":{…},…}
//   ← {"cmd":"toggle","tab":"media","x":812,"y":44,"width":300}
//   ← {"cmd":"play-pause"} | {"cmd":"next"} | {"cmd":"previous"}
//   ← {"cmd":"volume","steps":1}  (the playing app's volume, ±5% a step)
//   ← {"cmd":"shelf-add","urls":["file:///…"]} | {"cmd":"open","tab":"shelf",x,y,width}
//
// For the DMS desktop widgets (all additive; v stays 1):
//   → also "lyrics" {index, lines:[{t,text}], status, synced}, "tasks" {status,
//     error, items}, "pomodoro" {active, mode, label, clock, running, paused,
//     progress, todayCount, todayFocused} — see link/desk.mjs
//   ← {"cmd":"task-add","text":…,"due"?} | {"cmd":"task-done","id":…,"done":bool}
//   ← {"cmd":"timer-toggle"|"timer-start"|"timer-pause"|"timer-reset"|"timer-skip"}
//     | {"cmd":"timer-mode","mode":"focus"|"short"|"long"}
//   ← requests with an integer "req", answered to that client only with
//     {"reply":req,"ok":bool,"data"|"error"}: "notes-list" {limit?, tipe?},
//     "note-get" {id} → {blocks, cut}, "note-create" {markdown}, "task-delete" {id},
//     "calendar-month" {year, month}
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
            // A local file: the bar widget never loads art over https (see ArtCache).
            art: ArtCache.local,
            playing: L.isPlaying,
            line: singing ? l.main : "",
            progress: singing ? Math.round(L.progress * 1000) / 1000 : 0,
            source: L.source,
            viz: CavaService.small.map(v => Math.round(v * 100) / 100),
            timer: P.active ? { clock: P.clock, mode: P.mode, running: P.running, paused: P.paused, pausedFor: P.paused ? P.format(P.pausedFor) : "", progress: Math.round(P.progress * 1000) / 1000 } : null,
            bar: { width: o.barPillWidth, text: o.notchPillText, viz: o.barShowVisualizer, timer: o.barShowTimer, accent: Theme.primary.toString() },
            weather: o.weatherEnabled && WeatherService.ready ? { temp: WeatherService.tempText, icon: WeatherService.icon, text: WeatherService.description } : null,
            // Today: a lesson about to start (beats the song), deadlines due today.
            today: o.todayEnabled ? { soon: TodayService.soon ? `${TodayService.soon.title} · mulai ${Math.max(1, Math.ceil((TodayService.soon.startAt - Date.now()) / 60000))} mnt lagi` : "", due: TodayService.dueToday, dueText: TodayService.dueToday === 1 ? (d => d ? `${d.title} · ${d.label}` : "")(TodayService.deadlines.find(x => x.urgency === "today" || x.urgency === "overdue")) : `${TodayService.dueToday} tenggat hari ini` } : null,
            // The playing app's volume in %, or -1 when it can't be turned.
            volume: PlayerVolume.level < 0 ? -1 : Math.round(PlayerVolume.level * 100),
            notchOpen: root.notchOpen,
            // The DMS desktop widgets.
            lyrics: root.lyricsView,
            tasks: root.tasksView,
            pomodoro: Desk.pomodoroView(P)
        });
    }

    // Worked out only when their inputs change, not on every 33 ms tick.
    readonly property var lyricsView: Object.assign(Desk.lyricWindow(LyricsService.lines, LyricsService.currentIndex), { status: LyricsService.status, synced: LyricsService.synced })
    readonly property var tasksView: ({ status: TodayService.status, error: TodayService.error, message: TodayService.message, items: Desk.openTasks(TodayService.tasks) })

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

    // An answer to one client's request (the desktop widgets).
    function reply(client, req, ok, payload) {
        if (!client || typeof req !== "number")
            return;
        const msg = ok ? { reply: req, ok: true, data: payload } : { reply: req, ok: false, error: String(payload) };
        client.write(JSON.stringify(msg) + "\n");
        client.flush();
    }

    function handle(line, client) {
        const msg = Desk.parseCommand(line);
        if (!msg)
            return;
        const player = LyricsService.player;
        const P = PomodoroService;
        switch (msg.cmd) {
        case "task-add":
            TodayService.add(String(msg.text ?? ""), msg.due ? String(msg.due) : "", (ok, err) => root.reply(client, msg.req, ok, ok ? null : err));
            break;
        case "task-delete":
            TodayService.remove(String(msg.id ?? ""), (ok, err) => root.reply(client, msg.req, ok, ok ? null : err));
            break;
        case "task-done":
            if (msg.id)
                TodayService.tick(String(msg.id), !!msg.done);
            break;
        case "timer-toggle":
            P.toggle();
            break;
        case "timer-start":
            if (!P.running)
                P.start();
            break;
        case "timer-pause":
            if (P.running)
                P.pause();
            break;
        case "timer-reset":
            P.reset();
            break;
        case "timer-skip":
            P.skip();
            break;
        case "timer-mode":
            if (["focus", "short", "long"].includes(msg.mode))
                P.setMode(msg.mode);
            break;
        case "notes-list":
            NotesService.list(Number(msg.limit) || 30, msg.tipe ? String(msg.tipe) : "", (ok, data) => root.reply(client, msg.req, ok, data));
            break;
        case "note-get":
            NotesService.get(String(msg.id ?? ""), (ok, data, cut) => root.reply(client, msg.req, ok, ok ? { blocks: data, cut: !!cut } : data));
            break;
        case "note-create":
            NotesService.create(String(msg.markdown ?? ""), (ok, data) => root.reply(client, msg.req, ok, data));
            break;
        case "calendar-month": {
            const y = Number(msg.year), m = Number(msg.month);
            if (!(y > 1970 && m >= 0 && m <= 11)) {
                root.reply(client, msg.req, false, "bad month");
                break;
            }
            DcalService.listEvents(new Date(y, m, 1), new Date(y, m + 1, 1), "", (ok, evs) => {
                if (!ok)
                    return root.reply(client, msg.req, false, evs || "Dank Calendar didn't answer");
                root.reply(client, msg.req, true, Desk.monthEvents(evs, y, m, DcalService.calendars, new Date()));
            });
            break;
        }
        case "play-pause":
            player?.togglePlaying();
            break;
        case "next":
            player?.next();
            break;
        case "previous":
            player?.previous();
            break;
        case "volume":
            PlayerVolume.nudge(Math.max(-4, Math.min(4, Math.round(Number(msg.steps) || 0))));
            break;
        case "shelf-add":
            ShelfService.add(msg.urls ?? []);
            break;
        default:
            notchCommand(msg);
        }
    }

    // Fast while something moves (lyrics, timer), slow when idle.
    Timer {
        running: root.hasClients
        repeat: true
        interval: LyricsService.isPlaying || PomodoroService.running ? 33 : 1000
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
                onRead: line => root.handle(line, client)
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
