#!/system/bin/sh
# ==============================================================================
# 运存防线状态与多用户应用检测脚本 (高速流式版)
# 支持多用户空间识别 (u0/u12等)、ZRAM详细压缩换出分析、多用户黑白名单判定
# ==============================================================================

MODID="ram"
DEFAULT_MODDIR="/data/adb/modules/$MODID"
MODDIR="${0%/*}"
case "$MODDIR" in ""|"sh"|"."|"/") MODDIR="$DEFAULT_MODDIR" ;; esac
[ -d "$MODDIR" ] || MODDIR="$DEFAULT_MODDIR"
[ -f "$MODDIR/module_common.sh" ] && . "$MODDIR/module_common.sh" 2>/dev/null && MODDIR="$(get_moddir 2>/dev/null || echo "$DEFAULT_MODDIR")"
[ -d "$MODDIR" ] || MODDIR="$DEFAULT_MODDIR"

BIN="$MODDIR/ram.sh"
TMPDIR="${TMPDIR:-/data/local/tmp}/ram_guard_check_$$"
mkdir -p "$TMPDIR" 2>/dev/null
cleanup() { rm -rf "$TMPDIR" 2>/dev/null; }
trap cleanup EXIT INT TERM

CONFIG="$MODDIR/config.ini"
WHITE="$MODDIR/白名单.conf"
BLACK="$MODDIR/黑名单.conf"
LOG="$MODDIR/ram.log"
SYS="$TMPDIR/system"
CORE="$TMPDIR/core"
WL="$TMPDIR/white"
BL="$TMPDIR/black"

get_cfg_int() {
    key="$1"; def="$2"
    [ -f "$CONFIG" ] || { echo "$def"; return; }
    val=$(awk -F= -v k="$key" '
        /^[[:space:]]*[#;]/ {next}
        {
            line=$0
            sub(/[;#].*/, "", line)
            split(line, a, "=")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[1])
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[2])
            if (a[1] == k) {print a[2]; exit}
        }
    ' "$CONFIG" 2>/dev/null)
    case "$val" in ''|*[!0-9]*) echo "$def" ;; *) echo "$val" ;; esac
}

get_cfg_bool() {
    key="$1"; def="$2"
    [ -f "$CONFIG" ] || { echo "$def"; return; }
    val=$(awk -F= -v k="$key" '
        /^[[:space:]]*[#;]/ {next}
        {
            line=$0
            sub(/[;#].*/, "", line)
            split(line, a, "=")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[1])
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[2])
            if (a[1] == k) {print a[2]; exit}
        }
    ' "$CONFIG" 2>/dev/null | tr 'A-Z' 'a-z')
    case "$val" in
        1|true|yes|on) echo "true" ;;
        0|false|no|off) echo "false" ;;
        *) echo "$def" ;;
    esac
}

clean_pkg_file() {
    src="$1"; dst="$2"
    if [ -f "$src" ]; then
        sed 's/[#;].*$//' "$src" 2>/dev/null | awk '{$1=$1;print}' | grep -E '^[A-Za-z0-9_.:]+$' > "$dst"
    else
        : > "$dst"
    fi
}

MAX_CLEAN=$(get_cfg_int max_clean_count 2)
[ "$MAX_CLEAN" -lt 1 ] && MAX_CLEAN=1
STATUS_NOTIFY=$(get_cfg_bool enable_status_notification false)

# 核心保护清单
cat > "$CORE" <<'EOF_CORE'
android
com.android.systemui
com.android.phone
com.android.settings
com.android.bluetooth
com.android.shell
com.android.packageinstaller
com.google.android.packageinstaller
com.android.permissioncontroller
com.google.android.permissioncontroller
com.android.providers.downloads
com.android.providers.media
com.android.providers.settings
com.android.providers.telephony
com.android.providers.contacts
com.android.launcher
com.android.launcher3
com.google.android.apps.nexuslauncher
com.miui.home
com.huawei.android.launcher
com.oppo.launcher
com.vivo.launcher
com.realme.launcher
com.sec.android.app.launcher
net.oneplus.launcher
com.android.inputmethod.latin
com.google.android.inputmethod.latin
com.sohu.inputmethod.sogou
com.baidu.input
com.iflytek.inputmethod
com.topjohnwu.magisk
io.github.huskydg.magisk
me.weishu.kernelsu
com.dergoogler.mmrl
EOF_CORE

ime=$(settings get secure default_input_method 2>/dev/null | sed -n 's#^\([A-Za-z0-9_.]*\)/.*#\1#p')
[ -n "$ime" ] && echo "$ime" >> "$CORE"

clean_pkg_file "$WHITE" "$WL"
clean_pkg_file "$BLACK" "$BL"
(pm list packages -s 2>/dev/null || cmd package list packages -s 2>/dev/null) | sed 's/^package://' > "$SYS" 2>/dev/null

echo "==============[ 运存防线状态 ]=============="
echo "模块目录：$MODDIR"
if pgrep -f "$BIN" >/dev/null 2>&1; then
    echo "运行状态：正在运行"
    echo "进程PID：$(pgrep -f "$BIN" | tr '\n' ' ')"
else
    echo "运行状态：未运行"
fi

if [ -f "$BIN" ]; then
    echo "核心文件：存在 ram.sh"
else
    echo "核心文件：未检测到 ram.sh"
fi

echo "多用户空间支持：已就绪 (可识别主空间 User 0 与分身/工作空间)"

echo
echo "==============[ 内存与 ZRAM 状态 ]=============="
awk '
/MemTotal:/ {mt=$2}
/MemAvailable:/ {ma=$2}
/SwapTotal:/ {st=$2}
/SwapFree:/ {sf=$2}
END {
  if (mt>0) printf("物理内存：可用 %dMB / 总计 %dMB (可用率 %d%%)\n", ma/1024, mt/1024, ma*100/mt)
  if (st>0) {
    used = (st - sf) / 1024
    printf("ZRAM状态：已换出 %dMB / 总计 %dMB (剩余率 %d%%)\n", used, st/1024, sf*100/st)
  } else print "ZRAM：未开启"
}' /proc/meminfo

if [ -f /sys/block/zram0/mm_stat ]; then
    read orig compr mem_used _ _ _ _ < /sys/block/zram0/mm_stat 2>/dev/null || true
    if [ -n "$orig" ] && [ "$orig" -gt 0 ]; then
        orig_mb=$((orig / 1048576))
        compr_mb=$((compr / 1048576))
        mem_mb=$((mem_used / 1048576))
        ratio=$(awk -v o="$orig" -v c="$compr" 'BEGIN{if(c>0) printf "%.2f:1", o/c; else print "N/A"}')
        echo "ZRAM效率：原始数据 ${orig_mb}MB 压缩为 ${compr_mb}MB (占用物理内存 ${mem_mb}MB，压缩比 ${ratio})"
    fi
fi

echo
echo "==============[ 运行应用列表 (含多用户空间) ]=============="

dumpsys activity lru 2>/dev/null | awk \
    -v core_file="$CORE" \
    -v wl_file="$WL" \
    -v bl_file="$BL" \
    -v sys_file="$SYS" \
    -v max_clean="$MAX_CLEAN" '
BEGIN {
    while ((getline line < core_file) > 0) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "") core[line] = 1
    }
    close(core_file)

    while ((getline line < wl_file) > 0) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "") wl[line] = 1
    }
    close(wl_file)

    while ((getline line < bl_file) > 0) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "") bl[line] = 1
    }
    close(bl_file)

    while ((getline line < sys_file) > 0) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line != "") sys[line] = 1
    }
    close(sys_file)
}

/^[[:space:]]*#[0-9]+:/ {
    line = $0
    if (match(line, /[0-9]+:[A-Za-z0-9_.]+\.[A-Za-z0-9_.]+/)) {
        pkg = substr(line, RSTART, RLENGTH)
        sub(/^[0-9]+:/, "", pkg)

        uid = 0
        if (match(line, /\/u?[0-9]+/)) {
            uid_str = substr(line, RSTART, RLENGTH)
            gsub(/[^0-9]/, "", uid_str)
            uid = uid_str + 0
            if (uid >= 100000) uid = int(uid / 100000)
            else if (uid == 1000) uid = 0
        }

        key = uid ":" pkg
        if (!seen[key]++) {
            total++
            order[total] = key
            task_uid[key] = uid
            task_pkg[key] = pkg
            if (match(line, /[[:space:]]TOP[[:space:]]/) && fg_key == "") {
                fg_key = key
            }
        }
    }
}

END {
    if (total == 0) {
        print "未解析到运行应用列表"
        exit
    }
    if (fg_key == "") fg_key = order[1]

    cand_count = 0
    for (i = total; i >= 1; i--) {
        k = order[i]
        u = task_uid[k]
        p = task_pkg[k]

        if (k == fg_key) {
            status[k] = "当前前台"
            continue
        }
        if (p in wl || (u ":" p) in wl || ("u" u ":" p) in wl || (p ":" u) in wl) {
            status[k] = "白名单保护"
            continue
        }
        if (p in core) {
            status[k] = "系统核心保护"
            continue
        }
        if (p in sys) {
            if (p in bl || (u ":" p) in bl || ("u" u ":" p) in bl || (p ":" u) in bl) {
                # 黑名单系统应用允许清理
            } else {
                status[k] = "系统应用保护"
                continue
            }
        }

        if (cand_count < max_clean) {
            status[k] = "预计清理"
            cand_count++
        } else {
            status[k] = "后台"
        }
    }

    for (i = 1; i <= total; i++) {
        k = order[i]
        u = task_uid[k]
        p = task_pkg[k]
        st = status[k]
        if (st == "") st = "后台"
        printf "%02d. [u%-2s] %-45s %s\n", i, u, p, st
    }
}
'

echo
echo "==============[ 配置文件与规则 ]==============="
echo "配置文件：$CONFIG"
echo "白名单：$WHITE"
echo "黑名单：$BLACK"
echo "日志文件：$LOG"
echo
