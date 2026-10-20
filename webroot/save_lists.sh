#!/system/bin/sh
MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/ram"

TARGET_FILE="$1"
B64_DATA="$2"

if [ -n "$TARGET_FILE" ] && [ -n "$B64_DATA" ]; then
    DEST="$MODDIR/$TARGET_FILE"
    echo "$B64_DATA" | base64 -d > "$DEST.tmp" 2>/dev/null
    if [ -f "$DEST.tmp" ]; then
        mv -f "$DEST.tmp" "$DEST"
        chmod 0644 "$DEST"
        echo "OK"
        exit 0
    fi
fi
echo "FAIL"
exit 1
