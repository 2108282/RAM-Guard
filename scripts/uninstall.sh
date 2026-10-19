#!/system/bin/sh
MODDIR=${0%/*}
pkill -f "$MODDIR/ram.sh" 2>/dev/null
