#!/system/bin/sh
MODID="ram"
MODDIR="${0%/*}"
case "$MODDIR" in ""|"sh"|"."|"/") MODDIR="/data/adb/modules/$MODID" ;; esac
[ -f "$MODDIR/module_common.sh" ] && . "$MODDIR/module_common.sh" && MODDIR="$(get_moddir)"

BIN="$MODDIR/ram.sh"
LOG="$MODDIR/ram.log"

if [ ! -f "$BIN" ]; then
    echo "运存防线启动失败：未找到 $BIN" | tee -a "$LOG" 2>/dev/null
    exit 1
fi

chmod 0755 "$BIN" 2>/dev/null

# 防止重复启动，只匹配本模块路径，避免误杀其它同名文件
OLD_PIDS="$(pgrep -f "$BIN" 2>/dev/null)"
if [ -n "$OLD_PIDS" ]; then
    echo "$OLD_PIDS" | while read -r p; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
    done
    sleep 1
fi

# 注意：ram.sh 是 C++ 编译出的 ELF 二进制，不能用 sh ram.sh
nohup "$BIN" >/dev/null 2>&1 &
PID=$!

echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 运存防线已启动，pid=$PID，MODDIR=$MODDIR" >> "$LOG" 2>/dev/null
exit 0
