#!/system/bin/sh
MODID="ram"
MODDIR="${0%/*}"
case "$MODDIR" in ""|"sh"|"."|"/") MODDIR="/data/adb/modules/$MODID" ;; esac
[ -f "$MODDIR/module_common.sh" ] && . "$MODDIR/module_common.sh" && MODDIR="$(get_moddir)"

BIN="$MODDIR/ram.sh"
LOG="$MODDIR/ram.log"
PIDS="$(pgrep -f "$BIN" 2>/dev/null)"
if [ -n "$PIDS" ]; then
    echo "$PIDS" | while read -r p; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
    done
    echo "运存防线已请求关闭"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 运存防线已请求关闭" >> "$LOG" 2>/dev/null
else
    echo "运存防线未运行"
fi
# 关闭状态栏通知，避免进程被强制结束后留下旧通知
hide_notification() {
    su 2000 -c "cmd notification list 2>/dev/null | awk '/RAMGuard/ {print \$1}' | while read k; do [ -n \"\$k\" ] && cmd notification snooze --for 315360000000 \"\$k\" >/dev/null 2>&1; done" >/dev/null 2>&1 || \
    cmd notification list 2>/dev/null | awk '/RAMGuard/ {print $1}' | while read k; do [ -n "$k" ] && cmd notification snooze --for 315360000000 "$k" >/dev/null 2>&1; done
}
hide_notification
