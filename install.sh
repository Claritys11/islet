#!/bin/sh
# Install Islet for the current user.
#
#   curl -fsSL https://raw.githubusercontent.com/Claritys11/islet/main/install.sh | sh
#   ./install.sh            from a clone: link files, service and launcher entry
#   ./install.sh --enable   …and start Islet now and on every login
#   ./install.sh --no-enable
set -e

repo="https://github.com/Claritys11/islet.git"
config="${XDG_CONFIG_HOME:-$HOME/.config}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
bindir="$HOME/.local/bin"

say() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ── Bootstrap: piped from curl, there are no files next to us yet ──
src="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [ ! -f "$src/shell.qml" ]; then
    command -v git >/dev/null || die "git is needed to download Islet"
    dest="$data/islet"
    if [ -d "$dest/.git" ]; then
        say "Updating $dest"
        git -C "$dest" pull --ff-only --quiet
    else
        say "Downloading Islet to $dest"
        git clone --quiet --depth 1 "$repo" "$dest"
    fi
    # Piped installs enable the service unless told otherwise.
    [ $# -eq 0 ] && set -- --enable
    exec sh "$dest/install.sh" "$@"
fi

# ── Requirements ──────────────────────────────────────────────────
if ! command -v qs >/dev/null; then
    hint="see https://quickshell.org"
    if command -v pacman >/dev/null; then hint="sudo pacman -S quickshell"
    elif command -v nix-env >/dev/null; then hint="add pkgs.quickshell to your configuration"
    elif command -v dnf >/dev/null; then hint="sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell"
    fi
    die "Quickshell is required: $hint"
fi
[ -n "$WAYLAND_DISPLAY" ] || warn "No Wayland session detected — Islet needs a Wayland compositor with layer-shell (niri, Hyprland, Sway, KDE Plasma, river…)."
case "${XDG_CURRENT_DESKTOP:-}" in
    *GNOME*) warn "GNOME doesn't support layer-shell, so Islet can't show its windows there." ;;
esac

# Icons use Material Symbols Rounded (DankMaterialShell already ships it).
if ! fc-list 2>/dev/null | grep -q "Material Symbols Rounded"; then
    say "Installing the Material Symbols Rounded icon font"
    mkdir -p "$data/fonts"
    curl -fsSL -o "$data/fonts/MaterialSymbolsRounded.ttf" \
        "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf" &&
        fc-cache -f "$data/fonts" >/dev/null 2>&1 ||
        warn "Couldn't download the icon font; icons may show as text."
fi
command -v cava >/dev/null || say "Tip: install 'cava' for a real audio visualizer in the notch."
command -v spicetify >/dev/null && say "Using Spicy Lyrics? Run 'islet spicetify' for its syllable-exact lyrics and timing in Islet."

link() {
    if [ -e "$2" ] && [ ! -L "$2" ]; then
        die "$2 exists and is not a symlink, refusing to overwrite"
    fi
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
    echo "   linked $2"
}

# ── Retire lyrics-wheel (Islet's old name); settings migrate on first start ──
was_enabled=false
if systemctl --user is-enabled lyrics-wheel.service >/dev/null 2>&1; then
    was_enabled=true
fi
systemctl --user disable --now lyrics-wheel.service >/dev/null 2>&1 || true
qs kill -c lyrics-wheel >/dev/null 2>&1 || true
for old in "$config/quickshell/lyrics-wheel" "$bindir/lyrics-wheel" \
    "$config/systemd/user/lyrics-wheel.service" "$data/applications/lyrics-wheel-settings.desktop"; do
    [ -L "$old" ] && rm "$old" && echo "   removed old $old"
done

# ── Install ───────────────────────────────────────────────────────
say "Installing Islet from $src"
link "$src" "$config/quickshell/islet"
link "$src/bin/islet" "$bindir/islet"
link "$src/dist/islet.service" "$config/systemd/user/islet.service"
link "$src/dist/islet-settings.desktop" "$data/applications/islet-settings.desktop"
systemctl --user daemon-reload 2>/dev/null || true

if { [ "$1" = "--enable" ] || $was_enabled; } && [ "$1" != "--no-enable" ]; then
    if systemctl --user enable --now islet.service 2>/dev/null; then
        say "Islet is running and starts with your session."
    else
        warn "Couldn't enable the systemd service; start Islet with: islet start"
    fi
else
    echo
    say "Start now and on every login:  systemctl --user enable --now islet"
fi

case ":$PATH:" in
    *":$bindir:"*) ;;
    *) warn "$bindir is not in your PATH — add it to use the 'islet' command." ;;
esac
say "Open settings:  islet settings   (or 'Islet Settings' in your launcher)"
