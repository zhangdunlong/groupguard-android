#!/data/data/com.termux/files/usr/bin/bash
# ===========================================================================
# GroupGuard —— Termux 端一键部署脚本
#
# 用法（在 Termux 里执行）：
#   bash install-bot.sh
#
# 它做的事：
#   1. 检查 python3 / git，缺失时提示安装命令
#   2. 克隆或更新上游机器人源码到 $HOME/groupguard
#   3. 安装 Python 依赖
#   4. 生成 run.sh（Termux 专用入口，读取 .env）
#   5. 交互填写 BOT_TOKEN 并在线校验
#   6. 打印后续安装 Magisk 模块的步骤
#
# 重跑本脚本是安全的：已在的源码会走 git pull，已有 .env 会问是否覆盖。
# ===========================================================================
set -u

UPSTREAM="${GG_REPO:-https://github.com/slobys/telegram-group-manager.git}"
DEST="${GG_DIR:-$HOME/groupguard}"

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_b=$'\033[1;36m'; c_n=$'\033[0m'
say()  { printf '%s\n' "${c_b}$*${c_n}"; }
ok()   { printf '%s\n' "${c_g}  [OK] $*${c_n}"; }
warn() { printf '%s\n' "${c_y}  [!] $*${c_n}"; }
err()  { printf '%s\n' "${c_r}  [X] $*${c_n}"; }

say "================================================"
say "  GroupGuard —— Termux 部署"
say "================================================"
echo

# ---- 1. 依赖检查 -----------------------------------------------------------
say "【1/5】检查依赖"

PY=""
for c in "$PREFIX/bin/python3" "$PREFIX/bin/python"; do
  [ -x "$c" ] && PY="$c" && break
done
if [ -z "$PY" ]; then
  err "未找到 python3。请先执行： pkg install python"
  exit 1
fi
ok "Python: $PY ($("$PY" -V 2>&1))"

if ! command -v git >/dev/null 2>&1; then
  err "未找到 git。请先执行： pkg install git"
  exit 1
fi
ok "Git: $(git --version)"
echo

# ---- 2. 获取源码 -----------------------------------------------------------
say "【2/5】获取机器人源码"
if [ -d "$DEST/.git" ]; then
  echo "  已存在 $DEST，尝试更新到最新 main"
  if git -C "$DEST" pull --ff-only >/dev/null 2>&1; then
    ok "已更新到 $(git -C "$DEST" rev-parse --short HEAD)"
  else
    warn "自动更新失败（可能有本地改动），继续使用当前代码"
  fi
elif [ -d "$DEST" ] && [ -f "$DEST/app/main.py" ]; then
  ok "检测到已有部署，跳过克隆"
else
  echo "  克隆 $UPSTREAM"
  if ! git clone --depth 1 "$UPSTREAM" "$DEST"; then
    err "克隆失败。国内网络可先设置代理，或手动下载后解压到 $DEST"
    exit 1
  fi
  ok "已克隆到 $DEST"
fi

if [ ! -f "$DEST/app/main.py" ]; then
  err "$DEST 不是有效的 groupguard 目录（缺少 app/main.py）"
  exit 1
fi
echo

# ---- 3. 安装依赖 -----------------------------------------------------------
say "【3/5】安装 Python 依赖"
"$PY" -m pip install --upgrade pip >/dev/null 2>&1 || true
if "$PY" -m pip install -r "$DEST/requirements.txt"; then
  ok "依赖安装完成"
else
  err "依赖安装失败，请检查网络后重试： $PY -m pip install -r $DEST/requirements.txt"
  exit 1
fi
echo

# ---- 4. 生成 run.sh --------------------------------------------------------
say "【4/5】准备运行入口"
mkdir -p "$DEST/data" "$DEST/logs"

cat > "$DEST/run.sh" <<'RUN'
#!/data/data/com.termux/files/usr/bin/bash
# GroupGuard Termux 入口：载入 .env 后以前台方式运行（交给看门狗托管）
cd "$(dirname "$0")" || exit 1
set -a
. ./.env
set +a
mkdir -p logs
echo "[$(date '+%F %T')] 启动 GroupGuard, DB_PATH=$DB_PATH"
exec python3 -m app.main
RUN
chmod 755 "$DEST/run.sh"
ok "已写入 $DEST/run.sh"
echo

# ---- 5. 配置 .env ----------------------------------------------------------
say "【5/5】填写 Bot Token"
ENV_FILE="$DEST/.env"

write_env() {
  local token="$1" owners="$2"
  cat > "$ENV_FILE" <<EOF
# GroupGuard 配置（勿提交到任何仓库）
BOT_TOKEN=$token
DB_PATH=$DEST/data/bot.sqlite3
OWNER_IDS=$owners
API_BASE=https://api.telegram.org
POLL_TIMEOUT=25
TZ=Asia/Shanghai
DASHBOARD_TOKEN=
WITH_OCR=0
OCR_ENABLED=0
LATENCY_DEBUG=0
EOF
  chmod 600 "$ENV_FILE"
}

if [ -f "$ENV_FILE" ]; then
  printf '  已存在 .env，是否重新配置？[y/N]: '
  read -r redo
  case "$redo" in
    y|Y) : ;;
    *) ok "保留现有 .env"; SKIP_ENV=1 ;;
  esac
fi

if [ "${SKIP_ENV:-0}" != "1" ]; then
  echo "  获取 Token：Telegram 找 @BotFather → /newbot → 复制形如 123456789:AAH... 的串"
  TOKEN=""
  while [ -z "$TOKEN" ]; do
    printf '  Bot Token（输入不回显）: '
    read -r -s TOKEN
    echo
    TOKEN="$(printf '%s' "$TOKEN" | tr -d ' \t\r\n')"
    case "$TOKEN" in
      *:*) : ;;
      *) warn "格式不对，应包含冒号"; TOKEN=""; continue ;;
    esac
  done

  printf '  你的 Telegram 数字 ID（可留空，用于 /dban 等管理指令）： '
  read -r OWNERS
  OWNERS="$(printf '%s' "$OWNERS" | tr -d ' \t\r\n')"

  write_env "$TOKEN" "$OWNERS"
  ok "已写入 $ENV_FILE (600)"
fi

# ---- 完成 ------------------------------------------------------------------
echo
say "================================================"
say "  Termux 侧完成"
say "================================================"
echo "  源码 : $DEST"
echo "  配置 : $ENV_FILE"
echo "  数据库: $DEST/data/bot.sqlite3"
echo
echo "  手动试运行（看到 '机器人已启动' 即可 Ctrl-C）："
echo "    cd $DEST && bash run.sh"
echo
echo "  下一步：安装 Magisk 模块实现开机自启与保活"
echo "    1. 从 GitHub Releases 下载 groupguard-magisk-v*.zip"
echo "    2. Magisk → 模块 → 从本地安装 → 选择该 zip → 重启"
echo "    3. 重启后执行： su -c 'sh /data/adb/modules/groupguard/bin/gg-status.sh'"
echo
