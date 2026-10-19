#!/system/bin/sh
# ==============================================================================
# 运存防线 (RAM Guard) 关闭脚本 - 路径与状态自适应增强版
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

BIN="$MODDIR/ram.sh"
LOG="$MODDIR/ram.log"

PIDS="$(pgrep -f "$BIN" 2>/dev/null || pgrep -f "/data/adb/modules/ram/ram.sh" 2>/dev/null)"
if [ -n "$PIDS" ]; then
    for p in $PIDS; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
    done
    sleep 1
    # 二次检查
    STILL_PIDS="$(pgrep -f "$BIN" 2>/dev/null || pgrep -f "/data/adb/modules/ram/ram.sh" 2>/dev/null)"
    if [ -n "$STILL_PIDS" ]; then
        for p in $STILL_PIDS; do
            [ -n "$p" ] && kill -9 "$p" 2>/dev/null
        done
    fi
    echo "=========================================="
    echo " 运存防线已成功关闭"
    echo "=========================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 运存防线已关闭" >> "$LOG" 2>/dev/null
else
    echo "=========================================="
    echo " 运存防线当前未运行"
    echo "=========================================="
fi

# 关闭状态栏常驻通知，避免进程退出后残留
hide_notification() {
    su 2000 -c "cmd notification list 2>/dev/null | awk '/RAMGuard/ {print \$1}' | while read k; do [ -n \"\$k\" ] && cmd notification snooze --for 315360000000 \"\$k\" >/dev/null 2>&1; done" >/dev/null 2>&1 || \
    cmd notification list 2>/dev/null | awk '/RAMGuard/ {print $1}' | while read k; do [ -n "$k" ] && cmd notification snooze --for 315360000000 "$k" >/dev/null 2>&1; done
}
hide_notification 2>/dev/null || true
