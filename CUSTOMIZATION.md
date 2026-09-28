# Phone Touchpad Plus 修改说明

修改日期：2026-09-29

本项目基于 [Unrud/remote-touchpad](https://github.com/Unrud/remote-touchpad)
1.5.5，遵循 GPL-3.0-or-later 许可证。底层复用其 WebSocket、HMAC 挑战认证、
网页触控板和 X11 输入注入实现。

本地定制增加：

- 简体中文、iPhone 主屏幕元数据和触控反馈；
- 三指/四指上滑打开 GNOME 活动概览；
- 三指/四指下滑显示桌面；
- 三指/四指左右滑在当前工作区切换应用窗口；
- 双指捏合向当前应用发送放大/缩小快捷键；
- 屏幕底部提供上述动作的可点击后备按钮；
- 有限手势动作协议；网页不能发送任意系统命令。

## 构建与测试

```sh
go test -tags=x11 ./...
go test -tags=null ./...
node --test tests/*.test.mjs
go build -tags=x11 -trimpath -o phone-touchpad-plus .
```

服务仅供可信局域网使用。认证密钥放在 URL 的 fragment 中，不会随 HTTP 请求发送，
WebSocket 使用 HMAC-SHA256 挑战认证；但当前局域网传输没有 TLS，不应在公共 Wi-Fi 使用。
