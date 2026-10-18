import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

// Media tab: artwork, track info, live lyric line, scrubber and transport.
Item {
    id: root

    readonly property MprisPlayer player: LyricsService.player
    readonly property real length: LyricsService.length
    readonly property real position: Math.min(LyricsService.position, length)
    readonly property var line: LyricsService.status === "ready" && LyricsService.synced ? LyricsService.lines[LyricsService.currentIndex] : null

    function fmt(s) {
        s = Math.max(0, Math.floor(s));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    Text {
        anchors.centerIn: parent
        visible: !LyricsService.hasTrack
        text: "Nothing playing"
        color: Theme.subtext
        font.family: Theme.font
        font.pixelSize: 15
    }

    RowLayout {
        anchors.fill: parent
        spacing: 18
        visible: LyricsService.hasTrack

        NotchArt {
            Layout.preferredWidth: 132
            Layout.preferredHeight: 132
            Layout.alignment: Qt.AlignVCenter
            radius: 16
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: LyricsService.title
                color: Theme.text
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                text: LyricsService.artist
                color: Theme.subtext
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 14
            }

            // Current lyric line, with the same karaoke fill as the overlay.
            SweepText {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: root.line !== null
                text: root.line?.main ?? ""
                maxRows: 2
                pixelSize: 15
                minPixelSize: 10
                family: Theme.font
                alignment: Text.AlignLeft
                baseColor: Theme.subtext
                fillColor: Theme.primary
                glowColor: Theme.primary
                glow: 0.5
                fill: 1
                baseOpacity: 0.55
                feather: 16
                progress: LyricsService.progress
            }

            Item {
                Layout.fillHeight: true
            }

            // Scrubber
            Item {
                Layout.fillWidth: true
                implicitHeight: 14

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: scrub.containsMouse ? 6 : 4
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.15)

                    Rectangle {
                        width: root.length > 0 ? parent.width * root.position / root.length : 0
                        height: parent.height
                        radius: 3
                        color: Theme.primary
                    }
                }

                MouseArea {
                    id: scrub
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player?.canSeek ?? false
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        root.player.position = root.length * mouse.x / width;
                        LyricsService.resync(root.player.position);
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.fmt(root.position)
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Item {
                    Layout.fillWidth: true
                }
                Text {
                    text: root.fmt(root.length)
                    color: Theme.subtext
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                NotchIconButton {
                    icon: "shuffle"
                    size: 32
                    visible: root.player?.shuffleSupported ?? false
                    tint: root.player?.shuffle ? Theme.primary : Theme.subtext
                    onClicked: root.player.shuffle = !root.player.shuffle
                }
                NotchIconButton {
                    icon: "skip_previous"
                    filled: true
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: root.player?.previous()
                }
                NotchIconButton {
                    icon: LyricsService.isPlaying ? "pause" : "play_arrow"
                    filled: true
                    highlighted: true
                    size: 42
                    onClicked: root.player?.togglePlaying()
                }
                NotchIconButton {
                    icon: "skip_next"
                    filled: true
                    enabled: root.player?.canGoNext ?? false
                    onClicked: root.player?.next()
                }
                NotchIconButton {
                    readonly property int loop: root.player?.loopState ?? MprisLoopState.None
                    icon: loop === MprisLoopState.Track ? "repeat_one" : "repeat"
                    size: 32
                    visible: root.player?.loopSupported ?? false
                    tint: loop === MprisLoopState.None ? Theme.subtext : Theme.primary
                    onClicked: root.player.loopState = loop === MprisLoopState.None ? MprisLoopState.Playlist : loop === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
                }
            }
        }
    }
}
