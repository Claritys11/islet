pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Data the app produces (not settings): pomodoro history and the local
// checklist. Kept in ~/.local/state/lyrics-wheel/state.json.
Singleton {
    id: root

    readonly property string dir: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/lyrics-wheel`
    property alias db: adapter

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: file.writeAdapter()
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        onExited: file.writeAdapter()
    }

    FileView {
        id: file
        path: `${root.dir}/state.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                mkdir.running = true;
        }

        JsonAdapter {
            id: adapter

            // Completed focus sessions per day: { "2026-10-18": 3, … }
            property var focusLog: ({})
            // Local checklist: [{ id, text, checked }]
            property var checklist: []
        }
    }
}
