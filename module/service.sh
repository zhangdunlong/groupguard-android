#!/system/bin/sh
# GroupGuard Magisk 模块 —— 开机启动入口
# Magisk 在 late_start service 阶段执行本脚本（已 root 上下文）
#
# 设计要点（实测教训）：
#   /data/adb/ 是 root 专属目录，Termux UID 无法穿透。
#   而机器人必须以 Termux UID 运行（否则 socket 被 SELinux 拒绝）。
#   → 先用 gg-deploy-runtime.sh 把脚本投递到 Termux 目录，再从那里启动。

MODDIR=${0%/*}
BOOTLOG=/data/local/tmp/groupguard-boot.log

mkdir -p /data/local/tmp

{
  echo "==================================================="
  echo "[$(date '+%F %T')] GroupGuard service.sh 启动"

  # ---- 等待系统就绪 ----
  echo "[$(date '+%F %T')] 等待系统与网络就绪 (30s)..."
  sleep 30

  # ---- 读取配置 ----
  CONF="$MODDIR/gg.conf"
  [ -f "$CONF" ] && . "$CONF"
  : "${GG_UID:=$(stat -c %u /data/data/com.termux/files/home 2>/dev/null)}"
  : "${GG_UID:=10240}"
  : "${GG_APP:=${GG_TERMUX_HOME:-/data/data/com.termux/files/home}/groupguard}"

  echo "[$(date '+%F %T')] GG_UID=$GG_UID  GG_APP=$GG_APP"

  # ---- 前置检查 ----
  if [ ! -d "$GG_APP" ]; then
    echo "[!] $GG_APP 不存在，需先完成 groupguard 部署"
    exit 1
  fi
  if [ ! -f "$GG_APP/.env" ]; then
    echo "[!] $GG_APP/.env 不存在，未配置 Token"
    exit 1
  fi
  if ! grep -qE '^BOT_TOKEN=[0-9]+:' "$GG_APP/.env"; then
    echo "[!] .env 中 BOT_TOKEN 未填写或格式不正确"
    exit 1
  fi
  echo "[OK] 前置检查通过"

  # ---- 部署运行时脚本到 Termux 目录 ----
  echo "[..] 部署运行时脚本..."
  sh "$MODDIR/bin/gg-deploy-runtime.sh" "$MODDIR"

  RUNDIR="$GG_APP/.runtime"
  if [ ! -r "$RUNDIR/gg-daemon.sh" ]; then
    echo "[!] 运行时脚本部署失败"
    exit 1
  fi

  # ---- 启动看门狗（以 root）----
  # 实测：su -c (root) 有网络权限，su 10240 (Termux UID) 会被拒 socket。
  # 因此看门狗与机器人都在 root 下运行。
  echo "[..] 启动看门狗（root 身份）"
  mkdir -p "$GG_APP/logs"

  setsid nohup sh "$RUNDIR/gg-daemon.sh" > "$GG_APP/logs/daemon.log" 2>&1 &

  sleep 6
  if pgrep -f "gg-daemon.sh" >/dev/null 2>&1; then
    echo "[OK] 看门狗已运行"
  else
    echo "[!] 看门狗未启动，尝试直接运行机器人"
    cd "$GG_APP" && setsid nohup bash run.sh >> "$GG_APP/logs/bot.log" 2>&1 &
  fi

  echo "[$(date '+%F %T')] service.sh 结束"
  echo "==================================================="
} >> "$BOOTLOG" 2>&1
