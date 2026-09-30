# Phone Touchpad Plus fork notice

Modification date: 2026-09-29

Phone Touchpad Plus v0.1.0 is based on [Unrud/remote-touchpad v1.5.5](https://github.com/Unrud/remote-touchpad/tree/v1.5.5) and remains licensed under GPL-3.0-or-later. The fork retains the upstream WebSocket transport, HMAC challenge authentication, browser touchpad, platform controllers, history, and copyright notices.

## Fork changes

- Simplified Chinese, iPhone-oriented interface and Home Screen metadata.
- X11 enhanced gestures for GNOME overview, show desktop, current-workspace application switching, and application zoom.
- Gesture capability negotiation so unsupported backends keep basic pointer input without exposing unavailable controls.
- Independent pointer and scroll sensitivity, including a regression fix that prevents scroll drift from becoming pinch zoom.
- Secret-file authentication, private configuration permissions, LAN/default-route host selection, mDNS preference, and private QR storage.
- User-level install, read-only diagnosis, conservative uninstall, Codex Skill, protocol integration tests, and repository privacy gates.

## Supported release scope

The v0.1.0 release is source-only and validated on Ubuntu 24.04 GNOME X11 with iPhone Safari on a trusted LAN. It authenticates pairing but does not provide TLS. Enhanced gestures on Windows, macOS, and Wayland are outside this release.

The inherited `desktop/`, `flatpak/`, and `snap/` files still use upstream identities. They are retained for attribution and future porting work; they are not tested or published as Phone Touchpad Plus v0.1.0 binary channels.

## Build and verification

```bash
go test -tags=x11 ./...
go test -tags=null ./...
node --test tests/*.test.mjs
bash tests/run-live-protocol.sh
bash tests/check-repository.sh --self-test
go build -tags=x11 -trimpath -o phone-touchpad-plus .
```

Pairing secrets, QR images, machine-specific service files, host names, private network addresses, and developer paths must never be committed.
