#!/system/bin/sh
# ==============================================================================
# 运存防线 (RAM Guard) 关闭脚本 - 全环境兼容版 (Magisk / KernelSU / APatch)
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
PID_FILE="$MODDIR/ram.pid"
LOG="$MODDIR/ram.log"

# 三重定位查杀 PID：PID 文件 + pidof + pgrep
ALL_PIDS=""
[ -f "$PID_FILE" ] && ALL_PIDS="$(cat "$PID_FILE" 2>/dev/null)"
ALL_PIDS="$ALL_PIDS $(pidof ram.sh 2>/dev/null) $(pgrep -f "ram.sh" 2>/dev/null)"

KILL_PIDS=$(echo "$ALL_PIDS" | tr ' ' '\n' | sort -u | grep -E '^[0-9]+$')

if [ -n "$KILL_PIDS" ]; then
    for p in $KILL_PIDS; do
        [ "$p" != "$$" ] && kill "$p" 2>/dev/null
    done
    sleep 1
    # 二次检查
    for p in $KILL_PIDS; do
        [ -d "/proc/$p" ] && [ "$p" != "$$" ] && kill -9 "$p" 2>/dev/null
    done
    rm -f "$PID_FILE" 2>/dev/null

    echo "=========================================="
    echo " 运存防线已成功关闭"
    echo "=========================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 运存防线已关闭" >> "$LOG" 2>/dev/null
else
    rm -f "$PID_FILE" 2>/dev/null
    echo "=========================================="
    echo " 运存防线当前未运行"
    echo "=========================================="
fi

# 关闭状态栏常驻通知 (优先原生 cmd notification，兼容 KernelSU 无需依赖 su 2000)
hide_notification() {
    cmd notification list 2>/dev/null | awk '/RAMGuard/ {print $1}' | while read -r k; do
        [ -n "$k" ] && cmd notification snooze --for 315360000000 "$k" >/dev/null 2>&1
    done
    cmd notification snooze --for 315360000000 "0|com.android.shell|2020|RAMGuard|2000" >/dev/null 2>&1 || true
    su 2000 -c "cmd notification list 2>/dev/null | awk '/RAMGuard/ {print \$1}' | while read k; do [ -n \"\$k\" ] && cmd notification snooze --for 315360000000 \"\$k\" >/dev/null 2>&1; done" >/dev/null 2>&1 || true
}
hide_notification 2>/dev/null || true
