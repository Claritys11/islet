//@ pragma Env QT_QUICK_CONTROLS_STYLE=Material
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    property bool hidden: false
    property bool settingsOpen: false

    // `qs -c lyrics-wheel ipc call lyrics <function>` (or the `lyrics-wheel` CLI)
    IpcHandler {
        target: "lyrics"

        function settings(): void {
            // Recreate in case the compositor closed the window behind our back.
            shell.settingsOpen = false;
            shell.settingsOpen = true;
        }
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
            return `${LyricsService.status} · ${LyricsService.artist} — ${LyricsService.title}`;
        }
    }

    IpcHandler {
        target: "notch"

        function toggle(): void {
            shell.notch?.toggle();
        }
        function open(tab: string): void {
            shell.notch?.open(["media", "focus", "checklist"].indexOf(tab) >= 0 ? ["media", "focus", "checklist"].indexOf(tab) : undefined);
        }
        function close(): void {
            shell.notch?.close();
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
        function status(): string {
            return `${PomodoroService.label} ${PomodoroService.clock}${PomodoroService.running ? "" : " (paused)"} · ${PomodoroService.todayCount} today`;
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

    // The notch lives on one monitor: the configured one, else the first.
    readonly property var notchScreen: Quickshell.screens.find(s => s.name === Config.opts.notchScreen) ?? Quickshell.screens[0]
    property var notch: notchLoader.item

    LazyLoader {
        id: notchLoader
        active: Config.opts.notchEnabled && shell.notchScreen !== undefined

        NotchWindow {
            modelData: shell.notchScreen
            onSettingsRequested: {
                shell.settingsOpen = false;
                shell.settingsOpen = true;
            }
        }
    }

    LazyLoader {
        active: shell.settingsOpen

        SettingsWindow {
            visible: true
            shellNotch: shell.notch
            onVisibleChanged: if (!visible)
                shell.settingsOpen = false
        }
    }

    Variants {
        model: {
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
            readonly property bool shown: !shell.hidden && LyricsService.player !== null && LyricsService.title !== ""
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
            WlrLayershell.namespace: "lyrics-wheel"
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
                        text: "Lyrics area"
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
