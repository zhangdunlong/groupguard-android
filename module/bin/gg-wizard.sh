#!/system/bin/sh
# GroupGuard Magisk 模块 —— 交互式配置向导
# ---------------------------------------------------------------------------
# 用法：在 Termux 或 adb shell 中执行
#   sh /data/adb/modules/groupguard/bin/gg-wizard.sh
#
# 功能：
#   1. 自动探测环境（Termux、应用目录、Python）
#   2. 引导填写 BOT_TOKEN
#   3. 校验 Token 有效性（调用 Telegram getMe）
#   4. 可选设置 OWNER_IDS
#   5. 写入 .env 并设置正确权限
#   6. 可选启动机器人
# ---------------------------------------------------------------------------

MODDIR="${MODDIR:-/data/adb/modules/groupguard}"
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/groupguard

# 载入探测模块
if [ -f "$MODDIR/bin/gg-detect.sh" ]; then
  # shellcheck disable=SC1091
  . "$MODDIR/bin/gg-detect.sh"
fi

CONF="$MODDIR/gg.conf"
[ -f "$CONF" ] && . "$CONF"

# ---- 颜色（不支持时自动降级）----
if [ -t 1 ]; then
  C_R='\033[1;31m'; C_G='\033[1;32m'; C_Y='\033[1;33m'; C_B='\033[1;36m'; C_N='\033[0m'
else
  C_R=''; C_G=''; C_Y=''; C_B=''; C_N=''
fi

say()  { printf "${C_B}%s${C_N}\n" "$*"; }
ok()   { printf "${C_G}  [OK] %s${C_N}\n" "$*"; }
warn() { printf "${C_Y}  [!] %s${C_N}\n" "$*"; }
err()  { printf "${C_R}  [X] %s${C_N}\n" "$*"; }

# ===========================================================================
# 步骤 0：欢迎
# ===========================================================================
clear 2>/dev/null
cat <<'BANNER'
================================================
   GroupGuard Telegram Bot — 配置向导
================================================

本向导会帮你完成：
  1. 环境探测
  2. 填写 Bot Token
  3. 校验 Token 有效性
  4. 写入配置并启动

BANNER
printf "按回车开始..."; read -r _dummy

# ===========================================================================
# 步骤 1：环境探测
# ===========================================================================
say "【1/5】环境探测"
echo

detect_all
if [ $? -ne 0 ]; then
  err "$GG_DETECT_ERROR"
  echo
  echo "请先完成准备工作："
  echo "  1. 安装 Termux（F-Droid 版）"
  echo "  2. 在 Termux 中部署 groupguard 项目"
  echo "  3. 确保 python3 可用"
  echo
  printf "按回车退出..."; read -r _dummy
  exit 1
fi

printf "  Termux UID   : %s\n" "$GG_UID"
printf "  Termux 前缀  : %s\n" "$GG_TERMUX_PREFIX"
printf "  应用目录     : %s\n" "$GG_APP"
printf "  Python       : %s\n" "$GG_PYTHON"
echo
ok "环境探测完成"

# 持久化探测结果
save_config "$CONF"
echo

# ===========================================================================
# 步骤 2：填写 Token
# ===========================================================================
say "【2/5】填写 Bot Token"
echo
echo "  获取方式："
echo "    1. Telegram 搜索 @BotFather"
echo "    2. 发送 /newbot 创建机器人"
echo "    3. 复制形如 <数字ID>:<字母数字串> 的 Token"
echo

ENV_FILE="$GG_APP/.env"

# 读取已有的 Token（若有）
OLD_TOKEN=""
if [ -f "$ENV_FILE" ]; then
  OLD_TOKEN=$(grep '^BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
  case "$OLD_TOKEN" in
    ""|PASTE*|*YOUR_TOKEN*) OLD_TOKEN="" ;;
  esac
fi

if [ -n "$OLD_TOKEN" ]; then
  printf "  检测到已有 Token: %s...%s\n" "$(echo "$OLD_TOKEN" | cut -c1-8)" "$(echo "$OLD_TOKEN" | tail -c 5)"
  printf "  是否重新填写？[y/N]: "
  read -r redo
  case "$redo" in
    y|Y) OLD_TOKEN="" ;;
    *) ok "保留原 Token" ;;
  esac
fi

TOKEN="$OLD_TOKEN"
while [ -z "$TOKEN" ]; do
  printf "  请输入 Bot Token: "
  read -r input_token
  # 去除首尾空白
  input_token=$(echo "$input_token" | tr -d ' \t\r\n')
  if [ -z "$input_token" ]; then
    warn "不能为空"
    continue
  fi
  # 格式校验：数字:字母数字下划线连字符，长度 >= 30
  case "$input_token" in
    *:*)
      tid=${input_token%%:*}
      tval=${input_token#*:}
      case "$tid" in
        *[!0-9]*) warn "冒号前应为纯数字"; continue ;;
      esac
      if [ ${#tval} -lt 25 ]; then
        warn "冒号后部分太短，请确认复制完整"
        continue
      fi
      TOKEN="$input_token"
      ;;
    *)
      warn "格式错误：应形如 123456789:AAHdq..."
      ;;
  esac
done
ok "Token 已录入"
echo

# ===========================================================================
# 步骤 3：校验 Token
# ===========================================================================
say "【3/5】校验 Token 有效性"
echo

BOT_INFO=$("$GG_PYTHON" - "$TOKEN" <<'PYEOF' 2>&1
import json, sys, urllib.request
token = sys.argv[1]
url = "https://api.telegram.org/bot%s/getMe" % token
try:
    with urllib.request.urlopen(url, timeout=25) as r:
        d = json.loads(r.read().decode())
    if d.get("ok"):
        b = d["result"]
        print("OK|%s|%s|%s" % (b.get("username",""), b.get("first_name",""), b.get("id","")))
    else:
        print("FAIL|%s" % d.get("description", "unknown"))
except Exception as e:
    print("ERR|%s|%s" % (type(e).__name__, str(e)[:120]))
PYEOF
)

case "$BOT_INFO" in
  OK\|*)
    UNAME=$(echo "$BOT_INFO" | cut -d'|' -f2)
    BNAME=$(echo "$BOT_INFO" | cut -d'|' -f3)
    BID=$(echo "$BOT_INFO" | cut -d'|' -f4)
    ok "Token 有效"
    printf "    机器人用户名 : @%s\n" "$UNAME"
    printf "    机器人名称   : %s\n" "$BNAME"
    printf "    机器人 ID    : %s\n" "$BID"
    ;;
  FAIL\|*)
    err "Token 无效：$(echo "$BOT_INFO" | cut -d'|' -f2)"
    printf "  是否仍要继续写入？[y/N]: "
    read -r cont
    case "$cont" in y|Y) ;; *) exit 1 ;; esac
    ;;
  *)
    warn "无法连接 Telegram 校验（可能是网络问题）"
    echo "    详情: $BOT_INFO"
    printf "  是否继续？[y/N]: "
    read -r cont
    case "$cont" in y|Y) ;; *) exit 1 ;; esac
    ;;
esac
echo

# ===========================================================================
# 步骤 4：可选设置 OWNER_IDS
# ===========================================================================
say "【4/5】可选：设置管理员 ID（OWNER_IDS）"
echo
echo "  留空表示以群内管理员权限为准。"
echo "  获取自己的数字 ID：私聊 @userinfobot"
echo
printf "  请输入你的 Telegram 数字 ID（留空跳过）: "
read -r owner_ids
owner_ids=$(echo "$owner_ids" | tr -d ' \t\r\n')
[ -z "$owner_ids" ] && ok "已跳过" || ok "OWNER_IDS=$owner_ids"
echo

# ===========================================================================
# 步骤 5：写入配置
# ===========================================================================
say "【5/5】写入配置"
echo

DB_PATH="$GG_APP/data/bot.sqlite3"

cat > "$ENV_FILE" <<EOF
# GroupGuard 配置（由配置向导生成）
BOT_TOKEN=$TOKEN
DB_PATH=$DB_PATH
OWNER_IDS=$owner_ids
API_BASE=https://api.telegram.org
POLL_TIMEOUT=25
TZ=Asia/Shanghai
DASHBOARD_TOKEN=
WITH_OCR=0
OCR_ENABLED=0
LATENCY_DEBUG=0
EOF

# 权限：仅属主可读写
chmod 600 "$ENV_FILE"
chown "$GG_UID:$GG_UID" "$ENV_FILE" 2>/dev/null

# 确保目录存在
mkdir -p "$GG_APP/data" "$GG_APP/logs"
chown -R "$GG_UID:$GG_UID" "$GG_APP/data" "$GG_APP/logs" 2>/dev/null

ok "已写入 $ENV_FILE"
printf "    权限: %s\n" "$(ls -l "$ENV_FILE" | awk '{print $1}')"
echo

# 校验写入结果
if grep -qE '^BOT_TOKEN=[0-9]+:' "$ENV_FILE"; then
  ok "配置校验通过"
else
  err "配置校验失败"
  exit 1
fi
echo

# ===========================================================================
# 完成：可选启动
# ===========================================================================
echo "================================================"
printf "${C_G}  配置完成${C_N}\n"
echo "================================================"
echo
printf "  机器人 : @%s\n" "${UNAME:-未知}"
printf "  应用   : %s\n" "$GG_APP"
printf "  数据库 : %s\n" "$DB_PATH"
echo
printf "  是否现在启动机器人？[Y/n]: "
read -r start_now
case "$start_now" in
  n|N) echo "  已跳过。稍后可用以下命令启动：" ;;
  *)
    echo
    say "启动机器人..."
    # 停掉旧的
    pkill -f "app.main" 2>/dev/null
    pkill -f "gg-daemon" 2>/dev/null
    sleep 2

    RUNDIR="$GG_APP/.runtime"
    if [ -x "$RUNDIR/gg-daemon.sh" ]; then
      setsid nohup sh "$RUNDIR/gg-daemon.sh" > "$GG_APP/logs/daemon.log" 2>&1 &
    else
      cd "$GG_APP" && setsid nohup sh run.sh >> "$GG_APP/logs/bot.log" 2>&1 &
    fi
    sleep 12

    if pgrep -f "app.main" >/dev/null 2>&1; then
      ok "机器人已启动 (PID $(pgrep -f app.main | head -1))"
    else
      warn "启动中，请稍后查看日志"
    fi
    ;;
esac

echo
echo "  常用命令："
echo "    查看状态 : sh $MODDIR/bin/gg-status.sh"
echo "    查看日志 : sh $MODDIR/bin/gg-log.sh"
echo "    停止     : sh $MODDIR/bin/gg-stop.sh"
echo "    重新配置 : sh $MODDIR/bin/gg-wizard.sh"
echo
printf "  在 Telegram 中给 @%s 发送 /start 开始使用\n" "${UNAME:-你的机器人}"
echo
