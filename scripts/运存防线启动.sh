#!/system/bin/sh
# ==============================================================================
# 运存防线 (RAM Guard) 启动脚本 - 全环境兼容版 (Magisk / KernelSU / APatch)
# ==============================================================================

MODID="ram"
DEFAULT_MODDIR="/data/adb/modules/$MODID"

# 1. 严格解析脚本所在的真实模块目录
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

if [ ! -f "$BIN" ]; then
    echo "运存防线启动失败：未找到核心执行文件 $BIN"
    echo "请确认模块已完整安装在 $MODDIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 启动失败：未找到 $BIN" >> "$LOG" 2>/dev/null
    exit 1
fi

chmod 0755 "$BIN" 2>/dev/null

# 2. 终止旧进程，防止多重守护并发 (三重定位：PID 文件 + pidof + pgrep，完美兼容 KernelSU/APatch)
OLD_PIDS=""
[ -f "$PID_FILE" ] && OLD_PIDS="$(cat "$PID_FILE" 2>/dev/null)"
OLD_PIDS="$OLD_PIDS $(pidof ram.sh 2>/dev/null) $(pgrep -f "ram.sh" 2>/dev/null)"

KILL_PIDS=$(echo "$OLD_PIDS" | tr ' ' '\n' | sort -u | grep -E '^[0-9]+$')
if [ -n "$KILL_PIDS" ]; then
    for p in $KILL_PIDS; do
        [ "$p" != "$$" ] && kill "$p" 2>/dev/null
    done
    sleep 1
    # 二次检查，若未退出则强杀
    for p in $KILL_PIDS; do
        [ -d "/proc/$p" ] && [ "$p" != "$$" ] && kill -9 "$p" 2>/dev/null
    done
fi

# 3. 以后台孤儿守护进程模式启动 (优先 nohup，若无 nohup 则直接后台启动)
if command -v nohup >/dev/null 2>&1; then
    nohup "$BIN" "$MODDIR" >/dev/null 2>&1 &
else
    "$BIN" "$MODDIR" >/dev/null 2>&1 &
fi
PID=$!
echo "$PID" > "$PID_FILE" 2>/dev/null

sleep 1

# 4. 验证进程是否真正存活并向用户输出结果
if [ -d "/proc/$PID" ] || pidof ram.sh >/dev/null 2>&1 || pgrep -f "$BIN" >/dev/null 2>&1; then
    REAL_PID=$(cat "$PID_FILE" 2>/dev/null)
    [ -z "$REAL_PID" ] && REAL_PID=$(pidof ram.sh 2>/dev/null | awk '{print $1}')
    [ -z "$REAL_PID" ] && REAL_PID="$PID"

    # 若开启了状态栏通知，立即唤醒历史休眠锁定并发送初始就绪通知 (优先直接发送，兼容 KernelSU 无需依赖 su 2000)
    notify_enabled=$(grep -E "^enable_status_notification[[:space:]]*=[[:space:]]*true" "$MODDIR/config.ini" 2>/dev/null || true)
    if [ -n "$notify_enabled" ]; then
        cmd notification unsnooze "0|com.android.shell|2020|RAMGuard|2000" >/dev/null 2>&1 || true
        cmd notification post -t "运存防线" RAMGuard "清理 0 个 ｜ 上次 0MB ｜ 累计 0MB" >/dev/null 2>&1 || \
        su 2000 -c "cmd notification post -t '运存防线' RAMGuard '清理 0 个 ｜ 上次 0MB ｜ 累计 0MB'" >/dev/null 2>&1 || true
    fi

    echo "=========================================="
    echo " 运存防线启动成功！"
    echo " 进程 PID: $REAL_PID"
    echo " 模块目录: $MODDIR"
    echo "=========================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 运存防线启动成功，PID=$REAL_PID" >> "$LOG" 2>/dev/null
    exit 0
else
    echo "=========================================="
    echo " 运存防线启动异常：进程未在后台驻留"
    echo " 请运行 'sh 运存防线检测.sh' 查看具体状态与依赖"
    echo "=========================================="
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 启动异常：进程未驻留" >> "$LOG" 2>/dev/null
    exit 1
fi
