#!/system/bin/sh
MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/ram"

WHITE="$MODDIR/whitelist.conf"
[ -f "$WHITE" ] || WHITE="$MODDIR/白名单.conf"
BLACK="$MODDIR/blacklist.conf"
[ -f "$BLACK" ] || BLACK="$MODDIR/黑名单.conf"
CONFIG="$MODDIR/config.ini"
LOG="$MODDIR/ram.log"

MAX_CLEAN=5
if [ -f "$CONFIG" ]; then
    mc=$(grep -E "^max_clean_count[[:space:]]*=" "$CONFIG" 2>/dev/null | cut -d= -f2 | awk '{$1=$1;print}')
    [ -n "$mc" ] && [ "$mc" -gt 0 ] 2>/dev/null && MAX_CLEAN=$mc
fi

before_ma=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
before_mt=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
before_pct=$((before_ma * 100 / before_mt))

# 提取预计清理的名单并执行 force-stop
cleaned=0
clean_list=$(sh "$MODDIR/webroot/scan.sh" 2>/dev/null | grep "|预计清理|" | head -n "$MAX_CLEAN")

if [ -z "$clean_list" ]; then
    echo "未发现需要清理的后台应用"
    exit 0
fi

echo "$clean_list" | while IFS='|' read -r uid pkg st ram swap; do
    [ -n "$pkg" ] || continue
    # 多用户隔离查杀
    am force-stop --user "$uid" "$pkg" >/dev/null 2>&1 || su 2000 -c "am force-stop --user $uid '$pkg'" >/dev/null 2>&1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CLEAN] 已清理(手动触发)：[u${uid}] ${pkg}" >> "$LOG" 2>/dev/null
done

after_ma=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
after_pct=$((after_ma * 100 / before_mt))
freed_kb=$((after_ma - before_ma))
[ "$freed_kb" -lt 0 ] && freed_kb=0
freed_mb=$((freed_kb / 1024))

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] 手动清理完成：可用内存 ${before_pct}% → ${after_pct}%，释放约 ${freed_mb}MB" >> "$LOG" 2>/dev/null

# 刷新状态栏通知
if grep -Eq "^enable_status_notification[[:space:]]*=[[:space:]]*true" "$CONFIG" 2>/dev/null; then
    su 2000 -c "cmd notification post -t '运存防线' RAMGuard '已手动清理 ｜ 释放 ${freed_mb}MB ｜ 内存 ${after_pct}%'" >/dev/null 2>&1 || \
    cmd notification post -t '运存防线' RAMGuard "已手动清理 ｜ 释放 ${freed_mb}MB ｜ 内存 ${after_pct}%" >/dev/null 2>&1 || true
fi

echo "清理完成，释放内存约 ${freed_mb}MB"
