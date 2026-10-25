import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// "Look of all deskw widgets", on every deskw widget's settings page. The
// settings inside find this Column as their store (DMS looks up the
// nearest parent with loadValue/saveValue), so they save under the shared
// "deskwStyle" id instead of the page's own plugin; DeskStyle reads it.
Column {
    id: root

    readonly property var pluginService: PluginService

    function loadValue(key, defaultValue) {
        return PluginService.loadPluginData("deskwStyle", key, defaultValue);
    }

    function saveValue(key, value) {
        PluginService.savePluginData("deskwStyle", key, value);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingM

    StyledText {
        width: parent.width
        topPadding: Theme.spacingM
        text: "Tampilan semua widget deskw"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "style"
        label: "Gaya kartu"
        description: "Glass: tembus pandang dengan blur di belakangnya, seperti end4"
        options: [
            { label: "Solid", value: "solid" },
            { label: "Glass", value: "glass" }
        ]
        defaultValue: "solid"
    }

    SliderSetting {
        settingKey: "opacity"
        label: "Kepekatan kaca"
        defaultValue: 55
        minimum: 10
        maximum: 100
        unit: "%"
    }

    ToggleSetting {
        settingKey: "blur"
        label: "Blur di belakang kaca"
        description: "Butuh compositor dengan background blur (niri, KDE, Hyprland)"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "border"
        label: "Garis tepi tipis"
        defaultValue: true
    }

    StyleSettings {}
}
