import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Renders the README screenshots and demo GIF from Islet's real components on
// a mock desktop, so the media never shows anyone's actual screen.
//   ISLET_SHOWCASE=out/ ISLET_CONFIG_DIR=… ISLET_STATE_DIR=… qs -p .
// then `tools/make-media.sh` turns the frames into a GIF. See CONTRIBUTING.md.
// It's an overlay layer so the compositor keeps it on screen and rendering at
// full rate (a normal window can end up scrolled away and barely redrawn);
// it takes no input, so clicks pass through for the half minute it runs.
PanelWindow {
    id: root

    property string outDir
    property int step: 0
    property int frame: 0
    property bool recording: false

    implicitWidth: 1280
    implicitHeight: 720
    color: "#000000"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "islet-showcase"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // A capture in flight; the script waits for it before moving on.
    property bool busy: false

    function shot(item, name) {
        busy = true;
        item.grabToImage(r => {
            r.saveToFile(`${outDir}/${name}.png`);
            busy = false;
        });
    }

    // ── Scene ─────────────────────────────────────────────────────
    Rectangle {
        id: scene
        width: 1280
        height: 720
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: "#0d1030"
            }
            GradientStop {
                position: 0.6
                color: "#1a1240"
            }
            GradientStop {
                position: 1
                color: "#2a0f3a"
            }
        }

        // Soft colour blobs, like a wallpaper.
        Repeater {
            model: [
                { x: -120, y: 380, s: 520, c: "#3ee6ff", o: 0.16 },
                { x: 860, y: -160, s: 560, c: "#ff4fd8", o: 0.14 },
                { x: 420, y: 420, s: 460, c: "#7c5cff", o: 0.18 }
            ]
            Rectangle {
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.s
                height: modelData.s
                radius: width / 2
                color: modelData.c
                opacity: modelData.o
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 64
                    blur: 1
                }
            }
        }

        // A couple of mock windows so it reads as a desktop.
        component MockWindow: Rectangle {
            property var widths: []
            clip: true
            radius: 14
            color: "#d0101218"
            border.color: "#22ffffff"
            Row {
                x: 14
                y: 12
                spacing: 6
                Repeater {
                    model: ["#ff6b6b", "#ffd166", "#a8ff60"]
                    Rectangle {
                        required property string modelData
                        width: 10
                        height: 10
                        radius: 5
                        color: modelData
                        opacity: 0.8
                    }
                }
            }
            Column {
                x: 20
                y: 42
                spacing: 11
                Repeater {
                    model: parent.parent.widths
                    Rectangle {
                        required property real modelData
                        required property int index
                        width: modelData
                        height: 8
                        radius: 4
                        color: ["#5a8dee", "#c792ea", "#7fdbca", "#ffcb6b"][index % 4]
                        opacity: 0.35
                    }
                }
            }
        }

        MockWindow {
            x: 40
            y: 76
            width: 560
            height: 360
            widths: [220, 340, 180, 300, 260, 140, 320, 200, 280, 160, 240, 300, 120, 260, 200, 180, 230]
        }
        MockWindow {
            x: 40
            y: 452
            width: 560
            height: 228
            widths: [180, 260, 220, 140, 300, 200, 240, 160, 210, 120, 180]
        }

        // Lyrics overlay, as on the right edge of a screen.
        Item {
            id: lyricsArea
            x: 1280 - 620
            y: 0
            width: 620
            height: 720

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: Qt.rgba(0, 0, 0, 0.3)
                    }
                }
            }

            Item {
                id: fadeArea
                anchors.fill: parent
                layer.enabled: true
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
                            position: 0.14
                            color: "white"
                        }
                        GradientStop {
                            position: 0.86
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
                    items: LyricsService.lines
                    selected: LyricsService.currentIndex
                    progress: LyricsService.progress
                }
            }
        }

        NotchIsland {
            id: notch
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
        }
    }

    LazyLoader {
        id: settingsLoader
        active: false
        SettingsWindow {
            visible: true
            page: 1
            samplePreview: true
        }
    }

    // ── Script ────────────────────────────────────────────────────
    Component.onCompleted: {
        LyricsService.demo = true;
        PomodoroService.setMode("focus");
        PomodoroService._pausedLeft = 17 * 60 + 42;
        PomodoroService.start();
        for (const t of ["Finish trigonometry homework", "Practice the chorus", "Ship Islet v1.0", "Call grandma"])
            ChecklistService.add(t);
    }

    // Frames for the GIF: 12 fps while recording. If a capture is still
    // pending the frame is repeated, so the clip keeps real-time speed.
    property var _lastFrame: null
    property bool _framePending: false
    property real _recordStart: 0
    Timer {
        running: root.recording
        repeat: true
        interval: 83
        onTriggered: {
            const n = String(root.frame++).padStart(4, "0");
            if (root._framePending && root._lastFrame) {
                root._lastFrame.saveToFile(`${root.outDir}/frames/${n}.png`);
                return;
            }
            root._framePending = true;
            scene.grabToImage(r => {
                r.saveToFile(`${root.outDir}/frames/${n}.png`);
                root._lastFrame = r;
                root._framePending = false;
            });
        }
    }

    // Each entry runs once the previous one's wait is over. Waits give the
    // notch's spring animation time to settle before a capture.
    readonly property var script: [
        { when: () => LyricsService.position >= 5.9, run: () => shot(scene, "hero") },
        // Second loop of the sample song: record a clip.
        { when: () => LyricsService.position >= 1.0 && LyricsService.position < 2, run: () => {
                recording = true;
                _recordStart = Date.now();
            } },
        { when: () => LyricsService.position >= 15.0, run: () => {
                recording = false;
                // The real frame rate, so the clip plays back at true speed.
                const fps = frame / ((Date.now() - _recordStart) / 1000);
                Quickshell.execDetached(["sh", "-c", 'printf %s "$1" > "$0/fps"', outDir, fps.toFixed(3)]);
                ChecklistService.setChecked(ChecklistService.items[0].id, true);
                notch.close();
            } },
        { wait: 1500, run: () => shot(notch, "notch-pill") },
        { run: () => notch.mode = "peek" },
        { wait: 1500, run: () => shot(notch, "notch-peek") },
        { run: () => notch.open(0) },
        { wait: 1800, run: () => shot(notch, "notch-media") },
        { run: () => notch.open(1) },
        { wait: 1200, run: () => shot(notch, "notch-focus") },
        { run: () => notch.open(2) },
        { wait: 1200, run: () => shot(notch, "notch-checklist") },
        { run: () => settingsLoader.active = true },
        { wait: 2500, run: () => Config.set("glow", 0.9, "Glow strength") },
        { wait: 250, run: () => shot(settingsLoader.item.contentItem.children[0], "settings") },
        { wait: 1500, run: () => Qt.quit() }
    ]
    property real _readyAt: 0

    Timer {
        running: true
        repeat: true
        interval: 100
        onTriggered: {
            const s = root.script[root.step];
            if (!s || root.busy || Date.now() < root._readyAt + (s.wait ?? 0))
                return;
            if (s.when && !s.when())
                return;
            s.run();
            root.step++;
            root._readyAt = Date.now();
        }
    }

}
