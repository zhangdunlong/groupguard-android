#!/system/bin/sh
# GroupGuard Magisk 模块 —— 环境自适应探测
# ---------------------------------------------------------------------------
# 目的：让模块能在任意已 root 的 Android 设备上工作，不写死 UID 与路径。
#
# 探测内容：
#   1. Termux 数据目录（/data/data/com.termux）与真实 UID
#   2. groupguard 应用目录（支持多种候选位置）
#   3. Python 解释器位置
#
# 设计原则：
#   - 所有值都是「探测 + 可覆盖」，不硬编码
#   - 探测失败时给出明确错误，而不是静默使用错误默认值
# ---------------------------------------------------------------------------

# ---- 常量 ----
TERMUX_PKG="com.termux"
DEFAULT_APP_NAME="groupguard"

# ---- 输出变量（调用方 source 本文件后使用）----
GG_TERMUX_DATA=""
GG_UID=""
GG_TERMUX_PREFIX=""
GG_TERMUX_HOME=""
GG_APP=""
GG_PYTHON=""
GG_DETECT_ERROR=""

# ---------------------------------------------------------------------------
# 1. 探测 Termux
# ---------------------------------------------------------------------------
detect_termux() {
  # 优先用 pm 查询（更权威，能处理多用户/重打包场景）
  if command -v pm >/dev/null 2>&1; then
    local pkg_path
    pkg_path=$(pm path "$TERMUX_PKG" 2>/dev/null | head -1 | sed 's/^package://')
    if [ -n "$pkg_path" ]; then
      # /data/app/.../base.apk → /data/data/com.termux
      GG_TERMUX_DATA="/data/data/$TERMUX_PKG"
    fi
  fi

  # 回退：直接检查目录
  if [ -z "$GG_TERMUX_DATA" ] && [ -d "/data/data/$TERMUX_PKG" ]; then
    GG_TERMUX_DATA="/data/data/$TERMUX_PKG"
  fi

  if [ -z "$GG_TERMUX_DATA" ] || [ ! -d "$GG_TERMUX_DATA/files" ]; then
    GG_DETECT_ERROR="未检测到 Termux（$TERMUX_PKG）。请先安装 Termux。"
    return 1
  fi

  GG_TERMUX_PREFIX="$GG_TERMUX_DATA/files/usr"
  GG_TERMUX_HOME="$GG_TERMUX_DATA/files/home"

  # ---- 探测真实 UID ----
  GG_UID=$(stat -c %u "$GG_TERMUX_HOME" 2>/dev/null)
  if [ -z "$GG_UID" ]; then
    # 回退：从应用目录推
    GG_UID=$(stat -c %u "$GG_TERMUX_DATA" 2>/dev/null)
  fi
  if [ -z "$GG_UID" ]; then
    GG_DETECT_ERROR="无法探测 Termux UID。"
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# 2. 探测 groupguard 应用目录
#    按优先级尝试多个候选位置
# ---------------------------------------------------------------------------
detect_app_dir() {
  local candidates="
$GG_TERMUX_HOME/$DEFAULT_APP_NAME
$GG_TERMUX_HOME/${DEFAULT_APP_NAME}-bot
/data/local/groupguard
/data/adb/groupguard
"

  for d in $candidates; do
    if [ -f "$d/run.sh" ] || [ -f "$d/app/main.py" ]; then
      GG_APP="$d"
      return 0
    fi
  done

  # 最后尝试：在家目录下找任何含 app/main.py 的目录
  if [ -d "$GG_TERMUX_HOME" ]; then
    local found
    found=$(find "$GG_TERMUX_HOME" -maxdepth 2 -name "main.py" -path "*/app/*" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
      GG_APP=$(dirname "$(dirname "$found")")
      return 0
    fi
  fi

  GG_DETECT_ERROR="未找到 groupguard 应用目录。请先完成项目部署。"
  return 1
}

# ---------------------------------------------------------------------------
# 3. 探测 Python 解释器
# ---------------------------------------------------------------------------
detect_python() {
  for p in \
    "$GG_TERMUX_PREFIX/bin/python3" \
    "$GG_TERMUX_PREFIX/bin/python" \
    "$GG_TERMUX_PREFIX/bin/python3.14" \
    "$GG_TERMUX_PREFIX/bin/python3.13" \
    "$GG_TERMUX_PREFIX/bin/python3.12"
  do
    if [ -x "$p" ]; then
      GG_PYTHON="$p"
      return 0
    fi
  done

  # 回退：用 command -v（依赖 PATH）
  local which_py
  which_py=$(command -v python3 2>/dev/null)
  if [ -n "$which_py" ]; then
    GG_PYTHON="$which_py"
    return 0
  fi

  GG_DETECT_ERROR="未找到 Python 解释器。请在 Termux 中安装 python3。"
  return 1
}

# ---------------------------------------------------------------------------
# 4. 一键探测全部
# ---------------------------------------------------------------------------
detect_all() {
  GG_DETECT_ERROR=""

  detect_termux || return 1
  detect_app_dir || return 1
  detect_python || return 1

  return 0
}

# ---------------------------------------------------------------------------
# 5. 持久化探测结果到配置文件
# ---------------------------------------------------------------------------
save_config() {
  local conf="$1"
  [ -z "$conf" ] && return 1

  mkdir -p "$(dirname "$conf")"
  cat > "$conf" <<EOF
# GroupGuard 运行时配置（由环境探测自动生成）
# 修改后请重启看门狗或用 gg-start.sh 重新加载
GG_TERMUX_DATA=$GG_TERMUX_DATA
GG_TERMUX_PREFIX=$GG_TERMUX_PREFIX
GG_TERMUX_HOME=$GG_TERMUX_HOME
GG_UID=$GG_UID
GG_APP=$GG_APP
GG_PYTHON=$GG_PYTHON
EOF
  chmod 644 "$conf"
  return 0
}

# ---------------------------------------------------------------------------
# 6. 加载配置（若存在，则用配置值覆盖探测）
# ---------------------------------------------------------------------------
load_config() {
  local conf="$1"
  if [ -f "$conf" ]; then
    # shellcheck disable=SC1090
    . "$conf"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# 7. 打印探测结果（调试用）
# ---------------------------------------------------------------------------
print_detection() {
  echo "环境探测结果:"
  echo "  Termux 数据目录 : ${GG_TERMUX_DATA:-未探测}"
  echo "  Termux PREFIX   : ${GG_TERMUX_PREFIX:-未探测}"
  echo "  Termux HOME     : ${GG_TERMUX_HOME:-未探测}"
  echo "  Termux UID      : ${GG_UID:-未探测}"
  echo "  应用目录        : ${GG_APP:-未探测}"
  echo "  Python          : ${GG_PYTHON:-未探测}"
  [ -n "$GG_DETECT_ERROR" ] && echo "  错误            : $GG_DETECT_ERROR"
}
