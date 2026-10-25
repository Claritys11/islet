import QtQuick
import qs.Common
import qs.Modules.Plugins
import "common"

PluginSettings {
    id: root
    pluginId: "deskwGithub"

    StringSetting {
        settingKey: "githubUser"
        label: "GitHub user"
        placeholder: "your-github-name"
        defaultValue: ""
    }

    StyleSettings {}
}
