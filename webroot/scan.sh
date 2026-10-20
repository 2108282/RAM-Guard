#!/system/bin/sh
MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/ram"

WHITE="$MODDIR/whitelist.conf"
[ -f "$WHITE" ] || WHITE="$MODDIR/白名单.conf"
BLACK="$MODDIR/blacklist.conf"
[ -f "$BLACK" ] || BLACK="$MODDIR/黑名单.conf"
CONFIG="$MODDIR/config.ini"

# 读取 max_clean_count
MAX_CLEAN=10
if [ -f "$CONFIG" ]; then
    mc=$(grep -E "^max_clean_count[[:space:]]*=" "$CONFIG" 2>/dev/null | cut -d= -f2 | awk '{$1=$1;print}')
    [ -n "$mc" ] && [ "$mc" -gt 0 ] 2>/dev/null && MAX_CLEAN=$mc
fi

TMP_SYS="/data/local/tmp/ram_guard_sys_cache"
if [ ! -s "$TMP_SYS" ]; then
    (cmd package list packages -s 2>/dev/null || pm list packages -s 2>/dev/null) | sed 's/^package://' > "$TMP_SYS" 2>/dev/null
fi

dumpsys activity lru 2>/dev/null | awk \
    -v wl_file="$WHITE" \
    -v bl_file="$BLACK" \
    -v sys_file="$TMP_SYS" \
    -v max_clean="$MAX_CLEAN" '
BEGIN {
    # 核心保护硬编码清单
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
            task_pid[key] = pid

            if (match(line, /[[:space:]]TOP[[:space:]]/) && fg_key == "") {
                fg_key = key
            }
        }
    }
}
END {
    if (fg_key == "") fg_key = order[1]

    # 逆序（最老后台向上扫描），准确计算“预计清理”
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
                # 黑名单允许清理
            } else {
                status[k] = "系统应用保护"
                continue
            }
        }

        # 满足清理条件的候选应用
        if (cand_count < max_clean) {
            status[k] = "预计清理"
            cand_count++
        } else {
            status[k] = "后台"
        }
    }

    # 按照 LRU 顺序打印完整信息
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
