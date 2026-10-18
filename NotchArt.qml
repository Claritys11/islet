import QtQuick
import QtQuick.Effects

// Rounded album artwork with a music-note placeholder.
Item {
    id: root

    property real radius: 8

    Rectangle {
        id: placeholder
        anchors.fill: parent
        radius: root.radius
        color: Theme.raised

        Text {
            anchors.centerIn: parent
            text: "music_note"
            color: Theme.subtext
            font.family: Theme.iconFont
            font.pixelSize: parent.height * 0.5
        }
    }

    Image {
        id: art
        anchors.fill: parent
        source: LyricsService.artUrl
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }

    Rectangle {
        id: artMask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: art
        visible: art.status === Image.Ready
        maskEnabled: true
        maskSource: artMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
}
