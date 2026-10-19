#!/system/bin/sh
# ==============================================================================
# 运存防线 (RAM Guard) service.sh - 开机自动挂载与自启脚本
# ==============================================================================

MODID="ram"
DEFAULT_MODDIR="/data/adb/modules/$MODID"

case "$0" in
    */*) SCRIPT_DIR="${0%/*}" ;;
    *) SCRIPT_DIR="." ;;
esac
MODDIR="$(cd "$SCRIPT_DIR" 2>/dev/null && pwd -P)"
if [ -z "$MODDIR" ] || [ ! -f "$MODDIR/ram.sh" ]; then
    if [ -d "$DEFAULT_MODDIR" ]; then
        MODDIR="$DEFAULT_MODDIR"
    elif [ -d "/data/adb/modules_update/$MODID" ]; then
        MODDIR="/data/adb/modules_update/$MODID"
    fi
fi

chmod 0755 "$MODDIR/ram.sh" 2>/dev/null
chmod 0755 "$MODDIR/运存防线启动.sh" 2>/dev/null
chmod 0755 "$MODDIR/运存防线关闭.sh" 2>/dev/null
chmod 0755 "$MODDIR/运存防线检测.sh" 2>/dev/null
chmod 0755 "$MODDIR/action.sh" 2>/dev/null

# 启动运存防线
sh "$MODDIR/运存防线启动.sh" >/dev/null 2>&1 &
