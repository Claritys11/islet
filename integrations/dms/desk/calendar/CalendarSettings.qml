import QtQuick
import qs.Common
import qs.Modules.Plugins
import "common"

PluginSettings {
    id: root
    pluginId: "deskwCalendar"

    SelectionSetting {
        settingKey: "weekStart"
        label: "Week starts on"
        options: [
            { label: "Monday", value: "monday" },
            { label: "Sunday", value: "sunday" }
        ]
        defaultValue: "monday"
    }

    StyleSettings {}
}
