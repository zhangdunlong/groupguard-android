# GroupGuard Android · Telegram 群管机器人的 Android 常驻方案

把 [GroupGuard](https://github.com/slobys/telegram-group-manager)（自托管 Telegram 群管理机器人）跑在**一台已 root 的 Android 手机**上，并用 Magisk 模块解决手机上最麻烦的两件事：**开机自启**和**被杀后自动拉起**。

适用场景：手上有闲置的旧手机，想拿它当一台 7×24 小时的低功耗机器人服务器；没有公网 IP、没有域名、也不想开端口——GroupGuard 本身走 Telegram 长轮询，正好不需要这些。

> **本仓库只包含 Android 侧的封装与保活，不含机器人业务代码。**
> 机器人本体来自上游开源项目 [slobys/telegram-group-manager](https://github.com/slobys/telegram-group-manager)，安装时由脚本自动克隆，版权归原作者所有。

---

## 为什么需要这个模块

Android 和常规 Linux 服务器最大的差别是：**系统会主动杀你的进程**。

| 问题 | 纯 Termux 手动运行的后果 |
| --- | --- |
| 省电策略冻结 Termux | 息屏几分钟后机器人掉线 |
| 系统内存回收 | 进程被杀，Telegram 侧再无响应 |
| 重启手机 | 一切归零，需要手动重新执行命令 |
| 进程静默崩溃 | 无守护、无日志、无声卡死 |

Magisk 模块在 `late_start service` 阶段拿到 root 上下文，因此可以在系统开机时就把机器人拉起来，并用看门狗常驻监控。

## 工作原理

```
开机
 └─ Magisk: late_start service
     └─ module/service.sh               (root)
         ├─ 等 30s 让系统与网络就绪
         ├─ 校验 <app>/.env 里的 BOT_TOKEN
         ├─ bin/gg-deploy-runtime.sh    把脚本投递到 Termux 可访问目录
         └─ 启动 bin/gg-daemon.sh        (root, setsid nohup)
             └─ 每 30s 检查一次
                 ├─ app.main 不在 → 拉起 run.sh → python3 -m app.main
                 ├─ 连续失败 → 清残留进程 + 指数退避（5s→300s 封顶）
                 └─ bot.log / daemon.log 超 2MB → 轮转，保留 3 份
```

### 一个反直觉的实测结论：机器人必须以 root 运行

初次实现时按“最小权限”思路把机器人降权到 Termux UID 运行，结果 Telegram 请求全部报 `Errno 13 Permission denied`。

| 启动方式 | 实际 UID | SELinux 上下文 | 出网结果 |
| --- | --- | --- | --- |
| `su -c` | 0 | `u:r:magisk:s0` | ✅ socket 正常，HTTP 200 |
| `su 10240 -c` | 10240 | `u:r:magisk:s0`（相同） | ❌ socket 被拒 |

两者 SELinux 上下文完全一致，唯一的差别是 UID —— 说明瓶颈是 **Android 的按 UID 网络访问控制**，不是 SELinux 标签。所以看门狗与机器人都以 root 身份运行；脚本文件仍然投递到 Termux 目录并 `chown` 给 Termux UID，方便用户查看和修改。

> 这意味着机器人进程拥有 root 权限，请只在自己完全掌控的设备上使用，并审阅上游代码。详见 [安全说明](#安全说明)。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| Root | Magisk 24+（或 KernelSU / APatch，需支持标准模块目录） |
| Termux | 从 [F-Droid](https://f-droid.org/packages/com.termux/) 或 GitHub 安装，**不要用 Play 商店版**（已停止更新且路径不同） |
| Python | Termux 内 `pkg install python`（3.11+ 实测可用） |
| 网络 | 能在手机内直连 `api.telegram.org`（国内网络需自行准备代理） |
| 存储 | 约 20 MB（源码 7 MB + 数据库随群消息量增长） |

## 安装

### 第 1 步：在 Termux 里部署机器人

打开 Termux，执行：

```bash
pkg install -y git python
curl -fsSL https://raw.githubusercontent.com/zhangdunlong/groupguard-android/main/scripts/install-bot.sh -o install-bot.sh
bash install-bot.sh
```

脚本会依次完成：克隆上游源码到 `~/groupguard` → 安装依赖 → 生成 `run.sh` → 引导你粘贴 BotFather Token（输入不回显）→ 写 `.env`（权限 600）。

Token 从 [@BotFather](https://t.me/BotFather) 的 `/newbot` 获取，形如 `123456789:AAH...`。

先手动跑一次确认能起来（看到启动日志后按 `Ctrl-C`）：

```bash
cd ~/groupguard && bash run.sh
```

### 第 2 步：安装 Magisk 模块

1. 到 [Releases](https://github.com/zhangdunlong/groupguard-android/releases) 下载 `groupguard-magisk-v1.1.1.zip`
2. Magisk → **模块** → **从本地安装** → 选中 zip
3. 重启手机

也可以用 adb 刷入：

```bash
adb push groupguard-magisk-v1.1.1.zip /data/local/tmp/
adb shell su -c "magisk --install-module /data/local/tmp/groupguard-magisk-v1.1.1.zip"
adb reboot
```

### 第 3 步：验证

重启后等 1 分钟左右，在 Termux 或 `adb shell` 里执行：

```bash
su -c 'sh /data/adb/modules/groupguard/bin/gg-status.sh'
```

正常输出应当包含：

```
--- 进程 ---
  看门狗    : 运行中 (PID xxxxx)
  机器人    : 运行中 (PID xxxxx)
  运行时长  : 00:01:23
```

然后在 Telegram 里给机器人发 `/start`，能收到管理面板即全部就绪。

## 命令速查

所有管理脚本都在 `/data/adb/modules/groupguard/bin/` 下，需要 root 执行。

| 操作 | 命令 |
| --- | --- |
| 查看状态 | `su -c 'sh /data/adb/modules/groupguard/bin/gg-status.sh'` |
| 查看日志（默认 30 行） | `su -c 'sh /data/adb/modules/groupguard/bin/gg-log.sh 80'` |
| 启动 | `su -c 'sh /data/adb/modules/groupguard/bin/gg-start.sh'` |
| 停止 | `su -c 'sh /data/adb/modules/groupguard/bin/gg-stop.sh'` |
| 重新配置（换 Token / 换目录） | `su -c 'sh /data/adb/modules/groupguard/bin/gg-wizard.sh'` |
| 重新探测环境 | `su -c 'sh /data/adb/modules/groupguard/bin/gg-detect.sh'`（被 source 调用） |

Magisk 应用里点模块的**操作**按钮，等价于执行 `gg-status.sh` —— 不用进终端就能看是否在跑。

## 配置

### `.env`（机器人本体）

位于 `~/groupguard/.env`，由 `install-bot.sh` 或 `gg-wizard.sh` 生成。常用项：

| 变量 | 说明 |
| --- | --- |
| `BOT_TOKEN` | 必填，BotFather 提供的 Token |
| `DB_PATH` | SQLite 路径，默认 `~/groupguard/data/bot.sqlite3` |
| `OWNER_IDS` | 你的 Telegram 数字 ID，逗号分隔；留空则按群管理员权限判定 |
| `API_BASE` | 默认 `https://api.telegram.org`，可指向自建反代 |
| `POLL_TIMEOUT` | 长轮询超时，默认 25 秒 |
| `WITH_OCR` / `OCR_ENABLED` | 图片 OCR，Android 上默认关闭（需额外装 tesseract，Termux 内较重） |

### `gg.conf`（模块运行时）

位于 `/data/adb/modules/groupguard/gg.conf`，**首次开机自动生成**，一般不需要手改。它缓存了探测结果：

```ini
GG_TERMUX_DATA=/data/data/com.termux
GG_TERMUX_PREFIX=/data/data/com.termux/files/usr
GG_TERMUX_HOME=/data/data/com.termux/files/home
GG_UID=10240
GG_APP=/data/data/com.termux/files/home/groupguard
GG_PYTHON=/data/data/com.termux/files/usr/bin/python3
```

模块不写死任何设备相关路径：`gg-detect.sh` 会先用 `pm path com.termux` 确认 Termux 存在，再用 `stat -c %u` 取真实 UID（不同设备 UID 不同），找不到应用目录时还会在 `$HOME` 下按 `app/main.py` 特征搜索。换机型、换 Termux 变体都不用改代码。

## 常见问题

**机器人没起来，`gg-status.sh` 显示“未运行”**

先看开机日志，它是整条启动链最上游的记录：

```bash
su -c 'tail -40 /data/local/tmp/groupguard-boot.log'
```

常见原因：`~/groupguard/.env` 不存在或 Token 格式不对（脚本会用 `^BOT_TOKEN=[0-9]+:` 校验）、没有装 Python、`GG_APP` 路径变了。

**看门狗在跑，但机器人反复重启**

看 `~/groupguard/logs/bot.log`。如果是 `Errno 13`，说明进程没拿到 root 权限（可能被手动以 Termux 身份启动过，先 `gg-stop.sh` 再 `gg-start.sh`）；如果是连接超时，就是手机直连不上 `api.telegram.org`，检查代理。

**日志里出现“网络等待超时，仍尝试启动”**

看门狗启动前会用 `223.5.5.5` 做连通性探测，超时 120 秒。这句只是提示，机器人自身有重连逻辑，不影响最终恢复。

**改了 `.env` 之后没生效**

机器人只在启动时读 `.env`。改完执行 `gg-stop.sh` 再 `gg-start.sh`。

**模块更新后 Magisk 提示有新版本**

`module.prop` 里写了 `updateJson`，指向本仓库的 `update.json`，Magisk 会自动比对 `versionCode` 并给出更新提示。

**`gg-stop.sh` 提示“机器人未响应 TERM，强制结束”，会损坏数据库吗**

不会。机器人在长轮询里最长阻塞 25 秒，收到 TERM 要等这次 `getUpdates` 返回才退出，所以常见结果是强杀。数据库是 SQLite + WAL，进程被 `SIGKILL` 也不会写坏，重启后 WAL 会自动回放。

**想彻底卸载**

在 Magisk 里移除模块即可。`uninstall.sh` 只清进程和临时文件，**不会**删 `~/groupguard`（数据库、Token 都在里面，便于重装后接着用）。要连数据一起删：

```bash
su -c 'rm -rf /data/data/com.termux/files/home/groupguard'
```

## 目录结构

```
groupguard-android/
├── module/                 # Magisk 模块内容（打包后即为 zip 根）
│   ├── module.prop         # 模块元信息 + 自更新地址
│   ├── service.sh          # 开机入口：校验环境 → 投递运行时 → 启动看门狗
│   ├── action.sh           # Magisk「操作」按钮：打印状态
│   ├── uninstall.sh        # 卸载清理（保留数据）
│   └── bin/
│       ├── gg-detect.sh         # 环境探测（Termux/UID/应用目录/Python）
│       ├── gg-deploy-runtime.sh # 把 bin/ 投递到 Termux 可访问目录
│       ├── gg-daemon.sh         # 看门狗：保活、退避重启、日志轮转
│       ├── gg-start.sh          # 手动启动
│       ├── gg-stop.sh           # 手动停止
│       ├── gg-status.sh         # 状态总览
│       ├── gg-log.sh            # 日志查看
│       └── gg-wizard.sh         # 交互式配置向导
├── scripts/
│   ├── install-bot.sh      # Termux 侧一键部署机器人
│   └── build_module.py     # 打包模块 zip
├── docs/design-notes.md    # 设计取舍与踩坑记录
├── update.json             # Magisk 自更新清单
└── CHANGELOG.md
```

## 开发者

改完 `module/` 下的文件后打包：

```bash
python3 scripts/build_module.py
# → dist/groupguard-magisk-v1.1.1.zip
```

发版时同步三处版本号：`module/module.prop` 的 `version`/`versionCode`、`update.json`、`CHANGELOG.md`，然后把 zip 上传为 release 附件。

脚本本身没有构建依赖，直接放进模块目录就会在开机时运行；调试时不必刷机，把改好的脚本推到设备上执行即可：

```bash
adb push module/bin/gg-daemon.sh /data/adb/modules/groupguard/bin/
adb shell su -c 'sh /data/adb/modules/groupguard/bin/gg-stop.sh'
adb shell su -c 'sh /data/adb/modules/groupguard/bin/gg-start.sh'
```

## 安全说明

- 机器人以 **root** 身份运行（原因见上文 UID 实测）。Token 泄露或上游代码被投毒，影响范围就是整台设备。
- `.env` 权限设为 `600`，属主是 Termux UID；任何脚本都不会把 Token 打印到日志。
- 本仓库不含任何密钥、个人域名或设备标识。
- 上游项目未声明开源许可证，本仓库因此**不内嵌其源码**，只提供安装脚本与保活外壳。

## 致谢

- [slobys/telegram-group-manager](https://github.com/slobys/telegram-group-manager) —— GroupGuard 机器人本体
- [Magisk](https://github.com/topjohnwu/Magisk) —— 模块框架
- [Termux](https://termux.dev/) —— Android 上的 Linux 环境

## 许可

本仓库的模块脚本与文档以 MIT 许可证发布，详见 [LICENSE](LICENSE)。
机器人本体版权归上游作者所有，按其项目声明使用。
