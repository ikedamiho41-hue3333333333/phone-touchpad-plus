# Phone Touchpad Plus

[中文说明](README.zh-CN.md)

Phone Touchpad Plus turns an iPhone browser into a touchpad and keyboard for a Linux desktop. Release **v0.1.0** adds a Simplified Chinese mobile interface, independent pointer and scroll sensitivity, protected pairing-secret storage, LAN-aware pairing, and GNOME-style multi-touch gestures.

This fork is based on [Unrud/remote-touchpad v1.5.5](https://github.com/Unrud/remote-touchpad/tree/v1.5.5) and is licensed under **GPL-3.0-or-later**.

## Supported scope

v0.1.0 is source-only and validated on **Ubuntu 24.04 with GNOME X11**, using an iPhone with Safari. Use it only on a **trusted local network (trusted LAN)**: pairing is authenticated, but transport has **no TLS**.

Windows, macOS, and Wayland do not provide the Phone Touchpad Plus enhanced gestures in v0.1.0. Their inherited upstream code and the `desktop/`, `flatpak/`, and `snap/` metadata remain reference material, not supported Phone Touchpad Plus binary release channels.

## Install and pair

Requirements: Go 1.26 or newer, `curl`, and the Ubuntu development packages `libx11-dev`, `libxrandr-dev`, `libxtst-dev`, and `libxt-dev`.

```bash
git clone https://github.com/ikedamiho41-hue3333333333/phone-touchpad-plus.git
cd phone-touchpad-plus
bash scripts/install.sh --dry-run
bash scripts/install.sh
```

The installer creates a systemd user service and a private QR image at `${HOME}/.local/share/phone-touchpad-plus/pairing.png`. Scan it with the iPhone Camera app, open the page in Safari, and optionally add it to the Home Screen. The pairing URL fragment is a secret; do not paste it into issues or logs.

## Operate and maintain

Run read-only diagnostics:

```bash
bash scripts/doctor.sh
```

Pointer and scroll sensitivity are separate values in `${HOME}/.config/phone-touchpad-plus/settings.env`. Restart `phone-touchpad-plus.service` after an authorized edit.

Update while preserving the secret and settings:

```bash
git pull --ff-only
bash scripts/install.sh --upgrade
```

Uninstall the application while keeping configuration, or explicitly purge it:

```bash
bash scripts/uninstall.sh --dry-run
bash scripts/uninstall.sh
bash scripts/uninstall.sh --purge-config
```

## Codex Skill

The discoverable Skill lives at `skills/phone-touchpad-plus`. Copy that directory into `${CODEX_HOME:-$HOME/.codex}/skills/`, then invoke `$phone-touchpad-plus` for install, pairing, status, sensitivity, diagnosis, update, or uninstall requests. It runs diagnosis read-only and requires authorization before system changes.

For gesture details, reconnect behavior, troubleshooting statuses, permissions, and safe maintenance, see the [complete Chinese guide](README.zh-CN.md).
