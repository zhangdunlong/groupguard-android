# 更新日志

## v1.1.1 — 2026-10-26

首个公开版本。相比设备上长期运行的 1.1.0，逻辑修正一处、体验调整若干：

- **修复看门狗杀不掉的问题**：主循环 `sleep 30` 会把 SIGTERM 挂起到子进程结束，导致 `gg-stop.sh` 返回成功但进程仍在。改为 `trap` + 1 秒粒度可中断等待，停止延迟从“十几秒后自己回来”变为秒级
- `gg-stop.sh` 改为 TERM → 轮询等待 → 超时 KILL，并在仍有残留时列出进程、返回非 0
- `gg-status.sh` 修正「运行时长」被 `ps -o etime=` 的换行拆成两行
- `module.prop` 增加 `updateJson`，支持 Magisk 内自动检查更新
- 修正 `action.sh` 中 `MODOIR` 变量名笔误，并移除无效的 toast 广播（Magisk 直接展示 stdout）
- `gg-stop.sh` / `gg-log.sh` / `uninstall.sh` 统一从 `<模块目录>/gg.conf` 读取配置，兼容 `/data/adb/modules_update`
- 仓库化：拆出 `module/`、`scripts/`、`docs/`，新增打包脚本与文档

## v1.1.0 — 2026-10-17

- 看门狗连续失败 3 次后清理残留进程，指数退避上限 300 秒
- 日志按 2MB 轮转，保留 3 份
- `gg-wizard.sh` 增加 Token 在线校验（`getMe`）与格式检查
- 卸载时保留应用目录与数据库

## v1.0.0 — 2026-10-16

- 首个可用版本：开机自启、看门狗保活、环境自适应探测
