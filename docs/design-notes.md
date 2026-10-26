# 设计取舍与踩坑记录

这份笔记记录“为什么这么写”，而不是“怎么写”。所有结论都来自在一台 realme 5 Pro（RMX1971 / Android 11 / realme UI 2.0 / Magisk 30.7）上的实测，不是推测。

## 1. 为什么要把脚本投递到 Termux 目录

模块自己住在 `/data/adb/modules/groupguard`，但 `ls -ld /data/adb` 是 `drwx------ root root`：

```
/data/adb           700 root root
/data/adb/modules   700 root root
```

Termux UID 无法穿透这层目录。如果机器人以 Termux 身份运行并直接从模块目录读脚本，第一步 `cd` 就会失败。所以 `gg-deploy-runtime.sh` 在每次开机时把 `bin/*.sh` **复制**到 `$GG_APP/.runtime/`，`chown` 给 Termux UID，再从那里执行。

这样做的额外好处：用户可以直接编辑 `.runtime/gg-daemon.sh` 调试，不需要动模块本体；模块升级时重新覆盖也不会冲突。

## 2. 为什么最终以 root 运行（反直觉的部分）

最初的设计是“最小权限”：看门狗用 root，机器人降权到 Termux UID（10240）。结果 Telegram 请求全部失败：

```
socket.connect(("api.telegram.org", 443)) → [Errno 13] Permission denied
```

于是做了一个对照实验：

| 启动方式 | `id -u` | `id -Z` | 结果 |
| --- | --- | --- | --- |
| `su -c '...'` | 0 | `u:r:magisk:s0` | 成功，HTTP 200 |
| `su 10240 -c '...'` | 10240 | `u:r:magisk:s0` | 失败，Errno 13 |

**SELinux 上下文完全相同**，差异只有 UID。这说明拦截发生在 Android 的网络访问控制层（基于 UID 的 `netd` 规则 / eBPF 归属判定），不是 SELinux 标签不匹配。降权后进程没有归属到任何有网络权限的 UID 域，socket 直接被拒。

结论：机器人与看门狗都以 root 运行。脚本文件仍然 `chown 10240` 方便查看，但执行身份是 root。

> 这是这套方案最大的安全代价。若要规避，可改为把机器人装进 Docker/VM（例如 Termux 内跑 `proot-distro`，或用另一台真服务器），代价是资源占用和复杂度上升。

## 3. `setsid nohup ... &` 拿不到真实 PID

```sh
setsid nohup sh run.sh >> "$BOTLOG" 2>&1 &
echo $!        # 这是 setsid 的 PID，不是 python 的
```

`$!` 拿到的是 `setsid` 自身，它 fork 出子进程后立刻退出（成为会话首进程），所以 PID 文件里写的东西一秒钟后就失效了。

因此存活判据改为**按进程名匹配**：

```sh
pgrep -f "app.main"
```

`gg-daemon.sh` 在启动后最多等 15 秒轮询这个条件，命中才把 PID 写进 `bot.pid`（仅作展示用途）。`bot_running()` 里 PID 文件只是快路径，最终仍以 `pgrep` 兜底。

## 4. 日志轮转的顺序不能反

```sh
mv -f "$f.2" "$f.3"     # 先动最老的
mv -f "$f.1" "$f.2"
mv -f "$f"   "$f.1"
```

反过来写会让 `.1` 和 `.2` 互相覆盖，最后只剩一份。第一版就是反的，表现为“日志总是只有最近一次”。

## 5. 为什么要等 30 秒再启动

`service.sh` 在 `late_start service` 阶段执行，此时：

- `wlan0` 可能还没拿到 DHCP 地址
- 系统的 `netd` 规则还没完全就绪

第一版不等待，重启后 100% 出现几次 `ConnectionError` 然后才成功；虽然机器人自身会重试，但每次重启都会在日志里留下一串报错。加 `sleep 30` 之后基本一次连上。

看门狗内部还有一层 `wait_network`：用 `223.5.5.5` 做 ICMP 探测（失败时回退到 Python 的 TCP connect 到 53 端口），最多等 120 秒，超时也继续启动——不能因为探测本身有 bug 就把机器人永久卡住。

## 6. 长轮询超时为什么要动态调整

Telegram 长轮询 `getUpdates` 的 `timeout=25` 意味着**空转时每 25 秒才返回一次**。上游主循环里有一条逻辑：有待删除的临时提醒时，把轮询窗口压到 3 秒，否则“10 秒后自动删除”的提示会被 25 秒的轮询拖成几十秒。

这条逻辑在服务端容器里同样存在，模块不需要干预，但排查“按钮点了没反应”时要记得：**长轮询天生有延迟**，不是模块把请求拦了。

## 7. 环境探测为什么用 `pm path`

```sh
pm path com.termux | head -1 | sed 's/^package://'
```

直接判断 `/data/data/com.termux` 目录存在是不够的：某些定制 ROM（或应用分身/多用户）下包名路径会变体，而 `pm` 查询反映的是 PackageManager 的真实记录。拿到路径后仍统一映射回 `/data/data/com.termux`，因为 Termux 的数据目录不随 APK 安装位置变化。

UID 则必须现场 `stat -c %u` —— 不同设备、不同安装顺序下 UID 完全不同（这台机器是 10240，别的设备可能是 10201）。写死 UID 的模块换机必挂。

## 8. 停止脚本为什么要“先礼后兵”

第一版 `gg-stop.sh` 只有一句 `pkill -f gg-daemon.sh`，实测**杀不掉**看门狗：主循环阻塞在 `sleep 30` 里，Android 的 sh 会把 SIGTERM 挂起到前台子进程结束后才处理，于是“停止”命令返回成功、进程却还活着十几秒，随后又被看门狗把机器人拉起来——表现为“停了又自己回来”。

两处都改了：

- **看门狗**：`trap 'STOP=1' TERM INT` + `nap()` 用 1 秒粒度循环睡眠，信号在 1 秒内生效
- **停止脚本**：TERM → 轮询等待 → 超时才 KILL，并把残留进程列出来再返回失败码

现在 `gg-stop.sh` 停看门狗是秒级。机器人这边通常仍会走到 KILL：上游主循环阻塞在最长 25 秒的长轮询里，收到 TERM 要等这次 `getUpdates` 返回才退出。SQLite 的 WAL 机制保证进程被强杀也不会写坏数据库，所以用 8 秒宽限 + KILL 换取更快的停止体验，是刻意的取舍。

## 9. 已知限制

- **仅适配 Termux**：路径假设 `com.termux`，不适用 Termux:X11 或自编译改包名的版本（可用 `gg.conf` 手动覆盖）。
- **没有崩溃转储**：机器人的 stdout/stderr 全打到 `bot.log`，Python 异常有 traceback，但 native crash（几乎不会发生）不会留 tombstone。
- **Magisk 专属**：`service.sh` 的 `late_start service` 阶段与 `/data/adb/modules` 布局是 Magisk 约定。KernelSU/APatch 大体兼容，但未实测。
- **OCR 未预装**：`WITH_OCR=1` 需要 tesseract 与中文语言包，Termux 里体积较大，默认关闭。
