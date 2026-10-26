#!/system/bin/sh
# GroupGuard Magisk 模块 —— 部署运行时脚本
# ---------------------------------------------------------------------------
# 设计要点（实测教训）：
#   /data/adb/ 是 root 专属目录（drwx------ root root），
#   Termux UID 无法穿透 —— 实测 "Permission denied"。
#   而机器人必须以 root 运行才有网络权限（UID 问题，非 SELinux 上下文）。
#
#   因此：模块启动时先把 bin/ 下的脚本复制到 Termux 可访问目录，
#         再从那里执行。这样既保留模块的分发与自启能力，
#         又满足运行时的权限要求。
#
# 本脚本以 root 身份运行（由 service.sh 调用）。
# ---------------------------------------------------------------------------

MODDIR="${1:-$(dirname "$0")}"
[ -d "$MODDIR/bin" ] || MODDIR=/data/adb/modules/groupguard
[ -d "$MODDIR/bin" ] || MODDIR=/data/adb/modules_update/groupguard

# ---- 载入探测模块 ----
if [ -f "$MODDIR/bin/gg-detect.sh" ]; then
  # shellcheck disable=SC1091
  . "$MODDIR/bin/gg-detect.sh"
fi

CONF="$MODDIR/gg.conf"

logmsg() { echo "[$(date '+%F %T')] $*"; }

# ---- 优先读配置；无配置则现场探测 ----
GG_APP=""
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"
fi

if [ -z "$GG_APP" ] || [ ! -d "$GG_APP" ]; then
  logmsg "配置缺失或失效，执行环境探测"
  detect_all || {
    logmsg "[X] $GG_DETECT_ERROR"
    exit 1
  }
  save_config "$CONF"
fi

# ---- 兜底 ----
: "${GG_UID:=$(stat -c %u /data/data/com.termux/files/home 2>/dev/null)}"
: "${GG_UID:=10240}"
: "${GG_APP:=/data/data/com.termux/files/home/groupguard}"
: "${GG_TERMUX_HOME:=/data/data/com.termux/files/home}"

RUNDIR="$GG_APP/.runtime"

logmsg "部署运行时脚本"
logmsg "  MODDIR   = $MODDIR"
logmsg "  GG_UID   = $GG_UID"
logmsg "  GG_APP   = $GG_APP"
logmsg "  RUNDIR   = $RUNDIR"

# ---- 复制脚本到 Termux 可访问目录 ----
mkdir -p "$RUNDIR"
cp -f "$MODDIR/bin/"*.sh "$RUNDIR/" 2>/dev/null

# ---- 生成运行时配置 ----
if [ -f "$CONF" ]; then
  cat "$CONF" > "$RUNDIR/gg.conf"
else
  cat > "$RUNDIR/gg.conf" <<EOF
GG_UID=$GG_UID
GG_APP=$GG_APP
EOF
fi

# ---- 修正权限：属主给 Termux UID（便于用户查看），但执行时用 root ----
chown -R "$GG_UID:$GG_UID" "$RUNDIR" 2>/dev/null
chmod 755 "$RUNDIR"
chmod 755 "$RUNDIR"/*.sh 2>/dev/null
chmod 644 "$RUNDIR/gg.conf" 2>/dev/null

logmsg "已部署到 $RUNDIR:"
ls -la "$RUNDIR/" 2>/dev/null | head -15

# ---- 校验可读 ----
if [ -r "$RUNDIR/gg-daemon.sh" ]; then
  logmsg "[OK] 运行时脚本就绪"
else
  logmsg "[!] 运行时脚本不可读，请检查权限"
fi

logmsg "部署完成"
