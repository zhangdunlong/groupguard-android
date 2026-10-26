#!/system/bin/sh
# GroupGuard —— Magisk 应用内「操作」按钮触发
# 用途：在 Magisk 里点一下就能看状态，不用敲命令。
# Magisk 会把本脚本的 stdout 直接显示在操作结果界面。

MODDIR=${0%/*}
[ -d "$MODDIR/bin" ] || MODDIR=/data/adb/modules/groupguard
[ -d "$MODDIR/bin" ] || MODDIR=/data/adb/modules_update/groupguard

MODDIR="$MODDIR" sh "$MODDIR/bin/gg-status.sh"
exit 0
