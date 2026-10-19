#!/system/bin/sh
# 运存防线通用脚本函数：兼容 Magisk / KernelSU / APatch
MODID="ram"
DEFAULT_MODDIR="/data/adb/modules/$MODID"

get_moddir() {
    local d="${MODDIR:-}"
    [ -z "$d" ] && d="${0%/*}"
    case "$d" in
        ""|"sh"|"."|"/") d="$DEFAULT_MODDIR" ;;
    esac
    if [ ! -d "$d" ] && [ -d "$DEFAULT_MODDIR" ]; then
        d="$DEFAULT_MODDIR"
    fi
    cd "$d" 2>/dev/null && pwd -P || echo "$d"
}

module_log() {
    local d="$(get_moddir)"
    local msg="$*"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [script] $msg" >> "$d/ram.log" 2>/dev/null
}

root_manager_name() {
    if [ "${KSU:-}" = "true" ]; then
        echo "KernelSU"
    elif [ -n "${APATCH:-}" ] || [ -n "${APATCH_VER_CODE:-}" ] || [ -n "${APATCH_VER:-}" ]; then
        echo "APatch"
    elif [ -n "${MAGISK_VER_CODE:-}" ] || [ -n "${MAGISK_VER:-}" ]; then
        echo "Magisk"
    else
        echo "UnknownRootManager"
    fi
}
