import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// The dynamic island itself, independent of any window (NotchWindow puts it
// at the top of the screen; the showcase renders it for screenshots).
//   closed — a pill with live activities (music, running timer)
//   peek   — on hover: now playing + transport
//   open   — on click: tabs for Media, Focus, Checklist and Shelf
//   viz    — while you're away and music plays: a big visualizer
Item {
    id: win

    readonly property var o: Config.opts
    // "closed" | "peek" | "open" | "viz"
    property string mode: "closed"
    property int tab: 0
    readonly property int tabCount: 6
    signal settingsRequested
    // The visible island, for the window's input mask.
    property alias shapeItem: shape

    readonly property bool hasMusic: LyricsService.hasTrack
    readonly property bool hasTimer: PomodoroService.active
    // Today: a lesson about to start beats the song; a deadline due today
    // shows when nothing plays.
    readonly property var soon: o.todayEnabled ? TodayService.soon : null
    readonly property bool showSoon: soon !== null
    readonly property bool showDue: o.todayEnabled && !hasMusic && !hasTimer && !showSoon && TodayService.dueToday > 0
    readonly property string todayText: showSoon ? `${soon.title} · mulai ${Math.max(1, Math.ceil((soon.startAt - TodayService.now) / 60000))} mnt lagi`
        : showDue ? (TodayService.dueToday === 1 ? `${TodayService.deadlines.find(d => d.urgency === "today" || d.urgency === "overdue")?.title ?? ""} · ${TodayService.deadlines.find(d => d.urgency === "today" || d.urgency === "overdue")?.label ?? ""}` : `${TodayService.dueToday} tenggat hari ini`) : ""
    // Nothing playing and no timer: the weather keeps the pill company.
    readonly property bool showWeather: !hasMusic && !hasTimer && !showSoon && !showDue && o.weatherEnabled && WeatherService.ready
    readonly property bool idle: !hasMusic && !hasTimer && !showWeather && !showSoon && !showDue
    readonly property bool island: o.notchShape === "island" || barMode
    // "bar": no pill of its own — a bar widget (e.g. in DankMaterialShell)
    // shows the activities and opens the island as a dropdown.
    readonly property bool barMode: o.notchMode === "bar"
    readonly property string pillText: {
        const l = LyricsService.lines[LyricsService.currentIndex];
        if (o.notchPillText === "lyrics" && LyricsService.status === "ready" && LyricsService.synced && l && !l.interlude)
            return l.main;
        return LyricsService.title;
    }

    readonly property size target: {
        if (mode === "open")
            return Qt.size(o.notchWidth, tab >= 4 ? todayHeight : o.notchHeight);
        if (mode === "find")
            return Qt.size(o.notchWidth, finderHeight);
        if (mode === "peek")
            return Qt.size(430, 92);
        if (mode === "viz")
            return Qt.size(560, 140);
        if (idle)
            return o.notchIdle === "hidden" ? Qt.size(180, 4) : Qt.size(140, 10);
        if (showSoon || showDue)
            return Qt.size(Math.min(o.notchPillWidth + 60, todayChip.implicitWidth + 30), 34);
        if (showWeather)
            return Qt.size(weatherChip.implicitWidth + 30, 34);
        const w = (hasMusic ? o.notchPillWidth : 0) + (hasTimer ? (hasMusic ? 96 : 150) : 0);
        return Qt.size(w, 34);
    }

    // Pinned (📌), on the Shelf tab, or with files being dragged over it,
    // the island stays open after the mouse leaves; close it with ⌃ or Esc.
    property bool pinned: false
    // Opened by the Finder key (Mod+G): it has the keyboard, and typing
    // turns it into Finder.
    property bool hotkey: false
    // Opened on purpose (a click, the bar, a command) rather than by
    // hovering: a click anywhere else closes it, unless pinned.
    property bool clicked: false
    readonly property bool closesOnClickOutside: mode === "find" || (mode === "open" && clicked && !pinned && !ShelfService.dragging)
    readonly property bool keepOpen: pinned || hotkey || mode === "find" || drop.containsDrag
    // Today needs room for a school day's lessons next to the deadlines.
    readonly property real todayHeight: Math.max(o.notchHeight, 380)
    // Finder: the search box, 8 results and the key hints.
    readonly property real finderHeight: 64 + 8 * 44 + 34

    function close() {
        mode = "closed";
        pinned = false;
        shelfPin = false;
        hotkey = false;
        clicked = false;
    }

    function open(t) {
        if (t !== undefined)
            tab = t;
        mode = "open";
        clicked = true;
    }

    function toggle() {
        mode === "open" || mode === "find" ? close() : open();
    }

    // The Finder key: opens the notch, or closes it if it opened it.
    function summon() {
        if (mode === "find" || (mode === "open" && hotkey))
            return close();
        hotkey = true;
        open();
        Qt.callLater(() => typeCatcher.forceActiveFocus());
    }

    // Finder (`islet find text`), optionally with text already typed.
    function find(prefill) {
        mode = "find";
        finder.start(prefill ?? "");
    }

    // Visualizer mode by hand (it also comes on by itself when you're away).
    function toggleViz() {
        mode = mode === "viz" ? "closed" : "viz";
    }

    onHasMusicChanged: CavaService.wanted = hasMusic

    // Shelved files moved while the shelf wasn't looking: find them as it
    // opens.
    readonly property bool shelfShown: mode === "open" && tab === 3
    // The Shelf pins itself (files get dragged in and out, and the notch
    // must stay); 📌 unpins it, and leaving the tab undoes it.
    property bool shelfPin: false
    onShelfShownChanged: {
        if (shelfShown) {
            ShelfService.follow();
            if (!pinned)
                pinned = shelfPin = true;
        } else if (shelfPin && mode === "open") {
            pinned = shelfPin = false;
        }
    }

    // The first activity of the day: show the day for a few seconds.
    Connections {
        target: TodayService
        function onMorningOpen() {
            if (win.mode !== "closed")
                return;
            win.open(4);
            morningTimer.restart();
        }
    }
    Timer {
        id: morningTimer
        interval: Math.max(2, win.o.todayMorningSeconds) * 1000
        onTriggered: if (win.mode === "open" && win.tab === 4 && !hover.hovered && !win.keepOpen)
            win.close()
    }

    // Visualizer mode: no keyboard or mouse for a while (idle inhibitors,
    // like a fullscreen video, are respected) and music playing.
    IdleMonitor {
        id: idleMonitor
        enabled: win.o.vizMode
        timeout: Math.max(5, win.o.vizIdleSeconds)
        respectInhibitors: true
    }
    readonly property bool away: idleMonitor.isIdle
    readonly property bool vizWanted: o.vizMode && away && hasMusic && LyricsService.isPlaying
    onVizWantedChanged: {
        if (vizWanted && mode === "closed")
            mode = "viz";
        else if (!vizWanted && mode === "viz")
            mode = "closed";
    }

    implicitWidth: Math.max(o.notchWidth, 430) + 80
    implicitHeight: Math.max(o.notchHeight, finderHeight, todayHeight) + 50

    Timer {
        id: hoverTimer
        interval: win.o.notchHoverDelay
        onTriggered: if (win.mode === "closed")
            win.mode = win.hasMusic ? "peek" : "open"
    }

    // Opened from a bar widget but never visited: tidy it away, like a
    // popout would when you click elsewhere.
    Timer {
        id: unvisitedTimer
        interval: 5000
        running: win.barMode && win.mode === "open" && !hover.hovered && !win.keepOpen
        onTriggered: if (!checklist.inputFocused && !todayTab.inputFocused)
            win.close()
    }

    Timer {
        id: leaveTimer
        interval: win.o.notchCloseDelay
        onTriggered: {
            if (win.keepOpen)
                return;
            // Don't snatch the panel away while you're typing a task.
            if (win.mode === "open" && ((checklist.inputFocused && checklist.draft !== "") || (todayTab.inputFocused && todayTab.draft !== "")))
                return;
            win.close();
        }
    }

    // ── Shape ─────────────────────────────────────────────────────
    Item {
        id: body
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: win.mode === "closed" ? 0.25 : 0.5
            shadowBlur: 0.8
            shadowVerticalOffset: 4
        }

        Rectangle {
            id: shape

            readonly property real r: win.mode === "open" || win.mode === "find" ? 30 : win.mode === "peek" || win.mode === "viz" ? 26 : height / 2

            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: win.target.width
            height: win.target.height
            color: Theme.surface
            opacity: win.mode === "closed" && (win.barMode || (win.idle && win.o.notchIdle === "hidden")) ? 0 : 1
            // Faded out in bar mode (opened only by the bar widget): skip it,
            // and its animations (see below) stop. Elsewhere it must stay to
            // catch the hover that reveals it.
            visible: opacity > 0 || !win.barMode
            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                }
            }
            clip: true

            topLeftRadius: win.island ? r : 0
            topRightRadius: win.island ? r : 0
            bottomLeftRadius: r
            bottomRightRadius: r

            Behavior on width {
                SpringAnimation {
                    spring: 3.5
                    damping: 0.28
                    epsilon: 0.5
                }
            }
            Behavior on height {
                SpringAnimation {
                    spring: 3.5
                    damping: 0.3
                    epsilon: 0.5
                }
            }

            HoverHandler {
                id: hover
                onHoveredChanged: {
                    if (hovered) {
                        leaveTimer.stop();
                        if (win.mode === "closed" && !win.barMode)
                            hoverTimer.restart();
                    } else {
                        hoverTimer.stop();
                        if (win.mode !== "closed" && win.o.notchAutoClose && !win.keepOpen)
                            leaveTimer.restart();
                    }
                }
            }

            // Files dragged over the island open the shelf; dropping parks
            // them there.
            DropArea {
                id: drop
                anchors.fill: parent
                onEntered: drag => {
                    if (!drag.hasUrls)
                        return;
                    drag.accept(Qt.CopyAction);
                    leaveTimer.stop();
                    win.open(3);
                }
                onDropped: drop => {
                    if (drop.hasUrls && ShelfService.add(drop.urls) > 0)
                        drop.accept(Qt.CopyAction);
                }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                visible: drop.containsDrag
                radius: shape.r - 6
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                border.color: Theme.primary
                border.width: 2
            }

            TapHandler {
                enabled: win.mode !== "open" && win.mode !== "find"
                onTapped: win.mode === "viz" ? win.close() : win.open(win.showSoon || win.showDue ? 4 : win.hasMusic ? 0 : win.hasTimer ? 1 : win.tab)
            }

            // ── Closed: live activities ───────────────────────────
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 12
                spacing: 10
                opacity: win.mode === "closed" && (win.hasMusic || win.hasTimer) && !win.showSoon ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                    }
                }

                NotchArt {
                    visible: win.hasMusic
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                }
                // Long lyrics are cut off rather than ending in "…", and slide
                // along as the line is sung so the current words stay in view.
                Item {
                    visible: win.hasMusic
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Text {
                        id: pillLyric
                        readonly property real overflow: Math.max(0, implicitWidth - parent.width)
                        readonly property bool lyric: text !== LyricsService.title
                        anchors.verticalCenter: parent.verticalCenter
                        x: lyric ? -overflow * Math.max(0, Math.min(1, (LyricsService.progress - 0.2) / 0.6)) : 0
                        text: win.pillText
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                        // Animations only while on screen; the lyric moves
                        // constantly, so a hidden one would still cost.
                        Behavior on x {
                            enabled: pillLyric.visible
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                Visualizer {
                    visible: win.hasMusic
                    Layout.preferredHeight: 16
                }
                // Deadlines due today, small, while music plays.
                Text {
                    visible: win.hasMusic && win.o.todayEnabled && TodayService.dueToday > 0
                    text: `${TodayService.dueToday} tenggat`
                    color: Theme.danger
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                TimerChip {
                    visible: win.hasTimer
                    Layout.fillWidth: !win.hasMusic
                }
            }

            // Today: the next lesson about to start, or a deadline due today.
            Row {
                id: todayChip
                anchors.centerIn: parent
                spacing: 6
                opacity: win.mode === "closed" && (win.showSoon || win.showDue) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.showSoon ? "school" : "assignment_late"
                    color: win.showSoon ? Theme.primary : Theme.danger
                    font.family: Theme.iconFont
                    font.pixelSize: 17
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, win.o.notchPillWidth)
                    elide: Text.ElideRight
                    text: win.todayText
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }

            // Weather, when there's nothing else to show.
            Row {
                id: weatherChip
                anchors.centerIn: parent
                spacing: 6
                opacity: win.mode === "closed" && win.showWeather ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: WeatherService.icon
                    color: Theme.primary
                    font.family: Theme.iconFont
                    font.pixelSize: 18
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: WeatherService.tempText
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            // ── Viz: you're away, the music fills the island ──────
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                opacity: win.mode === "viz" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                    }
                }

                NotchArt {
                    Layout.preferredWidth: 108
                    Layout.preferredHeight: 108
                    radius: 16
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: win.pillText
                        color: Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        // Without lyrics the line above is already the title.
                        text: win.pillText === LyricsService.title ? LyricsService.artist : `${LyricsService.title}  ·  ${LyricsService.artist}`
                        color: Theme.subtext
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Row {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 4
                        Repeater {
                            model: CavaService.bars
                            Rectangle {
                                id: vizBar
                                required property int index
                                readonly property real v: CavaService.values[index] ?? 0
                                anchors.bottom: parent.bottom
                                width: Math.max(3, (parent.width - 4 * (CavaService.bars - 1)) / CavaService.bars)
                                height: Math.max(4, v * parent.height)
                                radius: width / 2
                                color: Theme.primary
                                opacity: 0.45 + v * 0.55
                                Behavior on height {
                                    enabled: vizBar.visible
                                    NumberAnimation {
                                        duration: 90
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Peek: now playing ─────────────────────────────────
            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12
                opacity: win.mode === "peek" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }

                NotchArt {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radius: 14
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: LyricsService.title
                        color: Theme.text
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: LyricsService.artist
                        color: Theme.subtext
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: 3
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.15)
                        Rectangle {
                            readonly property real len: LyricsService.player?.length ?? 0
                            width: len > 0 ? parent.width * Math.min(1, LyricsService.position / len) : 0
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                        }
                    }
                }
                Visualizer {
                    Layout.preferredHeight: 22
                }
                NotchIconButton {
                    icon: LyricsService.isPlaying ? "pause" : "play_arrow"
                    filled: true
                    highlighted: true
                    onClicked: LyricsService.player?.togglePlaying()
                }
                NotchIconButton {
                    icon: "skip_next"
                    filled: true
                    onClicked: LyricsService.player?.next()
                }
            }

            // ── Open: tabs ────────────────────────────────────────
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                anchors.topMargin: 12
                spacing: 12
                opacity: win.mode === "open" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: [
                            { icon: "music_note", text: "Media" },
                            { icon: "timer", text: "Focus" },
                            { icon: "checklist", text: "Checklist" },
                            { icon: "inventory_2", text: "Shelf" },
                            { icon: "today", text: "Hari ini" },
                            { icon: "calendar_month", text: "Kalender" }
                        ]
                        Rectangle {
                            id: tabButton
                            required property var modelData
                            required property int index
                            readonly property bool current: win.tab === index
                            implicitWidth: tabRow.implicitWidth + 22
                            implicitHeight: 30
                            radius: 15
                            color: current ? Qt.rgba(1, 1, 1, 0.12) : tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                            Behavior on implicitWidth {
                                NumberAnimation {
                                    duration: 180
                                    easing.type: Easing.OutCubic
                                }
                            }

                            // Six tabs don't fit with words: only the open
                            // one says its name.
                            Row {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: tabButton.current ? 6 : 0
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabButton.modelData.icon
                                    color: tabButton.current ? Theme.primary : Theme.subtext
                                    font.family: Theme.iconFont
                                    font.pixelSize: 17
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: tabButton.current
                                    text: tabButton.modelData.text
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                }
                            }
                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.tab = tabButton.index
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                    TimerChip {
                        visible: win.hasTimer && win.tab !== 1
                    }
                    NotchIconButton {
                        icon: "push_pin"
                        size: 28
                        filled: win.pinned
                        tint: win.pinned ? Theme.primary : Theme.subtext
                        onClicked: {
                            win.pinned = !win.pinned;
                            win.shelfPin = false;
                        }
                    }
                    NotchIconButton {
                        icon: "settings"
                        size: 28
                        tint: Theme.subtext
                        onClicked: {
                            win.close();
                            win.settingsRequested();
                        }
                    }
                    NotchIconButton {
                        icon: "expand_less"
                        size: 28
                        tint: Theme.subtext
                        onClicked: win.close()
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: win.tab

                    NotchMedia {}
                    NotchFocus {}
                    NotchChecklist {
                        id: checklist
                    }
                    NotchShelf {}
                    NotchToday {
                        id: todayTab
                        onCalendarRequested: win.tab = 5
                    }
                    NotchCalendar {
                        active: win.mode === "open" && win.tab === 5
                    }
                }
            }

            // ── Finder ────────────────────────────────────────────
            FinderView {
                id: finder
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: 12
                anchors.bottomMargin: 10
                opacity: win.mode === "find" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
                onCloseRequested: win.close()
            }

            // After the Finder key, the first letter typed starts Finder.
            Item {
                id: typeCatcher
                Keys.onPressed: event => {
                    if (win.mode !== "open" || event.text.length !== 1 || event.text < " " || event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                        return;
                    win.find(event.text);
                    event.accepted = true;
                }
            }

            // ← → go through the tabs (not while typing in a field).
            Shortcut {
                sequence: "Left"
                enabled: win.mode === "open" && !checklist.inputFocused && !todayTab.inputFocused
                onActivated: win.tab = (win.tab + win.tabCount - 1) % win.tabCount
            }
            Shortcut {
                sequence: "Right"
                enabled: win.mode === "open" && !checklist.inputFocused && !todayTab.inputFocused
                onActivated: win.tab = (win.tab + 1) % win.tabCount
            }
            Shortcut {
                sequence: "Escape"
                enabled: win.mode === "open" || win.mode === "find"
                onActivated: win.close()
            }
        }

        // Concave "ears" that blend a top-attached notch into the screen edge.
        Repeater {
            model: win.island ? 0 : 2
            Shape {
                required property int index
                readonly property real r: 12
                width: r
                height: r
                x: index === 0 ? shape.x - r : shape.x + shape.width
                y: 0
                transform: Scale {
                    origin.x: 6
                    xScale: index === 0 ? 1 : -1
                }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.surface
                    strokeColor: "transparent"
                    startX: 0
                    startY: 0
                    PathLine {
                        x: 12
                        y: 0
                    }
                    PathLine {
                        x: 12
                        y: 12
                    }
                    PathArc {
                        x: 0
                        y: 0
                        radiusX: 12
                        radiusY: 12
                    }
                }
            }
        }
    }

    // ── Small pieces ──────────────────────────────────────────────
    component Visualizer: Row {
        spacing: 2.5
        Repeater {
            // A count, not the values array: a new array every frame would
            // rebuild every bar.
            model: CavaService.smallBars
            Rectangle {
                id: bar
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: Math.max(3, (CavaService.small[index] ?? 0) * parent.height)
                radius: 1.5
                color: Theme.primary
                Behavior on height {
                    enabled: bar.visible
                    NumberAnimation {
                        duration: 80
                    }
                }
            }
        }
    }

    component TimerChip: Row {
        spacing: 6
        layoutDirection: Qt.RightToLeft
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: PomodoroService.clock
            color: PomodoroService.mode === "focus" ? Theme.focus : Theme.primary
            opacity: PomodoroService.running ? 1 : 0.55
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.features: ({ tnum: 1 })
        }
        Shape {
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: PomodoroService.mode === "focus" ? Theme.focus : Theme.primary
                strokeWidth: 2.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 8
                    centerY: 8
                    radiusX: 6
                    radiusY: 6
                    startAngle: -90
                    sweepAngle: 360 * Math.max(0.001, 1 - PomodoroService.progress)
                }
            }
        }
    }
}
