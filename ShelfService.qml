pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// File shelf: drop files on the notch to park them, drag them out later.
// It keeps where the files are (state.json), not copies of them.
Singleton {
    id: root

    readonly property var items: Store.db.shelf ?? []

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
            // Which of them are folders (for the icon).
            kinds.command = ["sh", "-c", 'for p; do [ -d "$p" ] && printf "%s\\n" "$p"; done; true', "sh"].concat(added.map(a => a.path));
            kinds.running = true;
        }
        return added.length;
    }

    Process {
        id: kinds
        stdout: SplitParser {
            onRead: path => {
                Store.db.shelf = root.items.map(i => i.path === path ? Object.assign({}, i, { dir: true }) : i);
            }
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
