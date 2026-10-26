#!/system/bin/sh
# GroupGuard —— 卸载清理
# 注意：只清理模块自身产生的运行时文件，不动 groupguard 部署与数据

MODDIR=${0%/*}
[ -d "$MODDIR/bin" ] || MODDIR=/data/adb/modules/groupguard

CONF="$MODDIR/gg.conf"
[ -f "$CONF" ] && . "$CONF"
: "${GG_APP:=${GG_TERMUX_HOME:-/data/data/com.termux/files/home}/groupguard}"

echo "[..] 停止进程"
pkill -f "gg-daemon.sh" 2>/dev/null
pkill -f "app.main" 2>/dev/null
sleep 2

echo "[..] 清理临时文件"
rm -f /data/local/tmp/groupguard-boot.log 2>/dev/null

# 数据保留：bot.sqlite3、.env、logs 都保留，便于重装后继续用
echo "[OK] 模块已移除"
echo "     数据保留在 $GG_APP（含数据库与配置）"
echo "     如需彻底删除： rm -rf $GG_APP"
