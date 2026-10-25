pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// File shelf: drop files on the notch to park them, drag them out later.
// It keeps where the files are (state.json), not copies of them, and
// follows a file that was moved (dragged out with Move, say).
Singleton {
    id: root

    readonly property var items: Store.db.shelf ?? []
    // A tile being dragged out: nothing may catch the drop but its target.
    property bool dragging: false

    // urls: file:// URLs or paths, as a drop or the bar widget gives them.
    function add(urls) {
        const have = new Set(items.map(i => i.path));
        const added = [];
        for (const u of urls) {
            let path = String(u);
            if (path.startsWith("file://"))
                path = decodeURIComponent(path.slice(7));
            if (!path.startsWith("/") || have.has(path))
                continue;
            have.add(path);
            added.push({ path, name: path.replace(/\/+$/, "").split("/").pop() || path, added: Date.now() });
        }
        if (added.length) {
            Store.db.shelf = added.concat(items).slice(0, 60);
            // Which of them are folders (for the icon), and their inodes
            // (to find them again once moved).
            info.command = [locate, "info"].concat(added.map(a => a.path));
            info.running = true;
        }
        return added.length;
    }

    readonly property string locate: decodeURIComponent(String(Qt.resolvedUrl("shelf/locate.sh")).replace(/^file:\/\//, ""))

    // ── Paste ─────────────────────────────────────────────────────
    // Copied files go on the shelf as they are; a copied picture or text is
    // saved here first (it has no file of its own).
    readonly property string pasteDir: `${Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"}/islet/shelf`
    // "" | a word on what the last paste did, for a moment.
    property string pasteNote: ""

    function paste() {
        if (!pasting.running)
            pasting.running = true;
    }
    Process {
        id: pasting
        command: [decodeURIComponent(String(Qt.resolvedUrl("shelf/paste.sh")).replace(/^file:\/\//, "")), root.pasteDir]
        stdout: StdioCollector {
            id: pasted
        }
        onExited: code => {
            const paths = code === 0 ? pasted.text.split("\n").filter(l => l.startsWith("/")) : [];
            const n = paths.length ? root.add(paths) : 0;
            root.pasteNote = code !== 0 ? Lang.t("Nothing to paste — copy a file, picture or text first", "Tidak ada yang bisa ditempel — copy file, gambar atau teks dulu") : n === 0 ? Lang.t("Already on the shelf", "Sudah ada di Shelf") : n === 1 ? Lang.t("Pasted", "Ditempel") : Lang.t(`Pasted ${n} files`, `${n} file ditempel`);
            noteTimer.restart();
        }
    }
    Timer {
        id: noteTimer
        interval: 2500
        onTriggered: root.pasteNote = ""
    }

    Process {
        id: info
        stdout: SplitParser {
            onRead: line => {
                const [path, inode, dir] = line.split("\t");
                Store.db.shelf = root.items.map(i => i.path === path ? Object.assign({}, i, { inode, dir: dir === "1" }) : i);
            }
        }
    }

    // Files that are gone from where they were: look for them (a moment
    // after a drag, so the file manager has finished moving).
    function follow() {
        if (items.length === 0)
            return;
        // Shelved before Islet kept inodes: note them now.
        const older = items.filter(i => !i.inode && !i.missing);
        if (older.length && !info.running) {
            info.command = [locate, "info"].concat(older.map(i => i.path));
            info.running = true;
        }
        if (finder.running)
            return followTimer.restart();
        finder.command = [locate, "find", Quickshell.env("HOME")].concat(...items.map(i => [i.path, i.inode ?? ""]));
        finder.running = true;
    }
    function followSoon() {
        followTimer.restart();
    }
    Timer {
        id: followTimer
        interval: 1500
        onTriggered: root.follow()
    }

    Process {
        id: finder
        property var gone: ({})
        onStarted: gone = {}
        stdout: SplitParser {
            onRead: line => {
                const [path, now] = line.split("\t");
                finder.gone[path] = true;
                Store.db.shelf = root.items.map(i => i.path !== path ? i : now ? Object.assign({}, i, { path: now, name: now.split("/").pop(), missing: false }) : Object.assign({}, i, { missing: true }));
            }
        }
        // One that's back where it was is no longer missing.
        onExited: {
            if (root.items.some(i => i.missing && !gone[i.path]))
                Store.db.shelf = root.items.map(i => i.missing && !gone[i.path] ? Object.assign({}, i, { missing: false }) : i);
        }
    }

    function remove(path) {
        Store.db.shelf = items.filter(i => i.path !== path);
    }

    function clear() {
        Store.db.shelf = [];
    }

    function url(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    // A Material Symbols icon for the kind of file.
    function icon(item) {
        if (item.dir)
            return "folder";
        const ext = (item.name.match(/\.([^.]+)$/)?.[1] ?? "").toLowerCase();
        if (["png", "jpg", "jpeg", "gif", "webp", "avif", "bmp", "svg", "heic"].includes(ext))
            return "image";
        if (["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"].includes(ext))
            return "audio_file";
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(ext))
            return "video_file";
        if (ext === "pdf")
            return "picture_as_pdf";
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar"].includes(ext))
            return "folder_zip";
        if (["js", "ts", "py", "qml", "rs", "go", "c", "cpp", "h", "java", "sh", "json", "html", "css"].includes(ext))
            return "code";
        return "description";
    }

    function isImage(name) {
        return /\.(png|jpe?g|gif|webp|bmp|avif)$/i.test(name);
    }
}
