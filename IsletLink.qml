pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "link/desk.mjs" as Desk
import "link/fill.mjs" as Fill

// Lets other shells show Islet: a Unix socket at $XDG_RUNTIME_DIR/islet.sock
// streams Islet's state as JSON lines and accepts commands back. The
// DankMaterialShell bar widget (integrations/dms) uses it.
//
//   → {"v":1,"hasTrack":true,"title":…,"line":…,"fill":{keys,clock},"timer":{…},…}
//     A line is sent when it changes, not as it's sung: "fill" has the line's
//     karaoke keys ([[time, fill]…]) and the lyric clock's anchor {t, at,
//     playing, rate} (link/fill.mjs: fillAt(keys, clockAt(clock, now))). The
//     state goes out only when something in it changes (a few times a second
//     at most), and the anchor only when a client's clock would be 80 ms off.
//   ← {"cmd":"toggle","tab":"media","x":812,"y":44,"width":300}
//   ← {"cmd":"play-pause"} | {"cmd":"next"} | {"cmd":"previous"}
//   ← {"cmd":"volume","steps":1}  (the playing app's volume, ±5% a step)
//   ← {"cmd":"shelf-add","urls":["file:///…"]} | {"cmd":"open","tab":"shelf",x,y,width}
//
// For the DMS desktop widgets (all additive; v stays 1):
//   → also "lyrics" {index, lines:[{t,text}], status, synced}, "tasks" {status,
//     error, canDue, items}, "pomodoro" {active, mode, label, clock, running, paused,
//     progress, todayCount, todayFocused, continuous, round, longEvery, tip,
//     sessionStart, pausedAt, pausedBefore, focused} — see link/desk.mjs
//   ← {"cmd":"task-add","text":…,"due"?} (due: "YYYY-MM-DD" or with "THH:MM:SS±HH:MM") | {"cmd":"task-done","id":…,"done":bool}
//   ← {"cmd":"timer-toggle"|"timer-start"|"timer-pause"|"timer-reset"|"timer-skip"}
//     | {"cmd":"timer-mode","mode":"focus"|"short"|"long"}
//     | {"cmd":"timer-continuous","on":bool} | {"cmd":"timer-reset-pause"}
//   ← requests with an integer "req", answered to that client only with
//     {"reply":req,"ok":bool,"data"|"error"}: "notes-list" {limit?, tipe?},
//     "note-get" {id} → {blocks, cut}, "note-create" {markdown}, "task-delete" {id},
//     "calendar-month" {year, month}
//
// For the DMS dashboard tab and card (Islet's notch inside DMS):
//   → also "day" (link/desk.mjs todayView: schedule, deadlines, soon, sync,
//     canAdd, canDue, canDaily, dailyUrl, daily),
//     "shelf" [{path, name, dir, image, missing}], "checklist" {source, items}
//   ← {"cmd":"today-refresh"} | {"cmd":"shelf-open"|"shelf-remove","path":…}
//     | {"cmd":"daily-done","id":…,"done":bool} | "daily-setup" (a request)
//     | {"cmd":"shelf-follow"} (a shelf file was dragged away: look where it went)
//     | {"cmd":"shelf-paste"} | {"cmd":"shelf-clear"}
//     | {"cmd":"checklist-add","text":…} | {"cmd":"checklist-check","id":…,"checked":bool}
//     | {"cmd":"checklist-remove","id":…} | {"cmd":"checklist-clear-done"}
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
            fill: singing ? { keys: root.fillKeys, clock: root.anchor() } : null,
            source: L.source,
            timer: P.active ? { clock: P.clock, mode: P.mode, running: P.running, paused: P.paused, pausedFor: P.paused ? P.format(P.pausedFor) : "", progress: Math.round(P.progress * 1000) / 1000 } : null,
            // The words the DMS pill, tab and cards use.
            lang: Lang.code,
            bar: { notch: o.notchMode, width: o.barPillWidth, text: o.notchPillText, viz: o.barShowVisualizer, timer: o.barShowTimer, accent: Theme.primary.toString() },
            weather: o.weatherEnabled && WeatherService.ready ? { temp: WeatherService.tempText, icon: WeatherService.icon, text: WeatherService.description } : null,
            // Today: a lesson about to start (beats the song), deadlines due today.
            today: o.todayEnabled ? { soon: TodayService.soon ? Lang.startsIn(TodayService.soon.title, TodayService.soon.startAt, Date.now()) : "", due: TodayService.dueToday, dueText: TodayService.dueToday === 1 ? (d => d ? `${d.title} · ${d.label}` : "")(TodayService.deadlines.find(x => x.urgency === "today" || x.urgency === "overdue")) : Lang.dueToday(TodayService.dueToday) } : null,
            // The playing app's volume in %, or -1 when it can't be turned.
            volume: PlayerVolume.level < 0 ? -1 : Math.round(PlayerVolume.level * 100),
            notchOpen: root.notchOpen,
            // The DMS desktop widgets.
            lyrics: root.lyricsView,
            tasks: root.tasksView,
            pomodoro: Desk.pomodoroView(P, { longEvery: o.longBreakEvery, breakTips: o.breakTips }),
            // The DMS dashboard tab and card.
            day: root.dayView,
            shelf: root.shelfView,
            checklist: root.checklistView
        });
    }

    // Worked out only when their inputs change, not on every 33 ms tick.
    // The line's fill keys, rounded (they go into every state message).
    readonly property var fillKeys: LyricsService.lineKeys.map(k => [Math.round(k[0] * 1000) / 1000, Math.round(k[1] * 1000) / 1000])
    // The lyric clock as the clients last got it; renewed only when theirs
    // would be off.
    property var _anchor: null
    function anchor() {
        const L = LyricsService, t = L.timeNow(), now = Date.now();
        if (Fill.needsAnchor(_anchor, t, L.isPlaying, 1, now))
            _anchor = { t: Math.round(t * 1000) / 1000, at: now, playing: L.isPlaying, rate: 1 };
        return _anchor;
    }

    readonly property var dayView: {
        const T = TodayService, o = Config.opts;
        const ago = ms => {
            const m = Math.round((T.now - ms) / 60000);
            return Lang.ago(ms, T.now);
        };
        const sync = !o.todaySync ? Lang.t("Google Calendar sync is off", "Sinkron Google Calendar mati")
            : T.syncStatus === "waiting" ? Lang.t("First sync waits for you (Islet Settings)", "Sinkron pertama menunggu konfirmasi (Islet Settings)")
            : T.syncStatus === "error" || T.syncStatus === "held" ? T.syncError
            : T.syncStatus === "syncing" ? Lang.t("Syncing…", "Menyinkronkan…")
            : T.lastSync ? Lang.t(`Synced ${ago(T.lastSync)}`, `Tersinkron ${ago(T.lastSync)}`) : "";
        return Desk.todayView({ schedule: T.scheduleToday, deadlines: T.deadlines, soon: T.soon, enabled: o.todayEnabled, status: T.status, error: T.error || T.message, sync, tasksDb: T.tasksDb, dueColumn: T.tasksMap.due ?? "", dailyDb: T.dailyDb, daily: T.dailyToday });
    }
    readonly property var shelfView: Desk.shelfView(ShelfService.items)
    readonly property var checklistView: Desk.checklistView(ChecklistService.items, ChecklistService.useNotion, ChecklistService.error)

    readonly property var lyricsView: Object.assign(Desk.lyricWindow(LyricsService.lines, LyricsService.currentIndex), { status: LyricsService.status, synced: LyricsService.synced })
    readonly property var tasksView: ({ status: TodayService.status, error: TodayService.error, message: TodayService.message, canDue: TodayService.tasksDb !== "" && !!TodayService.tasksMap.due, items: Desk.openTasks(TodayService.tasks) })

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
            TodayService.add(String(msg.text ?? ""), Desk.validDue(msg.due), (ok, err) => root.reply(client, msg.req, ok, ok ? null : err));
            break;
        case "daily-done":
            if (msg.id)
                TodayService.tickDaily(String(msg.id), !!msg.done);
            break;
        case "daily-setup":
            TodayService.makeDaily((ok, err) => root.reply(client, msg.req, ok, ok ? null : err));
            break;
        case "task-delete":
            TodayService.remove(String(msg.id ?? ""), (ok, err) => root.reply(client, msg.req, ok, ok ? null : err));
            break;
        case "today-refresh":
            TodayService.load();
            break;
        case "shelf-open":
            if (ShelfService.items.some(i => i.path === msg.path))
                Qt.openUrlExternally(ShelfService.url(msg.path));
            break;
        case "shelf-remove":
            ShelfService.remove(String(msg.path ?? ""));
            break;
        case "shelf-follow":
            ShelfService.followSoon();
            break;
        case "shelf-paste":
            ShelfService.paste();
            break;
        case "shelf-clear":
            ShelfService.clear();
            break;
        case "checklist-add":
            ChecklistService.add(String(msg.text ?? ""));
            break;
        case "checklist-check":
            ChecklistService.setChecked(String(msg.id ?? ""), !!msg.checked);
            break;
        case "checklist-remove":
            ChecklistService.remove(String(msg.id ?? ""));
            break;
        case "checklist-clear-done":
            ChecklistService.clearDone();
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
        case "timer-continuous":
            P.setContinuous(!!msg.on);
            break;
        case "timer-reset-pause":
            P.resetPause();
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
                root.reply(client, msg.req, true, Desk.monthEvents(evs, y, m, DcalService.calendars, new Date(), Lang.code));
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

    // Sent when something changed: checked a few times a second, and at once
    // when the line or play state does.
    Timer {
        running: root.hasClients
        repeat: true
        interval: LyricsService.isPlaying || PomodoroService.running ? 250 : 1000
        onTriggered: root.broadcast(false)
    }
    Connections {
        target: LyricsService
        enabled: root.hasClients
        function onCurrentIndexChanged() {
            Qt.callLater(() => root.broadcast(false));
        }
        function onIsPlayingChanged() {
            Qt.callLater(() => root.broadcast(false));
        }
        function onLinesChanged() {
            Qt.callLater(() => root.broadcast(false));
        }
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
