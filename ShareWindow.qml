import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// A "now playing" card to share: the artwork, the song and a lyric line,
// saved as a 1080×1080 image or copied to the clipboard.
PanelWindow {
    id: win

    readonly property var line: LyricsService.lines[ShareService.line] ?? null
    readonly property string lyric: line ? line.main : ""
    property string message: ""

    anchors.top: true
    margins.top: 80
    implicitWidth: 560
    implicitHeight: column.implicitHeight + 40
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "islet-share"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Render the card at 1080×1080 and hand the file to `then`.
    function render(then) {
        card.grabToImage(result => {
            if (result.saveToFile(ShareService.scratch))
                then();
            else
                win.message = "Couldn't render the card";
        }, Qt.size(1080, 1080));
    }

    function copy() {
        render(() => {
            Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$0"', ShareService.scratch]);
            win.message = "Copied — paste it anywhere";
        });
    }

    function save() {
        render(() => {
            saver.command = ["sh", "-c", 'd="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Islet"; mkdir -p "$d" && cp "$0" "$d/$1" && echo "$d/$1"', ShareService.scratch, ShareService.fileName()];
            saver.running = true;
        });
    }

    Connections {
        target: ShareService
        function onAction(what) {
            what === "copy" ? win.copy() : win.save();
        }
    }
    // Asked for from the command line before the window existed: wait for
    // the artwork, then do it.
    Timer {
        running: ShareService._pending !== ""
        interval: 600
        onTriggered: {
            const what = ShareService._pending;
            ShareService._pending = "";
            what === "copy" ? win.copy() : win.save();
        }
    }

    Process {
        id: saver
        stdout: SplitParser {
            onRead: path => {
                win.savedPath = path;
                win.message = `Saved to ${path.replace(Quickshell.env("HOME"), "~")}`;
            }
        }
    }
    property string savedPath: ""

    Rectangle {
        anchors.fill: parent
        radius: 28
        color: "#ee101114"
        border.color: Qt.rgba(1, 1, 1, 0.08)

        ColumnLayout {
            id: column
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: 14

            // ── The card ──────────────────────────────────────────
            Item {
                id: card
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 520
                implicitHeight: 520
                clip: true

                // Bigger than the card, so the blur's soft edges fall outside.
                Image {
                    id: backdropArt
                    anchors.fill: parent
                    anchors.margins: -60
                    source: LyricsService.artUrl
                    sourceSize: Qt.size(512, 512)
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                MultiEffect {
                    anchors.fill: backdropArt
                    source: backdropArt
                    blurEnabled: true
                    blurMax: 64
                    blur: 1
                    saturation: 0.2
                    brightness: -0.1
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: "#40000000"
                        }
                        GradientStop {
                            position: 1
                            color: "#b0000000"
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 36
                    spacing: 18

                    RowLayout {
                        spacing: 18
                        NotchArt {
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 120
                            radius: 18
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                text: LyricsService.title
                                color: "white"
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 24
                                font.weight: Font.Bold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: LyricsService.artist
                                color: "#d0ffffff"
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 16
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: win.lyric !== ""
                        text: win.lyric
                        color: "white"
                        wrapMode: Text.Wrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 22
                        font.family: Theme.font
                        font.pixelSize: win.lyric.length > 60 ? 30 : 38
                        font.weight: Font.Bold
                        lineHeight: 1.1
                        style: Text.Normal
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        Text {
                            text: "graphic_eq"
                            color: Theme.primary
                            font.family: Theme.iconFont
                            font.pixelSize: 18
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Islet"
                            color: "#99ffffff"
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // ── Controls ──────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                NotchIconButton {
                    icon: "chevron_left"
                    tint: Theme.subtext
                    onClicked: ShareService.step(-1)
                }
                Text {
                    text: "Line"
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 13
                }
                NotchIconButton {
                    icon: "chevron_right"
                    tint: Theme.subtext
                    onClicked: ShareService.step(1)
                }
                Item {
                    Layout.fillWidth: true
                }
                Pill {
                    icon: "content_copy"
                    text: "Copy"
                    primary: true
                    onClicked: win.copy()
                }
                Pill {
                    icon: "download"
                    text: "Save"
                    onClicked: win.save()
                }
                NotchIconButton {
                    icon: "close"
                    tint: Theme.subtext
                    onClicked: ShareService.open = false
                }
            }

            Text {
                Layout.fillWidth: true
                visible: win.message !== ""
                text: win.message
                color: Theme.primary
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.font
                font.pixelSize: 12
                MouseArea {
                    anchors.fill: parent
                    enabled: win.savedPath !== ""
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: Qt.openUrlExternally(`file://${win.savedPath.replace(/\/[^\/]*$/, "")}`)
                }
            }
        }

        Shortcut {
            sequence: "Escape"
            onActivated: ShareService.open = false
        }
        Shortcut {
            sequences: ["Left", "Up"]
            onActivated: ShareService.step(-1)
        }
        Shortcut {
            sequences: ["Right", "Down"]
            onActivated: ShareService.step(1)
        }
        Shortcut {
            sequences: [StandardKey.Copy]
            onActivated: win.copy()
        }
    }

    component Pill: Rectangle {
        id: pill
        property string icon
        property string text
        property bool primary: false
        signal clicked
        implicitWidth: pillRow.implicitWidth + 28
        implicitHeight: 36
        radius: 18
        color: primary ? Theme.primary : pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.icon
                color: pill.primary ? Theme.onPrimary : Theme.text
                font.family: Theme.iconFont
                font.pixelSize: 18
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.primary ? Theme.onPrimary : Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }
}
