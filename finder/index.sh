#!/bin/sh
# Builds Finder's index: every folder, every file and every project (a folder
# holding .git) under the given roots, one absolute path per line.
#   index.sh OUTDIR HIDDEN EXCLUDES ROOT...
# HIDDEN is 0 or 1; EXCLUDES is comma-separated names or globs. Folders and
# files go to separate lists because filtering the folders alone is ~5×
# faster, so they can show first.
set -u
# No wildcard expansion anywhere: * and [..] here are fd patterns.
set -f
out=$1 hidden=$2 excludes=$3
shift 3
command -v fd >/dev/null 2>&1 || exit 127
mkdir -p "$out"

# Only roots that exist: a typo or an unplugged drive must not replace a good
# index with an empty one. None left: fail and keep the old index.
for r; do
    shift
    [ -d "$r" ] && set -- "$@" "$r"
done
[ $# -gt 0 ] || { echo "index.sh: none of the folders to search exist" >&2; exit 2; }

# Options as "$@": the roots, the excludes and the hidden switch. ".git" is
# skipped here and added per search: its insides are never worth finding,
# but finding .git folders is how projects are spotted.
set -- --absolute-path --color never "$@"
[ "$hidden" = 1 ] && set -- -H "$@"
# Split on commas and trim the spaces people type after them.
old_ifs=$IFS
IFS=,
for e in $excludes; do
    e=${e#"${e%%[! ]*}"}
    e=${e%"${e##*[! ]}"}
    [ -n "$e" ] && [ "$e" != .git ] && set -- -E "$e" "$@"
done
IFS=$old_ifs

# NUL-separated so a name with a newline in it can't split into bogus lines;
# such names are dropped. fd ends folders with "/", which goes too.
clean() { awk 'BEGIN { RS = "\0" } !/\n/ { sub(/\/$/, ""); print }'; }

# The pattern "." goes first: everything after it is a root or an option.
# Finding .git means walking hidden folders, which are most of a home's
# folders (caches, toolchains). Unless hidden files are wanted, skip every
# hidden name except .git itself.
skip_hidden=
[ "$hidden" = 1 ] || skip_hidden="-E .[!g]* -E .g[!i]* -E .gi[!t]* -E .git?*"

# fd writes to a file first so its own failure is noticed (in a pipe, only
# the last command's status counts).
fd -0 -t d -E .git . "$@" > "$out/dirs.raw" &&
    fd -0 -t f -E .git . "$@" > "$out/files.raw" &&
    fd -0 -H -t d -g $skip_hidden .git "$@" > "$out/projects.raw" || { rm -f "$out"/*.raw; exit 1; }
clean < "$out/dirs.raw" > "$out/dirs.txt.tmp"
clean < "$out/files.raw" > "$out/files.txt.tmp"
clean < "$out/projects.raw" | sed 's|/\.git$||' > "$out/projects.txt.tmp"
rm -f "$out"/*.raw

for f in dirs files projects; do
    mv "$out/$f.txt.tmp" "$out/$f.txt"
done
