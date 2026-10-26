#!/system/bin/sh
# GroupGuard —— 启动机器人（含看门狗）
# 自动定位运行时脚本目录与配置

MODDIR="${MODDIR:-/data/adb/modules/groupguard}"
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/groupguard

CONF="$MODDIR/gg.conf"
[ -f "$CONF" ] && . "$CONF"

: "${GG_UID:=$(stat -c %u /data/data/com.termux/files/home 2>/dev/null)}"
: "${GG_UID:=10240}"
: "${GG_APP:=/data/data/com.termux/files/home/groupguard}"

RUNDIR="$GG_APP/.runtime"

# 前置检查
if [ ! -f "$GG_APP/.env" ]; then
  echo "[X] $GG_APP/.env 不存在"
  echo "    请先运行配置向导: sh $MODDIR/bin/gg-wizard.sh"
  exit 1
fi
if ! grep -qE '^BOT_TOKEN=[0-9]+:' "$GG_APP/.env"; then
  echo "[X] .env 中 BOT_TOKEN 未填写或格式不正确"
  echo "    请运行配置向导: sh $MODDIR/bin/gg-wizard.sh"
  exit 1
fi

# 运行时脚本缺失则先部署
if [ ! -r "$RUNDIR/gg-daemon.sh" ]; then
  echo "[..] 运行时脚本缺失，先部署"
  sh "$MODDIR/bin/gg-deploy-runtime.sh" "$MODDIR" 2>&1 | tail -5
fi

if [ ! -r "$RUNDIR/gg-daemon.sh" ]; then
  echo "[X] 无法准备运行时脚本"
  exit 1
fi

mkdir -p "$GG_APP/logs"

if pgrep -f "gg-daemon.sh" >/dev/null 2>&1; then
  echo "[i] 看门狗已在运行"
else
  echo "[..] 启动看门狗（root 身份，实测才有网络权限）"
  setsid nohup sh "$RUNDIR/gg-daemon.sh" > "$GG_APP/logs/daemon.log" 2>&1 &
  sleep 6
fi

if pgrep -f "gg-daemon.sh" >/dev/null 2>&1; then
  echo "[OK] 看门狗运行中 (PID $(pgrep -f gg-daemon.sh | head -1))"
else
  echo "[X] 看门狗启动失败，查看 $GG_APP/logs/daemon.log"
  exit 1
fi

echo "[..] 确保机器人进程运行"
if ! pgrep -f "app.main" >/dev/null 2>&1; then
  cd "$GG_APP" && setsid nohup sh run.sh >> "$GG_APP/logs/bot.log" 2>&1 &
  sleep 10
fi

if pgrep -f "app.main" >/dev/null 2>&1; then
  echo "[OK] 机器人已启动 (PID $(pgrep -f app.main | head -1))"
else
  echo "[!] 机器人尚未就绪，看门狗会继续尝试"
fi
