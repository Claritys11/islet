import QtQuick

// Karaoke text that wraps long lines onto several rows (balanced, so the
// last row isn't a lonely word) and carries the fill through them in reading
// order. With `wrap: false`, long lines shrink to fit instead.
Item {
    id: root

    property string text
    property bool wrap: true
    property int maxRows: 3
    property real pixelSize: 30
    property real minPixelSize: 14
    property int weight: Font.Normal
    // Weight used to measure rows; pass the widest weight the text can take so
    // rows don't re-flow when the line becomes active.
    property int measureWeight: weight
    property bool italic: false
    property string family
    property int alignment: Text.AlignRight

    property color baseColor: "#a6a6a6"
    property color fillColor: "#ffffff"
    property color glowColor: "#ffffff"
    property real glow: 0.7
    property real baseOpacity: 1
    property real fill: 0
    property real progress: 0
    property real feather: 28
    property bool typewriter: false

    readonly property real rowHeight: pixelSize * 1.3
    implicitHeight: rows.length * rowHeight

    FontMetrics {
        id: metrics
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: root.measureWeight
        font.italic: root.italic
    }

    function layout(words, maxWidth) {
        const out = [];
        let cur = "";
        for (const w of words) {
            const next = cur === "" ? w : `${cur} ${w}`;
            if (cur !== "" && metrics.advanceWidth(next) > maxWidth) {
                out.push(cur);
                cur = w;
            } else {
                cur = next;
            }
        }
        if (cur !== "")
            out.push(cur);
        return out;
    }

    readonly property var rows: {
        const words = text.split(/\s+/).filter(w => w !== "");
        if (!wrap || width <= 0 || words.length < 2 || metrics.advanceWidth(text) <= width)
            return [text];
        const greedy = layout(words, width);
        const count = Math.min(greedy.length, maxRows);
        // Balance: find the narrowest width that still needs the same number
        // of rows, so the text splits evenly.
        let lo = width / count, hi = width;
        for (let k = 0; k < 10; k++) {
            const mid = (lo + hi) / 2;
            if (layout(words, mid).length > count)
                lo = mid;
            else
                hi = mid;
        }
        const balanced = layout(words, hi);
        // Past maxRows, the last row takes the rest and shrinks to fit.
        return balanced.length <= maxRows ? balanced : balanced.slice(0, maxRows - 1).concat([balanced.slice(maxRows - 1).join(" ")]);
    }

    // Character offset where each row starts, for spreading the progress.
    readonly property var starts: {
        const out = [];
        let n = 0;
        for (const r of rows) {
            out.push(n);
            n += r.length + 1;
        }
        return out;
    }
    readonly property int total: Math.max(1, rows.reduce((n, r) => n + r.length, 0) + rows.length - 1)

    Repeater {
        model: root.rows

        SweepLine {
            required property string modelData
            required property int index

            y: index * root.rowHeight
            width: root.width
            text: modelData
            pixelSize: root.pixelSize
            minPixelSize: root.minPixelSize
            weight: root.weight
            italic: root.italic
            family: root.family
            alignment: root.alignment
            baseColor: root.baseColor
            fillColor: root.fillColor
            glowColor: root.glowColor
            glow: root.glow
            baseOpacity: root.baseOpacity
            fill: root.fill
            feather: root.feather
            typewriter: root.typewriter
            progress: Math.max(0, Math.min(1, (root.progress * root.total - root.starts[index]) / Math.max(modelData.length, 1)))
        }
    }
}
