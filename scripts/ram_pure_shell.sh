#!/system/bin/sh
# ==============================================================================
# 运存防线 (RAM Guard) - 纯 Shell 免编译等价实现 (多用户与全量进程增强版)
# 100% 对齐 C++ 原版核心逻辑，可直接替代 /data/adb/modules/ram/ram.sh 运行
# ==============================================================================

MODID="ram"
MODDIR="${0%/*}"
case "$MODDIR" in ""|"sh"|"."|"/") MODDIR="/data/adb/modules/$MODID" ;; esac
[ -f "$MODDIR/module_common.sh" ] && . "$MODDIR/module_common.sh" && MODDIR="$(get_moddir)"

CONFIG="$MODDIR/config.ini"
WHITE="$MODDIR/白名单.conf"
BLACK="$MODDIR/黑名单.conf"
LOG="$MODDIR/ram.log"

TMPDIR="/data/local/tmp/ram_guard_runtime_$$"
mkdir -p "$TMPDIR" 2>/dev/null
cleanup() { rm -rf "$TMPDIR" 2>/dev/null; }
trap cleanup EXIT INT TERM

WL="$TMPDIR/white"
BL="$TMPDIR/black"
CORE="$TMPDIR/core"
SYS="$TMPDIR/sys"
TASKS="$TMPDIR/tasks"

# 1. 核心硬编码保护清单
cat > "$CORE" <<'EOF'
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
EOF

# 动态保护输入法
ime=$(settings get secure default_input_method 2>/dev/null | sed -n 's#^\([A-Za-z0-9_.]*\)/.*#\1#p')
[ -n "$ime" ] && echo "$ime" >> "$CORE"

# 读取系统应用列表
(pm list packages -s 2>/dev/null || cmd package list packages -s 2>/dev/null) | sed 's/^package://' > "$SYS" 2>/dev/null

clean_list_file() {
    src="$1"; dst="$2"
    if [ -f "$src" ]; then
        sed 's/[#;].*$//' "$src" 2>/dev/null | awk '{$1=$1;print}' | grep -E '^[A-Za-z0-9_.:]+$' > "$dst"
    else
        : > "$dst"
    fi
}

reload_lists() {
    clean_list_file "$WHITE" "$WL"
    clean_list_file "$BLACK" "$BL"
}

reload_lists

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

log_msg() {
    tag="$1"; shift
    msg="$*"
    enable_log=$(get_cfg_bool enable_log true)
    [ "$enable_log" = "true" ] || return 0

    max_kb=$(get_cfg_int log_max_size_kb 512)
    if [ -f "$LOG" ]; then
        cur_bytes=$(wc -c < "$LOG" 2>/dev/null || echo 0)
        if [ "$cur_bytes" -gt $((max_kb * 1024)) ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] 日志过大，已清理旧日志" > "$LOG"
        fi
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$tag] $msg" >> "$LOG" 2>/dev/null
}

format_kb() {
    kb="$1"
    mb=$((kb / 1024))
    if [ "$mb" -le 0 ]; then
        echo "0MB"
    elif [ "$mb" -lt 1024 ]; then
        echo "${mb}MB"
    else
        awk -v m="$mb" 'BEGIN {printf "%.1fGB", m/1024}'
    fi
}

LAST_CLEAN_TIME=0
TOTAL_CLEANED_COUNT=0
TOTAL_FREED_KB=0
TOTAL_ZRAM_FREED_KB=0

update_notification() {
    last_freed_kb="$1"
    status_notify=$(get_cfg_bool enable_status_notification false)
    if [ "$status_notify" = "true" ]; then
        last_str=$(format_kb "$last_freed_kb")
        total_str=$(format_kb "$TOTAL_FREED_KB")
        text="清理 ${TOTAL_CLEANED_COUNT} 个 ｜ 上次 ${last_str} ｜ 累计 ${total_str}"
        cmd notification post -S bigtext -t "运存防线" RAMGuard "$text" >/dev/null 2>&1
    fi
}

clean_ram_once() {
    is_fast="${1:-false}"
    reload_lists

    start_mem=$(get_cfg_int start_mem_percent 10)
    target_mem=$(get_cfg_int target_mem_percent 16)
    emerg_mem=$(get_cfg_int emergency_mem_percent 4)
    swap_start=$(get_cfg_int swap_free_start_percent 40)
    swap_emerg=$(get_cfg_int swap_free_emergency_percent 15)
    max_clean=$(get_cfg_int max_clean_count 2)
    emerg_max_clean=$(get_cfg_int emergency_max_clean_count 3)
    clean_interval=$(get_cfg_int clean_interval_ms 400)
    cooldown=$(get_cfg_int clean_cooldown_sec 30)

    now_sec=$(date +%s)
    if [ "$is_fast" != "true" ]; then
        if [ $((now_sec - LAST_CLEAN_TIME)) -lt "$cooldown" ]; then
            return 0
        fi
    fi

    # 读取物理内存与 Swap/ZRAM
    mt=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    ma=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    st=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
    sf=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
    [ -n "$mt" ] && [ "$mt" -gt 0 ] || return 0

    avail_pct=$((ma * 100 / mt))
    swap_pct=-1
    [ -n "$st" ] && [ "$st" -gt 0 ] && swap_pct=$((sf * 100 / st))

    under_pressure=0
    [ "$avail_pct" -lt "$start_mem" ] && under_pressure=1
    [ "$swap_pct" -ge 0 ] && [ "$swap_pct" -lt "$swap_start" ] && under_pressure=1

    [ "$under_pressure" -eq 1 ] || return 0

    mode="普通"
    limit="$max_clean"
    if [ "$avail_pct" -lt "$emerg_mem" ] || { [ "$swap_pct" -ge 0 ] && [ "$swap_pct" -lt "$swap_emerg" ]; }; then
        mode="紧急"
        limit="$emerg_max_clean"
    elif [ "$is_fast" = "true" ]; then
        mode="轻清理"
        limit=1
    fi

    swap_desc="无"
    [ "$swap_pct" -ge 0 ] && swap_desc="${swap_pct}%"

    if [ "$is_fast" = "true" ]; then
        log_msg "INFO" "快速切换内存压力：可用内存=${avail_pct}%，模式=${mode}"
    else
        log_msg "INFO" "内存压力：可用内存=${avail_pct}%，Swap/ZRAM剩余=${swap_desc}，模式=${mode}"
    fi

    # 优先从 dumpsys activity lru 收集全量运行进程
    dumpsys activity lru 2>/dev/null | awk '
    /^[[:space:]]*#[0-9]+:/ {
        line = $0
        if (match(line, /[0-9]+:([A-Za-z0-9_.]+\.[A-Za-z0-9_.]+)(:[^/[:space:]]+)?\/u?([0-9]+)[as]?/)) {
            match(line, /[0-9]+:([A-Za-z0-9_.]+\.[A-Za-z0-9_.]+)/)
            pkg = substr(line, RSTART, RLENGTH)
            sub(/^[0-9]+:/, "", pkg)
            
            match(line, /\/u?([0-9]+)[as]?/)
            uid_str = substr(line, RSTART+1, RLENGTH-1)
            gsub(/[^0-9]/, "", uid_str)
            uid = uid_str + 0
            if (uid >= 100000) uid = int(uid / 100000)
            else if (uid == 1000) uid = 0

            key = uid ":" pkg
            if (!seen[key]++) {
                print uid "\t" pkg
            }
        }
    }' > "$TASKS"

    if [ ! -s "$TASKS" ]; then
        dumpsys activity activities 2>/dev/null | awk '
        /Task\{.*U=[0-9]+/ {
            match($0, /U=[0-9]+/)
            cur_u = substr($0, RSTART+2, RLENGTH-2) + 0
        }
        /mActivityComponent|realActivity|topResumedActivity/ {
            line=$0
            if (match(line, /[A-Za-z0-9_.]+\//)) {
                s=substr(line, RSTART, RLENGTH-1)
                if (s ~ /^[A-Za-z0-9_.]+\.[A-Za-z0-9_.]+$/) {
                    key = cur_u ":" s
                    if (!seen[key]++) print cur_u "\t" s
                }
            }
        }' > "$TASKS"
    fi

    [ -s "$TASKS" ] || {
        log_msg "ERROR" "获取运行应用列表失败，跳过本次清理"
        return 0
    }

    FOREGROUND_LINE=$(head -n 1 "$TASKS")
    FOREGROUND_UID=$(echo "$FOREGROUND_LINE" | awk '{print $1}')
    FOREGROUND_PKG=$(echo "$FOREGROUND_LINE" | awk '{print $2}')
    cleaned=0
    pred_list=""

    # 栈底/队尾向上逆序遍历
    candidate_list=$(awk '{a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$TASKS")

    echo "$candidate_list" | while IFS=$'\t' read -r uid pkg; do
        [ -n "$pkg" ] || continue
        app_tag="[u${uid}] ${pkg}"

        if [ "$uid" = "$FOREGROUND_UID" ] && [ "$pkg" = "$FOREGROUND_PKG" ]; then
            log_msg "跳过" "当前前台：$app_tag"
            continue
        fi

        # 白名单匹配: 全局或多用户
        if grep -Fxq "$pkg" "$WL" 2>/dev/null || \
           grep -Fxq "${uid}:${pkg}" "$WL" 2>/dev/null || \
           grep -Fxq "u${uid}:${pkg}" "$WL" 2>/dev/null || \
           grep -Fxq "${pkg}:${uid}" "$WL" 2>/dev/null; then
            log_msg "跳过" "白名单：$app_tag"
            continue
        fi

        # 系统核心保护
        if grep -Fxq "$pkg" "$CORE" 2>/dev/null; then
            log_msg "跳过" "系统核心保护：$app_tag"
            continue
        fi

        is_sys=0
        grep -Fxq "$pkg" "$SYS" 2>/dev/null && is_sys=1
        is_bl=0
        if grep -Fxq "$pkg" "$BL" 2>/dev/null || \
           grep -Fxq "${uid}:${pkg}" "$BL" 2>/dev/null || \
           grep -Fxq "u${uid}:${pkg}" "$BL" 2>/dev/null || \
           grep -Fxq "${pkg}:${uid}" "$BL" 2>/dev/null; then
            is_bl=1
        fi

        if [ "$is_sys" -eq 1 ] && [ "$is_bl" -eq 0 ]; then
            log_msg "跳过" "系统应用保护：$app_tag"
            continue
        fi

        if [ "$cleaned" -ge "$limit" ]; then
            [ -z "$pred_list" ] && pred_list="$app_tag" || pred_list="$pred_list, $app_tag"
            continue
        fi

        # 多用户空间专属查杀
        am force-stop --user "$uid" "$pkg" >/dev/null 2>&1 || su 2000 -c "am force-stop --user $uid '$pkg'" >/dev/null 2>&1

        if [ "$is_bl" -eq 1 ]; then
            log_msg "CLEAN" "已清理黑名单：$app_tag"
        else
            log_msg "CLEAN" "已清理：$app_tag"
        fi
        cleaned=$((cleaned + 1))

        if [ "$clean_interval" -gt 0 ]; then
            sleep "$(awk -v ms="$clean_interval" 'BEGIN{print ms/1000}')" 2>/dev/null || sleep 1
        fi

        # 动态检查是否已达物理内存目标
        cur_ma=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
        cur_avail=$((cur_ma * 100 / mt))
        [ "$cur_avail" -ge "$target_mem" ] && break
    done

    # 重新读取计算释放指标
    ma_after=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    sf_after=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)
    avail_after=$((ma_after * 100 / mt))
    freed_kb=$((ma_after - ma))
    [ "$freed_kb" -lt 0 ] && freed_kb=0

    zram_freed_kb=0
    swap_after_pct=-1
    if [ -n "$st" ] && [ "$st" -gt 0 ]; then
        zram_freed_kb=$((sf_after - sf))
        [ "$zram_freed_kb" -lt 0 ] && zram_freed_kb=0
        swap_after_pct=$((sf_after * 100 / st))
    fi

    TOTAL_FREED_KB=$((TOTAL_FREED_KB + freed_kb))
    TOTAL_ZRAM_FREED_KB=$((TOTAL_ZRAM_FREED_KB + zram_freed_kb))
    TOTAL_CLEANED_COUNT=$((TOTAL_CLEANED_COUNT + cleaned))
    LAST_CLEAN_TIME=$(date +%s)

    freed_desc=$(format_kb "$freed_kb")
    zram_desc=$(format_kb "$zram_freed_kb")

    if [ "$cleaned" -gt 0 ]; then
        log_line="清理完成：可用内存 ${avail_pct}% → ${avail_after}% (释放约 ${freed_desc})"
        if [ "$swap_pct" -ge 0 ]; then
            log_line="${log_line}，ZRAM ${swap_pct}% → ${swap_after_pct}% (回收约 ${zram_desc})"
        fi
        log_line="${log_line}，清理数量=${cleaned}"
        log_msg "INFO" "$log_line"
        update_notification "$freed_kb"
    else
        log_msg "INFO" "未清理：没有符合条件的后台应用"
    fi
}

log_msg "INFO" "运存防线启动，配置加载完成"
clean_ram_once false

# 启动前台日志监听循环
logcat -b events -v brief -T 1 2>/dev/null | while read -r line; do
    case "$line" in
        *wm_resume_activity*|*am_start_activity*|*wm_set_resumed_activity*|*am_focused_activity*)
            switch_delay=$(get_cfg_int clean_delay_after_switch_ms 2000)
            if [ "$switch_delay" -gt 0 ]; then
                sleep "$(awk -v ms="$switch_delay" 'BEGIN{print ms/1000}')" 2>/dev/null || sleep 2
            fi
            clean_ram_once true
            ;;
    esac
done
