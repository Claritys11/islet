import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Islet settings. Every change applies live, is saved to
// ~/.config/islet/config.json, and is called out: the row lights up, changed
// rows get a dot and a reset button, the sidebar counts changes per module,
// and a toast on screen names what changed.
FloatingWindow {
    id: win

    title: "Islet Settings"
    implicitWidth: 900
    implicitHeight: 700
    color: bg

    // The notch window, if enabled (for preview buttons).
    property var shellNotch: null
    // Test mode: sample lyrics on screen while configuring. On by itself
    // when nothing plays (if samplePreview is set); the switches override it.
    property var sampleOverride: undefined
    // Opened as `islet settings <words>`: start with that search.
    property string initialQuery: ""
    property int page: 0

    readonly property var o: Config.opts
    readonly property color bg: "#121316"
    readonly property color card: "#1b1c20"
    readonly property color text: "#e4e4e8"
    readonly property color subtext: "#9a9ca5"
    readonly property color accent: Theme.primary
    readonly property string font: "Google Sans Flex"

    Binding {
        target: LyricsService
        property: "demo"
        value: win.visible && (win.sampleOverride !== undefined ? win.sampleOverride : win.o.samplePreview && (LyricsService.player?.trackTitle ?? "") === "")
        restoreMode: Binding.RestoreValue
    }

    // Which settings belong to which page (for the change badges).
    readonly property var pages: [
        { icon: "dashboard", title: "Overview", subtitle: "Modules and quick looks", keys: ["maxFps"] },
        { icon: "lyrics", title: "Lyrics", subtitle: "Synced lyrics on the screen edge", keys: ["lyricsEnabled", "karaoke", "fillSpeed", "unsungOpacity", "feather", "glow", "glowColor", "bgVocals", "bgScale", "bgOpacity", "bgItalic", "bgLinger", "activeColor", "textColor", "fontFamily", "fontSize", "minFontSize", "longLines", "restingWeight", "activeWeight", "spacing", "curve", "tilt", "blur", "fade", "visibleLines", "smoothing", "side", "width", "viewHeight", "viewOffset", "edgeFade", "inset", "marginTop", "marginBottom", "marginSide", "layer", "screens", "clickThrough", "shadow", "backdrop", "showTrackInfo", "hideWhenPaused", "hideWhenNoLyrics", "player", "samplePreview", "lyricsSource", "spicyOffsetMs", "offsetMs", "lrclibUrl"] },
        { icon: "page_header", title: "Notch", subtitle: "Dynamic island, or in your bar", keys: ["language", "notchEnabled", "notchMode", "barPillWidth", "barShowVisualizer", "barShowTimer", "notchShape", "notchStyle", "notchPillText", "notchIdle", "notchScreen", "notchMarginTop", "notchPillWidth", "notchWidth", "notchHeight", "notchHoverDelay", "notchAutoClose", "notchCloseDelay", "vizMode", "vizIdleSeconds", "weatherEnabled", "weatherCity", "weatherUnit"] },
        { icon: "timer", title: "Focus", subtitle: "Pomodoro timer", keys: ["focusMinutes", "shortBreakMinutes", "longBreakMinutes", "longBreakEvery", "autoStartBreaks", "autoStartFocus", "pomodoroSound", "pauseReminderMinutes", "breakTips"] },
        { icon: "checklist", title: "Checklist", subtitle: "Local or Notion to-dos", keys: ["checklistSource", "notionPage"] },
        { icon: "event_note", title: "Calendar & Notion", subtitle: "Lessons, deadlines, Google sync", keys: ["todayEnabled", "todaySync", "todaySyncLessons", "todayCalendar", "todayTimetableDb", "todayTasksDb", "todayDailyDb", "notesDb", "todayColumns", "todayDays", "todayMorningOpen", "todayMorningSeconds", "todayNudges", "todayEventMinutes", "todaySemesterEnd", "todaySyncMinutes"] },
        { icon: "search", title: "Finder", subtitle: "Find files and folders", keys: ["finderRoots", "finderExclude", "finderHidden", "finderFileManager", "finderTerminal", "finderEditor", "finderReindexMinutes"] },
        { icon: "widgets", title: "DankMaterialShell", subtitle: "Bar, desktop widgets, notepad", keys: [] },
        { icon: "info", title: "About", subtitle: "Updates, files, shortcuts", keys: ["checkUpdates"] }
    ]

    // Bumped on every edit so the change badges recount.
    property int _revision: 0
    Connections {
        target: Config
        function onEdited() {
            win._revision++;
        }
    }

    function changedCount(keys, revision) {
        return keys.filter(k => Config.opts[k] !== Config.defaults[k]).length;
    }

    readonly property var presets: Config.presets
    function applyPreset(p) {
        Config.applyPreset(p);
    }

    // ── Search ────────────────────────────────────────────────────
    // Every setting row registers itself here (key → row), so search can
    // find it and jump to it.
    property var rows: ({})
    // (A QML var property hands out copies of objects; mutating one would
    // be lost, so the map is replaced instead.)
    function register(key, row) {
        const next = Object.assign({}, rows);
        next[key] = row;
        rows = next;
    }

    // Questions people actually ask, with the answer and where to go.
    readonly property var guides: [
        { words: "google calendar kalender gcal sync sinkron", title: "Sync with Google Calendar", answer: "Islet uses Dank Calendar, which is already signed in to Google. Check the preview on the Calendar & Notion page and press Confirm once.", key: "todaySync" },
        { words: "notion template templat database databases bikin buat create setup new baru teman friend", title: "Make the Notion databases for me", answer: "On the Calendar & Notion page: 'Make Islet's databases' builds a timetable, task list, notes and checklist in a page you shared, and Islet uses them.", action: "page:Calendar & Notion" },
        { words: "notion jadwal pelajaran timetable schedule lesson kelas", title: "Lessons from your Notion timetable", answer: "Islet finds your timetable database by itself; pick another one on the Calendar & Notion page if it chose wrong.", key: "todayTimetableDb" },
        { words: "daily harian rutin routine habit tugas harian", title: "Daily tasks", answer: "Things to do on certain days, kept in a Daily Tasks list in Notion (Hari: which days, none is every day; Jam: a time). Tick them in Hari ini → Daily or in Notion's Selesai column; ticks come off by themselves on a new day.", key: "todayDailyDb" },
        { words: "tugas task deadline tenggat due homework pr", title: "Deadlines from Notion", answer: "Tasks that aren't Done and are due within a few days show in the notch's Hari ini tab. Tick one to mark it Done in Notion.", key: "todayDays" },
        { words: "pagi morning remind reminder pengingat lupa", title: "Don't forget to check", answer: "The notch opens to Hari ini at your first activity each morning, and you get a nudge before a deadline.", key: "todayMorningOpen" },
        { words: "find search file files folder folders listary launcher locate project dolphin open", title: "Find a file or folder", answer: "Press Mod+G (or run 'islet find'), type part of the name — \"isw\" finds islet-windows — and press Enter. Ctrl+T opens a terminal there, Ctrl+E the editor.", key: "finderRoots" },
        { words: "keybind shortcut hotkey key mod+g finder", title: "Shortcut for Finder", answer: "Press 'Set it up' on the Finder page: it adds Mod+G to niri for you.", key: "finderTerminal" },
        { words: "terminal ghostty kitty vscode code editor", title: "Open results in another terminal or editor", answer: "Type the program on the Finder page; empty picks one that's installed.", key: "finderTerminal" },
        { words: "youtube music yt browser chrome chromium firefox brave web video", title: "Use YouTube or YouTube Music", answer: "Nothing to set up: play it in your browser and Islet follows it. If several things play at once, the preferred player wins.", key: "player" },
        { words: "spotify spicy spicetify exact timing syllable", title: "Exact timing with Spicy Lyrics (Spotify)", answer: "Run 'islet spicetify' once in a terminal (Spotify restarts). Then the source below says Spicy Lyrics.", key: "lyricsSource" },
        { words: "early late fast slow sync out off delay offset ahead behind timing too", title: "Lyrics too early or too late", answer: "Move the timing offset. Positive shows lines earlier.", key: "offsetMs" },
        { words: "fill speed karaoke too fast slow sweep", title: "Karaoke fill too fast or slow", answer: "Fill speed changes how quickly a line lights up (for songs without word timing).", key: "fillSpeed" },
        { words: "wrong lyrics version different song live remix", title: "Wrong lyrics for this song", answer: "Pick another version from LRCLIB for the song playing now.", key: "lyricsSource" },
        { words: "bar dms dankmaterialshell panel widget top media", title: "Put Islet in the DankMaterialShell bar", answer: "Choose 'In the DMS bar', then 'Set up DMS bar widget'.", key: "notchMode" },
        { words: "language bahasa indonesia english inggris translate terjemah words", title: "Notch in English or Bahasa Indonesia", answer: "Pick the language on the Notch page.", key: "language" },
        { words: "floating island notch top pill", title: "Floating island instead of the bar", answer: "Choose 'Floating island'.", key: "notchMode" },
        { words: "desktop widget widgets dms clock jam calendar kalender notes catatan todo pomodoro github glass end4 wallpaper", title: "Widgets on the desktop", answer: "On the DankMaterialShell page: 'Put them on the desktop' adds Lyrics, To-Do, Notes, Pomodoro, Calendar and a clock, laid out for you.", action: "page:DankMaterialShell" },
        { words: "notepad toolbar bold format markdown dms", title: "Formatting toolbar in DMS's notepad", answer: "On the DankMaterialShell page: 'Add the toolbar'.", action: "page:DankMaterialShell" },
        { words: "close closes closing stay open shut leave pin drag drop", title: "The notch closes too soon", answer: "Pin it with 📌, use the Shelf tab, or close it later.", key: "notchCloseDelay" },
        { words: "shelf file files drag drop keep park", title: "File shelf", answer: "Drag files onto the notch or the Islet pill in your bar; drag them out into any app. Open it with the Shelf tab." },
        { words: "share picture image photo instagram story card screenshot", title: "Share the song as a picture", answer: "The ⬆ button in the notch's Media tab (or 'islet share') makes a card to copy or save." },
        { words: "weather city temperature location celsius fahrenheit", title: "Weather", answer: "Shown when nothing plays. Type your city, or leave it empty to use DankMaterialShell's location.", key: "weatherCity" },
        { words: "visualizer away idle afk screen", title: "Visualizer when you're away", answer: "The notch turns into a visualizer after you've been away for a while.", key: "vizMode" },
        { words: "pomodoro timer focus minutes length long work", title: "Focus timer length", answer: "Set focus, short and long break lengths.", key: "focusMinutes" },
        { words: "continuous auto start automatic loop deep focus", title: "Keep focus going by itself", answer: "Start breaks and focus automatically (the ∞ button in the Focus tab does both).", key: "autoStartFocus" },
        { words: "break tips stretch water eyes", title: "Break tips", answer: "A suggestion for each break.", key: "breakTips" },
        { words: "pause emergency reminder", title: "Pause reminder", answer: "Get one nudge when a pause runs long.", key: "pauseReminderMinutes" },
        { words: "notion tasks todo to-do checklist sync", title: "Tasks from Notion", answer: "Paste your integration secret and page link here.", key: "checklistSource" },
        { words: "colour color theme glow neon look style preset", title: "Change how the lyrics look", answer: "Try a look preset, or set colours and glow yourself.", key: "glow" },
        { words: "big bigger small smaller font size text", title: "Bigger or smaller lyrics", answer: "Change the text size.", key: "fontSize" },
        { words: "left right side position move", title: "Lyrics on the left or right", answer: "Pick the side of the screen.", key: "side" },
        { words: "hide disable turn off remove lyrics overlay wheel edge", title: "Turn the lyrics on the screen edge off", answer: "Switch the overlay off; lyrics still show in the notch.", key: "lyricsEnabled" },
        { words: "cpu battery performance lag slow heavy smooth fps laggy", title: "Make Islet lighter", answer: "Choose 'Light · 30' for less CPU and battery.", key: "maxFps" },
        { words: "update version upgrade new", title: "Updates", answer: "Islet checks for updates; update with one click or 'islet update'.", key: "checkUpdates" },
        { words: "test sample demo preview example", title: "Test with sample lyrics", answer: "The switch at the bottom left shows sample lyrics while you change things.", key: "samplePreview" },
        { words: "setup guide start beginning wizard welcome help", title: "Run the setup guide again", answer: "A few questions that set Islet up for you.", action: "setup" }
    ]

    function search(query) {
        const words = query.toLowerCase().split(/\s+/).filter(w => w.length > 1);
        if (words.length === 0)
            return [];
        const hit = (hay, w) => hay.includes(w) ? 1 : 0;
        const out = [];
        for (const g of guides) {
            const hay = `${g.words} ${g.title}`.toLowerCase();
            const n = words.reduce((a, w) => a + hit(hay, w), 0);
            if (n > 0)
                out.push({ score: n * 3 + 1, title: g.title, answer: g.answer, key: g.key ?? "", action: g.action ?? "", where: g.key ? pageTitleOf(g.key) : (g.action ?? "").startsWith("page:") ? g.action.slice(5) : "" });
        }
        for (const key in rows) {
            const r = rows[key];
            const hay = `${r.label} ${r.hint} ${key}`.toLowerCase();
            const n = words.reduce((a, w) => a + hit(hay, w), 0);
            if (n > 0 && !out.some(o => o.key === key))
                out.push({ score: n * 2, title: r.label, answer: r.hint, key, action: "", where: pageTitleOf(key) });
        }
        return out.sort((a, b) => b.score - a.score).slice(0, 12);
    }

    function pageTitleOf(key) {
        return pages.find(p => p.keys.includes(key))?.title ?? "";
    }

    // Show a setting: its page, scrolled to it, glowing.
    function jumpTo(key) {
        const i = pages.findIndex(p => p.keys.includes(key));
        if (i >= 0)
            page = i;
        jumpTimer.key = key;
        jumpTimer.restart();
    }
    // Scroll once the page has been laid out.
    Timer {
        id: jumpTimer
        property string key
        interval: 120
        onTriggered: {
            const r = win.rows[key];
            if (!r)
                return;
            let f = r.parent;
            while (f && f.contentY === undefined)
                f = f.parent;
            if (f)
                f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, r.mapToItem(f.contentItem, 0, 0).y - 90));
            r.pulse();
        }
    }

    signal setupRequested

    // `islet settings weatherCity` goes straight to that setting.
    // (Later: the rows register themselves once they're all built.)
    Component.onCompleted: Qt.callLater(() => {
        if (!rows[initialQuery])
            return;
        const key = initialQuery;
        searchField.text = "";
        jumpTo(key);
    })
    readonly property string query: searchField.text.trim()
    readonly property var results: search(query)

    function openResult(r) {
        searchField.text = "";
        if (r.action === "setup")
            setupRequested();
        else if (r.action.startsWith("page:"))
            page = Math.max(0, pages.findIndex(p => p.title === r.action.slice(5)));
        else if (r.key !== "")
            jumpTo(r.key);
    }

    function fmtTime(s) {
        s = Math.max(0, Math.round(s));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    // ── Building blocks ───────────────────────────────────────────
    component Icon: Text {
        property real size: 20
        font.family: Theme.iconFont
        font.pixelSize: size
        font.hintingPreference: Font.PreferNoHinting
        font.variableAxes: ({ FILL: 0, GRAD: 0, opsz: 24, wght: 400 })
        color: win.subtext
    }

    // A DankMaterialShell part Islet sets up with `islet dms …`: whether it's
    // in, and a button to put it in or take it out.
    component DmsPart: ColumnLayout {
        id: part
        property var statusArgs: []
        property var installArgs: []
        property var uninstallArgs: []
        // The status command's output → is it set up?
        property var isIn: out => false
        property string inText: "Set up"
        property string outText: "Not set up"
        property string installText: "Set up"
        property string uninstallText: "Remove"
        // Said before a step that briefly takes DMS away.
        property string warn: ""
        property bool on: false
        property bool known: false
        property string said: ""
        readonly property string islet: decodeURIComponent(String(Qt.resolvedUrl("bin/islet")).replace(/^file:\/\//, ""))
        function refresh() {
            if (!statusProc.running)
                statusProc.running = true;
        }
        function run(args) {
            said = "";
            actProc.command = ["sh", islet].concat(args);
            actProc.running = true;
        }
        Layout.fillWidth: true
        spacing: 6
        Component.onCompleted: refresh()
        Connections {
            target: win
            function onPageChanged() {
                part.refresh();
            }
        }
        Process {
            id: statusProc
            command: ["sh", part.islet].concat(part.statusArgs)
            stdout: StdioCollector {
                id: statusOut
            }
            onExited: {
                part.on = part.isIn(statusOut.text);
                part.known = true;
            }
        }
        Process {
            id: actProc
            stdout: StdioCollector {
                id: actOut
            }
            stderr: StdioCollector {
                id: actErr
            }
            onExited: code => {
                part.said = (code === 0 ? actOut.text : actErr.text || actOut.text).trim().split("\n")[0] ?? "";
                part.refresh();
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: !part.known ? "…" : part.on ? "● " + part.inText : "○ " + part.outText
                color: part.on ? "#a5d6a7" : win.subtext
                font.family: win.font
                font.pixelSize: 12
            }
            Button {
                visible: part.known && part.on && part.uninstallArgs.length > 0
                text: part.uninstallText
                flat: true
                enabled: !actProc.running
                onClicked: part.run(part.uninstallArgs)
            }
            Button {
                visible: part.known && !part.on
                text: actProc.running ? "Working…" : part.installText
                enabled: !actProc.running
                onClicked: part.run(part.installArgs)
            }
        }
        Label {
            Layout.fillWidth: true
            visible: part.warn !== "" && part.known && !part.on
            wrapMode: Text.WordWrap
            text: part.warn
            color: win.subtext
            font.family: win.font
            font.pixelSize: 11
        }
        Label {
            Layout.fillWidth: true
            visible: part.said !== ""
            wrapMode: Text.WordWrap
            text: part.said
            color: win.subtext
            font.family: win.font
            font.pixelSize: 11
        }
    }

    component Card: Rectangle {
        id: cardRoot
        property string title
        property string hint
        default property alias content: cardCol.data
        Layout.fillWidth: true
        implicitHeight: cardCol.implicitHeight + 32
        radius: 18
        color: win.card

        ColumnLayout {
            id: cardCol
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 4

            Label {
                visible: cardRoot.title !== ""
                text: cardRoot.title
                color: win.text
                font.family: win.font
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.bottomMargin: cardRoot.hint === "" ? 6 : 0
            }
            Label {
                visible: cardRoot.hint !== ""
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                text: cardRoot.hint
                color: win.subtext
                wrapMode: Text.WordWrap
                font.family: win.font
                font.pixelSize: 12
            }
        }
    }

    // A setting row: label (+ hint) on the left, control on the right. Rows
    // whose value differs from the default get an accent dot and a reset
    // button, and every change makes the row glow briefly.
    component Row_: Rectangle {
        id: row
        property string key
        property string label
        property string hint
        property bool stacked: false
        default property alias control: slot.data
        readonly property bool changed: key !== "" && win.o[key] !== Config.defaults[key]

        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + 12
        radius: 10
        color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, flash.value)

        QtObject {
            id: flash
            property real value: 0
        }
        NumberAnimation {
            id: flashAnim
            target: flash
            property: "value"
            from: 0.22
            to: 0
            duration: 900
            easing.type: Easing.OutCubic
        }
        // Found by search: a longer, brighter glow so the eye lands on it.
        SequentialAnimation {
            id: pulseAnim
            NumberAnimation {
                target: flash
                property: "value"
                to: 0.4
                duration: 250
            }
            NumberAnimation {
                target: flash
                property: "value"
                to: 0
                duration: 1800
                easing.type: Easing.InOutQuad
            }
        }
        function pulse() {
            pulseAnim.restart();
        }
        Component.onCompleted: if (key !== "")
            win.register(key, row)
        Connections {
            target: Config
            function onEdited(k) {
                if (k === row.key)
                    flashAnim.restart();
            }
        }

        GridLayout {
            id: body
            x: 8
            y: 6
            width: parent.width - 16
            columns: row.stacked ? 1 : 2
            columnSpacing: 12
            rowSpacing: 2

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    spacing: 6
                    Rectangle {
                        visible: row.changed
                        width: 6
                        height: 6
                        radius: 3
                        color: win.accent
                    }
                    Label {
                        text: row.label
                        color: row.changed ? win.accent : win.text
                        font.family: win.font
                        font.pixelSize: 14
                    }
                    Icon {
                        visible: row.changed
                        text: "undo"
                        size: 16
                        color: resetMouse.containsMouse ? win.accent : win.subtext
                        MouseArea {
                            id: resetMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.resetKey(row.key, `${row.label} reset`)
                        }
                        ToolTip.visible: resetMouse.containsMouse
                        ToolTip.text: `Reset to ${Config.defaults[row.key]}`
                    }
                }
                Label {
                    visible: row.hint !== ""
                    Layout.fillWidth: true
                    text: row.hint
                    color: win.subtext
                    wrapMode: Text.WordWrap
                    font.family: win.font
                    font.pixelSize: 12
                }
            }
            Item {
                id: slot
                Layout.fillWidth: row.stacked
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }

    component SliderSetting: Row_ {
        id: ss
        property real from: 0
        property real to: 1
        property real stepSize: 0.05
        property int decimals: 2
        property string unit: ""
        property real scale: 1 // display multiplier (e.g. 100 for %)
        stacked: true

        RowLayout {
            width: ss.width - 16
            Slider {
                Layout.fillWidth: true
                from: ss.from
                to: ss.to
                stepSize: ss.stepSize
                value: win.o[ss.key]
                onMoved: Config.set(ss.key, ss.decimals === 0 ? Math.round(value) : Number(value.toFixed(ss.decimals)), ss.label)
            }
            Label {
                Layout.preferredWidth: 72
                horizontalAlignment: Text.AlignRight
                text: Number(win.o[ss.key] * ss.scale).toFixed(ss.scale === 1 ? ss.decimals : 0) + ss.unit
                color: ss.changed ? win.accent : win.subtext
                font.family: win.font
                font.pixelSize: 13
                font.features: ({ tnum: 1 })
            }
        }
    }

    component SwitchSetting: Row_ {
        id: sw
        Switch {
            checked: win.o[sw.key]
            onToggled: Config.set(sw.key, checked, sw.label)
        }
    }

    // Segmented buttons: every option visible at once.
    component ChoiceSetting: Row_ {
        id: ch
        property var choices: [] // [{ text, value }]
        Row {
            spacing: 0
            Repeater {
                model: ch.choices
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: win.o[ch.key] === modelData.value
                    width: choiceLabel.implicitWidth + 24
                    height: 32
                    color: current ? win.accent : choiceMouse.containsMouse ? "#2c2e34" : "#24262b"
                    topLeftRadius: index === 0 ? 16 : 0
                    bottomLeftRadius: index === 0 ? 16 : 0
                    topRightRadius: index === ch.choices.length - 1 ? 16 : 0
                    bottomRightRadius: index === ch.choices.length - 1 ? 16 : 0
                    Label {
                        id: choiceLabel
                        anchors.centerIn: parent
                        text: modelData.text
                        color: parent.current ? Theme.onPrimary : win.text
                        font.family: win.font
                        font.pixelSize: 13
                        font.weight: parent.current ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: choiceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.set(ch.key, modelData.value, `${ch.label}: ${modelData.text}`)
                    }
                }
            }
        }
    }

    component TextSetting: Row_ {
        id: tr
        property string placeholder
        TextField {
            width: 240
            text: win.o[tr.key]
            placeholderText: tr.placeholder
            font.family: win.font
            onEditingFinished: Config.set(tr.key, text.trim(), tr.label)
        }
    }

    component ColorSetting: Row_ {
        id: cr
        property var swatches: ["#ffffff", "#a6a6a6", "#ff4fd8", "#3ee6ff", "#a8ff60", "#ffd166", "#ff6b6b", "#b388ff"]
        stacked: true
        Row {
            spacing: 6
            Repeater {
                model: cr.swatches
                Rectangle {
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 13
                    color: modelData
                    border.width: win.o[cr.key] === modelData ? 3 : 1
                    border.color: win.o[cr.key] === modelData ? win.accent : "#40ffffff"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.set(cr.key, parent.modelData, cr.label)
                    }
                }
            }
            TextField {
                width: 110
                text: win.o[cr.key]
                font.family: "monospace"
                font.pixelSize: 13
                validator: RegularExpressionValidator {
                    regularExpression: /#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?/
                }
                onEditingFinished: Config.set(cr.key, text.toLowerCase(), cr.label)
            }
        }
    }

    component Page: ScrollView {
        id: pg
        default property alias content: col.data
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: col
            width: pg.availableWidth - 48
            x: 24
            spacing: 14
            Item {
                implicitHeight: 4
            }
        }
    }

    component PresetChip: Rectangle {
        required property var modelData
        width: chipRow.implicitWidth + 28
        height: 36
        radius: 18
        color: chipMouse.containsMouse ? "#2c2e34" : "#24262b"
        border.width: 1
        border.color: "#33ffffff"
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: modelData.color
            }
            Label {
                text: modelData.name
                color: win.text
                font.family: win.font
                font.pixelSize: 13
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.applyPreset(modelData)
        }
    }

    // ── Layout ────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: win.bg

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Attached Material properties don't cross the window boundary, so
        // the theme is set on the root item and inherited from here.
        Material.theme: Material.Dark
        Material.accent: win.accent
        Material.background: win.card

        // Sidebar
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            color: "#0e0f12"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4

                RowLayout {
                    Layout.bottomMargin: 14
                    Layout.topMargin: 6
                    spacing: 10
                    Rectangle {
                        width: 36
                        height: 20
                        radius: 10
                        color: "#000000"
                        border.color: win.accent
                        border.width: 2
                    }
                    Label {
                        text: "Islet"
                        color: win.text
                        font.family: win.font
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                }

                // Search: "youtube", "too fast", "weather"… (Ctrl+F)
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.bottomMargin: 8
                    placeholderText: "Search — e.g. youtube"
                    font.family: win.font
                    font.pixelSize: 13
                    leftPadding: 34
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        text: "search"
                        size: 20
                    }
                    text: win.initialQuery
                    Keys.onEscapePressed: text = ""
                    onAccepted: {
                        const first = win.search(text)[0];
                        if (first)
                            win.openResult(first);
                    }
                }
                Shortcut {
                    sequences: [StandardKey.Find]
                    onActivated: searchField.forceActiveFocus()
                }

                Repeater {
                    model: win.pages
                    Rectangle {
                        id: nav
                        required property var modelData
                        required property int index
                        readonly property bool current: win.page === index
                        readonly property int changes: win.changedCount(modelData.keys, win._revision)
                        Layout.fillWidth: true
                        implicitHeight: 52
                        radius: 14
                        color: current ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.16) : navMouse.containsMouse ? "#1a1b1f" : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12
                            Icon {
                                text: nav.modelData.icon
                                size: 22
                                color: nav.current ? win.accent : win.subtext
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    text: nav.modelData.title
                                    color: nav.current ? win.text : "#c9cad0"
                                    font.family: win.font
                                    font.pixelSize: 14
                                    font.weight: nav.current ? Font.DemiBold : Font.Normal
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: nav.modelData.subtitle
                                    color: win.subtext
                                    elide: Text.ElideRight
                                    font.family: win.font
                                    font.pixelSize: 11
                                }
                            }
                            // How many settings in this module differ from the defaults.
                            Rectangle {
                                visible: nav.changes > 0
                                implicitWidth: Math.max(20, badge.implicitWidth + 10)
                                implicitHeight: 20
                                radius: 10
                                color: win.accent
                                Label {
                                    id: badge
                                    anchors.centerIn: parent
                                    text: nav.changes
                                    color: Theme.onPrimary
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        MouseArea {
                            id: navMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.page = nav.index
                        }
                        ToolTip.visible: navMouse.containsMouse && changes > 0
                        ToolTip.text: `${changes} setting${changes === 1 ? "" : "s"} changed from default`
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                // What's playing, so you know what the preview shows.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: nowCol.implicitHeight + 20
                    radius: 14
                    color: "#17181c"
                    ColumnLayout {
                        id: nowCol
                        x: 12
                        y: 10
                        width: parent.width - 24
                        spacing: 2
                        // Test mode on/off, from any page.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            Label {
                                Layout.fillWidth: true
                                text: "Sample lyrics"
                                color: win.text
                                font.family: win.font
                                font.pixelSize: 13
                            }
                            Switch {
                                scale: 0.8
                                checked: LyricsService.demo
                                onToggled: win.sampleOverride = checked
                            }
                        }
                        Label {
                            text: LyricsService.demo ? "PREVIEWING SAMPLE" : "NOW PLAYING"
                            color: win.accent
                            font.family: win.font
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            font.weight: Font.DemiBold
                        }
                        Label {
                            Layout.fillWidth: true
                            text: LyricsService.title || "Nothing playing"
                            color: win.text
                            elide: Text.ElideRight
                            font.family: win.font
                            font.pixelSize: 13
                        }
                        Label {
                            Layout.fillWidth: true
                            text: LyricsService.artist
                            color: win.subtext
                            elide: Text.ElideRight
                            font.family: win.font
                            font.pixelSize: 11
                        }
                    }
                }

                Button {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    text: "Done"
                    highlighted: true
                    onClicked: win.visible = false
                }
            }
        }

        // Content
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Search results ────────────────────────────────────
            ScrollView {
                visible: win.query !== ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true
                ColumnLayout {
                    x: 24
                    width: parent.width - 48
                    spacing: 8
                    Label {
                        Layout.topMargin: 20
                        Layout.bottomMargin: 6
                        text: win.results.length ? `Results for “${win.query}”` : `Nothing found for “${win.query}”. Try other words, like “timing”, “bar” or “colour”.`
                        color: win.text
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        font.family: win.font
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                    Repeater {
                        model: win.results
                        Rectangle {
                            id: res
                            required property var modelData
                            readonly property bool clickable: modelData.key !== "" || modelData.action !== ""
                            Layout.fillWidth: true
                            implicitHeight: resCol.implicitHeight + 24
                            radius: 14
                            color: resMouse.containsMouse && clickable ? "#24262b" : win.card
                            ColumnLayout {
                                id: resCol
                                x: 16
                                y: 12
                                width: parent.width - 32
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        Layout.fillWidth: true
                                        text: res.modelData.title
                                        color: win.text
                                        wrapMode: Text.Wrap
                                        font.family: win.font
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }
                                    Label {
                                        visible: res.modelData.where !== ""
                                        text: `${res.modelData.where}  →`
                                        color: win.accent
                                        font.family: win.font
                                        font.pixelSize: 12
                                    }
                                }
                                Label {
                                    visible: res.modelData.answer !== ""
                                    Layout.fillWidth: true
                                    text: res.modelData.answer
                                    color: win.subtext
                                    wrapMode: Text.Wrap
                                    font.family: win.font
                                    font.pixelSize: 13
                                }
                            }
                            MouseArea {
                                id: resMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: res.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (res.clickable)
                                    win.openResult(res.modelData)
                            }
                        }
                    }
                    Item {
                        implicitHeight: 20
                    }
                }
            }

            RowLayout {
                visible: win.query === ""
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                Layout.topMargin: 20
                Layout.bottomMargin: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: win.pages[win.page].title
                        color: win.text
                        font.family: win.font
                        font.pixelSize: 26
                        font.weight: Font.Bold
                    }
                    Label {
                        text: win.pages[win.page].subtitle
                        color: win.subtext
                        font.family: win.font
                        font.pixelSize: 13
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                // Module on/off right in the header.
                Switch {
                    visible: win.page === 1 || win.page === 2
                    text: checked ? "On" : "Off"
                    checked: win.page === 1 ? win.o.lyricsEnabled : win.o.notchEnabled
                    onToggled: win.page === 1 ? Config.set("lyricsEnabled", checked, checked ? "Lyrics overlay on" : "Lyrics overlay off") : Config.set("notchEnabled", checked, checked ? "Notch on" : "Notch off")
                }
            }

            StackLayout {
                visible: win.query === ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.page

                // ── Overview ──────────────────────────────────────
                Page {
                    Card {
                        visible: UpdateService.status === "available"
                        title: `Update available: ${UpdateService.latest}`
                        hint: UpdateService.changes.slice(0, 3).join(" · ")
                        RowLayout {
                            Button {
                                text: "Update now"
                                highlighted: true
                                onClicked: UpdateService.update()
                            }
                            Button {
                                text: "Details"
                                flat: true
                                onClicked: win.page = win.pages.length - 1
                            }
                        }
                    }
                    Card {
                        title: "Modules"
                        hint: "Turn on what you want. Lyrics can show on the screen edge, inside the notch, or both."
                        SwitchSetting {
                            key: "lyricsEnabled"
                            label: "Lyrics overlay"
                            hint: "Curved, glowing lyrics on the edge of the screen"
                        }
                        SwitchSetting {
                            key: "notchEnabled"
                            label: "Notch"
                            hint: "Music, Focus timer and Checklist in a dynamic island"
                        }
                        ChoiceSetting {
                            key: "notchPillText"
                            label: "Notch pill shows"
                            choices: [
                                { text: "Current lyric", value: "lyrics" },
                                { text: "Song title", value: "title" }
                            ]
                        }
                    }
                    Card {
                        title: "Lyrics look"
                        hint: "One click sets colours, glow and fill together."
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: win.presets
                                PresetChip {}
                            }
                        }
                    }
                    Card {
                        title: "Smoothness"
                        hint: "How often moving lyrics are redrawn. Lower uses less battery and CPU."
                        ChoiceSetting {
                            key: "maxFps"
                            label: "Frame rate"
                            choices: [
                                { text: "Light · 30", value: 30 },
                                { text: "Smooth · 60", value: 60 },
                                { text: "Max · 120", value: 120 }
                            ]
                        }
                    }
                    Card {
                        title: "Notch colour"
                        ChoiceSetting {
                            key: "notchStyle"
                            label: "Background"
                            choices: [
                                { text: "Black", value: "black" },
                                { text: "Wallpaper (DMS)", value: "dms" }
                            ]
                        }
                    }
                }

                // ── Lyrics ────────────────────────────────────────
                Page {
                    Card {
                        title: "Preview"
                        hint: LyricsService.demo ? "Showing sample lyrics on screen so you can see every change." : "Changes show on the song that's playing."
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: "Use sample lyrics"
                                color: win.text
                                font.family: win.font
                                font.pixelSize: 14
                            }
                            Switch {
                                checked: LyricsService.demo
                                onToggled: win.sampleOverride = checked
                            }
                        }
                        SwitchSetting {
                            key: "samplePreview"
                            label: "Start with sample lyrics when nothing plays"
                        }
                    }
                    Card {
                        title: "Look"
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: win.presets
                                PresetChip {}
                            }
                        }
                    }
                    Card {
                        title: "Karaoke fill & glow"
                        ChoiceSetting {
                            key: "karaoke"
                            label: "Fill"
                            choices: [
                                { text: "Sweep", value: "sweep" },
                                { text: "Typewriter", value: "typewriter" },
                                { text: "Off", value: "none" }
                            ]
                        }
                        SliderSetting {
                            key: "fillSpeed"
                            label: "Fill speed"
                            hint: `Follows each song's singing pace automatically (this one: ${LyricsService.pace.toFixed(1)} letters/s). Fill finishes too early? Lower it.`
                            from: 0.5
                            to: 1.5
                            stepSize: 0.05
                            unit: "×"
                        }
                        SliderSetting {
                            key: "glow"
                            label: "Glow strength"
                            scale: 100
                            unit: "%"
                        }
                        ColorSetting {
                            key: "glowColor"
                            label: "Glow colour"
                        }
                        SliderSetting {
                            key: "unsungOpacity"
                            label: "Not-yet-sung text"
                            hint: "How visible the rest of the line is before it's sung"
                            scale: 100
                            unit: "%"
                        }
                        SliderSetting {
                            key: "feather"
                            label: "Fill edge softness"
                            to: 80
                            stepSize: 1
                            decimals: 0
                            unit: " px"
                        }
                    }
                    Card {
                        title: "Background vocals  ( … )"
                        hint: "Parts in parentheses are usually a second voice. They glow while they're sung — even after the main line has moved on."
                        ChoiceSetting {
                            key: "bgVocals"
                            label: "Show"
                            choices: [
                                { text: "Small, below", value: "below" },
                                { text: "Same as lyrics", value: "same" },
                                { text: "Hidden", value: "hidden" }
                            ]
                        }
                        SliderSetting {
                            key: "bgScale"
                            label: "Size"
                            from: 0.3
                            scale: 100
                            unit: "%"
                        }
                        SliderSetting {
                            key: "bgOpacity"
                            label: "Opacity"
                            scale: 100
                            unit: "%"
                        }
                        SliderSetting {
                            key: "bgLinger"
                            label: "Keep glowing after"
                            hint: "How long the echo stays lit once it's been sung"
                            to: 4
                            stepSize: 0.1
                            decimals: 1
                            unit: " s"
                        }
                        SwitchSetting {
                            key: "bgItalic"
                            label: "Italic"
                        }
                    }
                    Card {
                        title: "Text"
                        ColorSetting {
                            key: "activeColor"
                            label: "Active line"
                        }
                        ColorSetting {
                            key: "textColor"
                            label: "Other lines"
                        }
                        Row_ {
                            key: "fontFamily"
                            label: "Font"
                            ComboBox {
                                width: 240
                                editable: true
                                model: Qt.fontFamilies()
                                currentIndex: Qt.fontFamilies().indexOf(win.o.fontFamily)
                                onActivated: Config.set("fontFamily", currentText, "Font")
                                onAccepted: Config.set("fontFamily", editText, "Font")
                            }
                        }
                        SliderSetting {
                            key: "fontSize"
                            label: "Size"
                            from: 14
                            to: 72
                            stepSize: 1
                            decimals: 0
                            unit: " px"
                        }
                        ChoiceSetting {
                            key: "longLines"
                            label: "Long lines"
                            hint: "Wrap onto the next row, or shrink to fit the area width"
                            choices: [
                                { text: "Wrap below", value: "wrap" },
                                { text: "Shrink", value: "shrink" }
                            ]
                        }
                        SliderSetting {
                            key: "minFontSize"
                            label: "Smallest size when shrinking"
                            from: 8
                            to: 40
                            stepSize: 1
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "restingWeight"
                            label: "Weight — other lines"
                            from: 100
                            to: 900
                            stepSize: 100
                            decimals: 0
                        }
                        SliderSetting {
                            key: "activeWeight"
                            label: "Weight — active line"
                            from: 100
                            to: 900
                            stepSize: 100
                            decimals: 0
                        }
                    }
                    Card {
                        title: "Area"
                        hint: "Where lyrics may appear. While this window is open the area is outlined on screen; lines fade out at its edges instead of being cut."
                        ChoiceSetting {
                            key: "side"
                            label: "Screen edge"
                            choices: [
                                { text: "Left", value: "left" },
                                { text: "Right", value: "right" }
                            ]
                        }
                        SliderSetting {
                            key: "width"
                            label: "Width"
                            hint: "Long lines wrap to fit this width"
                            from: 250
                            to: 1400
                            stepSize: 10
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "viewHeight"
                            label: "Height"
                            from: 0.1
                            stepSize: 0.01
                            scale: 100
                            unit: "%"
                        }
                        SliderSetting {
                            key: "viewOffset"
                            label: "Move up / down"
                            from: -500
                            to: 500
                            stepSize: 5
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "edgeFade"
                            label: "Edge fade"
                            to: 300
                            stepSize: 2
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "inset"
                            label: "Distance from screen edge"
                            to: 400
                            stepSize: 2
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "marginTop"
                            label: "Top margin"
                            to: 500
                            stepSize: 5
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "marginBottom"
                            label: "Bottom margin"
                            to: 500
                            stepSize: 5
                            decimals: 0
                            unit: " px"
                        }
                        ChoiceSetting {
                            key: "layer"
                            label: "Layer"
                            choices: [
                                { text: "Behind windows", value: "bottom" },
                                { text: "Above windows", value: "top" },
                                { text: "Above all", value: "overlay" }
                            ]
                        }
                        TextSetting {
                            key: "screens"
                            label: "Monitors"
                            hint: "Available: " + Quickshell.screens.map(s => s.name).join(", ")
                            placeholder: "all"
                        }
                    }
                    Card {
                        title: "Wheel"
                        SliderSetting {
                            key: "spacing"
                            label: "Line spacing"
                            from: 1
                            to: 3
                            unit: "×"
                        }
                        SliderSetting {
                            key: "curve"
                            label: "Curve"
                            to: 2
                        }
                        SliderSetting {
                            key: "tilt"
                            label: "Tilt"
                            to: 20
                            stepSize: 0.5
                            decimals: 1
                            unit: "°"
                        }
                        SliderSetting {
                            key: "blur"
                            label: "Blur per line"
                            to: 8
                            stepSize: 0.1
                            decimals: 1
                            unit: " px"
                        }
                        SliderSetting {
                            key: "fade"
                            label: "Fade per line"
                            scale: 100
                            unit: "%"
                        }
                        SliderSetting {
                            key: "visibleLines"
                            label: "Lines around the active one"
                            from: 1
                            to: 12
                            stepSize: 1
                            decimals: 0
                        }
                        SliderSetting {
                            key: "smoothing"
                            label: "Scroll smoothing"
                            from: 30
                            to: 800
                            stepSize: 10
                            decimals: 0
                            unit: " ms"
                        }
                    }
                    Card {
                        title: "Readability & behaviour"
                        SwitchSetting {
                            key: "shadow"
                            label: "Text shadow"
                        }
                        SliderSetting {
                            key: "backdrop"
                            label: "Backdrop darkness"
                            scale: 100
                            unit: "%"
                        }
                        SwitchSetting {
                            key: "showTrackInfo"
                            label: "Song title & artist"
                        }
                        SwitchSetting {
                            key: "clickThrough"
                            label: "Click-through"
                            hint: "Off: click a line to jump to it"
                        }
                        SwitchSetting {
                            key: "hideWhenPaused"
                            label: "Hide when paused"
                        }
                        SwitchSetting {
                            key: "hideWhenNoLyrics"
                            label: "Hide when no lyrics are found"
                        }
                    }
                    Card {
                        title: "Source & timing"
                        ChoiceSetting {
                            key: "lyricsSource"
                            label: "Lyrics from"
                            hint: "Spicy Lyrics has syllable-by-syllable timing and Spotify's exact clock. Needs Spicetify with Spicy Lyrics, plus the Islet Bridge extension (run: islet spicetify)."
                            choices: [
                                { text: "Spicy Lyrics, else LRCLIB", value: "auto" },
                                { text: "LRCLIB only", value: "lrclib" }
                            ]
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            visible: win.o.lyricsSource !== "lrclib"
                            wrapMode: Text.WordWrap
                            font.family: win.font
                            font.pixelSize: 12
                            color: SpicyBridge.connected ? "#a5d6a7" : win.subtext
                            text: SpicyBridge.connected ? (LyricsService.source === "spicy" ? "● Connected to Spicy Lyrics — this song is synced syllable by syllable" : "● Connected to Spicy Lyrics — no Spicy lyrics for this song, using LRCLIB") : "○ Spicy Lyrics bridge not connected. Install it with: islet spicetify"
                        }
                        SliderSetting {
                            key: "spicyOffsetMs"
                            label: "Timing offset — Spicy Lyrics"
                            hint: "Spicy Lyrics itself uses +100 ms. Positive shows lyrics earlier."
                            from: -1000
                            to: 1000
                            stepSize: 10
                            decimals: 0
                            unit: " ms"
                        }
                        TextSetting {
                            key: "player"
                            label: "Preferred player"
                            hint: "Islet follows whatever is playing (Spotify, YouTube Music in a browser, mpv…); this one wins when several are. Running now: " + (Mpris.players.values.map(p => p.identity).join(", ") || "none")
                            placeholder: "any"
                        }
                        SliderSetting {
                            key: "offsetMs"
                            label: "Timing offset — LRCLIB"
                            hint: "Positive shows lines earlier"
                            from: -2000
                            to: 2000
                            stepSize: 50
                            decimals: 0
                            unit: " ms"
                        }
                        TextSetting {
                            key: "lrclibUrl"
                            label: "LRCLIB server"
                        }
                    }
                    Card {
                        title: "Lyrics version for this song"
                        hint: "Out of sync? LRCLIB often has several versions (album, live, radio edit). Pick the one whose length matches the song."
                        visible: !LyricsService.demo && LyricsService.title !== ""

                        Label {
                            Layout.fillWidth: true
                            visible: LyricsService.timingMismatch
                            text: "⚠  The lyrics in use are for a recording of a different length — timing may drift."
                            color: Theme.danger
                            wrapMode: Text.WordWrap
                            font.family: win.font
                            font.pixelSize: 13
                        }
                        Label {
                            text: `Song length ${win.fmtTime(LyricsService.length)} · status: ${LyricsService.status}`
                            color: win.subtext
                            font.family: win.font
                            font.pixelSize: 12
                        }
                        RowLayout {
                            Button {
                                text: "Find versions"
                                onClicked: LyricsService.loadCandidates()
                            }
                            Button {
                                text: "Re-fetch"
                                flat: true
                                onClicked: LyricsService.refetch()
                            }
                        }
                        Repeater {
                            model: LyricsService.candidates
                            Rectangle {
                                id: cand
                                required property var modelData
                                readonly property bool inUse: LyricsService.chosenId === modelData.id
                                readonly property real diff: Math.abs(modelData.duration - LyricsService.length)
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: 10
                                color: inUse ? Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.15) : candMouse.containsMouse ? "#24262b" : "transparent"
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10
                                    Icon {
                                        text: cand.inUse ? "radio_button_checked" : "radio_button_unchecked"
                                        color: cand.inUse ? win.accent : win.subtext
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: cand.modelData.label
                                        elide: Text.ElideRight
                                        color: win.text
                                        font.family: win.font
                                        font.pixelSize: 13
                                    }
                                    Label {
                                        text: cand.modelData.synced ? "synced" : "plain"
                                        color: cand.modelData.synced ? win.accent : win.subtext
                                        font.pixelSize: 11
                                    }
                                    Label {
                                        text: win.fmtTime(cand.modelData.duration)
                                        color: cand.diff <= 3 ? "#a5d6a7" : Theme.danger
                                        font.pixelSize: 12
                                        font.features: ({ tnum: 1 })
                                    }
                                }
                                MouseArea {
                                    id: candMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: LyricsService.choose(cand.modelData.id)
                                }
                            }
                        }
                    }
                }

                // ── Notch ─────────────────────────────────────────
                Page {
                    Card {
                        title: "Language"
                        hint: "The words in the notch, the Islet pill in your bar, Islet's DMS cards and desktop widgets, and its notifications."
                        ChoiceSetting {
                            key: "language"
                            label: "Language"
                            choices: [
                                { text: "English", value: "en" },
                                { text: "Bahasa Indonesia", value: "id" }
                            ]
                        }
                    }
                    Card {
                        title: "Where it lives"
                        hint: "As a floating island at the top of the screen, or as a widget in your DankMaterialShell bar (in place of DMS's media widget). In the bar, clicking the widget drops Islet down right under it. Inside DMS, it opens Islet's tab in DMS's dashboard instead — in DMS's Island if you use one — and Islet's own island only shows for Finder and the visualizer when you're away."
                        ChoiceSetting {
                            key: "notchMode"
                            label: "Show as"
                            choices: [
                                { text: "Floating island", value: "island" },
                                { text: "In the DMS bar", value: "bar" },
                                { text: "Inside DMS (dashboard & Island)", value: "dms" }
                            ]
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: win.o.notchMode === "bar" || win.o.notchMode === "dms"
                            Button {
                                text: "Set up DMS bar widget"
                                onClicked: Quickshell.execDetached([Qt.resolvedUrl("bin/islet").toString().replace(/^file:\/\//, ""), "dms", "install"])
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: IsletLink.hasClients ? "● Connected to the DMS bar" : "○ Not in the bar yet — press the button (or run: islet dms)"
                                color: IsletLink.hasClients ? "#a5d6a7" : win.subtext
                                font.family: win.font
                                font.pixelSize: 12
                            }
                        }
                    }
                    Card {
                        title: "Bar widget"
                        visible: win.o.notchMode === "bar" || win.o.notchMode === "dms"
                        SliderSetting {
                            key: "barPillWidth"
                            label: "Max width"
                            hint: "The whole pill (cover, lyric, deadlines, timer) never gets wider, so it won't cover your workspaces. Longer lines slide along as they're sung"
                            from: 120
                            to: 600
                            stepSize: 10
                            decimals: 0
                            unit: " px"
                        }
                        SwitchSetting {
                            key: "barShowVisualizer"
                            label: "Visualizer"
                        }
                        SwitchSetting {
                            key: "barShowTimer"
                            label: "Focus timer"
                        }
                    }
                    Card {
                        title: "Preview"
                        hint: "Size changes open the notch so you can see them; other changes show the closed pill."
                        RowLayout {
                            Button {
                                text: "Open notch"
                                onClicked: win.shellNotch?.open()
                            }
                            Button {
                                text: "Show pill"
                                flat: true
                                onClicked: win.shellNotch?.close()
                            }
                        }
                    }
                    Card {
                        title: "Look"
                        ChoiceSetting {
                            key: "notchShape"
                            label: "Shape"
                            choices: [
                                { text: "Floating island", value: "island" },
                                { text: "Attached notch", value: "notch" }
                            ]
                        }
                        ChoiceSetting {
                            key: "notchStyle"
                            label: "Background"
                            choices: [
                                { text: "Black", value: "black" },
                                { text: "Wallpaper (DMS)", value: "dms" }
                            ]
                        }
                        ChoiceSetting {
                            key: "notchPillText"
                            label: "Pill shows"
                            choices: [
                                { text: "Current lyric", value: "lyrics" },
                                { text: "Song title", value: "title" }
                            ]
                        }
                        ChoiceSetting {
                            key: "notchIdle"
                            label: "When idle"
                            choices: [
                                { text: "Small handle", value: "handle" },
                                { text: "Invisible", value: "hidden" }
                            ]
                        }
                    }
                    Card {
                        title: "Size & position"
                        SliderSetting {
                            key: "notchMarginTop"
                            label: "Distance from top"
                            hint: "0 with the attached shape sits on the screen edge; ~44 floats under the DMS bar"
                            to: 120
                            stepSize: 1
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "notchPillWidth"
                            label: "Pill width"
                            from: 180
                            to: 600
                            stepSize: 5
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "notchWidth"
                            label: "Open width"
                            from: 440
                            to: 1000
                            stepSize: 10
                            decimals: 0
                            unit: " px"
                        }
                        SliderSetting {
                            key: "notchHeight"
                            label: "Open height"
                            from: 200
                            to: 600
                            stepSize: 10
                            decimals: 0
                            unit: " px"
                        }
                        TextSetting {
                            key: "notchScreen"
                            label: "Monitor"
                            hint: "Available: " + Quickshell.screens.map(s => s.name).join(", ")
                            placeholder: "first"
                        }
                    }
                    Card {
                        title: "Behaviour"
                        SliderSetting {
                            key: "notchHoverDelay"
                            label: "Hover delay"
                            to: 1000
                            stepSize: 10
                            decimals: 0
                            unit: " ms"
                        }
                        SwitchSetting {
                            key: "notchAutoClose"
                            label: "Close when the mouse leaves"
                            hint: "Pin it (📌) or use the Shelf tab to keep it open, e.g. while dragging files in"
                        }
                        SliderSetting {
                            key: "notchCloseDelay"
                            label: "Close after"
                            from: 200
                            to: 5000
                            stepSize: 100
                            decimals: 0
                            unit: " ms"
                        }
                    }
                    Card {
                        title: "Visualizer mode"
                        hint: "When you step away while music plays, the notch becomes a big visualizer. Any key or mouse move brings it back. Also: islet notch viz."
                        SwitchSetting {
                            key: "vizMode"
                            label: "Visualizer when I'm away"
                        }
                        SliderSetting {
                            key: "vizIdleSeconds"
                            label: "After"
                            from: 10
                            to: 300
                            stepSize: 5
                            decimals: 0
                            unit: " s"
                        }
                    }
                    Card {
                        title: "Weather"
                        hint: {
                            const W = WeatherService;
                            const where = Config.opts.weatherCity.trim() !== "" ? (W.place || "city not found") : W.coords !== "" ? "DankMaterialShell's location" : "no location yet — type a city";
                            return `Shown in the pill when nothing plays. ${W.ready ? `${W.tempText} ${W.description.toLowerCase()}, ` : ""}${where}. From Open-Meteo; your location is never looked up from your IP.`;
                        }
                        SwitchSetting {
                            key: "weatherEnabled"
                            label: "Show the weather"
                        }
                        TextSetting {
                            key: "weatherCity"
                            label: "City"
                            hint: "Empty: use DankMaterialShell's weather location"
                            placeholder: "e.g. Malang"
                        }
                        ChoiceSetting {
                            key: "weatherUnit"
                            label: "Units"
                            choices: [
                                { text: "°C", value: "c" },
                                { text: "°F", value: "f" }
                            ]
                        }
                    }
                }

                // ── Focus ─────────────────────────────────────────
                Page {
                    Card {
                        title: `${PomodoroService.label} · ${PomodoroService.clock}`
                        hint: {
                            const P = PomodoroService;
                            const today = `${P.todayCount} focus session${P.todayCount === 1 ? "" : "s"} · ${P.formatShort(P.todayFocused)} focused today`;
                            return P.sessionStart > 0 ? `${today}\nThis session: ${P.format(P.elapsed)} elapsed · ${P.formatShort(P.focused)} focus · ${P.formatShort(P.pausedTotal)} paused` : today;
                        }
                        RowLayout {
                            Button {
                                text: PomodoroService.running ? "Pause" : "Start"
                                highlighted: true
                                onClicked: PomodoroService.toggle()
                            }
                            Button {
                                text: "Reset"
                                flat: true
                                onClicked: PomodoroService.reset()
                            }
                            Button {
                                text: "Skip"
                                flat: true
                                onClicked: PomodoroService.skip()
                            }
                            Button {
                                visible: PomodoroService.pausedTotal >= 1
                                text: "Reset pause time"
                                flat: true
                                onClicked: PomodoroService.resetPause()
                            }
                        }
                    }
                    Card {
                        title: "Timer"
                        SliderSetting {
                            key: "focusMinutes"
                            label: "Focus"
                            from: 5
                            to: 90
                            stepSize: 1
                            decimals: 0
                            unit: " min"
                        }
                        SliderSetting {
                            key: "shortBreakMinutes"
                            label: "Short break"
                            from: 1
                            to: 30
                            stepSize: 1
                            decimals: 0
                            unit: " min"
                        }
                        SliderSetting {
                            key: "longBreakMinutes"
                            label: "Long break"
                            from: 5
                            to: 60
                            stepSize: 1
                            decimals: 0
                            unit: " min"
                        }
                        SliderSetting {
                            key: "longBreakEvery"
                            label: "Long break after"
                            from: 2
                            to: 8
                            stepSize: 1
                            decimals: 0
                            unit: " sessions"
                        }
                    }
                    Card {
                        title: "Behaviour"
                        SwitchSetting {
                            key: "autoStartBreaks"
                            label: "Start breaks automatically"
                        }
                        SwitchSetting {
                            key: "autoStartFocus"
                            label: "Start focus automatically after a break"
                        }
                        SliderSetting {
                            key: "pauseReminderMinutes"
                            label: "Pause reminder (0 = off)"
                            from: 0
                            to: 60
                            stepSize: 1
                            decimals: 0
                            unit: " min"
                        }
                        SwitchSetting {
                            key: "pomodoroSound"
                            label: "Sound when time is up"
                        }
                        SwitchSetting {
                            key: "breakTips"
                            label: "Break tips"
                            hint: "Stretch, drink water, rest your eyes… a different one each break"
                        }
                    }
                }

                // ── Checklist ─────────────────────────────────────
                Page {
                    Card {
                        title: "Where tasks are saved"
                        ChoiceSetting {
                            key: "checklistSource"
                            label: "Save in"
                            choices: [
                                { text: "This computer", value: "local" },
                                { text: "Notion", value: "notion" }
                            ]
                        }
                        Label {
                            text: `${ChecklistService.items.length} task${ChecklistService.items.length === 1 ? "" : "s"}, ${ChecklistService.doneCount} done`
                            color: win.subtext
                            font.family: win.font
                            font.pixelSize: 12
                        }
                    }
                    Card {
                        title: "Notion"
                        visible: win.o.checklistSource === "notion"
                        hint: "1. notion.so/profile/integrations → New integration → copy the Internal Integration Secret.\n2. Open your checklist page → ••• → Connections → add the integration.\n3. Paste both below. To-do blocks on that page become your checklist."

                        Row_ {
                            label: "Integration secret"
                            hint: ChecklistService.token !== "" ? "Saved on this computer only ✓" : "Stored only on this computer, readable by you"
                            RowLayout {
                                TextField {
                                    id: tokenField
                                    Layout.preferredWidth: 180
                                    echoMode: TextInput.Password
                                    placeholderText: ChecklistService.token !== "" ? "paste to replace" : "ntn_…"
                                    onAccepted: saveToken.clicked()
                                }
                                Button {
                                    id: saveToken
                                    text: "Save"
                                    enabled: tokenField.text.trim() !== ""
                                    onClicked: {
                                        ChecklistService.saveToken(tokenField.text);
                                        tokenField.text = "";
                                    }
                                }
                            }
                        }
                        TextSetting {
                            key: "notionPage"
                            label: "Checklist page"
                            placeholder: "https://www.notion.so/…"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                text: "Test connection"
                                onClicked: ChecklistService.refresh()
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.family: win.font
                                font.pixelSize: 12
                                color: ChecklistService.status === "error" ? Theme.danger : ChecklistService.status === "ready" ? "#a5d6a7" : win.subtext
                                text: ChecklistService.status === "ready" ? `Connected ✓ · ${ChecklistService.items.length} to-dos` : ChecklistService.status === "loading" ? "Connecting…" : ChecklistService.error
                            }
                        }
                    }
                }

                // ── Calendar & Notion ─────────────────────────────
                Page {
                    Card {
                        title: "Hari ini"
                        hint: "Today's lessons and close deadlines in the notch (Hari ini tab), from your Notion timetable and tasks, kept in sync with Google Calendar."
                        SwitchSetting {
                            key: "todayEnabled"
                            label: "Show lessons and deadlines"
                        }
                    }
                    Card {
                        title: "Google Calendar"
                        visible: win.o.todayEnabled
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.family: win.font
                            font.pixelSize: 13
                            color: DcalService.healthy ? "#a5d6a7" : DcalService.available ? Theme.danger : win.subtext
                            text: DcalService.healthy ? `Connected via Dank Calendar ✓ · ${DcalService.account}` : DcalService.available ? DcalService.error : "Dank Calendar isn't running. Islet reaches Google through it."
                        }
                        Button {
                            visible: !DcalService.healthy
                            text: "Open Dank Calendar"
                            onClicked: DcalService.show()
                        }
                        Row_ {
                            key: "todayCalendar"
                            label: "Write to"
                            hint: "Where your lessons and plans go. Empty: your main Google calendar."
                            ComboBox {
                                id: calPick
                                width: 260
                                readonly property var items: [{ id: "", name: `Main calendar${DcalService.primary ? " (" + DcalService.primary.name + ")" : ""}` }].concat(DcalService.writable.map(c => ({ id: c.id, name: `${c.name} · ${c.accountName}` })))
                                model: items.map(i => i.name)
                                currentIndex: Math.max(0, items.findIndex(i => i.id === win.o.todayCalendar))
                                onActivated: i => Config.set("todayCalendar", items[i].id, "Calendar")
                            }
                        }
                    }
                    // Islet's Notion template, made for you in a page you shared.
                    Card {
                        id: tplCard
                        title: "Islet's Notion template"
                        visible: win.o.todayEnabled && ChecklistService.token !== ""
                        readonly property bool fresh: TodayService.timetableDb === "" && TodayService.tasksDb === ""
                        property bool confirming: false
                        hint: (fresh ? "No timetable or task list yet? " : "Starting over, or setting Islet up for a friend? ")
                            + "Islet makes them for you: an Islet page with Mata Pelajaran, Jadwal Pelajaran (your week), Tasks (deadlines) and Notes, linked to each other, and a Checklist page — the same columns Islet reads. Then Islet uses them. Pick a page you shared with the integration (••• → Connections) to put it in."
                        onVisibleChanged: if (visible && NotionTemplate.places.length === 0)
                            NotionTemplate.loadPlaces()
                        Component.onCompleted: if (visible)
                            NotionTemplate.loadPlaces()
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            ComboBox {
                                id: tplPlace
                                Layout.fillWidth: true
                                enabled: NotionTemplate.places.length > 0 && NotionTemplate.status !== "working"
                                model: NotionTemplate.loadingPlaces ? ["Looking for your pages…"] : NotionTemplate.places.length ? NotionTemplate.places.map(p => p.title) : ["No shared pages — share one with the integration"]
                            }
                            NotchIconButton {
                                icon: "refresh"
                                size: 30
                                tint: win.subtext
                                onClicked: NotionTemplate.loadPlaces()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.family: win.font
                                font.pixelSize: 12
                                color: NotionTemplate.status === "error" ? Theme.danger : NotionTemplate.status === "done" ? "#a5d6a7" : win.subtext
                                text: NotionTemplate.status === "working" ? `Making it… (${NotionTemplate.step})`
                                    : NotionTemplate.status === "done" ? (NotionTemplate.took.length === 4 ? "✓ Made, and Islet uses it now. Fill in your subjects and timetable in Notion." : NotionTemplate.took.length ? `✓ Made. Islet now uses its ${NotionTemplate.took.join(", ")}; it keeps your other ones — switch them below if you like.` : "✓ Made. Islet keeps the databases it already uses — switch to the new ones below if you like.")
                                    : NotionTemplate.status === "error" ? NotionTemplate.error
                                    : tplCard.confirming ? `Make it in “${NotionTemplate.places[tplPlace.currentIndex]?.title ?? ""}”? ${tplCard.fresh ? "Islet then reads these." : "Islet keeps the databases it uses now; you can switch below."}` : ""
                            }
                            Button {
                                visible: NotionTemplate.status === "done" && NotionTemplate.url !== ""
                                text: "Open in Notion"
                                onClicked: Qt.openUrlExternally(NotionTemplate.url)
                            }
                            Button {
                                visible: tplCard.confirming
                                text: "Cancel"
                                flat: true
                                onClicked: tplCard.confirming = false
                            }
                            Button {
                                visible: NotionTemplate.status !== "done"
                                text: tplCard.confirming ? "Yes, make it" : "Make Islet's databases"
                                enabled: NotionTemplate.places.length > 0 && NotionTemplate.status !== "working"
                                onClicked: {
                                    if (!tplCard.confirming) {
                                        tplCard.confirming = true;
                                        return;
                                    }
                                    tplCard.confirming = false;
                                    NotionTemplate.create(NotionTemplate.places[tplPlace.currentIndex].id);
                                }
                            }
                        }
                    }
                    Card {
                        title: "Notion"
                        visible: win.o.todayEnabled
                        hint: ChecklistService.token === "" ? "Islet uses the same Notion integration as the Checklist: add its secret on the Checklist page, then share your Workspace page with it (••• → Connections)." : ""
                        Label {
                            Layout.fillWidth: true
                            visible: TodayService.status === "error" || TodayService.status === "setup"
                            wrapMode: Text.WordWrap
                            text: TodayService.error
                            color: Theme.danger
                            font.family: win.font
                            font.pixelSize: 12
                        }
                        Repeater {
                            model: [
                                { key: "todayTimetableDb", label: "Timetable", kind: "timetable", picked: TodayService.timetableDb },
                                { key: "todayTasksDb", label: "Tasks", kind: "tasks", picked: TodayService.tasksDb },
                                { key: "todayDailyDb", label: "Daily tasks", kind: "daily", picked: TodayService.dailyDb },
                                { key: "notesDb", label: "Notes", kind: "notes", picked: win.o.notesDb || (TodayService.databases.find(d => (d.title ?? []).map(t => t.plain_text).join("").trim().toLowerCase() === "notes")?.id ?? "") }
                            ]
                            Row_ {
                                id: dbRow
                                required property var modelData
                                key: modelData.key
                                label: modelData.label
                                hint: `${modelData.kind === "timetable" ? TodayService.allLessons.length + " lessons" : modelData.kind === "tasks" ? TodayService.tasks.length + " tasks" : modelData.kind === "daily" ? (TodayService.dailyDb === "" ? "none yet: make it from Hari ini → Daily" : TodayService.daily.length + " daily tasks") : "for the Notes desktop widget"}${win.o[modelData.key] === "" ? " · found by itself" : ""}`
                                ComboBox {
                                    width: 260
                                    readonly property var dbs: TodayService.databases.map(d => ({ id: d.id, name: (d.title ?? []).map(t => t.plain_text).join("") || "Untitled" }))
                                    model: dbs.map(d => d.name + (d.id === dbRow.modelData.picked && win.o[dbRow.modelData.key] === "" ? " (terdeteksi)" : ""))
                                    currentIndex: dbs.findIndex(d => d.id === dbRow.modelData.picked)
                                    onActivated: i => {
                                        Config.set(dbRow.modelData.key, dbs[i].id, dbRow.modelData.label);
                                        TodayService.load();
                                    }
                                }
                            }
                        }
                        // Which column means what; fixed here if a guess was wrong.
                        Label {
                            Layout.fillWidth: true
                            text: "Columns"
                            color: win.text
                            font.family: win.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: [
                                { kind: "timetable", field: "hari", label: "Day (Hari)" },
                                { kind: "timetable", field: "jam", label: "Time (Jam)" },
                                { kind: "timetable", field: "mapel", label: "Subject (Mapel)" },
                                { kind: "tasks", field: "title", label: "Task name" },
                                { kind: "tasks", field: "status", label: "Status" },
                                { kind: "tasks", field: "start", label: "Plan (goes to Google)" },
                                { kind: "tasks", field: "due", label: "Deadline" },
                                { kind: "tasks", field: "gcal", label: "GCal ID" }
                            ]
                            Row_ {
                                id: colRow
                                required property var modelData
                                label: modelData.label
                                readonly property string db: modelData.kind === "timetable" ? TodayService.timetableDb : TodayService.tasksDb
                                readonly property var names: Object.keys((TodayService.databases.find(d => d.id === db) ?? {}).properties ?? {}).sort()
                                readonly property string current: (modelData.kind === "timetable" ? TodayService.timetableMap : TodayService.tasksMap)[modelData.field] ?? ""
                                ComboBox {
                                    width: 260
                                    model: ["—"].concat(colRow.names)
                                    currentIndex: Math.max(0, colRow.names.indexOf(colRow.current) + 1)
                                    onActivated: i => {
                                        let cols = {};
                                        try {
                                            cols = JSON.parse(win.o.todayColumns || "{}");
                                        } catch (e) {}
                                        cols[colRow.modelData.kind] = Object.assign({}, cols[colRow.modelData.kind] ?? {});
                                        cols[colRow.modelData.kind][colRow.modelData.field] = i === 0 ? "" : colRow.names[i - 1];
                                        Config.set("todayColumns", JSON.stringify(cols), "Columns");
                                        TodayService.load();
                                    }
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: TodayService.problems.length > 0
                            wrapMode: Text.WordWrap
                            text: `Skipped ${TodayService.problems.length} row(s): ${TodayService.problems.map(p => p.error).join(" · ")}`
                            color: Theme.danger
                            font.family: win.font
                            font.pixelSize: 12
                        }
                    }
                    Card {
                        title: "Sync with Google Calendar"
                        visible: win.o.todayEnabled
                        hint: "Both ways: change a task's plan in Notion or in Google Calendar and the other follows within a few minutes. If both change the same thing between two syncs, the later change is kept and you're told."
                        SwitchSetting {
                            key: "todaySync"
                            label: "Sync"
                        }
                        SwitchSetting {
                            key: "todaySyncLessons"
                            label: "Lessons too"
                            hint: "Off: only tasks and deadlines go to Google; lessons stay in Notion and on the Hari ini tab. Turning it off deletes the lesson events Islet made."
                        }
                        // The first sync asks before writing anything.
                        Rectangle {
                            Layout.fillWidth: true
                            visible: TodayService.syncStatus === "waiting" && win.o.todaySync
                            implicitHeight: firstSync.implicitHeight + 24
                            radius: 12
                            color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, 0.12)
                            ColumnLayout {
                                id: firstSync
                                anchors.fill: parent
                                anchors.margins: 12
                                Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: `First sync: ${TodayService.previewText || "…"} in ${(DcalService.calendars.find(c => c.id === TodayService.targetCalendar) ?? {}).name ?? "your calendar"}. Lessons become weekly events from this week; tasks with a plan date become events. Nothing in your calendar that Islet didn't make is touched.`
                                    color: win.text
                                    font.family: win.font
                                    font.pixelSize: 13
                                }
                                Button {
                                    text: "Confirm and sync"
                                    highlighted: true
                                    onClicked: TodayService.confirmFirstSync()
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.family: win.font
                            font.pixelSize: 12
                            color: TodayService.syncStatus === "error" ? Theme.danger : win.subtext
                            text: TodayService.syncStatus === "error" ? TodayService.syncError : TodayService.lastSync ? `Last sync ${Qt.formatTime(new Date(TodayService.lastSync), "HH:mm")} · ${TodayService.linked} linked` : ""
                        }
                        Button {
                            text: "Sync now"
                            visible: TodayService.syncStatus !== "waiting"
                            onClicked: TodayService.load()
                        }
                        Button {
                            visible: TodayService.held > 0
                            text: `Allow removing ${TodayService.held}`
                            onClicked: TodayService.allowRemovals()
                        }
                        Repeater {
                            model: TodayService.conflicts
                            RowLayout {
                                id: conflictRow
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: `Conflict: ${conflictRow.modelData.title} — Google's version kept`
                                    color: win.text
                                    font.family: win.font
                                    font.pixelSize: 12
                                }
                                Button {
                                    text: "Use Notion's"
                                    onClicked: TodayService.useOther(conflictRow.index)
                                }
                            }
                        }
                        Repeater {
                            model: TodayService.removedInGoogle
                            RowLayout {
                                id: removedRow
                                required property var modelData
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: `${removedRow.modelData.title}: deleted in Google Calendar`
                                    color: win.text
                                    font.family: win.font
                                    font.pixelSize: 12
                                }
                                Button {
                                    text: "Put it back"
                                    onClicked: TodayService.putBack(removedRow.modelData.pageId)
                                }
                                Button {
                                    text: "Remove from Notion"
                                    onClicked: TodayService.removeFromNotion(removedRow.modelData.pageId)
                                }
                            }
                        }
                    }
                    Card {
                        title: "Reminders"
                        visible: win.o.todayEnabled
                        SliderSetting {
                            key: "todayDays"
                            label: "Show deadlines up to"
                            from: 1
                            to: 14
                            stepSize: 1
                            decimals: 0
                            unit: " days"
                        }
                        SwitchSetting {
                            key: "todayMorningOpen"
                            label: "Open Hari ini each morning"
                            hint: "At your first activity of the day, the notch shows the day for a few seconds."
                        }
                        SliderSetting {
                            key: "todayMorningSeconds"
                            label: "…for"
                            from: 3
                            to: 30
                            stepSize: 1
                            decimals: 0
                            unit: " s"
                        }
                        SwitchSetting {
                            key: "todayNudges"
                            label: "Deadline reminders"
                            hint: "A morning summary, and a nudge 3 hours before a deadline with a time."
                        }
                    }
                    Card {
                        title: "Details"
                        visible: win.o.todayEnabled
                        SliderSetting {
                            key: "todayEventMinutes"
                            label: "Length of a plan with only a start time"
                            from: 15
                            to: 180
                            stepSize: 15
                            decimals: 0
                            unit: " min"
                        }
                        TextSetting {
                            key: "todaySemesterEnd"
                            label: "Semester ends on"
                            hint: "Lessons stop repeating after this date. Empty: they keep going."
                            placeholder: "2026-12-19"
                        }
                        SliderSetting {
                            key: "todaySyncMinutes"
                            label: "Sync every"
                            from: 2
                            to: 30
                            stepSize: 1
                            decimals: 0
                            unit: " min"
                        }
                    }
                }

                // ── Finder ────────────────────────────────────────
                Page {
                    Card {
                        title: "Shortcut"
                        hint: "Finder opens from the notch: type part of a name, Enter opens it. Ctrl+T terminal · Ctrl+E editor · Alt+Enter containing folder · Ctrl+C copy path."
                        // Asks first: the second click writes the niri config.
                        Row_ {
                            id: bindRow
                            property bool confirming: false
                            label: "Open Finder with Mod+G"
                            hint: bindResult.text.trim() !== "" ? bindResult.text.trim() : bindRow.confirming ? "This adds one line to your niri keybinds (a backup is kept) and checks it with niri. Go ahead?" : "Islet can add the shortcut to niri for you."
                            RowLayout {
                                Button {
                                    visible: bindRow.confirming
                                    text: "Cancel"
                                    flat: true
                                    onClicked: bindRow.confirming = false
                                }
                                Button {
                                    text: bindRow.confirming ? "Yes, add it" : "Set it up"
                                    enabled: !bindProc.running
                                    onClicked: {
                                        if (!bindRow.confirming) {
                                            bindRow.confirming = true;
                                            return;
                                        }
                                        bindRow.confirming = false;
                                        bindProc.running = true;
                                    }
                                }
                            }
                        }
                        Process {
                            id: bindProc
                            command: ["sh", decodeURIComponent(String(Qt.resolvedUrl("bin/islet")).replace(/^file:\/\//, "")), "find", "--bind"]
                            stdout: StdioCollector {
                                id: bindResult
                            }
                        }
                        // Selectable, to copy into another compositor's config.
                        TextEdit {
                            Layout.fillWidth: true
                            readOnly: true
                            selectByMouse: true
                            wrapMode: Text.WordWrap
                            text: "Hyprland: bind = SUPER, G, exec, islet find\nSway: bindsym $mod+g exec islet find"
                            color: win.subtext
                            selectionColor: win.accent
                            font.family: win.font
                            font.pixelSize: 12
                        }
                    }
                    Card {
                        title: "What to search"
                        TextSetting {
                            key: "finderRoots"
                            label: "Search in"
                            hint: "Folders, separated by commas. ~ is your home."
                        }
                        TextSetting {
                            key: "finderExclude"
                            label: "Skip folders named"
                            hint: "Separated by commas. **/a/b skips a/b anywhere."
                        }
                        SwitchSetting {
                            key: "finderHidden"
                            label: "Include hidden files"
                            hint: "Files and folders whose names start with a dot."
                        }
                        SliderSetting {
                            key: "finderReindexMinutes"
                            label: "Look for new files every"
                            from: 2
                            to: 60
                            stepSize: 1
                            decimals: 0
                            unit: " min"
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                text: "Rebuild now"
                                enabled: FinderService.status !== "indexing"
                                onClicked: FinderService.reindex()
                            }
                            Label {
                                Layout.fillWidth: true
                                font.family: win.font
                                font.pixelSize: 12
                                color: FinderService.status === "missing-tools" ? Theme.danger : win.subtext
                                text: FinderService.status === "missing-tools" ? "Install fd and fzf to use Finder." : FinderService.status === "indexing" ? "Indexing…" : `${FinderService.counts.dirs.toLocaleString()} folders and ${FinderService.counts.files.toLocaleString()} files`
                            }
                        }
                    }
                    Card {
                        title: "Open with"
                        hint: "Leave a box empty to use what's installed."
                        TextSetting {
                            key: "finderFileManager"
                            label: "Folders (Enter)"
                            hint: `Empty: your default file manager${FinderService.apps.fileManager ? " (" + FinderService.apps.fileManager + ")" : ""}`
                            placeholder: "dolphin"
                        }
                        TextSetting {
                            key: "finderTerminal"
                            label: "Terminal (Ctrl+T)"
                            hint: `Empty: ${FinderService.apps.terminal || "none found"}`
                            placeholder: "ghostty"
                        }
                        TextSetting {
                            key: "finderEditor"
                            label: "Editor (Ctrl+E)"
                            hint: `Empty: ${FinderService.apps.editor || "none found"}`
                            placeholder: "code"
                        }
                    }
                }

                // ── DankMaterialShell ─────────────────────────────
                Page {
                    id: dmsPage
                    readonly property bool hasDms: dmsCheck.found
                    Process {
                        id: dmsCheck
                        property bool found: true
                        running: true
                        command: ["sh", "-c", "command -v dms"]
                        onExited: code => found = code === 0
                    }
                    Card {
                        visible: !dmsPage.hasDms
                        title: "DankMaterialShell isn't installed"
                        hint: "These parts need DankMaterialShell (dms). Everything else in Islet works without it."
                    }
                    Card {
                        visible: dmsPage.hasDms
                        title: "Islet in the bar"
                        hint: "Islet's pill in place of DMS's media widget: the line being sung, your timer and today's deadlines; scroll on it to turn the music's volume, drop files on it for the Shelf. On DMS 1.7+ Islet's notch goes inside DMS too: an Islet tab in the dashboard (and the Island), and Focus, Hari ini, Shelf and Checklist as cards on the overview."
                        DmsPart {
                            statusArgs: ["dms", "status"]
                            installArgs: ["dms", "install"]
                            uninstallArgs: ["dms", "uninstall"]
                            isIn: out => /bar: Islet Media is in the bar/.test(out)
                            inText: "In the bar"
                            outText: "Not in the bar"
                            installText: "Put it in the bar"
                        }
                    }
                    Card {
                        id: dashKeyCard
                        visible: dmsPage.hasDms
                        title: "A key for DMS's overview"
                        hint: "Opens DMS's dashboard on its overview — Islet's cards are there — or DMS's Island when you use one. Adds Mod+Z to niri (a backup is kept; it won't take a key that's already used)."
                        property bool confirming: false
                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: dashKeyProc.running ? "Adding…" : dashKeyOut.text.trim() || (dashKeyCard.confirming ? "Add Mod+Z to your niri binds?" : "")
                                color: win.subtext
                                font.family: win.font
                                font.pixelSize: 12
                            }
                            Button {
                                visible: dashKeyCard.confirming
                                text: "Cancel"
                                flat: true
                                onClicked: dashKeyCard.confirming = false
                            }
                            Button {
                                text: dashKeyCard.confirming ? "Yes, add it" : "Set it up"
                                enabled: !dashKeyProc.running
                                onClicked: {
                                    if (!dashKeyCard.confirming) {
                                        dashKeyCard.confirming = true;
                                        return;
                                    }
                                    dashKeyCard.confirming = false;
                                    dashKeyProc.running = true;
                                }
                            }
                        }
                        Process {
                            id: dashKeyProc
                            command: ["sh", decodeURIComponent(String(Qt.resolvedUrl("bin/islet")).replace(/^file:\/\//, "")), "dms", "bind"]
                            stdout: StdioCollector {
                                id: dashKeyOut
                            }
                        }
                    }
                    Card {
                        visible: dmsPage.hasDms
                        title: "Desktop widgets"
                        hint: "Lyrics, To-Do, Notes, Pomodoro, Calendar and a clock on your wallpaper, laid out on the side away from the lyrics (move them in DMS's widget edit mode). A GitHub contributions widget waits in DMS Settings → Desktop Widgets. Solid or glass: any widget's settings → Tampilan semua widget Islet. To-Do and Notes use Notion (Calendar & Notion page)."
                        DmsPart {
                            statusArgs: ["dms", "widgets", "status"]
                            installArgs: ["dms", "widgets", "install"]
                            uninstallArgs: ["dms", "widgets", "uninstall"]
                            isIn: out => /deskwNotes: installed/.test(out)
                            inText: "On the desktop"
                            outText: "Not on the desktop"
                            installText: "Put them on the desktop"
                            warn: "Your bar disappears for a few seconds while DMS takes them in."
                        }
                    }
                    Card {
                        visible: dmsPage.hasDms
                        title: "Notepad toolbar"
                        hint: "The Notes widget's formatting bar (bold, headings, lists; Ctrl+B, Ctrl+Shift+1…) in DMS's own notepad. DMS then runs from a patched copy of its interface, rebuilt by itself after DMS updates, and its own whenever the patch doesn't fit."
                        DmsPart {
                            statusArgs: ["dms", "notepad", "status"]
                            installArgs: ["dms", "notepad", "install"]
                            uninstallArgs: ["dms", "notepad", "uninstall"]
                            isIn: out => /notepad toolbar: installed/.test(out)
                            inText: "Added"
                            outText: "DMS's own notepad"
                            installText: "Add the toolbar"
                            warn: "DMS restarts once (a few seconds without the bar)."
                        }
                    }
                }

                // ── About ─────────────────────────────────────────
                Page {
                    Card {
                        id: updateCard
                        title: {
                            switch (UpdateService.status) {
                            case "available":
                                return `Update available: ${UpdateService.latest}`;
                            case "updating":
                                return "Updating…";
                            case "checking":
                                return "Checking for updates…";
                            case "current":
                                return "Islet is up to date";
                            case "error":
                                return "Couldn't check for updates";
                            }
                            return "Updates";
                        }
                        hint: {
                            switch (UpdateService.status) {
                            case "available":
                                return `You have ${UpdateService.current}. Updating restarts Islet; a notification tells you when it's done.`;
                            case "updating":
                                return "Islet restarts in a moment.";
                            case "current":
                                return `Version ${UpdateService.current}`;
                            case "error":
                                return UpdateService.message;
                            }
                            return "Or from a terminal: islet update";
                        }
                        Repeater {
                            model: UpdateService.status === "available" ? UpdateService.changes : []
                            Label {
                                required property string modelData
                                Layout.fillWidth: true
                                text: `•  ${modelData}`
                                color: win.text
                                font.family: win.font
                                font.pixelSize: 13
                                wrapMode: Text.Wrap
                            }
                        }
                        RowLayout {
                            Layout.topMargin: 6
                            Button {
                                visible: UpdateService.status === "available"
                                text: "Update now"
                                highlighted: true
                                onClicked: UpdateService.update()
                            }
                            Button {
                                text: "Check now"
                                flat: UpdateService.status === "available"
                                enabled: UpdateService.status !== "checking" && UpdateService.status !== "updating"
                                onClicked: UpdateService.check()
                            }
                            Button {
                                text: "What's new"
                                flat: true
                                onClicked: Qt.openUrlExternally("https://github.com/Claritys11/islet/blob/main/CHANGELOG.md")
                            }
                        }
                        SwitchSetting {
                            key: "checkUpdates"
                            label: "Check for updates automatically"
                        }
                    }
                    Card {
                        title: "Islet"
                        hint: "Lyrics, music, focus and to-dos for your Linux desktop. Built on Quickshell."
                        RowLayout {
                            Button {
                                text: "Setup guide"
                                highlighted: true
                                onClicked: win.setupRequested()
                            }
                            Button {
                                text: "GitHub"
                                onClicked: Qt.openUrlExternally("https://github.com/Claritys11/islet")
                            }
                            Button {
                                text: "Open config folder"
                                flat: true
                                onClicked: Qt.openUrlExternally(`file://${Config.dir}`)
                            }
                        }
                    }
                    Card {
                        title: "Command line"
                        hint: "Bind these to keys in niri (see README)."
                        Repeater {
                            model: ["islet settings", "islet toggle  ·  show / hide lyrics", "islet notch [media|focus|checklist]", "islet pomodoro [toggle|reset|skip]", "islet todo \"Buy milk\""]
                            Label {
                                required property string modelData
                                text: modelData
                                color: win.text
                                font.family: "monospace"
                                font.pixelSize: 13
                            }
                        }
                    }
                    Card {
                        title: "Files"
                        Repeater {
                            model: [`Settings  ${Config.path}`, `Data  ${Store.dir}/state.json`]
                            Label {
                                required property string modelData
                                Layout.fillWidth: true
                                text: modelData
                                color: win.subtext
                                elide: Text.ElideMiddle
                                font.family: "monospace"
                                font.pixelSize: 12
                            }
                        }
                    }
                    Card {
                        title: "Reset"
                        hint: "Puts every setting back to its default. Your tasks and focus history are kept."
                        Button {
                            text: "Reset all settings"
                            onClicked: Config.reset()
                        }
                    }
                }
            }
        }
    }
    }
}
