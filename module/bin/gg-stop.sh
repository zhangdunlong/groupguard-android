#!/system/bin/sh
# GroupGuard —— 停止机器人与看门狗
# 先礼后兵：SIGTERM（让机器人优雅退出、写完 WAL）→ 等不到就 SIGKILL

MODDIR="${MODDIR:-/data/adb/modules/groupguard}"
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/groupguard

CONF="$MODDIR/gg.conf"
[ -f "$CONF" ] && . "$CONF"
: "${GG_APP:=${GG_TERMUX_HOME:-/data/data/com.termux/files/home}/groupguard}"

# 等待某个进程消失，最多 $2 秒；返回 0 表示已消失
wait_gone() {
  _w=0
  while [ "$_w" -lt "$2" ]; do
    pgrep -f "$1" >/dev/null 2>&1 || return 0
    sleep 1
    _w=$((_w+1))
  done
  pgrep -f "$1" >/dev/null 2>&1 && return 1
  return 0
}

echo "[..] 停止看门狗"
pkill -f "gg-daemon.sh" 2>/dev/null
if ! wait_gone "gg-daemon.sh" 6; then
  echo "[..] 看门狗未响应 TERM，强制结束"
  pkill -9 -f "gg-daemon.sh" 2>/dev/null
  wait_gone "gg-daemon.sh" 3
fi

echo "[..] 停止机器人"
pkill -f "app.main" 2>/dev/null
if ! wait_gone "app.main" 8; then
  echo "[..] 机器人未响应 TERM，强制结束"
  pkill -9 -f "app.main" 2>/dev/null
  wait_gone "app.main" 3
fi

rm -f "$GG_APP/logs/bot.pid" 2>/dev/null

if pgrep -f "app.main" >/dev/null 2>&1 || pgrep -f "gg-daemon.sh" >/dev/null 2>&1; then
  echo "[!] 仍有进程残留："
  ps -A -o PID,ARGS 2>/dev/null | grep -E "gg-daemon|app[.]main" | grep -v grep
  exit 1
fi

echo "[OK] 已全部停止"
