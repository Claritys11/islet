pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Colours for the notch. Follows DankMaterialShell's Matugen palette when it
// exists (so it changes with your wallpaper), with neutral fallbacks otherwise.
Singleton {
    id: root

    property var _palette: ({})
    readonly property bool hasDms: Object.keys(_palette).length > 0
    readonly property bool black: Config.opts.notchStyle === "black"

    function pick(key, fallback) {
        return _palette[key] ?? fallback;
    }

    readonly property color primary: pick("primary", "#a8c7fa")
    readonly property color onPrimary: pick("on_primary", "#062e6f")
    readonly property color text: pick("on_surface", "#e3e3e8")
    readonly property color subtext: pick("on_surface_variant", "#c4c6cf")
    readonly property color outline: pick("outline_variant", "#44474e")
    readonly property color surface: black ? "#000000" : pick("surface_container_lowest", "#0b0e13")
    readonly property color raised: black ? "#161616" : pick("surface_container_high", "#1d2024")
    readonly property color danger: pick("error", "#ffb4ab")
    readonly property color focus: pick("tertiary", "#ffb3c6")

    readonly property string iconFont: "Material Symbols Rounded"
    readonly property string font: Config.opts.fontFamily

    FileView {
        path: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/DankMaterialShell/dms-colors.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root._palette = data.colors?.[data.mode ?? "dark"] ?? {};
            } catch (e) {
                root._palette = {};
            }
        }
    }
}
