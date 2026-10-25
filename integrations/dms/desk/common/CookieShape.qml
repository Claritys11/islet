import QtQuick
import QtQuick.Shapes
import "cookie.mjs" as Cookie

// The clock's cookie (cookie.mjs): a circle with a wavy edge, filled.
Item {
    id: root

    property real sides: 9
    property int implicitSize: 100
    // How far each dip goes in, as a part of the size.
    property real depth: 0.02
    property color color: "#605790"

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Behavior on sides {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            fillColor: root.color

            PathPolyline {
                readonly property real size: Math.min(shape.width, shape.height)
                path: Cookie.cookiePoints(size, root.sides, root.depth, 360).map(p => Qt.point(p.x + (shape.width - size) / 2, p.y + (shape.height - size) / 2))
            }
        }
    }
}
