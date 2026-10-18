# Installing Islet — instructions for AI agents

You are helping a user install **Islet** (lyrics overlay, dynamic-island notch, Pomodoro and checklist
for Linux, built on Quickshell). Follow these steps in order, run the checks, and report what you did.
Ask before editing the user's compositor config.

## 1. Check the system

```sh
echo "$XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP"   # need: wayland
command -v qs && qs --version                   # need: Quickshell 0.2 or newer
```

- **Wayland with wlr-layer-shell is required.** Supported: niri, Hyprland, Sway, river, KDE Plasma,
  Wayfire, labwc. **Not supported:** GNOME (no layer-shell), X11 sessions, Windows, macOS — stop and
  tell the user.
- If `qs` is missing, install Quickshell:
  - Arch / CachyOS / EndeavourOS / Manjaro: `sudo pacman -S quickshell`
  - Fedora: `sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell`
  - NixOS: add `pkgs.quickshell` to the configuration
  - Others: see https://quickshell.org
- Optional: `cava` (real audio visualizer in the notch).

## 2. Install

```sh
curl -fsSL https://raw.githubusercontent.com/Claritys11/islet/main/install.sh | sh
```

This clones Islet to `~/.local/share/islet`, links it into `~/.config/quickshell/islet`, installs
the `islet` command to `~/.local/bin`, the icon font if missing, a launcher entry, and enables the
`islet.service` systemd user service. It never uses sudo.

If the user prefers a manual clone: `git clone https://github.com/Claritys11/islet && ./islet/install.sh --enable`.

## 3. Verify

```sh
systemctl --user is-active islet        # → active
islet status                            # → "<status> · <artist> — <title>" or "idle"
journalctl --user -u islet -n 30        # look for lines containing ERROR
```

`~/.local/bin` must be on `PATH` for the `islet` command. If `islet status` prints `idle`, nothing is
playing — that's fine.

## 4. Optional: keybinds (ask first)

**niri** (`~/.config/niri/config.kdl`) — add inside the existing `binds { }` block, and add the
window rule at top level. Check for conflicting keys first (`grep -n "Mod+N" config.kdl`).

```kdl
Mod+Shift+L { spawn "islet" "toggle"; }
Mod+Ctrl+L  { spawn "islet" "settings"; }
Mod+N       { spawn "islet" "notch"; }

window-rule {
    match title="^Islet Settings$"
    open-floating true
}
```

Validate with `niri validate`. **Hyprland** (`hyprland.conf`):

```
bind = SUPER SHIFT, L, exec, islet toggle
bind = SUPER, N, exec, islet notch
windowrulev2 = float, title:^(Islet Settings)$
```

**Sway**: `bindsym $mod+Shift+l exec islet toggle` and `for_window [title="^Islet Settings$"] floating enable`.

## 5. Optional: Spicy Lyrics timing (Spotify + Spicetify users)

If `command -v spicetify` succeeds, ask whether the user uses Spicy Lyrics. If so, and they agree to a
Spotify restart:

```sh
islet spicetify            # copies the extension, runs `spicetify apply`
islet spicetify status     # → "extension: installed", and a status line containing "Spicy Lyrics"
```

If `spicetify apply` reports *"Preprocessed Spotify data is outdated"*, run
`spicetify restore backup apply` (Spicetify's standard fix after a Spotify update). Play a song and check
`islet status` mentions "Spicy Lyrics" (songs Spicy Lyrics lacks use LRCLIB).

## 6. Optional: DankMaterialShell bar

If the user runs DankMaterialShell (`command -v dms`) and would rather have Islet in the bar than as a
floating notch, run `islet dms` (it replaces DMS's media widget; a backup of DMS's settings is kept) and
check `islet dms status` shows the plugin as `loaded`. If DMS reports the plugin failed to load after an
Islet update, `systemctl --user restart dms` clears DMS's QML cache.

## 7. Optional: configure

Prefer the GUI (`islet settings`). For scripted changes use `islet set <key> <value>`; every key and its default
is in the `defaults` block of `Config.qml`. Don't hand-edit `~/.config/islet/config.json` while Islet is
running unless you write valid JSON — it reloads on save.

Notion checklist: the user must create an integration and share a page with it themselves (see README).
Never ask the user to paste their Notion secret into the chat; have them paste it into
*Settings → Checklist*.

## Uninstall

```sh
~/.local/share/islet/uninstall.sh   # or ./uninstall.sh from the clone
```
