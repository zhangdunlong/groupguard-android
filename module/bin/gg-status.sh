#!/system/bin/sh
# GroupGuard —— 状态查看
# 环境自适配：优先读 gg.conf，缺失则现场探测
MODDIR="${MODDIR:-/data/adb/modules/groupguard}"
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/groupguard

CONF="$MODDIR/gg.conf"
[ -f "$CONF" ] && . "$CONF"

# 兜底
: "${GG_UID:=$(stat -c %u /data/data/com.termux/files/home 2>/dev/null)}"
: "${GG_UID:=10240}"
: "${GG_APP:=/data/data/com.termux/files/home/groupguard}"

echo "=============== GroupGuard 状态 ==============="
echo ""
echo "--- 模块 ---"
if [ -d "$MODDIR" ]; then
  V=$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2)
  echo "  已安装  v${V:-未知}"
  [ -f "$MODDIR/disable" ] && echo "  !! 模块已被禁用"
  [ -f "$MODDIR/remove" ] && echo "  !! 模块已标记删除"
  [ -f "$MODDIR/update" ] && echo "  ** 待重启生效"
else
  echo "  未安装"
fi
echo ""
echo "--- 环境 ---"
echo "  应用目录  : $GG_APP"
echo "  Termux UID: $GG_UID"
if [ -f "$GG_APP/.env" ]; then
  echo "  .env      : 存在 ($(ls -l "$GG_APP/.env" | awk '{print $1}'))"
  if grep -qE '^BOT_TOKEN=[0-9]+:' "$GG_APP/.env"; then
    echo "  Token     : 已配置"
  else
    echo "  Token     : !! 未配置或格式错误"
  fi
  echo "  DB_PATH   : $(grep '^DB_PATH=' "$GG_APP/.env" 2>/dev/null | cut -d= -f2-)"
else
  echo "  .env      : 不存在（请运行 gg-wizard.sh 配置）"
fi
echo ""
echo "--- 进程 ---"
DPID=$(pgrep -f "gg-daemon.sh" 2>/dev/null | head -1)
if [ -n "$DPID" ]; then
  echo "  看门狗    : 运行中 (PID $DPID)"
else
  echo "  看门狗    : 未运行"
fi

BPID=$(pgrep -f "app.main" 2>/dev/null | head -1)
if [ -n "$BPID" ]; then
  echo "  机器人    : 运行中 (PID $BPID)"
  ET=$(ps -o etime= -p "$BPID" 2>/dev/null | tr -d ' \n')
  [ -n "$ET" ] && echo "  运行时长  : $ET"
else
  echo "  机器人    : 未运行"
fi
echo ""
echo "--- 数据库 ---"
if [ -f "$GG_APP/data/bot.sqlite3" ]; then
  echo "  文件      : $GG_APP/data/bot.sqlite3"
  echo "  大小      : $(wc -c < "$GG_APP/data/bot.sqlite3" 2>/dev/null) 字节"
else
  echo "  尚未创建"
fi
echo ""
echo "--- 最近日志 ---"
if [ -f "$GG_APP/logs/bot.log" ]; then
  tail -6 "$GG_APP/logs/bot.log" 2>/dev/null
else
  echo "  (无 bot.log)"
fi
echo ""
echo "==============================================="
