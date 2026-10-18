# Changelog

## 1.1.1 — 2026-10-18

### Fixed
- Lyrics now **scroll** from line to line on a smooth spring instead of blinking: the wheel position was
  bound to the current line, so it jumped instantly and the animation never ran
- Rows could overlap (wrapped lines, background vocals) after the lyrics were reloaded: row heights are
  now read from the rows themselves instead of reports that could be lost
- Lyrics re-sent by the Spicy Lyrics bridge no longer rebuild every line (a visible flash every 15 s)
- The active line's font weight blends in instead of snapping, and the glow layer is prepared before a
  line becomes active

## 1.1.0 — 2026-10-18

### Added
- **Spicy Lyrics integration**: `islet spicetify` installs the Islet Bridge Spicetify extension, which
  shares the syllable-synced lyrics Spicy Lyrics already loaded and Spotify's own playback position with
  Islet over localhost. The karaoke fill follows every syllable, background vocals included.
- *Lyrics from* setting (Spicy Lyrics with LRCLIB fallback, or LRCLIB only) with a live connection status,
  and a separate timing offset for Spicy Lyrics (+100 ms, like Spicy Lyrics itself)

### Changed
- The playback clock uses Spicy Lyrics' smoothing: real jumps snap, small jitter is pulled in with a
  300 ms time constant, so lyrics never stutter or drift

## 1.0.0 — 2026-10-18

First release as **Islet** (previously *lyrics-wheel*).

### Added
- **Notch**: a dynamic island with live-activity pill, hover peek, and Media / Focus / Checklist tabs
- **Focus**: Pomodoro timer with auto-advancing breaks, notifications and a daily count
- **Checklist**: local tasks, or synced with the to-dos of a Notion page
- **Settings window** with per-module pages, change markers, one-click resets, an on-screen toast for
  every change, live notch preview and sample lyrics
- Lyrics: balanced line wrapping, background vocals with their own timing, visible-area controls with
  soft edges, LRCLIB version picker
- Karaoke fill follows each song's own singing pace (measured from the lyric timestamps), with a
  *Fill speed* adjustment
- One-line installer, `islet` CLI (`settings`, `set`, `get`, `notch`, `pomodoro`, `todo`, `update`…),
  systemd user service, launcher entry, Arch PKGBUILD, instructions for AI agents

### Fixed
- Lyrics drifting ahead of the song: the fill used a fixed pace that was too fast for most songs
- Picking the wrong LRCLIB version (different recording or broken upload) when the track length
  wasn't known yet
- Pill lyrics in the notch are cut off and follow the singer instead of ending in "…"

## 0.1.0

Initial release as *lyrics-wheel*: OptionWheel-style synced lyrics with karaoke glow.
