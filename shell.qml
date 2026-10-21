//@ pragma Env QT_QUICK_CONTROLS_STYLE=Material
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    // ISLET_SHOWCASE=<dir> renders the README media instead of running.
    readonly property string showcase: Quickshell.env("ISLET_SHOWCASE") ?? ""

    LazyLoader {
        active: shell.showcase !== ""
        Showcase {
            outDir: shell.showcase
            visible: true
        }
    }

    property bool hidden: false
    property bool settingsOpen: false

    property int settingsPage: 0
    property string settingsQuery: ""

    function openSettings(page) {
        if (page !== undefined)
            shell.settingsPage = page;
        // Recreate in case the compositor closed the window behind our back.
        shell.settingsOpen = false;
        shell.settingsOpen = true;
    }

    // `qs -c islet ipc call <target> <function>` (or the `islet` CLI)
    IpcHandler {
        target: "islet"

        function setup(): void {
            shell.setupOpen = true;
        }
        function settings(): void {
            shell.settingsQuery = "";
            shell.openSettings();
        }
        // A page name opens that page; anything else searches settings.
        function open(page: string): void {
            const i = ["overview", "lyrics", "notch", "focus", "checklist", "finder", "about"].indexOf(page.toLowerCase());
            shell.settingsQuery = i >= 0 ? "" : page;
            shell.openSettings(Math.max(0, i));
        }
        // Change one setting, e.g. `islet set glow 0.9`. The value is read
        // according to the setting's type.
        function set(key: string, value: string): string {
            const def = Config.defaults[key];
            if (def === undefined)
                return `unknown setting: ${key}`;
            const v = typeof def === "number" ? Number(value) : typeof def === "boolean" ? ["1", "true", "on", "yes"].includes(value.toLowerCase()) : value;
            if (typeof v === "number" && isNaN(v))
                return `${key} needs a number`;
            Config.set(key, v, key);
            return `${key} = ${Config.opts[key]}`;
        }
        function get(key: string): string {
            return String(Config.opts[key]);
        }
    }

    IpcHandler {
        target: "lyrics"

        function toggle(): void {
            shell.hidden = !shell.hidden;
        }
        // Not called `show`: qs would parse that as its own `ipc show` command.
        function unhide(): void {
            shell.hidden = false;
        }
        function hide(): void {
            shell.hidden = true;
        }
        function refetch(): void {
            LyricsService.refetch();
        }
        function status(): string {
            const src = LyricsService.source === "spicy" ? " · Spicy Lyrics" : LyricsService.source === "lrclib" ? " · LRCLIB" : "";
            return `${LyricsService.status}${src} · ${LyricsService.artist} — ${LyricsService.title}`;
        }
        // Islet's playback clock next to what the player reports.
        function debug(): string {
            const p = LyricsService.player;
            p?.positionChanged();
            const b = SpicyBridge.sampleFor(LyricsService.spotifyId);
            const bridge = b ? (b.position + (b.playing ? (Date.now() - b.at) / 1000 : 0)).toFixed(2) : "-";
            return `source ${LyricsService.source}  bridge ${SpicyBridge.connected ? "on" : "off"} ${bridge}  clock ${LyricsService.position.toFixed(2)}  player ${(p?.position ?? -1).toFixed(2)}  playing ${LyricsService.isPlaying}  demo ${LyricsService.demo}  line ${LyricsService.currentIndex}  pace ${LyricsService.pace.toFixed(2)}  fill ${(LyricsService.progress*100).toFixed(0)}%`;
        }
    }

    IpcHandler {
        target: "notch"

        function toggle(): void {
            shell.notch?.toggle();
        }
        function open(tab: string): void {
            const i = shell.tabs.indexOf(tab);
            shell.notch?.open(i >= 0 ? i : undefined);
        }
        function close(): void {
            shell.notch?.close();
        }
        function viz(): void {
            shell.notch?.toggleViz();
        }
        function status(): string {
            const n = shell.notch;
            return n ? `mode ${n.mode}  away ${n.away}  visualizer ${n.vizWanted}` : "notch off";
        }
    }

    // Finder: `islet find [text]`, `islet find --reindex`, `islet find --print text`.
    IpcHandler {
        target: "finder"

        function open(q: string): void {
            FinderService.openRequested(q);
        }
        function reindex(): void {
            FinderService.reindex();
        }
        // Starts a search without showing anything; read it with results().
        function search(q: string): void {
            FinderService.begin(q);
        }
        function results(q: string): string {
            return FinderService.resultsFor(q);
        }
        // Search and act on the best match without showing Finder:
        // `islet find --open|--copy text`.
        function pick(q: string, action: string): void {
            FinderService.begin(q);
            FinderService.act(0, action);
        }
        function status(): string {
            const f = FinderService;
            return `${f.status}  ${f.counts.dirs} folders  ${f.counts.files} files  indexed ${f.indexedAt ? Math.round((Date.now() - f.indexedAt) / 1000) + " s ago" : "never"}`;
        }
    }

    // Today: `islet today [status|sync|preview|add "text"]`.
    IpcHandler {
        target: "today"

        function status(): string {
            return TodayService.statusText();
        }
        function reload(): void {
            TodayService.load();
        }
        function list(): string {
            return TodayService.listText();
        }
        function add(text: string): void {
            TodayService.add(text, "");
        }
        function tick(pageId: string): void {
            TodayService.tick(pageId, true);
        }
        function trashTest(): void {
            TodayService.trashTestTasks();
        }
        // The plan of the next sync, without writing anything.
        function preview(): string {
            TodayService.preview();
            return "ok";
        }
        function previewText(): string {
            return TodayService.previewText;
        }
        function confirm(): void {
            TodayService.confirmFirstSync();
        }
        function sync(): void {
            TodayService.sync();
        }
    }

    // File shelf: `islet shelf FILE…`, `islet shelf` lists, `islet shelf clear`.
    IpcHandler {
        target: "shelf"

        function add(path: string): string {
            return ShelfService.add([path]) ? `added ${path}` : `already there, or not a full path: ${path}`;
        }
        function list(): string {
            return ShelfService.items.map(i => i.path).join("\n");
        }
        function clear(): void {
            ShelfService.clear();
        }
    }

    // Share card for the song playing now.
    IpcHandler {
        target: "share"

        function open(): void {
            ShareService.show();
        }
        function copy(): void {
            ShareService.run("copy");
        }
        function save(): void {
            ShareService.run("save");
        }
    }

    IpcHandler {
        target: "pomodoro"

        function toggle(): void {
            PomodoroService.toggle();
        }
        function reset(): void {
            PomodoroService.reset();
        }
        function skip(): void {
            PomodoroService.skip();
        }
        function resetpause(): void {
            PomodoroService.resetPause();
        }
        function status(): string {
            const P = PomodoroService;
            const session = P.sessionStart > 0 ? ` · ${P.format(P.elapsed)} elapsed, ${P.formatShort(P.focused)} focus, ${P.formatShort(P.pausedTotal)} paused` : "";
            return `${P.label} ${P.clock}${P.paused ? ` (paused ${P.format(P.pausedFor)})` : P.running ? "" : " (stopped)"} · ${P.todayCount} today${session}`;
        }
    }

    IpcHandler {
        target: "checklist"

        function add(text: string): void {
            ChecklistService.add(text);
        }
        function list(): string {
            return ChecklistService.items.map(i => `${i.checked ? "[x]" : "[ ]"} ${i.text}`).join("\n");
        }
        function refresh(): void {
            ChecklistService.refresh();
        }
        function status(): string {
            return `${ChecklistService.useNotion ? "notion" : "local"} · ${ChecklistService.status}${ChecklistService.error && ChecklistService.status !== "ready" ? " · " + ChecklistService.error : ""}`;
        }
    }

    // Bar widgets (DankMaterialShell) talk to Islet over IsletLink.
    Binding {
        target: IsletLink
        property: "notchOpen"
        value: shell.notch?.mode === "open" || shell.notch?.mode === "find"
    }

    Connections {
        target: FinderService
        function onOpenRequested(prefill) {
            shell.notch?.find(prefill);
        }
    }

    // While Finder has the keyboard, a click anywhere else closes it (like a
    // popup), so the keyboard is never stuck in Islet.
    // One per screen: a click on another monitor closes it too.
    Variants {
        model: shell.notch?.mode === "find" ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "islet-finder-backdrop"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: shell.notch?.close()
            }
        }
    }

    Connections {
        target: IsletLink
        function onNotchCommand(msg) {
            const n = shell.notch;
            if (!n)
                return;
            const at = () => n.openAt(Math.max(0, shell.tabs.indexOf(msg.tab ?? "media")), msg.x >= 0 ? msg.x + (msg.width ?? 0) / 2 : -1, msg.y ?? -1);
            if (msg.cmd === "toggle") {
                if (n.mode === "open")
                    n.close();
                else
                    at();
            } else if (msg.cmd === "open") {
                at();
            } else if (msg.cmd === "close") {
                n.close();
            }
        }
    }

    // The notch lives on one monitor: the configured one, else the first.
    // The notch's tabs, by name.
    readonly property var tabs: ["media", "focus", "checklist", "shelf"]

    // Starts the background update check.
    readonly property var updates: UpdateService

    readonly property var notchScreen: Quickshell.screens.find(s => s.name === Config.opts.notchScreen) ?? Quickshell.screens[0]
    property var notch: notchWindows.instances[0] ?? null

    // A Variants rather than a loader: when the monitor sleeps or is unplugged
    // its screen object goes away, and a window left on it never shows again.
    // Keyed by screen, the window is rebuilt on the screen that comes back.
    Variants {
        id: notchWindows
        model: Config.opts.notchEnabled && shell.notchScreen && shell.showcase === "" ? [shell.notchScreen] : []

        NotchWindow {
            onSettingsRequested: shell.openSettings()
        }
    }

    LazyLoader {
        active: ShareService.open

        ShareWindow {
            screen: shell.notchScreen
        }
    }

    LazyLoader {
        active: shell.settingsOpen

        SettingsWindow {
            visible: true
            page: shell.settingsPage
            initialQuery: shell.settingsQuery
            shellNotch: shell.notch
            onVisibleChanged: if (!visible)
                shell.settingsOpen = false
            onSetupRequested: {
                visible = false;
                shell.setupOpen = true;
            }
        }
    }

    // First-run guide (and `islet setup`).
    property bool setupOpen: false
    LazyLoader {
        active: shell.setupOpen

        SetupWindow {
            visible: true
            // Closed any way at all: seen, don't open it again by itself.
            onVisibleChanged: if (!visible) {
                Store.db.setupDone = true;
                shell.setupOpen = false;
            }
            onOpenSettings: shell.openSettings(0)
        }
    }
    // Once, a moment after the very first start (state.json has loaded).
    Timer {
        running: shell.showcase === ""
        interval: 2500
        onTriggered: if (!Store.db.setupDone)
            shell.setupOpen = true
    }

    // ── Feedback while configuring ────────────────────────────────
    // Notch edits preview themselves: size changes open the island, anything
    // else shows the pill.
    Connections {
        target: Config
        function onEdited(key) {
            if (!shell.notch || !key.startsWith("notch"))
                return;
            if (key === "notchWidth" || key === "notchHeight")
                shell.notch.open();
            else
                shell.notch.close();
        }
    }

    // A toast naming each change, so you always see what you just did.
    // (In a Variants for the same reason as the notch.)
    Variants {
        model: shell.notchScreen ? [shell.notchScreen] : []

        PanelWindow {
            id: toast

            required property var modelData
            property string message
            property string detail

            screen: modelData
            anchors.bottom: true
            margins.bottom: 48
            implicitWidth: toastBox.implicitWidth + 40
            implicitHeight: 76
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            visible: toastBox.opacity > 0
            mask: Region {}
            WlrLayershell.namespace: "islet-toast"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            function format(v) {
                if (typeof v === "boolean")
                    return v ? "On" : "Off";
                if (typeof v === "number")
                    return Number.isInteger(v) ? String(v) : v.toFixed(2);
                return String(v);
            }

            Connections {
                target: Config
                function onEdited(key, label, value) {
                    // Choices, presets, resets and module switches already say
                    // what happened in their label.
                    const self = key === "" || label.includes(":") || /\b(look|reset|on|off)$/.test(label);
                    toast.message = label;
                    toast.detail = self ? "" : toast.format(value);
                    toastBox.opacity = 1;
                    toastTimer.restart();
                }
            }

            Timer {
                id: toastTimer
                interval: 1600
                onTriggered: toastBox.opacity = 0
            }

            Rectangle {
                id: toastBox
                anchors.centerIn: parent
                implicitWidth: toastRow.implicitWidth + 36
                height: 44
                radius: 22
                color: "#e6101114"
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                border.width: 1
                opacity: 0
                scale: opacity > 0.5 ? 1 : 0.92
                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutBack
                    }
                }

                Row {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "tune"
                        color: Theme.primary
                        font.family: Theme.iconFont
                        font.pixelSize: 18
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: toast.message
                        color: "#e4e4e8"
                        font.family: "Google Sans Flex"
                        font.pixelSize: 14
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: toast.detail !== ""
                        text: toast.detail
                        color: Theme.primary
                        font.family: "Google Sans Flex"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    Variants {
        model: {
            if (!Config.opts.lyricsEnabled || shell.showcase !== "")
                return [];
            const wanted = Config.opts.screens.split(",").map(s => s.trim()).filter(s => s !== "");
            const matching = Quickshell.screens.filter(s => wanted.includes(s.name));
            return wanted.length === 0 || matching.length === 0 ? Quickshell.screens : matching;
        }

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            readonly property var o: Config.opts
            readonly property bool right: o.side === "right"
            readonly property string message: {
                switch (LyricsService.status) {
                case "loading":
                    return "Looking for lyrics…";
                case "notfound":
                    return "No lyrics found";
                case "error":
                    return "Couldn't reach LRCLIB";
                default:
                    return "";
                }
            }
            readonly property bool shown: !shell.hidden && LyricsService.hasTrack
                && !(o.hideWhenPaused && !LyricsService.isPlaying)
                && !(o.hideWhenNoLyrics && LyricsService.status !== "ready")

            anchors {
                top: true
                bottom: true
                right: win.right
                left: !win.right
            }
            margins {
                top: win.o.marginTop
                bottom: win.o.marginBottom
                right: win.right ? win.o.marginSide : 0
                left: win.right ? 0 : win.o.marginSide
            }
            implicitWidth: o.width
            color: "transparent"
            visible: content.opacity > 0

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "islet-lyrics"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.layer: o.layer === "overlay" ? WlrLayer.Overlay : o.layer === "bottom" ? WlrLayer.Bottom : WlrLayer.Top

            // An empty input region lets every click fall through to the windows below.
            mask: o.clickThrough ? emptyRegion : null
            Region {
                id: emptyRegion
            }

            Item {
                id: content
                anchors.fill: parent
                opacity: win.shown ? 1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: win.o.fadeDuration
                        easing.type: Easing.InOutQuad
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: win.o.backdrop > 0
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: Qt.rgba(0, 0, 0, win.right ? 0 : win.o.backdrop)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.rgba(0, 0, 0, win.right ? win.o.backdrop : 0)
                        }
                    }
                }

                // The visible area: lyrics fade out softly at its top and
                // bottom edges instead of being cut off.
                Item {
                    id: viewport
                    width: parent.width
                    height: parent.height * Math.max(0.1, Math.min(1, win.o.viewHeight))
                    y: (parent.height - height) / 2 + win.o.viewOffset

                    readonly property real fadeFrac: Math.min(0.5, win.o.edgeFade / Math.max(height, 1))

                    layer.enabled: win.o.edgeFade > 0
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: fadeMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }

                    Rectangle {
                        id: fadeMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: "transparent"
                            }
                            GradientStop {
                                position: viewport.fadeFrac
                                color: "white"
                            }
                            GradientStop {
                                position: 1 - viewport.fadeFrac
                                color: "white"
                            }
                            GradientStop {
                                position: 1
                                color: "transparent"
                            }
                        }
                    }

                LyricsWheel {
                    anchors.fill: parent
                    items: LyricsService.status === "ready" ? LyricsService.lines : [{ main: win.message || "♪", bg: "", bgOnly: false }]
                    selected: LyricsService.status === "ready" ? LyricsService.currentIndex : 0
                    progress: LyricsService.status === "ready" ? LyricsService.progress : 0
                    onItemClicked: index => LyricsService.seek(index)
                }
                }

                // While the settings panel is open, outline the visible area
                // and its fade bands so you can see what you're adjusting.
                Rectangle {
                    visible: shell.settingsOpen
                    x: viewport.x + 6
                    y: viewport.y
                    width: viewport.width - 12
                    height: viewport.height
                    color: "transparent"
                    radius: 10
                    border.width: 2
                    border.color: Qt.rgba(0.66, 0.78, 0.98, 0.8)

                    Repeater {
                        model: 2
                        Rectangle {
                            required property int index
                            width: parent.width
                            height: Math.min(win.o.edgeFade, parent.height / 2)
                            y: index === 0 ? 0 : parent.height - height
                            radius: 10
                            color: Qt.rgba(0.66, 0.78, 0.98, 0.12)
                        }
                    }

                    Text {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: 10
                        text: `Lyrics area · ${win.o.width} × ${Math.round(viewport.height)} px`
                        color: Qt.rgba(0.66, 0.78, 0.98, 1)
                        font.pixelSize: 12
                    }
                }

                Column {
                    visible: win.o.showTrackInfo
                    anchors.bottom: parent.bottom
                    anchors.right: win.right ? parent.right : undefined
                    anchors.left: win.right ? undefined : parent.left
                    anchors.margins: 24
                    anchors.rightMargin: win.right ? win.o.inset : 24
                    anchors.leftMargin: win.right ? 24 : win.o.inset
                    spacing: 2

                    Repeater {
                        model: [
                            { text: LyricsService.title, size: 15, alpha: 0.85 },
                            { text: LyricsService.artist + (LyricsService.status === "ready" && !LyricsService.synced ? "  ·  unsynced" : ""), size: 12, alpha: 0.55 }
                        ]
                        Text {
                            required property var modelData
                            anchors.right: win.right ? parent.right : undefined
                            width: Math.min(implicitWidth, win.o.width - win.o.inset - 24)
                            text: modelData.text
                            elide: Text.ElideRight
                            color: win.o.activeColor
                            opacity: modelData.alpha
                            font.family: win.o.fontFamily
                            font.pixelSize: modelData.size
                        }
                    }
                }
            }
        }
    }
}
