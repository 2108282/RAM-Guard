#!/system/bin/sh
MODDIR="${0%/*}"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/ram"

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

echo "$pid|$mt|$ma|$st|$sf|$z_ratio"
