pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Audio spectrum for the notch. Uses `cava` (real PipeWire audio) when it's
// installed, otherwise a gentle fake animation that follows play/pause.
Singleton {
    id: root

    // 24 bars for visualizer mode; the small visualizers show 6, each the
    // average of 4 neighbours.
    readonly property int bars: 24
    readonly property int smallBars: 6
    // Set by the notch so nothing runs while it's hidden.
    property bool wanted: false
    readonly property bool active: wanted && LyricsService.isPlaying
    property bool hasCava: false
    // 0..1 per bar
    property var values: Array(bars).fill(0)
    property var small: Array(smallBars).fill(0)
    onValuesChanged: {
        const k = bars / smallBars;
        const out = [];
        for (let i = 0; i < smallBars; i++) {
            let sum = 0;
            for (let j = 0; j < k; j++)
                sum += values[i * k + j] ?? 0;
            out.push(sum / k);
        }
        small = out;
    }

    readonly property string config: [
        "[general]", `bars = ${bars}`, "framerate = 50",
        "[input]", "method = pipewire", "source = auto",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 100", "bar_delimiter = 59", "frame_delimiter = 10",
        "[smoothing]", "noise_reduction = 70"
    ].join("\n")

    Process {
        running: true
        command: ["sh", "-c", "command -v cava"]
        onExited: code => root.hasCava = code === 0
    }

    Process {
        running: root.active && root.hasCava
        command: ["sh", "-c", 'cfg="${XDG_RUNTIME_DIR:-/tmp}/islet-cava.conf"; printf "%s\\n" "$0" > "$cfg"; exec cava -p "$cfg"', root.config]
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(s => s !== "").map(s => Math.min(1, parseInt(s) / 100));
                if (v.length === root.bars)
                    root.values = v;
            }
        }
    }

    // Fallback: each bar wanders toward a random target.
    property var _targets: Array(bars).fill(0.3)
    Timer {
        running: root.active && !root.hasCava
        repeat: true
        interval: 90
        onTriggered: {
            // Neighbouring bars move together a little, like a real spectrum.
            root._targets = root._targets.map((t, i) => Math.random() < 0.35 ? Math.max(0.1, Math.min(1, 0.55 - i / root.bars * 0.35 + (Math.random() - 0.5) * 0.7)) : t);
            root.values = root.values.map((v, i) => v + (root._targets[i] - v) * 0.45);
        }
    }

    onActiveChanged: if (!active)
        values = Array(bars).fill(0)
}
