#!/system/bin/sh
MODID="ram"
MODDIR="${0%/*}"
case "$MODDIR" in ""|"sh"|"."|"/") MODDIR="/data/adb/modules/$MODID" ;; esac
[ -f "$MODDIR/module_common.sh" ] && . "$MODDIR/module_common.sh" && MODDIR="$(get_moddir)"

chmod 0755 "$MODDIR/ram.sh" 2>/dev/null
chmod 0755 "$MODDIR/运存防线启动.sh" 2>/dev/null
chmod 0755 "$MODDIR/运存防线关闭.sh" 2>/dev/null
chmod 0755 "$MODDIR/运存防线检测.sh" 2>/dev/null
chmod 0755 "$MODDIR/action.sh" 2>/dev/null

[ -n "$(command -v module_log 2>/dev/null)" ] && module_log "service.sh 启动，Root管理器=$(root_manager_name)，MODDIR=$MODDIR"
sh "$MODDIR/运存防线启动.sh"
