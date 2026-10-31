import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services
import "fill.mjs" as Fill
import "common"

// Islet in the DankMaterialShell bar. Islet runs separately and streams its
// state over $XDG_RUNTIME_DIR/islet.sock; this pill only displays it and
// sends clicks back. Left click opens Islet's island under the pill, right
// click plays/pauses, scrolling turns the playing app's volume.
PluginComponent {
    id: root

    layerNamespacePlugin: "islet-media"

    // Latest state from Islet (see IsletLink.qml in the Islet repo), through
    // the one connection this plugin's tab, card and the desktop widgets share.
    readonly property var st: IsletClient.state
    readonly property bool linked: IsletClient.connected && st !== null
    readonly property bool hasTrack: linked && st.hasTrack
    readonly property bool hasTimer: linked && st.timer !== null && (st.bar?.timer ?? true)
    readonly property string text: !hasTrack ? "" : st.line !== "" && st.bar?.text !== "title" ? st.line : `${st.title}  ·  ${st.artist}`
    // Today: a lesson about to start beats the song; deadlines due today
    // show when nothing plays (and as a small count while music does).
    readonly property string soon: linked ? (st.today?.soon ?? "") : ""
    readonly property int due: linked ? (st.today?.due ?? 0) : 0
    readonly property bool hasSoon: soon !== ""
    readonly property bool hasDue: !hasTrack && !hasTimer && !hasSoon && due > 0
    readonly property bool hasWeather: linked && !hasTrack && !hasTimer && !hasSoon && !hasDue && !!st.weather
    readonly property bool isLyric: hasTrack && st.line !== "" && st.bar?.text !== "title"

    // The karaoke fill, worked out here from the line's keys and Islet's
    // clock anchor (link/fill.mjs): Islet sends a line once, not 30 times a
    // second. 30 times a second while it's sung on screen (not every frame:
    // on a 180 Hz screen that redraws the whole bar 180 times), and only a
    // change of about a pixel redraws it, so held syllables cost nothing.
    property real lyricFill: 0
    function updateFill() {
        const f = st?.fill;
        const p = f ? Fill.fillAt(f.keys, Fill.clockAt(f.clock, Date.now())) : 1;
        if (p === 1 || p === 0 || Math.abs(p - lyricFill) >= 0.004)
            lyricFill = p;
    }
    onStChanged: updateFill()
    Timer {
        running: root.isLyric && !!root.st?.fill?.clock?.playing && root.lyricFill < 1 && root.surfaceLive
        repeat: true
        interval: 33
        onTriggered: root.updateFill()
    }

    // The visualizer from DMS's own cava (shared with its widgets). Asking
    // for it is what makes DMS look for cava, so don't wait for cavaAvailable.
    readonly property bool vizLive: hasTrack && !!st?.playing && (st.bar?.viz ?? true) && surfaceLive
    property var vizLevels: [0, 0, 0, 0, 0, 0]
    Loader {
        active: root.vizLive
        sourceComponent: Component {
            Ref {
                service: CavaService
            }
        }
    }
    Connections {
        target: CavaService
        enabled: root.vizLive
        function onValuesChanged() {
            const v = CavaService.values;
            if (v.length >= 6)
                root.vizLevels = [0, 1, 2, 3, 4, 5].map(i => v[i] <= 0 ? 0 : v[i] >= 100 ? 1 : Math.sqrt(v[i] * 0.01));
        }
    }
    onVizLiveChanged: if (!vizLive)
        vizLevels = [0, 0, 0, 0, 0, 0]
    // Without cava, the gentle stand-in Islet always had: each bar wanders
    // toward a random target (about 11 steps a second).
    property var _vizTargets: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
    Timer {
        running: root.vizLive && CavaService._cavaChecked && !CavaService.cavaAvailable
        repeat: true
        interval: 90
        onTriggered: {
            root._vizTargets = root._vizTargets.map((t, i) => Math.random() < 0.35 ? Math.max(0.1, Math.min(1, 0.55 - i / 6 * 0.35 + (Math.random() - 0.5) * 0.7)) : t);
            root.vizLevels = root.vizLevels.map((v, i) => v + (root._vizTargets[i] - v) * 0.45);
        }
    }
    // The playing app's volume (%), -1 when it can't be turned; shown in place
    // of the lyric for a moment after scrolling.
    readonly property int volume: hasTrack ? (st.volume ?? -1) : -1
    property bool showVolume: false
    Timer {
        id: volumeShown
        interval: 1200
        onTriggered: root.showVolume = false
    }

    function send(msg) {
        IsletClient.send(msg);
    }

    // Islet's notch: in DMS mode the Islet tab of DMS's dashboard (in the
    // Island when DMS has one), else Islet's own island under the pill.
    pillClickAction: (x, y, width, section, screen) => {
        if (st?.bar?.notch === "dms")
            Quickshell.execDetached(["dms", "ipc", "call", "dash", "toggle", "plugin_isletMedia"]);
        else
            send({ cmd: "toggle", tab: hasSoon || hasDue ? "today" : hasTrack ? "media" : "focus", x, y, width });
    }
    pillRightClickAction: () => send({ cmd: "play-pause" })

    horizontalBarPill: Component {
        Item {
            id: pill
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight

            // The whole pill stays within Islet's "Max width", so a long
            // line or deadline never pushes it over the workspaces: the text
            // gets what the other parts leave.
            readonly property real cap: root.st?.bar?.width ?? 300
            readonly property real others: [art, dueCount, viz, timer].reduce((w, i) => w + (i.visible ? i.width + pillRow.spacing : 0), 0) + (todayIcon.visible ? todayIcon.width + Theme.spacingXS : 0)
            readonly property real room: Math.max(60, cap - others)

            // Scrolling turns the playing app's volume, 5% a notch (a
            // touchpad's small steps add up to one).
            WheelHandler {
                enabled: root.volume >= 0
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                property real acc: 0
                onWheel: event => {
                    acc += event.angleDelta.y;
                    const steps = acc > 0 ? Math.floor(acc / 120) : Math.ceil(acc / 120);
                    root.showVolume = true;
                    volumeShown.restart();
                    if (steps === 0)
                        return;
                    acc -= steps * 120;
                    root.send({ cmd: "volume", steps });
                }
            }

            // Files dragged onto the pill open Islet's shelf right below it
            // (in DMS mode the dashboard's Islet tab, at Shelf, which takes
            // them too), and dropping them here parks them on the shelf.
            DropArea {
                id: pillDrop
                anchors.fill: parent
                anchors.margins: -6
                onEntered: drag => {
                    if (!drag.hasUrls)
                        return;
                    drag.accept(Qt.CopyAction);
                    IsletClient.panelPage = "shelf";
                    const p = pill.mapToGlobal(0, 0);
                    root.send({ cmd: "open", tab: "shelf", x: p.x, y: -1, width: pill.width });
                }
                onDropped: drop => {
                    if (!drop.hasUrls)
                        return;
                    root.send({ cmd: "shelf-add", urls: drop.urls.map(u => u.toString()) });
                    drop.accept(Qt.CopyAction);
                }
            }

            Rectangle {
                visible: pillDrop.containsDrag
                anchors.fill: parent
                anchors.margins: -4
                radius: Theme.cornerRadius
                color: Qt.alpha(Theme.primary, 0.15)
                border.color: Theme.primary
                border.width: 1
            }

            Row {
                id: pillRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                // Islet isn't running: a quiet hint instead of an empty gap.
                DankIcon {
                    visible: !root.linked
                    anchors.verticalCenter: parent.verticalCenter
                    name: "lyrics"
                    size: Theme.iconSize - 4
                    color: Theme.surfaceVariantText
                }

                ClippingRectangle {
                    id: art
                    visible: root.hasTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(root.widgetThickness * 0.62)
                    height: width
                    radius: width / 2
                    color: Theme.surfaceContainerHigh

                    Image {
                        anchors.fill: parent
                        source: root.st?.art ?? ""
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                }

                // The lyric with its karaoke fill: a dim copy, and a bright copy
                // revealed as the line is sung. Long lines are cut off and slide
                // along with the singer instead of ending in "…".
                // A lesson starting soon, or a deadline due today.
                Row {
                    visible: root.hasSoon || root.hasDue
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    DankIcon {
                        id: todayIcon
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.hasSoon ? "school" : "assignment_late"
                        size: Theme.iconSize - 4
                        color: root.hasSoon ? Theme.primary : Theme.error
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, pill.room)
                        elide: Text.ElideRight
                        text: root.hasSoon ? root.soon : root.st?.today?.dueText ?? ""
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                // The volume, for a moment after scrolling.
                Row {
                    id: volumeRow
                    visible: root.showVolume && root.volume >= 0 && !root.hasSoon
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.volume === 0 ? "volume_off" : root.volume < 50 ? "volume_down" : "volume_up"
                        size: Theme.iconSize - 4
                        color: Theme.surfaceText
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(90, pill.room - 60)
                        height: 4
                        radius: 2
                        color: Theme.surfaceVariant
                        Rectangle {
                            width: parent.width * Math.max(0, root.volume) / 100
                            height: parent.height
                            radius: 2
                            color: Theme.primary
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: `${root.volume}%`
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                        font.features: ({ tnum: 1 })
                    }
                }

                Item {
                    id: lyric
                    visible: root.hasTrack && !root.hasSoon && !volumeRow.visible
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(base.implicitWidth, pill.room)
                    height: base.implicitHeight
                    clip: true

                    readonly property real overflow: Math.max(0, base.implicitWidth - width)
                    readonly property real progress: root.isLyric ? root.lyricFill : 1
                    readonly property real shift: root.isLyric ? overflow * Math.max(0, Math.min(1, (progress - 0.2) / 0.6)) : 0

                    StyledText {
                        id: base
                        x: -lyric.shift
                        text: root.text
                        color: Theme.surfaceText
                        opacity: root.isLyric ? 0.5 : 0.9
                        font.pixelSize: Theme.fontSizeMedium
                        // The same weight as the sung copy over it: a bolder one
                        // is wider, and the two read as a doubled line.
                        font.weight: Font.Medium
                    }

                    Item {
                        visible: root.isLyric
                        x: -lyric.shift
                        width: base.implicitWidth * lyric.progress
                        height: base.height
                        clip: true

                        StyledText {
                            text: root.text
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                        }
                    }
                }

                StyledText {
                    id: dueCount
                    visible: root.hasTrack && !root.hasSoon && root.due > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: IsletClient.t(`${root.due} due`, `${root.due} tenggat`)
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                }

                Row {
                    id: viz
                    visible: root.hasTrack && !root.hasSoon && (root.st?.bar?.viz ?? true)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: Math.max(3, (root.vizLevels[index] ?? 0) * root.widgetThickness * 0.5)
                            radius: 1.5
                            color: Theme.primary
                        }
                    }
                }

                Row {
                    id: timer
                    visible: root.hasTimer
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.st?.timer?.paused ? "pause_circle" : "timer"
                        size: Theme.iconSize - 6
                        color: root.st?.timer?.mode === "focus" ? Theme.primary : Theme.surfaceText
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.st?.timer?.clock ?? ""
                        color: Theme.surfaceText
                        opacity: root.st?.timer?.running ? 1 : 0.55
                        font.pixelSize: Theme.fontSizeSmall
                        font.features: ({ tnum: 1 })
                    }
                }

                // Nothing playing and no timer: the weather, if Islet has it.
                Row {
                    visible: root.hasWeather
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.st?.weather?.icon ?? "cloud"
                        size: Theme.iconSize - 4
                        color: Theme.primary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.st?.weather?.temp ?? ""
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                // …or just a small icon to open Islet.
                DankIcon {
                    visible: root.linked && !root.hasTrack && !root.hasTimer && !root.hasWeather && !root.hasSoon && !root.hasDue
                    anchors.verticalCenter: parent.verticalCenter
                    name: "music_note"
                    size: Theme.iconSize - 4
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            ClippingRectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(root.widgetThickness * 0.62)
                height: width
                radius: width / 2
                color: Theme.surfaceContainerHigh
                Image {
                    anchors.fill: parent
                    visible: root.hasTrack
                    source: root.st?.art ?? ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                DankIcon {
                    anchors.centerIn: parent
                    visible: !root.hasTrack
                    name: "lyrics"
                    size: Theme.iconSize - 6
                    color: Theme.surfaceVariantText
                }
            }
            StyledText {
                visible: root.hasTimer
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.st?.timer?.clock ?? ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
