#!/bin/sh
# Loads the DMS desktop widgets' common code (integrations/dms/desk/common) outside DMS. Pass: prints the connection line, no QML errors.
dir=$(cd "$(dirname "$0")" && pwd)
out=$(timeout 15 qs -p "$dir/desk-load/shell.qml" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
echo "$out" | grep -E "ERROR|ReferenceError|TypeError|is not a type|not installed" && { echo "load: FAIL"; exit 1; }
echo "$out" | grep -o "deskw-load connected=[a-z]* hasState=[a-z]*" || { echo "load: FAIL (no report)"; exit 1; }
echo "$out" | grep -q "deskw-load m1=ok" || { echo "$out" | grep -o "deskw-load m1=[a-z-]*"; echo "load: FAIL (M1)"; exit 1; }
echo "$out" | grep -q "deskw-load formatbar=ok" || { echo "$out" | grep -o "deskw-load formatbar=.*"; echo "load: FAIL (FormatBar)"; exit 1; }
echo "load: ok"
