import QtQuick
import qs.Common
import qs.Modules.Plugins
import "common"

PluginSettings {
    id: root
    pluginId: "deskwNotes"

    StringSetting {
        settingKey: "tipe"
        label: "Only notes of this Tipe (empty = all)"
        placeholder: "e.g. Materi / Cheatsheet"
        defaultValue: ""
    }

    SliderSetting {
        settingKey: "limit"
        label: "How many notes"
        defaultValue: 30
        minimum: 10
        maximum: 50
        unit: ""
    }

    StyleSettings {}
}
