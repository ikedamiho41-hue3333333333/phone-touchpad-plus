# Phone Touchpad Plus 中文指南

Phone Touchpad Plus 可把 iPhone 的 Safari 页面变成 Linux 或 macOS 电脑的触控板和键盘。**v0.1.0** 提供简体中文界面、指针与滚动独立灵敏度、受保护的配对密钥、局域网地址选择，以及多指手势。

本项目基于 [Unrud/remote-touchpad v1.5.5](https://github.com/Unrud/remote-touchpad/tree/v1.5.5)，采用 **GPL-3.0-or-later** 许可证。

## 支持范围与安全提示

v0.1.0 是仅提供源码的首版，主要验证环境为 **Ubuntu 24.04 + GNOME X11**，手机端为 iPhone Safari。当前源码还提供 macOS Apple Silicon 安装脚本、LaunchAgent 常驻服务和 macOS 增强手势映射。

只能在家庭等**可信局域网**中使用。连接使用配对密钥和 HMAC 挑战认证，但当前传输**不提供 TLS**；不要在公共 Wi‑Fi 使用，也不要把配对链接、二维码或密钥发到聊天、Issue 或日志中。

Windows 和 Wayland 当前不支持 Phone Touchpad Plus 增强手势。仓库中的 `desktop/`、`flatpak/`、`snap/` 以及其他平台代码继承自上游，仅作为参考，不是 v0.1.0 已支持的二进制安装渠道。

## Ubuntu 24.04 GNOME X11 安装

准备条件：

- Go 1.26 或更高版本；
- `curl`；
- Ubuntu 构建依赖：`libx11-dev`、`libxrandr-dev`、`libxtst-dev`、`libxt-dev`；
- 已登录 GNOME X11 桌面，而不是 Wayland 会话。

安装系统依赖需要管理员权限，请先确认命令和来源。项目安装本身使用用户目录和 systemd 用户服务：

```bash
git clone https://github.com/ikedamiho41-hue3333333333/phone-touchpad-plus.git
cd phone-touchpad-plus
bash scripts/install.sh --dry-run
bash scripts/install.sh
```

`--dry-run` 只展示目标，不写文件、不编译、不启动服务。正式安装会创建：

- 程序：`${HOME}/.local/lib/phone-touchpad-plus/`；
- 私密配置：`${HOME}/.config/phone-touchpad-plus/`；
- 用户服务：`${HOME}/.config/systemd/user/phone-touchpad-plus.service`；
- 配对二维码：`${HOME}/.local/share/phone-touchpad-plus/pairing.png`。

配置目录权限为 `0700`，密钥与设置文件为 `0600`。服务命令行只接收密钥文件路径，不携带密钥正文。

## macOS Apple Silicon 安装

准备条件：

- Go 1.26 或更高版本；
- Xcode Command Line Tools；
- Mac 与 iPhone 连接同一个可信局域网。

```bash
git clone https://github.com/ikedamiho41-hue3333333333/phone-touchpad-plus.git
cd phone-touchpad-plus
bash scripts/install-macos.sh --dry-run
bash scripts/install-macos.sh
```

安装器会创建与 Linux 版相同的程序、私密配置和二维码目录，并额外创建：

- 常驻服务：`${HOME}/Library/LaunchAgents/com.ikedamiho41.phone-touchpad-plus.plist`；
- 日志：`${HOME}/Library/Logs/Phone Touchpad Plus/`。

第一次启动时，macOS 会要求输入控制权限。在“系统设置 → 隐私与安全性 → 辅助功能”中添加并允许 `${HOME}/Applications/Phone Touchpad Plus`，服务随后会由 LaunchAgent 自动重试。其他辅助程序位于 `${HOME}/.local/lib/phone-touchpad-plus/`。查看服务状态：

```bash
launchctl print "gui/$(id -u)/com.ikedamiho41.phone-touchpad-plus"
```

macOS 手势映射为：三指或四指左右滑切换桌面或全屏空间，上滑打开调度中心，下滑显示桌面，双指捏合向当前应用发送放大或缩小快捷键。应用可以覆盖系统快捷键，因此实际行为以当前 macOS“键盘快捷键”设置为准。

## iPhone 配对与再次连接

1. 安装完成后，在电脑本地查看安装器给出的二维码文件。
2. 用 iPhone 相机扫描二维码，点开 Safari 页面。
3. 页面显示“手机妙控板”且可以移动鼠标后，可在 Safari 分享菜单中选择“添加到主屏幕”。
4. 手机关闭页面后，再次打开保存的主屏幕入口或原 Safari 标签即可；若页面显示“连接已断开”，点刷新按钮。

macOS 可用以下命令打开二维码：

```bash
open "${HOME}/.local/share/phone-touchpad-plus/pairing.png"
```

配对身份保存在 URL 的 fragment 中，不会作为普通 HTTP 请求路径发送，但仍属于秘密。只要没有清除浏览器地址、二维码和电脑端配置，通常不需要重新配对。

## 操作与手势

| 手机操作 | 电脑行为 |
|---|---|
| 一指移动 | 移动指针 |
| 一指轻点 | 左键 |
| 双指轻点 | 右键 |
| 三指轻点 | 中键 |
| 双指同向移动 | 横向或纵向滚动 |
| 双指张开 / 合拢 | 当前应用放大 / 缩小 |
| 三指或四指左滑 / 右滑 | macOS 切换到下一个 / 上一个桌面或全屏空间；GNOME X11 切换应用窗口 |
| 三指或四指上滑 | 打开 GNOME 活动概览或 macOS 调度中心 |
| 三指或四指下滑 | 显示桌面 |

页面底部还有左右切换、活动概览和显示桌面的后备按钮。增强手势仅在服务器声明支持时显示。

## 分别调节指针与滚动灵敏度

编辑 `${HOME}/.config/phone-touchpad-plus/settings.env`：

```text
PTP_BIND_PORT=8765
PTP_MOVE_SPEED=1.5
PTP_SCROLL_SPEED=1.0
PTP_SCROLL_INVERT_Y=false
```

`PTP_MOVE_SPEED` 只影响鼠标移动，`PTP_SCROLL_SPEED` 只影响双指滚动。把 `PTP_SCROLL_INVERT_Y` 改为 `true` 可反转双指上下滚动方向，并保持横向方向不变。修改一个值时保留其他值和密钥文件。保存后需要重启用户服务：

```bash
systemctl --user restart phone-touchpad-plus.service
```

macOS 使用以下命令重启：

```bash
launchctl kickstart -k "gui/$(id -u)/com.ikedamiho41.phone-touchpad-plus"
```

如果由自动化助手操作，编辑配置和重启都应在获得你的明确授权后执行。

## 状态与诊断

诊断脚本严格只读，不会启动、停止或重启服务：

```bash
bash scripts/doctor.sh
```

| 状态 | 含义与处理方向 |
|---|---|
| `SERVICE_MANAGER_UNAVAILABLE` | 无法查询 systemd 用户服务；确认当前系统和用户会话。 |
| `INSTALLATION_INCOMPLETE` | 文件缺失、端口无效或私密权限不安全；重新核对安装。 |
| `SERVICE_STOPPED` | 服务未运行；查看日志后再决定是否授权启动。 |
| `PHONE_ADDRESS_UNREACHABLE` | 本机页面、WebSocket 或手机可达地址不可用；确认同一可信局域网。 |
| `GRAPHICAL_SESSION_UNAVAILABLE` | `DISPLAY` 或 `XAUTHORITY` 不可用；登录 GNOME X11 桌面。 |
| `AUTHENTICATION_FAILED` | 密钥未通过认证；使用当前二维码重新配对，避免泄露旧密钥。 |
| `OK` | 服务、图形会话、网络与认证检查均通过。 |

诊断输出会遮盖密钥和配对 URL fragment。如果问题仍存在，可在不暴露秘密的前提下提供状态分类和已遮蔽日志。

## 安全升级与卸载

升级前拉取已审阅的源码，然后使用显式升级模式；它会保留密钥、端口和两项灵敏度：

```bash
git pull --ff-only
bash scripts/install.sh --upgrade
```

先预览卸载。默认卸载删除程序、用户服务和二维码，但保留配置；只有明确要求时才清除配置与配对信息：

```bash
bash scripts/uninstall.sh --dry-run
bash scripts/uninstall.sh
bash scripts/uninstall.sh --purge-config
```

## 安装与使用 Codex Skill

Skill 源码位于 `skills/phone-touchpad-plus`。在仓库根目录执行：

```bash
skill_root="${CODEX_HOME:-$HOME/.codex}/skills"
mkdir -p "$skill_root"
cp -R skills/phone-touchpad-plus "$skill_root/"
```

重新开始 Codex 会话后，可使用 `$phone-touchpad-plus` 请求安装、配对、查看状态、修改灵敏度、诊断、升级或卸载。Skill 会直接执行只读诊断；安装依赖、改防火墙、编辑配置、重启、升级和卸载前都会保留用户授权边界。

## 发布说明

v0.1.0 不提供预编译二进制、自动 TLS 或自动更新。源码测试覆盖 X11/Null 后端、WebSocket 认证协议、手机端手势、安装/诊断/卸载生命周期、Skill 包和隐私扫描。
