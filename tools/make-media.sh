#!/bin/sh
# Render the README screenshots and demo GIF into docs/media/.
# Uses a throwaway config so your own settings and tasks are never touched.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/docs/media"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$out" "$work/frames" "$work/config" "$work/state"

echo "Rendering… (about 40 seconds)"
ISLET_SHOWCASE="$work" ISLET_CONFIG_DIR="$work/config" ISLET_STATE_DIR="$work/state" \
    timeout 120 qs -p "$root" >/dev/null 2>&1 || true

cp "$work/hero.png" "$out/hero.png"
magick "$work/settings.png" -resize 1100x "$out/settings.png"
# Trim the transparent margin around the notch captures.
for f in notch-pill notch-peek notch-media notch-focus notch-checklist; do
    magick "$work/$f.png" -trim +repage -bordercolor none -border 24 "$out/$f.png"
done

# GIF: 960 px wide, optimised palette, played at the rate frames were captured.
fps="$(cat "$work/fps" 2>/dev/null || echo 12)"
echo "frames captured at $fps fps"
ffmpeg -loglevel error -y -framerate "$fps" -i "$work/frames/%04d.png" \
    -vf "scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
    "$out/demo.gif"
ffmpeg -loglevel error -y -framerate "$fps" -i "$work/frames/%04d.png" \
    -c:v libx264 -pix_fmt yuv420p -crf 22 -movflags +faststart "$out/demo.mp4"
ls -la "$out"
