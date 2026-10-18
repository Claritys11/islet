pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Data the app produces (not settings): pomodoro history and the local
// checklist. Kept in ~/.local/state/islet/state.json.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("ISLET_STATE_DIR") || `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/islet`
    property alias db: adapter

    Timer {
        id: saveTimer
        interval: 300
        onTriggered: file.writeAdapter()
    }

    // First run: create the folder and bring over data from the old
    // lyrics-wheel location, then load whatever is there.
    property bool _setupDone: false
    Process {
        id: setup
        command: ["sh", "-c", 'mkdir -p "$0" && [ -e "$1/state.json" ] && [ ! -e "$0/state.json" ] && cp -p "$1/state.json" "$0/"; true', root.dir, Quickshell.env("ISLET_STATE_DIR") ? "" : root.dir.replace(/islet$/, "lyrics-wheel")]
        onExited: {
            root._setupDone = true;
            file.reload();
        }
    }

    FileView {
        id: file
        path: `${root.dir}/state.json`
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                return;
            if (root._setupDone)
                writeAdapter();
            else
                setup.running = true;
        }

        JsonAdapter {
            id: adapter

            // Completed focus sessions per day: { "2026-10-18": 3, … }
            property var focusLog: ({})
            // Local checklist: [{ id, text, checked }]
            property var checklist: []
            // LRCLIB version picked by hand per song: { "artist\ntitle": id }
            property var lyricsChoice: ({})
        }
    }
}
