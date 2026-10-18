#!/bin/sh
# Install Islet for the current user.
#   ./install.sh           link files, install service + launcher entry
#   ./install.sh --enable  …and start it now and on every login
set -e
src="$(cd "$(dirname "$0")" && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
bindir="$HOME/.local/bin"

command -v qs >/dev/null || { echo "error: quickshell (qs) is not installed — pacman -S quickshell" >&2; exit 1; }

link() {
    if [ -e "$2" ] && [ ! -L "$2" ]; then
        echo "error: $2 exists and is not a symlink, refusing to overwrite" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
    echo "  linked $2"
}

# Islet used to be called lyrics-wheel: retire the old install. Settings are
# carried over automatically on first start.
was_enabled=false
if systemctl --user is-enabled lyrics-wheel.service >/dev/null 2>&1; then
    was_enabled=true
fi
systemctl --user disable --now lyrics-wheel.service >/dev/null 2>&1 || true
qs kill -c lyrics-wheel >/dev/null 2>&1 || true
for old in "$config/quickshell/lyrics-wheel" "$bindir/lyrics-wheel" \
    "$config/systemd/user/lyrics-wheel.service" "$data/applications/lyrics-wheel-settings.desktop"; do
    [ -L "$old" ] && rm "$old" && echo "  removed old $old"
done

echo "Installing Islet from $src"
link "$src" "$config/quickshell/islet"
link "$src/bin/islet" "$bindir/islet"
link "$src/dist/islet.service" "$config/systemd/user/islet.service"
link "$src/dist/islet-settings.desktop" "$data/applications/islet-settings.desktop"
systemctl --user daemon-reload

if [ "$1" = "--enable" ] || $was_enabled; then
    systemctl --user enable --now islet.service
    echo "Enabled: Islet starts with your session."
else
    echo
    echo "Start now and on every login:   systemctl --user enable --now islet"
fi

case ":$PATH:" in
    *":$bindir:"*) ;;
    *) echo "note: $bindir is not in your PATH" ;;
esac
echo "Open settings:   islet settings   (or 'Islet Settings' in your launcher)"
