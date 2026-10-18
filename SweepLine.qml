import QtQuick
import QtQuick.Effects

// One row of text with a karaoke fill: a dim base copy, plus a bright glowing
// copy revealed left-to-right through a soft-edged gradient mask.
Item {
    id: root

    property string text
    property real pixelSize: 30
    property real minPixelSize: 14
    property int weight: Font.Normal
    property bool italic: false
    property string family
    property int alignment: Text.AlignRight

    property color baseColor: "#a6a6a6"
    property color fillColor: "#ffffff"
    property color glowColor: "#ffffff"
    property real glow: 0.7
    property real baseOpacity: 1
    // 0 → 1 strength of the bright copy (fades in as the line becomes active)
    property real fill: 0
    // 0 → 1 how far the fill has swept through the text
    property real progress: 0
    property real feather: 28
    // Snap the sweep to whole characters, like a typewriter.
    property bool typewriter: false

    implicitHeight: pixelSize * 1.3

    readonly property real _progress: typewriter && text.length > 0 ? Math.floor(progress * text.length + 0.001) / text.length : progress
    // Where the glyphs actually start/end inside the item, in 0..1.
    readonly property real _start: alignment === Text.AlignRight ? 1 - base.contentWidth / Math.max(width, 1) : 0
    readonly property real _soft: typewriter ? 0.001 : feather / Math.max(width, 1)
    readonly property real _edge: _start + _progress * base.contentWidth / Math.max(width, 1)
    // Stops collapse onto each other at the end, so a finished line is drawn
    // with a solid mask instead.
    readonly property bool _done: _progress >= 0.999

    component Line: Text {
        anchors.fill: parent
        text: root.text
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        font.italic: root.italic
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: root.minPixelSize
        elide: root.alignment === Text.AlignRight ? Text.ElideLeft : Text.ElideRight
        horizontalAlignment: root.alignment
        verticalAlignment: Text.AlignVCenter
    }

    Line {
        id: base
        color: root.baseColor
        opacity: root.baseOpacity
    }

    Line {
        id: bright
        visible: root.fill > 0.001 && root._progress > 0
        color: root.fillColor
        opacity: root.fill
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
            shadowEnabled: root.glow > 0
            shadowColor: root.glowColor
            shadowOpacity: root.glow
            shadowBlur: 1
            shadowScale: 1.02
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            brightness: root.glow * 0.15
        }
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: "white"
            }
            GradientStop {
                position: Math.max(0, Math.min(1, root._edge - root._soft / 2))
                color: "white"
            }
            GradientStop {
                position: Math.max(0, Math.min(1, root._edge + root._soft / 2))
                color: root._done ? "white" : "transparent"
            }
            GradientStop {
                position: 1
                color: root._done ? "white" : "transparent"
            }
        }
    }
}
