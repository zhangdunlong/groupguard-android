#!/system/bin/sh
# GroupGuard —— 日志查看
MODDIR="${MODDIR:-/data/adb/modules/groupguard}"
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/groupguard

CONF="$MODDIR/gg.conf"
[ -f "$CONF" ] && . "$CONF"
: "${GG_APP:=${GG_TERMUX_HOME:-/data/data/com.termux/files/home}/groupguard}"

N="${1:-30}"

echo "=========== 机器人日志 (bot.log, 末 $N 行) ==========="
if [ -f "$GG_APP/logs/bot.log" ]; then
  tail -n "$N" "$GG_APP/logs/bot.log"
else
  echo "(无)"
fi

echo ""
echo "=========== 看门狗日志 (daemon.log, 末 $N 行) ==========="
if [ -f "$GG_APP/logs/daemon.log" ]; then
  tail -n "$N" "$GG_APP/logs/daemon.log"
else
  echo "(无)"
fi

echo ""
echo "=========== 开机日志 (groupguard-boot.log) ==========="
if [ -f /data/local/tmp/groupguard-boot.log ]; then
  tail -n "$N" /data/local/tmp/groupguard-boot.log
else
  echo "(无)"
fi
