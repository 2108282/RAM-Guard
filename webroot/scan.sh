#!/system/bin/sh
MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/ram"

WHITE="$MODDIR/白名单.conf"
BLACK="$MODDIR/黑名单.conf"
CONFIG="$MODDIR/config.ini"

# 读取 max_clean_count
MAX_CLEAN=10
if [ -f "$CONFIG" ]; then
    mc=$(grep -E "^max_clean_count[[:space:]]*=" "$CONFIG" 2>/dev/null | cut -d= -f2 | awk '{$1=$1;print}')
    [ -n "$mc" ] && [ "$mc" -gt 0 ] 2>/dev/null && MAX_CLEAN=$mc
fi

TMP_SYS="$MODDIR/system_packages.cache"
if [ ! -s "$TMP_SYS" ]; then
    (cmd package list packages -s 2>/dev/null || pm list packages -s 2>/dev/null) | sed 's/^package://' > "$TMP_SYS" 2>/dev/null
fi

dumpsys activity lru 2>/dev/null | awk \
    -v wl_file="$WHITE" \
    -v bl_file="$BLACK" \
    -v sys_file="$TMP_SYS" \
    -v max_clean="$MAX_CLEAN" '
BEGIN {
    # 核心防砖名单 (绝对保护)
    core["android"] = 1
    core["com.android.systemui"] = 1
    core["com.android.phone"] = 1
    core["com.android.settings"] = 1
    core["com.android.bluetooth"] = 1
    core["com.android.shell"] = 1
    core["com.android.packageinstaller"] = 1
    core["com.google.android.packageinstaller"] = 1
    core["com.android.permissioncontroller"] = 1
    core["com.google.android.permissioncontroller"] = 1
    core["com.android.providers.downloads"] = 1
    core["com.android.providers.media"] = 1
    core["com.android.providers.settings"] = 1
    core["com.android.providers.telephony"] = 1
    core["com.android.providers.contacts"] = 1
    core["com.android.launcher"] = 1
    core["com.android.launcher3"] = 1
    core["com.google.android.apps.nexuslauncher"] = 1
    core["com.miui.home"] = 1
    core["com.huawei.android.launcher"] = 1
    core["com.oppo.launcher"] = 1
    core["com.vivo.launcher"] = 1
    core["com.realme.launcher"] = 1
    core["com.sec.android.app.launcher"] = 1
    core["net.oneplus.launcher"] = 1
    core["com.android.inputmethod.latin"] = 1
    core["com.google.android.inputmethod.latin"] = 1
    core["com.sohu.inputmethod.sogou"] = 1
    core["com.baidu.input"] = 1
    core["com.iflytek.inputmethod"] = 1
    core["com.topjohnwu.magisk"] = 1
    core["io.github.huskydg.magisk"] = 1
    core["me.weishu.kernelsu"] = 1
    core["com.dergoogler.mmrl"] = 1

    while ((getline l < wl_file) > 0) {
        sub(/[#;].*$/, "", l); gsub(/^[[:space:]]+|[[:space:]]+$/, "", l)
        if (l != "") wl[l] = 1
    }
    close(wl_file)
    while ((getline l < bl_file) > 0) {
        sub(/[#;].*$/, "", l); gsub(/^[[:space:]]+|[[:space:]]+$/, "", l)
        if (l != "") bl[l] = 1
    }
    close(bl_file)
    while ((getline l < sys_file) > 0) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", l)
        if (l != "") sys[l] = 1
    }
    close(sys_file)
}
/^[[:space:]]*#[0-9]+:/ {
    line = $0
    if (match(line, /[0-9]+:[A-Za-z0-9_.]+\.[A-Za-z0-9_.]+/)) {
        pair_str = substr(line, RSTART, RLENGTH)
        colon_idx = index(pair_str, ":")
        pid = substr(pair_str, 1, colon_idx - 1)
        pkg = substr(pair_str, colon_idx + 1)

        user_id = 0
        is_sys_proc = 0

        # 通用 AOSP 格式解析：/u<userId>a<appId> 或 /u<userId>s<sysId> 或 /<sysId>
        # 支持任意用户空间 (0, 10, 12, 99, 999 等)
        if (match(line, /\/u[0-9]+[as][0-9]+/)) {
            u_part = substr(line, RSTART + 2, RLENGTH - 2)
            if (match(u_part, /[as]/)) {
                as_idx = RSTART
                type_char = substr(u_part, as_idx, 1)
                user_id = substr(u_part, 1, as_idx - 1) + 0
                if (type_char == "s") {
                    is_sys_proc = 1
                }
            }
        } else if (match(line, /\/[0-9]+/)) {
            # 纯数字 UID 结构 (如 /1000, /1073, /1027)，属于主空间底层特权系统服务
            raw_uid = substr(line, RSTART + 1, RLENGTH - 1) + 0
            if (raw_uid < 10000) {
                user_id = 0
                is_sys_proc = 1
            } else if (raw_uid >= 100000) {
                user_id = int(raw_uid / 100000)
            }
        }

        key = user_id ":" pkg
        if (!seen[key]++) {
            total++
            order[total] = key
            task_uid[key] = user_id
            task_is_sys[key] = is_sys_proc
            task_pkg[key] = pkg
            task_pid[key] = pid

            if (match(line, /[[:space:]]TOP[[:space:]]/) && fg_key == "") {
                fg_key = key
            }
        }
    }
}
END {
    if (fg_key == "") fg_key = order[1]

    # 逆序 (最老后台向上扫描) 准确评估候选
    cand_count = 0
    for (i = total; i >= 1; i--) {
        k = order[i]
        u = task_uid[k]
        is_sys = task_is_sys[k]
        p = task_pkg[k]
        pid = task_pid[k]

        # 1. 前台保护
        if (k == fg_key) {
            status[k] = "当前前台"
            continue
        }

        # 2. 核心防砖保护
        if (p in core) {
            status[k] = "系统核心保护"
            continue
        }

        # 3. 白名单匹配 (全局白名单 或 自适应任意空间的专属白名单)
        if (p in wl || (u ":" p) in wl || ("u" u ":" p) in wl || (p ":" u) in wl) {
            status[k] = "白名单保护"
            continue
        }

        # 4. 【黑名单最高裁决权】
        in_blacklist = 0
        if (p in bl || (u ":" p) in bl || ("u" u ":" p) in bl || (p ":" u) in bl) {
            in_blacklist = 1
        }

        if (in_blacklist) {
            if (cand_count < max_clean) {
                status[k] = "预计清理"
                cand_count++
            } else {
                status[k] = "黑名单系统应用"
            }
            continue
        }

        # 5. 系统底层与物理分区免杀拦截
        # 5.1 明确的系统特权进程 (带有 s 标识或纯特权 UID，如 networkstack, nfc 等)
        if (is_sys == 1) {
            status[k] = "系统核心保护"
            continue
        }

        # 5.2 芯片底层硬件服务前缀 (高通/联发科/指纹生物认证)
        if (p ~ /^vendor\./ || p ~ /^com\.qti\./ || p ~ /^com\.qualcomm\./ || p ~ /^org\.ifaa\./) {
            status[k] = "系统应用保护"
            continue
        }

        # 5.3 系统已安装包清单匹配
        if (p in sys) {
            status[k] = "系统应用保护"
            continue
        }

        # 5.4 物理分区路径检查：APK 非 /data/app/ 的判定为系统应用保护
        is_data_app = 0
        maps_file = "/proc/" pid "/maps"
        while ((getline ml < maps_file) > 0) {
            if (ml ~ /\.apk/ && ml ~ /\/data\/app\//) {
                is_data_app = 1
                break
            }
        }
        close(maps_file)

        if (is_data_app == 0) {
            status[k] = "系统应用保护"
            continue
        }

        # 6. 剩余普通第三方应用进入预计清理
        if (cand_count < max_clean) {
            status[k] = "预计清理"
            cand_count++
        } else {
            status[k] = "后台"
        }
    }

    # 按照 LRU 顺序打印每一项
    for (i = 1; i <= total; i++) {
        k = order[i]
        u = task_uid[k]
        p = task_pkg[k]
        pid = task_pid[k]
        st = status[k]
        if (st == "") st = "后台"

        rss_mb = 0
        swap_mb = 0
        statm_file = "/proc/" pid "/statm"
        if ((getline sm < statm_file) > 0) {
            split(sm, a, " ")
            rss_mb = int(a[2] * 4 / 1024)
        }
        close(statm_file)

        status_file = "/proc/" pid "/status"
        while ((getline sl < status_file) > 0) {
            if (sl ~ /^VmSwap:/) {
                split(sl, a, " ")
                swap_mb = int(a[2] / 1024)
                break
            }
        }
        close(status_file)

        print u "|" p "|" st "|" rss_mb "|" swap_mb
    }
}
'
