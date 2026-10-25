pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "style.mjs" as Style

// The shared look of every deskw widget (solid or glass, its opacity,
// blur, border), from the "deskwStyle" entry in DMS's
// plugin_settings.json — StyleSettings.qml writes it from any widget's
// settings page; the file is watched, so all widgets change at once.
Singleton {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    // DMS 2 keeps its config in ~/.config/dms; older ones in DankMaterialShell.
    property var paths: [root.configHome + "/dms/plugin_settings.json", root.configHome + "/DankMaterialShell/plugin_settings.json"]
    property int pathIndex: 0
    property var style: Style.styleFrom(null)

    readonly property bool glass: root.style.glass
    readonly property real opacity: root.style.opacity
    readonly property bool blur: root.style.glass && root.style.blur
    readonly property bool border: root.style.glass && root.style.border

    // A card colour as the style draws it.
    function fill(c): color {
        return root.glass ? Qt.alpha(c, root.opacity) : c;
    }

    FileView {
        path: root.paths[root.pathIndex]
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.style = Style.styleFrom(JSON.parse(text()));
            } catch (e) {}
        }
        onLoadFailed: {
            if (root.pathIndex + 1 < root.paths.length)
                root.pathIndex++;
        }
    }
}
