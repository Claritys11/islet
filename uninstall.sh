#!/bin/sh
# Remove Islet's links. Settings (~/.config/islet) and data (~/.local/state/islet) are kept.
config="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
systemctl --user disable --now islet.service 2>/dev/null
qs kill -c islet >/dev/null 2>&1
for f in "$config/quickshell/islet" "$HOME/.local/bin/islet" \
    "$config/systemd/user/islet.service" "$data/applications/islet-settings.desktop"; do
    [ -L "$f" ] && rm "$f" && echo "  removed $f"
done
systemctl --user daemon-reload
echo "Uninstalled. Settings kept in $config/islet (delete it to reset)."
