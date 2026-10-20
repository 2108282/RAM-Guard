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

        # 同步更新对应的英文名称文件，保证所有脚本和 C++ 都能 100% 读到完全一致的规则
        case "$TARGET_FILE" in
            *白名单.conf*|*whitelist.conf*)
                cp -f "$DEST" "$MODDIR/白名单.conf" 2>/dev/null || true
                cp -f "$DEST" "$MODDIR/whitelist.conf" 2>/dev/null || true
                chmod 0644 "$MODDIR/白名单.conf" "$MODDIR/whitelist.conf" 2>/dev/null || true
                ;;
            *黑名单.conf*|*blacklist.conf*)
                cp -f "$DEST" "$MODDIR/黑名单.conf" 2>/dev/null || true
                cp -f "$DEST" "$MODDIR/blacklist.conf" 2>/dev/null || true
                chmod 0644 "$MODDIR/黑名单.conf" "$MODDIR/blacklist.conf" 2>/dev/null || true
                ;;
        esac

        echo "OK"
        exit 0
    fi
fi
echo "FAIL"
exit 1
