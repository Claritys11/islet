import QtQuick
import qs.Common
import qs.Modules.Plugins
import "common"

PluginSettings {
    id: root
    pluginId: "deskwClock"

    ToggleSetting {
        settingKey: "showSeconds"
        label: "Show seconds"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showDate"
        label: "Show date"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "sides"
        label: "Cookie waves"
        defaultValue: 9
        minimum: 6
        maximum: 14
        unit: ""
    }

    StyleSettings {}
}
