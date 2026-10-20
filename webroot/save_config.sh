#!/system/bin/sh
MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/ram"
CONFIG="$MODDIR/config.ini"

# 如果传入了 base64 文本
if [ -n "$1" ]; then
    echo "$1" | base64 -d > "$CONFIG.tmp" 2>/dev/null
    if [ -s "$CONFIG.tmp" ]; then
        mv -f "$CONFIG.tmp" "$CONFIG"
        chmod 0644 "$CONFIG"
        echo "OK"
        exit 0
    fi
fi
echo "FAIL"
exit 1
