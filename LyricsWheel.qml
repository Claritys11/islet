import QtQuick
import QtQuick.Effects

// The React Bits <OptionWheel /> layout, ported to QML and adapted to lyrics:
// lines sit on a circle whose radius keeps the arc length between neighbours
// equal to their row height, eased toward `selected` with frame-rate
// independent exponential smoothing. Rows differ in height (wrapped lines,
// background vocals), so positions are measured along the arc by
// accumulating the heights each row reports.
Item {
    id: root

    // [{ main, bg, bgOnly }]
    property var items: []
    property int selected: 0
    property real progress: 0
    signal itemClicked(int index)

    readonly property var o: Config.opts

    // Wheel position, chasing `selected` on a critically damped spring: it
    // starts gently, glides, and settles without overshoot — a scroll, not a
    // jump. `smoothing` sets how long that takes.
    // Not `pos: selected` — that would be a binding, snapping pos to every
    // new line instantly and leaving the spring nothing to animate.
    property real pos: 0
    property real _velocity: 0
    Component.onCompleted: pos = selected

    readonly property bool onRight: o.side === "right"
    readonly property real mirror: onRight ? -1 : 1
    readonly property real textH: o.fontSize * 1.3
    readonly property real rowH: Math.max(o.fontSize * o.spacing, 1)
    readonly property real spacingFactor: rowH / textH
    readonly property real tiltRad: o.tilt * Math.PI / 180
    readonly property real radius: tiltRad > 0.0005 ? rowH / tiltRad : 0
    readonly property real lineWidth: Math.max(0, width - o.inset - 24)
    readonly property bool karaoke: o.karaoke !== "none"
    readonly property color textColor: o.textColor
    readonly property color activeColor: o.activeColor

    function display(item) {
        const mode = o.bgVocals;
        if (mode === "same")
            return { main: item.text ?? item.main, bg: "", small: false };
        return { main: item.main, bg: mode === "below" ? (item.bg ?? "") : "", small: item.bgOnly ?? false };
    }

    // Row heights, read from the rows themselves whenever any of them (or the
    // list) changes. Reading beats collecting reports: reports sent while the
    // list was being rebuilt could be lost, leaving tall rows (wrapped lines,
    // background vocals) counted as short ones and overlapping.
    property var heights: []
    function collectHeights() {
        const out = [];
        for (let i = 0; i < rows.count; i++)
            out.push(rows.itemAt(i)?.height ?? textH);
        if (JSON.stringify(out) !== JSON.stringify(heights))
            heights = out;
    }
    onItemsChanged: Qt.callLater(collectHeights)

    // Arc-length position (in px) of each line's centre.
    readonly property var centers: {
        const out = [];
        let s = 0;
        const h = i => heights[i] ?? textH;
        for (let i = 0; i < items.length; i++) {
            if (i > 0)
                s += (h(i - 1) + h(i)) / 2 * spacingFactor;
            out.push(s);
        }
        return out;
    }

    function centerAt(p) {
        const n = centers.length;
        if (n === 0)
            return 0;
        const i = Math.max(0, Math.min(n - 1, Math.floor(p)));
        const j = Math.min(n - 1, i + 1);
        return centers[i] + (centers[j] - centers[i]) * (p - i);
    }

    readonly property real posCenter: centerAt(pos)

    clip: true

    // A list swap (new song) jumps straight to the current line instead of
    // spinning through the whole song.
    onSelectedChanged: if (Math.abs(selected - pos) > 8) {
        pos = selected;
        _velocity = 0;
    }

    FrameAnimation {
        running: root.pos !== root.selected || root._velocity !== 0
        onTriggered: {
            // Settles in ~2.5 × smoothing (200 ms → about half a second).
            const omega = 6.6 / (Math.max(root.o.smoothing, 20) * 2.5 / 1000);
            let dt = Math.min(frameTime, 0.05);
            // Small fixed steps keep the spring stable at any frame rate.
            while (dt > 0) {
                const h = Math.min(dt, 1 / 240);
                const accel = -2 * omega * root._velocity - omega * omega * (root.pos - root.selected);
                root._velocity += accel * h;
                root.pos += root._velocity * h;
                dt -= h;
            }
            if (Math.abs(root.selected - root.pos) < 0.001 && Math.abs(root._velocity) < 0.01) {
                root.pos = root.selected;
                root._velocity = 0;
            }
        }
    }

    function mix(a, b, t) {
        return Qt.rgba(b.r + (a.r - b.r) * t, b.g + (a.g - b.g) * t, b.b + (a.b - b.b) * t, b.a + (a.a - b.a) * t);
    }

    Repeater {
        id: rows
        model: root.items
        onItemAdded: Qt.callLater(root.collectHeights)

        Item {
            id: line

            required property var modelData
            required property int index

            readonly property var o: root.o
            readonly property var shown: root.display(modelData)
            readonly property real dist: Math.abs(index - root.pos)
            readonly property real ds: (root.centers[index] ?? 0) - root.posCenter
            readonly property real ang: Math.max(-Math.PI / 2, Math.min(Math.PI / 2, root.radius > 0 ? ds / root.radius : 0))
            // 0 → 1 as the line approaches the middle of the wheel
            readonly property real p: Math.max(0, 1 - Math.min(dist, 1))
            readonly property real offX: root.radius > 0 ? -root.mirror * root.radius * (1 - Math.cos(ang)) * o.curve : 0
            readonly property real offY: root.radius > 0 ? root.radius * Math.sin(ang) : ds
            readonly property real sweep: index < root.selected ? 1 : index === root.selected ? root.progress : 0
            readonly property real mainSize: o.fontSize * (shown.small ? o.bgScale : 1)
            // Only lines near the middle can still have a voice singing.
            readonly property var bg: shown.bg !== "" && dist < 3 ? LyricsService.bgState(index, LyricsService.time) : { progress: index < root.selected ? 1 : 0, glow: 0 }

            visible: dist <= o.visibleLines + 0.5
            width: root.lineWidth
            height: mainPart.implicitHeight + (bgPart.visible ? bgPart.implicitHeight : 0)
            onHeightChanged: Qt.callLater(root.collectHeights)
            x: (root.onRight ? root.width - o.inset - width : o.inset) + offX
            y: root.height / 2 + offY - height / 2

            transformOrigin: root.onRight ? Item.Right : Item.Left
            rotation: root.radius > 0 ? root.mirror * ang * 180 / Math.PI : 0
            opacity: Math.max(o.minOpacity, 1 - dist * o.fade)

            layer.enabled: visible && (o.shadow || (o.blur > 0 && dist > 0.01))
            layer.effect: MultiEffect {
                blurEnabled: line.o.blur > 0
                blurMax: 32
                // A background voice still singing keeps its line sharp.
                blur: Math.min(1, line.dist * line.o.blur * (1 - line.bg.glow * 0.7) / 32)
                shadowEnabled: line.o.shadow
                shadowColor: "#000000"
                shadowOpacity: 0.55
                shadowBlur: 0.5
                shadowVerticalOffset: 1
                shadowHorizontalOffset: 0
            }

            component Part: SweepText {
                width: line.width
                family: line.o.fontFamily
                wrap: line.o.longLines === "wrap"
                minPixelSize: line.o.minFontSize
                alignment: root.onRight ? Text.AlignRight : Text.AlignLeft
                // Blend the weight as the line arrives instead of snapping.
                weight: Math.round(line.o.restingWeight + (line.o.activeWeight - line.o.restingWeight) * line.p)
                measureWeight: Math.max(line.o.activeWeight, line.o.restingWeight)
                fillColor: line.o.activeColor
                glowColor: line.o.glowColor
                feather: line.o.feather
                typewriter: line.o.karaoke === "typewriter"
            }

            Part {
                id: mainPart
                text: line.shown.main
                pixelSize: line.mainSize
                italic: line.shown.small && line.o.bgItalic
                opacity: line.shown.small ? line.o.bgOpacity : 1
                baseColor: root.karaoke ? line.o.textColor : root.mix(root.activeColor, root.textColor, line.p)
                glow: line.o.glow * line.p
                fill: root.karaoke ? line.p : 0
                progress: line.sweep
                baseOpacity: !root.karaoke ? 1 : typewriter ? 1 - line.p : 1 - line.p * (1 - line.o.unsungOpacity)
            }

            Part {
                id: bgPart
                // A background voice stays lit while it's still being sung,
                // even after the wheel has moved on to the next line.
                readonly property real live: Math.max(line.p, line.bg.glow)
                anchors.top: mainPart.bottom
                visible: line.shown.bg !== ""
                text: line.shown.bg
                pixelSize: line.o.fontSize * line.o.bgScale
                italic: line.o.bgItalic
                opacity: line.o.bgOpacity
                baseColor: root.karaoke ? line.o.textColor : root.mix(root.activeColor, root.textColor, live)
                glow: line.o.glow * live
                fill: root.karaoke ? live : 0
                progress: line.bg.progress
                baseOpacity: !root.karaoke ? 1 : typewriter ? 1 - live : 1 - live * (1 - line.o.unsungOpacity)
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.itemClicked(line.index)
            }
        }
    }
}
