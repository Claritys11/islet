#!/bin/sh
# Remove lyrics-wheel links. Your settings in ~/.config/lyrics-wheel are kept.
config="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
systemctl --user disable --now lyrics-wheel.service 2>/dev/null
qs kill -c lyrics-wheel >/dev/null 2>&1
for f in "$config/quickshell/lyrics-wheel" "$HOME/.local/bin/lyrics-wheel" \
    "$config/systemd/user/lyrics-wheel.service" "$data/applications/lyrics-wheel-settings.desktop"; do
    [ -L "$f" ] && rm "$f" && echo "  removed $f"
done
systemctl --user daemon-reload
echo "Uninstalled. Settings kept in $config/lyrics-wheel (delete it to reset)."
