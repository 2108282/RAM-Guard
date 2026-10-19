#!/system/bin/sh
# ==============================================================================
# 运存防线 (RAM Guard) 启动脚本 - 路径与状态自适应增强版
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
LOG="$MODDIR/ram.log"

if [ ! -f "$BIN" ]; then
    echo "运存防线启动失败：未找到核心执行文件 $BIN"
    echo "请确认模块已完整安装在 $MODDIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] 启动失败：未找到 $BIN" >> "$LOG" 2>/dev/null
    exit 1
fi

chmod 0755 "$BIN" 2>/dev/null

# 2. 终止旧进程，防止多重守护并发
OLD_PIDS="$(pgrep -f "$BIN" 2>/dev/null || pgrep -f "/data/adb/modules/ram/ram.sh" 2>/dev/null)"
if [ -n "$OLD_PIDS" ]; then
    for p in $OLD_PIDS; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
    done
    sleep 1
    # 再次检查，若仍未退出则强杀
    STILL_PIDS="$(pgrep -f "$BIN" 2>/dev/null || pgrep -f "/data/adb/modules/ram/ram.sh" 2>/dev/null)"
    if [ -n "$STILL_PIDS" ]; then
        for p in $STILL_PIDS; do
            [ -n "$p" ] && kill -9 "$p" 2>/dev/null
        done
        sleep 1
    fi
fi

# 3. 以后台孤儿守护进程模式启动 (通过 nohup + setsid / disown 彻底与当前终端解绑)
nohup "$BIN" "$MODDIR" >/dev/null 2>&1 &
PID=$!

sleep 1

# 4. 验证进程是否真正存活并向用户输出结果
if pgrep -f "$BIN" >/dev/null 2>&1 || [ -d "/proc/$PID" ]; then
    REAL_PID=$(pgrep -f "$BIN" 2>/dev/null | tr '\n' ' ' | awk '{$1=$1;print}')
    [ -z "$REAL_PID" ] && REAL_PID="$PID"
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
