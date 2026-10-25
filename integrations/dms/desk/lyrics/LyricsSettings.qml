import QtQuick
import qs.Common
import qs.Modules.Plugins
import "common"

PluginSettings {
    id: root
    pluginId: "deskwLyrics"

    SliderSetting {
        settingKey: "lines"
        label: "Lyric lines"
        defaultValue: 7
        minimum: 3
        maximum: 7
        unit: ""
    }

    ToggleSetting {
        settingKey: "showControls"
        label: "Show play controls"
        defaultValue: true
    }

    StyleSettings {}
}
