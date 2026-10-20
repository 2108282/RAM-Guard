#!/system/bin/sh
MODDIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P)"
[ -d "$MODDIR" ] || MODDIR="/data/adb/modules/ram"

WHITE="$MODDIR/whitelist.conf"
[ -f "$WHITE" ] || WHITE="$MODDIR/白名单.conf"
BLACK="$MODDIR/blacklist.conf"
[ -f "$BLACK" ] || BLACK="$MODDIR/黑名单.conf"

TMP_SYS="/data/local/tmp/ram_guard_sys_cache"
if [ ! -s "$TMP_SYS" ]; then
    (cmd package list packages -s 2>/dev/null || pm list packages -s 2>/dev/null) | sed 's/^package://' > "$TMP_SYS" 2>/dev/null
fi

dumpsys activity lru 2>/dev/null | awk \
    -v wl_file="$WHITE" \
    -v bl_file="$BLACK" \
    -v sys_file="$TMP_SYS" '
BEGIN {
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
            st = "后台"
            if (match(line, /[[:space:]]TOP[[:space:]]/)) st = "当前前台"
            else if (pkg in wl || (uid ":" pkg) in wl || ("u" uid ":" pkg) in wl) st = "白名单保护"
            else if (pkg in sys) {
                if (pkg in bl || (uid ":" pkg) in bl) st = "黑名单系统应用"
                else st = "系统应用保护"
            }

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

            print uid "|" pkg "|" st "|" rss_mb "|" swap_mb
        }
    }
}
'
