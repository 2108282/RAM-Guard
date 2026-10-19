#!/system/bin/sh
MODID="ram"
MODDIR="${0%/*}"
case "$MODDIR" in ""|"sh"|"."|"/") MODDIR="/data/adb/modules/$MODID" ;; esac
sh "$MODDIR/运存防线检测.sh"
