#!/bin/sh
# Builds Finder's index: every folder, every file and every project (a folder
# holding .git) under the given roots, one absolute path per line.
#   index.sh OUTDIR HIDDEN EXCLUDES ROOT...
# HIDDEN is 0 or 1; EXCLUDES is comma-separated names or globs. Folders and
# files go to separate lists because filtering the folders alone is ~5×
# faster, so they can show first.
set -u
out=$1 hidden=$2 excludes=$3
shift 3
command -v fd >/dev/null 2>&1 || exit 127
mkdir -p "$out"

# Options as "$@": the roots, the excludes and the hidden switch. ".git" is
# skipped here and added per search: its insides are never worth finding,
# but finding .git folders is how projects are spotted.
set -- --absolute-path --color never "$@"
[ "$hidden" = 1 ] && set -- -H "$@"
old_ifs=$IFS
IFS=,
for e in $excludes; do
    [ -n "$e" ] && [ "$e" != .git ] && set -- -E "$e" "$@"
done
IFS=$old_ifs

# NUL-separated so a name with a newline in it can't split into bogus lines;
# such names are dropped. fd ends folders with "/", which goes too.
clean() { awk 'BEGIN { RS = "\0" } !/\n/ { sub(/\/$/, ""); print }'; }

# The pattern "." goes first: everything after it is a root or an option.
fd -0 -t d -E .git . "$@" | clean > "$out/dirs.txt.tmp" &&
    fd -0 -t f -E .git . "$@" | clean > "$out/files.txt.tmp" &&
    fd -0 -H -t d -g .git "$@" | clean | sed 's|/\.git$||' > "$out/projects.txt.tmp" || exit 1

for f in dirs files projects; do
    mv "$out/$f.txt.tmp" "$out/$f.txt"
done
