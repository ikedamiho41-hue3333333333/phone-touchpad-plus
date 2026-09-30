---
name: phone-touchpad-plus
description: Use when installing, pairing, checking status, changing sensitivity, diagnosing, updating, or uninstalling Phone Touchpad Plus on a supported Linux desktop.
---

# Phone Touchpad Plus

Manage the Phone Touchpad Plus iPhone-to-desktop touchpad service through the repository's tested lifecycle scripts. The supported v0.1.0 target is Ubuntu 24.04 with GNOME X11, an iPhone using Safari, and a trusted local network or LAN.

## Workflow

For status or connection problems, run the bundled read-only wrapper first, resolving this relative path from the directory containing `SKILL.md`:

```bash
bash scripts/run-doctor.sh
```

Interpret its `STATUS` before proposing a change:

| Status | Meaning |
|---|---|
| `SERVICE_MANAGER_UNAVAILABLE` | The user service manager cannot be queried. |
| `INSTALLATION_INCOMPLETE` | Required files, settings, or private permissions are invalid. |
| `SERVICE_STOPPED` | The user service is not running. |
| `PHONE_ADDRESS_UNREACHABLE` | The local web or WebSocket address is unavailable. |
| `GRAPHICAL_SESSION_UNAVAILABLE` | X11 display credentials are unavailable. |
| `AUTHENTICATION_FAILED` | The installed pairing secret was rejected. |
| `OK` | Service, session, network, and authentication checks passed. |

Resolve the checkout for lifecycle commands with `bash scripts/resolve-repo.sh`. Use the returned path; do not duplicate installer, diagnostic, or uninstall logic in ad hoc commands.

## Authorization boundary

Read-only inspection may proceed. Obtain explicit user authorization immediately before any mutation.

| Operation | Authorization required? | Repository command after authorization |
|---|---|---|
| Diagnose or view status | No | `bash scripts/run-doctor.sh` |
| Preview installation | No | `bash "$repo/scripts/install.sh" --dry-run` |
| Install or update | Yes | `bash "$repo/scripts/install.sh"` or add `--upgrade` |
| Change sensitivity and restart | Yes | Edit `settings.env`, then restart the user service |
| Change firewall rules | Yes | Use the platform's firewall tool only for the required trusted-LAN port |
| Uninstall | Yes | `bash "$repo/scripts/uninstall.sh"`; add `--purge-config` only when separately requested |

If dependencies are missing, report them and ask before using a system package manager. For sensitivity, change `PTP_MOVE_SPEED` and `PTP_SCROLL_SPEED` independently. Preserve the untouched value and existing secret. Pair using the installed local QR image; if it is missing, diagnose before regenerating anything.

Never print a secret or pairing URL fragment in chat, logs, commands, or diagnostic summaries. Report the redacted status and evidence. On failure, stop after the verified result; do not loop through installs, restarts, firewall changes, updates, or uninstalls.
