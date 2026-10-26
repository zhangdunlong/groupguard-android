#!/system/bin/sh
# GroupGuard 看门狗守护进程
# ---------------------------------------------------------------------------
# 职责：
#   1. 保活：机器人进程不在就拉起
#   2. 崩溃重启：带指数退避，避免疯狂重启
#   3. 日志轮转：防止日志无限增长
#   4. 网络等待：启动前确认网络可用
#
# 【关键实测结论】必须以 root 运行，不能用 Termux UID：
#   su -c      (UID 0)     → socket OK,  Telegram HTTP 200
#   su 10240 -c (UID 10240) → socket FAIL, Errno 13 Permission denied
#   两者 SELinux 上下文相同（都 u:r:magisk:s0），
#   所以瓶颈是 UID 而非上下文 —— 降权会断网。
#
# 环境自适应：通过 gg-detect.sh 探测路径与 UID，不写死设备相关值。
# ---------------------------------------------------------------------------

SELFDIR=$(dirname "$0")
MODDIR="${MODDIR:-/data/adb/modules/groupguard}"
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/groupguard

# ---- 载入探测模块 ----
DETECT=""
for c in "$SELFDIR/gg-detect.sh" "$MODDIR/bin/gg-detect.sh"; do
  [ -f "$c" ] && DETECT="$c" && break
done

# ---- 加载配置（探测结果缓存）----
CONF=""
for c in "$SELFDIR/gg.conf" "$MODDIR/gg.conf"; do
  [ -f "$c" ] && CONF="$c" && break
done

if [ -n "$DETECT" ]; then
  # shellcheck disable=SC1090
  . "$DETECT"
  # 先尝试读配置；失败则现场探测
  if ! load_config "$CONF" 2>/dev/null || [ -z "$GG_APP" ]; then
    detect_all || true
  fi
fi

# ---- 兜底默认值 ----
: "${GG_UID:=$(stat -c %u /data/data/com.termux/files/home 2>/dev/null)}"
: "${GG_UID:=10240}"
: "${GG_TERMUX_PREFIX:=/data/data/com.termux/files/usr}"
: "${GG_TERMUX_HOME:=/data/data/com.termux/files/home}"
: "${GG_APP:=$GG_TERMUX_HOME/groupguard}"
: "${GG_PYTHON:=$GG_TERMUX_PREFIX/bin/python3}"

# ---- 运行环境 ----
export PATH="$GG_TERMUX_PREFIX/bin:$PATH"
export PREFIX="$GG_TERMUX_PREFIX"
export HOME="$GG_TERMUX_HOME"
export LD_LIBRARY_PATH="$GG_TERMUX_PREFIX/lib"
export TMPDIR="$GG_TERMUX_PREFIX/tmp"
export LANG=C.UTF-8

LOG="$GG_APP/logs/daemon.log"
BOTLOG="$GG_APP/logs/bot.log"
PIDFILE="$GG_APP/logs/bot.pid"

mkdir -p "$GG_APP/logs" 2>/dev/null

logmsg() {
  echo "[$(date '+%F %T')] $*"
}

# ---- 可中断等待 ----
# 实测教训：Android 的 sh 在等待前台子进程（sleep）时，会把 SIGTERM 挂起到
# 子进程结束后才处理。原先主循环里 `sleep 30` 导致 gg-stop.sh 发 TERM 后
# 最多 30 秒才真正退出，看起来像「杀不掉」。
# 这里用 1 秒粒度的循环睡眠，收到信号后 1 秒内就能跳出。
STOP=0
trap 'STOP=1' TERM INT

nap() {
  _n=0
  while [ "$_n" -lt "$1" ]; do
    [ "$STOP" = "1" ] && return 1
    sleep 1
    _n=$((_n+1))
  done
  return 0
}

# ---- 日志轮转：超过 2MB 就轮转，保留 3 份 ----
# 注意顺序：必须先移位旧的 .1，再移位 .2，否则会互相覆盖
rotate_log() {
  f="$1"
  if [ -f "$f" ]; then
    sz=$(wc -c < "$f" 2>/dev/null || echo 0)
    if [ "$sz" -gt 2097152 ]; then
      rm -f "$f.3" 2>/dev/null
      [ -f "$f.2" ] && mv -f "$f.2" "$f.3" 2>/dev/null
      [ -f "$f.1" ] && mv -f "$f.1" "$f.2" 2>/dev/null
      mv -f "$f" "$f.1" 2>/dev/null
      : > "$f"
      logmsg "日志已轮转: $f"
    fi
  fi
}

# ---- 机器人是否在运行 ----
bot_running() {
  if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  # PID 文件不可信时，按进程名兜底
  if pgrep -f "app.main" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# ---- 等待网络就绪（最多 120 秒）----
# 用公共 DNS 做连通性探测（阿里 DNS，非用户隐私数据）
wait_network() {
  i=0
  while [ "$i" -lt 40 ]; do
    [ "$STOP" = "1" ] && return 0
    if ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1; then
      logmsg "网络就绪（耗时 $((i*3)) 秒）"
      return 0
    fi
    # ping 不可用时，用 Python 直接测
    if [ "$i" -eq 5 ] && [ -x "$GG_PYTHON" ]; then
      if "$GG_PYTHON" -c "import socket;s=socket.socket();s.settimeout(5);s.connect(('223.5.5.5',53));s.close()" 2>/dev/null; then
        logmsg "网络就绪（TCP 探测，耗时 $((i*3)) 秒）"
        return 0
      fi
    fi
    sleep 3
    i=$((i+1))
  done
  logmsg "网络等待超时，仍尝试启动（机器人自身有重连逻辑）"
  return 0
}

# ---- 启动机器人 ----
start_bot() {
  logmsg "启动机器人..."
  cd "$GG_APP" || { logmsg "无法进入 $GG_APP"; return 1; }

  if [ ! -f "$GG_APP/run.sh" ]; then
    logmsg "缺少 run.sh，无法启动"
    return 1
  fi

  # 关键：setsid nohup 的 $! 拿到的是 setsid 的 PID，不是 python 的。
  # 因此不依赖 PID 文件，改用进程名（app.main）作为存活判据。
  setsid nohup sh run.sh >> "$BOTLOG" 2>&1 &

  i=0
  while [ "$i" -lt 15 ]; do
    sleep 1
    bpid=$(pgrep -f "app.main" 2>/dev/null | head -1)
    if [ -n "$bpid" ]; then
      echo "$bpid" > "$PIDFILE"
      logmsg "已启动，PID=$bpid"
      return 0
    fi
    i=$((i+1))
  done

  logmsg "启动后 15 秒内未检测到 app.main 进程"
  return 1
}

# ===========================================================================
# 主循环
# ===========================================================================
logmsg "==================================================="
logmsg "看门狗启动 (UID=$(id -u), 上下文=$(id -Z 2>/dev/null || echo unknown))"
logmsg "APP=$GG_APP"
logmsg "PYTHON=$GG_PYTHON"
logmsg "==================================================="

wait_network

FAIL=0
BACKOFF=5

while [ "$STOP" != "1" ]; do
  rotate_log "$BOTLOG"
  rotate_log "$LOG"

  if bot_running; then
    if [ "$FAIL" -ne 0 ]; then
      logmsg "机器人已恢复运行"
      FAIL=0
      BACKOFF=5
    fi
  else
    FAIL=$((FAIL+1))
    logmsg "机器人未运行（第 $FAIL 次检测）"

    if [ "$FAIL" -gt 3 ]; then
      logmsg "连续失败 $FAIL 次，清理残留进程"
      pkill -f "app.main" 2>/dev/null
      sleep 2
    fi

    if start_bot; then
      FAIL=0
      BACKOFF=5
      nap 3 || break
      continue
    fi

    logmsg "本次启动失败，$BACKOFF 秒后重试"
    nap "$BACKOFF" || break
    BACKOFF=$((BACKOFF * 2))
    [ "$BACKOFF" -gt 300 ] && BACKOFF=300
    continue
  fi

  nap 30 || break
done

logmsg "看门狗退出（STOP=$STOP）"
