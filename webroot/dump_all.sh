#!/system/bin/sh
MODDIR="/data/adb/modules/ram"
[ -d "$MODDIR" ] || MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"

CONFIG="$MODDIR/config.ini"
[ -f "$CONFIG" ] || CONFIG="$MODDIR/config/config.ini"
WHITE="$MODDIR/白名单.conf"
[ -f "$WHITE" ] || WHITE="$MODDIR/whitelist.conf"
BLACK="$MODDIR/黑名单.conf"
[ -f "$BLACK" ] || BLACK="$MODDIR/blacklist.conf"
LOG="$MODDIR/ram.log"

# 1. 状态与内存
pid=$(pgrep -f "/data/adb/modules/ram/ram.sh" 2>/dev/null || pgrep -f "ram.sh" 2>/dev/null | tr '\n' ' ' | awk '{$1=$1;print}')
mt=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
ma=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
st=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
sf=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
z_ratio="N/A"
if [ -f /sys/block/zram0/mm_stat ]; then
    read o c m _ < /sys/block/zram0/mm_stat 2>/dev/null || true
    if [ -n "$c" ] && [ "$c" -gt 0 ]; then
        z_ratio=$(awk -v o="${o:-0}" -v c="${c:-1}" 'BEGIN{printf "%.2f:1", o/c}')
    fi
fi

echo "===STATUS==="
echo "$pid|$mt|$ma|$st|$sf|$z_ratio"

# 2. 配置项
echo "===CONFIG==="
[ -f "$CONFIG" ] && cat "$CONFIG"

# 3. 白名单
echo "===WHITELIST==="
[ -f "$WHITE" ] && cat "$WHITE"

# 4. 黑名单
echo "===BLACKLIST==="
[ -f "$BLACK" ] && cat "$BLACK"

# 5. 全量运行进程
echo "===APPS==="
sh "$MODDIR/webroot/scan.sh"
