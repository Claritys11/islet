#!/bin/sh
# Install lyrics-wheel for the current user.
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

echo "Installing lyrics-wheel from $src"
link "$src" "$config/quickshell/lyrics-wheel"
link "$src/bin/lyrics-wheel" "$bindir/lyrics-wheel"
link "$src/dist/lyrics-wheel.service" "$config/systemd/user/lyrics-wheel.service"
link "$src/dist/lyrics-wheel-settings.desktop" "$data/applications/lyrics-wheel-settings.desktop"
systemctl --user daemon-reload

if [ "$1" = "--enable" ]; then
    systemctl --user enable --now lyrics-wheel.service
    echo "Enabled: lyrics-wheel starts with your session."
else
    echo
    echo "Start now and on every login:   systemctl --user enable --now lyrics-wheel"
fi

case ":$PATH:" in
    *":$bindir:"*) ;;
    *) echo "note: $bindir is not in your PATH" ;;
esac
echo "Open settings:   lyrics-wheel settings   (or 'Lyrics Wheel Settings' in your launcher)"
