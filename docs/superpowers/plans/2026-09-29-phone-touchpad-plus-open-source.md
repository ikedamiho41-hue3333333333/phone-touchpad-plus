# Phone Touchpad Plus Open-Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a secure, testable `v0.1.0` fork named Phone Touchpad Plus that preserves the current Chinese iPhone touchpad behavior and supplies isolated install, diagnose, uninstall, and Codex Skill workflows.

**Architecture:** Keep the upstream Go/WebSocket server and browser client, add small Go boundaries for build identity, secrets, capabilities, and host selection, then package the X11-first build with user-level shell lifecycle scripts. Treat the application, lifecycle tooling, and Skill/release material as separate reviewable units connected through documented CLI and filesystem contracts.

**Tech Stack:** Go 1.26+, HTML/CSS/JavaScript ES modules, Node.js test runner, Bash, systemd user services, GitHub Actions, GNU GPL-3.0-or-later.

**Spec:** `docs/superpowers/specs/2026-09-29-phone-touchpad-plus-open-source-design.md`

## Global Constraints

- Public identity is `ikedamiho41-hue3333333333/phone-touchpad-plus`; display name is `Phone Touchpad Plus`; first release is `v0.1.0`; upstream baseline is Remote Touchpad `v1.5.5`.
- Preserve `COPYING`, upstream copyright/history, and clearly mark the fork's 2026 modifications.
- Validated target is Ubuntu 24.04, GNOME X11, and iPhone Safari on one trusted LAN; Windows, macOS, and Wayland enhanced gestures remain unverified.
- Do not modify, restart, replace, reconfigure, or test against the live `phone-magic-trackpad.service`, its current secret, port, URL, speed settings, or autostart state.
- Installer tests use a temporary `HOME`, temporary prefix, independent port, and mocked systemd commands; no lifecycle test may write to the real user configuration.
- Pairing secrets must never appear in process arguments, logs, diagnostics, repository files, or GitHub Actions output; secret files use mode `0600` inside a mode `0700` directory.
- The public default move and scroll multipliers are both `1.0`; current machine-specific sensitivity is not migrated into the repository.
- No automatic TLS, prebuilt binaries, auto-update mechanism, or complete enhanced-gesture support for Windows/macOS/Wayland in `v0.1.0`.
- GitHub publication and tag creation happen only after local verification, privacy scanning, and green CI.

## Review Focus

- Empty, unreadable, newline-terminated, or simultaneously supplied `-secret`/`-secret-file` input must fail safely or normalize exactly as documented without leaking the value; Task 3 owns these tests.
- A VPN, container bridge, link-local address, or machine with no private LAN candidate must never silently become the pairing address; Task 4 owns these tests.
- A controller or older server config without gesture capability must leave move/click/scroll usable while hiding or suppressing enhanced gestures; Task 5 owns these tests.
- Reinstall, explicit upgrade, and failed binary replacement must preserve the existing secret and settings and must not leave a partial install; Task 7 owns these tests.
- Missing systemd, missing `DISPLAY`/`XAUTHORITY`, stopped service, bad route, and authentication failure must produce distinct read-only, redacted diagnostics; Task 8 owns these tests.

## Pre-Execution Safety Gate

- [ ] Before Task 1, record a mode-`0600` snapshot outside the repository containing only the live service's `ActiveState`, `ActiveEnterTimestampMonotonic`, `MainPID`, unit checksum, binary checksum, and listening port. Do not query or record `ExecStart`, environment, URL, QR, or any value that could reveal the current secret.
- [ ] Confirm every test command in this plan targets Null backend, a temporary home, a mock command, or source-only unit tests. If a command resolves to `phone-magic-trackpad.service`, stop rather than execute it.

---

### Task 1: Capture the Existing Chinese Gesture Product Baseline

**Files:**
- Modify: `inputcontrol/controller.go`
- Modify: `inputcontrol/controller_null.go`
- Modify: `inputcontrol/controller_x11.go`
- Modify: `main.go`
- Modify: `webdata/app/inputcontroller.mjs`
- Modify: `webdata/app/main.mjs`
- Modify: `webdata/app/touchpad.mjs`
- Modify: `webdata/app/ui.mjs`
- Modify: `webdata/index.html`
- Modify: `webdata/main.css`
- Create: `inputcontrol/controller_x11_test.go`
- Create: `tests/touchpad.test.mjs`

**Interfaces:**
- Consumes: upstream `inputcontrol.Controller`, the one-byte WebSocket command protocol, and browser touch events.
- Produces: `inputcontrol.GestureAction`, `inputcontrol.GestureController.Gesture(GestureAction) error`, WebSocket command `g<action>`, and Chinese gesture controls whose behavior is pinned by regression tests.

- [ ] **Step 1: Add characterization tests for the already-written working-tree behavior**

  In `inputcontrol/controller_x11_test.go`, assert `GestureAppPrevious` maps to Alt+Shift+Tab and `GestureAppNext` maps to Alt+Tab. In `tests/touchpad.test.mjs`, retain the two-finger-drift regression and add named cases for pinch-in/out, three-finger horizontal application switching, upward overview, and downward show-desktop commands.

- [ ] **Step 2: Run the focused tests as a baseline**

  Run: `go test -tags=x11 ./inputcontrol && node --test tests/touchpad.test.mjs`

  Expected: PASS. These are characterization tests for behavior that already exists locally; a failure means repair the existing change before continuing.

- [ ] **Step 3: Review the finite gesture protocol and touch classifier**

  Confirm `processCommand` accepts only enum values in `[0, GestureLimit)`, no gesture path executes arbitrary text or shell commands, and pinch classification requires opposite finger motion before sending zoom. Keep move and scroll multipliers independent.

- [ ] **Step 4: Run the full current behavior suite**

  Run: `go test -tags=x11 ./... && go test -tags=null ./... && node --test tests/*.test.mjs`

  Expected: all packages and Node tests PASS.

- [ ] **Step 5: Commit the product behavior separately**

  ```bash
  git add inputcontrol/controller.go inputcontrol/controller_null.go inputcontrol/controller_x11.go inputcontrol/controller_x11_test.go main.go webdata tests/touchpad.test.mjs
  git commit -m "feat: add Chinese multi-touch controls"
  ```

### Task 2: Establish Fork Identity and a Single Version Source

**Files:**
- Create: `internal/buildinfo/buildinfo.go`
- Create: `internal/buildinfo/buildinfo_test.go`
- Modify: `go.mod`
- Modify: `main.go`
- Modify: all Go imports returned by `rg 'github.com/unrud/remote-touchpad' -g '*.go'`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: no earlier task-specific API.
- Produces: `buildinfo.AppName`, `buildinfo.Version`, `buildinfo.UpstreamName`, and `buildinfo.UpstreamVersion` constants plus `writeVersion(io.Writer) error`, used by CLI output and release checks.

- [ ] **Step 1: Write failing identity tests**

  Add `TestReleaseIdentity` asserting app name `Phone Touchpad Plus`, version `0.1.0`, upstream name `Remote Touchpad`, and upstream version `1.5.5`. Add `TestWriteVersion` asserting `writeVersion` writes exactly `0.1.0` plus a newline; the release gate later executes the built binary with `-version`.

- [ ] **Step 2: Verify the tests fail on upstream identity**

  Run: `go test ./internal/buildinfo ./...`

  Expected: FAIL because `internal/buildinfo` and the new CLI seam do not exist.

- [ ] **Step 3: Add the build identity package and migrate the module**

  Define the four constants in `internal/buildinfo/buildinfo.go`; change the module to `github.com/ikedamiho41-hue3333333333/phone-touchpad-plus`; update internal imports; make terminal title and `-version` read the constants instead of local literals.

- [ ] **Step 4: Record the fork version without rewriting upstream history**

  Prepend a `0.1.0 (2026-09-29)` section to `CHANGELOG.md` that names the upstream `1.5.5` baseline and summarizes the fork's Chinese UI, gestures, security, lifecycle scripts, and tests.

- [ ] **Step 5: Verify module and identity consistency**

  Run: `go test -tags=null ./... && go list -m`

  Expected: tests PASS and module output is `github.com/ikedamiho41-hue3333333333/phone-touchpad-plus`.

- [ ] **Step 6: Commit**

  ```bash
  git add go.mod go.sum main.go internal/buildinfo CHANGELOG.md
  git add inputcontrol terminal tools
  git commit -m "chore: establish Phone Touchpad Plus identity"
  ```

### Task 3: Load Pairing Secrets Without Process or Log Exposure

**Files:**
- Create: `secret.go`
- Create: `secret_test.go`
- Modify: `main.go`
- Modify: `live_protocol_integration_test.go`

**Interfaces:**
- Consumes: CLI values for `-secret`, new `-secret-file`, and new `-show-pairing` flags.
- Produces: `resolveSecret(secretArg string, secretFile string) (string, error)`, `generateSecret(reader io.Reader, byteLength int) (string, error)`, and `maybeWritePairingOutput(w io.Writer, pairingURL string, colorize bool, enabled bool) error`; the server uses only the returned in-memory secret.

- [ ] **Step 1: Write failing secret boundary tests**

  Add table tests asserting: a `0600` file with one trailing LF or CRLF returns the content without the line ending; an empty file, embedded newline, unreadable file, or simultaneous non-empty `-secret` and `-secret-file` returns an error that contains no secret; generation returns Base64 for exactly 12 input bytes. Add an output test asserting `maybeWritePairingOutput(..., false)` never writes the URL fragment or QR data.

- [ ] **Step 2: Verify tests fail**

  Run: `go test -tags=null -run 'Test(ResolveSecret|GenerateSecret|PairingOutput)' ./...`

  Expected: FAIL because the functions and flags do not exist.

- [ ] **Step 3: Implement the secret boundary**

  Implement the two exact functions in `secret.go`. Register `-secret-file` and `-show-pairing` in `main.go`; reject conflicting secret sources; generate a random secret only when neither source is provided; keep secret values out of all formatted errors.

- [ ] **Step 4: Suppress pairing material in service mode**

  Refactor pairing URL/QR printing behind `-show-pairing`; interactive default remains `true`, while the future systemd unit will pass `false`. Extend the live protocol fixture to start the server with `-secret-file` and ensure authentication still succeeds.

- [ ] **Step 5: Verify security behavior**

  Run: `go test -tags=null ./...`

  Expected: PASS; test output contains neither fixture secret nor URL fragment.

- [ ] **Step 6: Commit**

  ```bash
  git add main.go secret.go secret_test.go live_protocol_integration_test.go
  git commit -m "feat: read pairing secret from protected file"
  ```

### Task 4: Select a Phone-Reachable LAN Address

**Files:**
- Modify: `host.go`
- Create: `host_test.go`
- Create: `host_route_linux.go`
- Create: `host_route_linux_test.go`
- Create: `host_route_other.go`
- Modify: `main.go`

**Interfaces:**
- Consumes: interface name, flags, IP address, and Linux default-route interface when available.
- Produces: `hostCandidate{Name string, IP net.IP, DefaultRoute bool}`, `selectHosts([]hostCandidate) (primary string, alternatives []string, err error)`, `findDefaultHosts() (string, []string, error)`, and `writeHosts(io.Writer, primary string, alternatives []string) error`.

- [ ] **Step 1: Write failing host-ranking tests**

  Test that an up, private IPv4 candidate on the default-route Wi-Fi/Ethernet interface beats a VPN address; names beginning with `tun`, `tap`, `wg`, `tailscale`, `docker`, `br-`, `veth`, `virbr`, or `zt` are excluded; loopback and link-local are excluded; private IPv4 beats global IPv6; and no eligible candidate returns a descriptive error plus candidates rather than silently selecting `localhost`.

- [ ] **Step 2: Write failing Linux route-parser tests**

  Add `parseDefaultRouteInterface(io.Reader) (string, error)` tests using synthetic `/proc/net/route` fixtures for one default route, malformed rows, and no default route.

- [ ] **Step 3: Verify tests fail**

  Run: `go test -tags=null -run 'Test(SelectHosts|ParseDefaultRoute)' ./...`

  Expected: FAIL because the selection boundary does not exist.

- [ ] **Step 4: Implement deterministic selection and alternatives**

  Collect active interface addresses, mark the Linux default-route interface, filter virtual/tunnel/container/link-local entries, rank eligible private IPv4 candidates first, and return explicit alternatives for ambiguity. On non-Linux platforms, return no default-route hint without breaking compilation. Add `-print-hosts` to output one non-secret selected host per line and exit before initializing an input controller.

- [ ] **Step 5: Add mDNS and URL presentation without trusting it blindly**

  If `<hostname>.local` resolves to the chosen LAN address, present it first; always retain the chosen IPv4 fallback. Print/encode the primary pairing URL and print redacted alternative host guidance without duplicating the secret into logs when `-show-pairing=false`.

- [ ] **Step 6: Verify cross-platform compilation and ranking**

  Run: `go test -tags=null ./... && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go test ./... && GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go test ./...`

  Expected: PASS, with platform-incompatible tests excluded by build tags.

- [ ] **Step 7: Commit**

  ```bash
  git add host.go host_test.go host_route_linux.go host_route_linux_test.go host_route_other.go main.go
  git commit -m "fix: prefer reachable local network addresses"
  ```

### Task 5: Negotiate Enhanced-Gesture Capability

**Files:**
- Modify: `main.go`
- Create: `main_test.go`
- Modify: `webdata/app/inputcontroller.mjs`
- Modify: `webdata/app/ui.mjs`
- Modify: `webdata/app/touchpad.mjs`
- Modify: `webdata/index.html`
- Create: `tests/capabilities.test.mjs`
- Modify: `live_protocol_integration_test.go`

**Interfaces:**
- Consumes: whether the selected controller implements `inputcontrol.GestureController`.
- Produces: Go `capabilities{Gestures bool}` from `controllerCapabilities(inputcontrol.Controller) capabilities`, JSON `config.capabilities.gestures`, and `InputController.gesture(action)` returning `true` only when it sent a command and `false` when gestures are unavailable.

- [ ] **Step 1: Write failing Go capability tests**

  Use one fake base controller and one fake gesture controller. Assert `controllerCapabilities` reports `false` and `true` respectively, and `processCommand` returns the existing unsupported error for `g` commands on the base controller without affecting pointer commands.

- [ ] **Step 2: Write failing browser capability tests**

  Assert configs with `capabilities.gestures: true` send `g<action>` and reveal `.gesture-capability`; `false` or a missing `capabilities` object sends nothing, returns `false`, and hides those controls while move/click/scroll messages still send.

- [ ] **Step 3: Verify tests fail**

  Run: `go test -tags=null -run 'TestControllerCapabilities' ./... && node --test tests/capabilities.test.mjs`

  Expected: FAIL because capability negotiation is absent.

- [ ] **Step 4: Implement server and browser negotiation**

  Add `capabilities` to the WebSocket config after controller selection. Gate gesture sends and gesture feedback in the client, mark the guide/dock/buttons with `.gesture-capability`, and default missing capability data to disabled for compatibility with older servers.

- [ ] **Step 5: Verify base controls and live config**

  Extend the Null-backend integration assertion to require `capabilities.gestures == true`. Run: `go test -tags=null ./... && node --test tests/*.test.mjs`.

  Expected: PASS.

- [ ] **Step 6: Commit**

  ```bash
  git add main.go main_test.go live_protocol_integration_test.go webdata tests/capabilities.test.mjs
  git commit -m "feat: negotiate enhanced gesture support"
  ```

### Task 6: Make Protocol and Regression Tests Actually Execute

**Files:**
- Create: `tests/run-live-protocol.sh`
- Create: `tests/check-repository.sh`
- Modify: `.github/workflows/test.yaml`
- Delete: `.github/workflows/build-release.yaml`
- Create: `.gitignore`

**Interfaces:**
- Consumes: binary flags from Tasks 3-5 and existing Go/Node tests.
- Produces: `tests/run-live-protocol.sh [go-command]` with cleanup traps and `tests/check-repository.sh` returning nonzero on private artifacts or missing license/attribution.

- [ ] **Step 1: Write the live-test runner with an intentional preflight failure**

  Have the runner allocate the fixed isolated test port `18765`, fail if already occupied, create a temporary secret file, start `go run -tags=null . -bind 127.0.0.1:18765 -secret-file <temp> -show-pairing=false`, wait for HTTP readiness with a timeout, run `go test -tags='null integration' -run TestLiveProtocol`, and always terminate only the PID it started.

- [ ] **Step 2: Execute the runner locally**

  Run: `bash tests/run-live-protocol.sh`

  Expected: PASS and no process remains listening on `18765` afterward.

- [ ] **Step 3: Add repository privacy/license checks**

  Scan `git ls-files --cached --others --exclude-standard` for secret-shaped values, private IPs, the local OS username/hostname, personal absolute paths, QR images, and live service configuration; explicitly allow the public GitHub owner string and documentation-range IP fixtures. At this stage assert `COPYING`, upstream attribution, and the modification date; Task 10 adds the complete bilingual documentation assertions.

- [ ] **Step 4: Add safe ignore rules**

  Ignore generated binaries, coverage, temporary directories, local settings, secret files, generated QR files, and editor state without ignoring service templates or test fixtures.

- [ ] **Step 5: Update CI to run behavior rather than compile-only checks**

  Keep upstream platform compile/test coverage, add explicit X11 dependencies, `node --test tests/*.test.mjs`, ShellCheck for the scripts that now exist, `tests/run-live-protocol.sh`, and `tests/check-repository.sh`. Remove the prebuilt Windows/macOS release workflow because `v0.1.0` is source-only; Tasks 7-9 extend CI as each lifecycle/Skill test becomes available.

- [ ] **Step 6: Verify the gate**

  Run: `bash tests/check-repository.sh --self-test && bash tests/check-repository.sh && bash tests/run-live-protocol.sh && node --test tests/*.test.mjs`

  Expected: PASS; `--self-test` creates a trap-protected untracked fixture, proves it is detected, removes it, and proves the clean repository passes.

- [ ] **Step 7: Commit**

  ```bash
  git add .gitignore .github/workflows/test.yaml tests
  git rm .github/workflows/build-release.yaml
  git commit -m "test: enforce release and protocol gates"
  ```

### Task 7: Build an Isolated User Installer and Safe Upgrade Path

**Files:**
- Create: `scripts/lib/common.sh`
- Create: `scripts/install.sh`
- Create: `scripts/run-service.sh`
- Create: `scripts/templates/phone-touchpad-plus.service.in`
- Modify: `tools/makeqr/main.go`
- Create: `tools/makeqr/main_test.go`
- Create: `tests/scripts/install_test.sh`
- Modify: `.github/workflows/test.yaml`

**Interfaces:**
- Consumes: `--dry-run`, `--upgrade`, optional `--prefix`, and test-only command overrides `PTP_SYSTEMCTL`/`PTP_GO`; application flags `-secret-file`, `-show-pairing=false`, `-print-hosts`, `-move-speed`, and `-scroll-speed`.
- Produces: application and QR helper binaries under `${HOME}/.local/lib/phone-touchpad-plus/`, config under `${XDG_CONFIG_HOME:-$HOME/.config}/phone-touchpad-plus/`, data under `${XDG_DATA_HOME:-$HOME/.local/share}/phone-touchpad-plus/`, and `phone-touchpad-plus.service` under the user systemd directory.

- [ ] **Step 1: Write failing isolated install tests**

  In a `mktemp -d` home with mocked `systemctl` and build commands, assert `--dry-run` creates nothing and calls nothing; fresh install creates mode `0700` config and mode `0600` secret/QR, settings default to move/scroll `1.0`, and the unit references only the secret file path; normal reinstall stops before mutation; `--upgrade` preserves secret/settings; failed staged binary verification leaves the prior binary and unit unchanged.

- [ ] **Step 2: Verify the lifecycle tests fail**

  Run: `bash tests/scripts/install_test.sh`

  Expected: FAIL because the installer does not exist.

- [ ] **Step 3: Implement shared path, logging, and atomic-write helpers**

  In `scripts/lib/common.sh`, define path resolution, `run`, `atomic_install`, redacted logging, command detection, and mode checks. All helpers honor the supplied temporary `HOME`/prefix; no helper contains a developer-specific absolute path. In `scripts/run-service.sh`, load only the non-secret settings, resolve session display authorization, and `exec` the application with a secret-file path rather than secret content.

- [ ] **Step 4: Implement preflight and dry-run behavior**

  Detect Linux, GNOME/X11, effective UID, `DISPLAY`, usable `XAUTHORITY`, Go version from `go.mod`, and X11 build dependencies. Print exact missing dependencies and stop; never run a system package manager automatically. Import `DISPLAY`/`XAUTHORITY` into user systemd only during a real authorized install.

- [ ] **Step 5: Implement fresh install and explicit upgrade**

  Build the application and `tools/makeqr` to temporary files, execute version/helper checks, atomically replace the targets, generate a secret only for fresh install, render the service launcher with `-secret-file` and `-show-pairing=false`, preserve existing settings in `--upgrade`, then daemon-reload/enable/start through the injectable systemctl command. Change `tools/makeqr` to read the full pairing URL from standard input and accept only the output path as an argument so the secret never enters its process arguments.

- [ ] **Step 6: Produce and verify pairing output safely**

  Read candidate hosts from `-print-hosts`, combine the primary host and configured port with the secret in shell memory, feed the full URL to the QR helper over standard input, create the QR file as `0600`, and print the interactive URL plus IPv4 fallback. Probe the actual HTTP listening address without its fragment and separately assert that the displayed URL contains a non-empty `#` fragment.

- [ ] **Step 7: Verify isolation and process arguments**

  Add the isolated installer test to CI. Run: `go test ./tools/makeqr && bash tests/scripts/install_test.sh && shellcheck scripts/*.sh scripts/lib/*.sh tests/scripts/*.sh`

  Expected: PASS; the recorded mocked `ExecStart` contains the secret path but not the secret content, and no file outside the temporary home changes.

- [ ] **Step 8: Commit**

  ```bash
  git add scripts/lib/common.sh scripts/install.sh scripts/run-service.sh scripts/templates tools/makeqr tests/scripts/install_test.sh .github/workflows/test.yaml
  git commit -m "feat: add safe user-level installer"
  ```

### Task 8: Add Read-Only Diagnostics and Conservative Uninstall

**Files:**
- Create: `scripts/doctor.sh`
- Create: `scripts/uninstall.sh`
- Create: `internal/protocol/auth.go`
- Create: `internal/protocol/auth_test.go`
- Create: `tools/probe/main.go`
- Create: `tools/probe/main_test.go`
- Modify: `main.go`
- Modify: `live_protocol_integration_test.go`
- Modify: `scripts/install.sh`
- Create: `tests/scripts/doctor_test.sh`
- Create: `tests/scripts/uninstall_test.sh`
- Modify: `.github/workflows/test.yaml`

**Interfaces:**
- Consumes: paths and redaction helpers from `scripts/lib/common.sh`; `uninstall.sh` accepts `--dry-run` and explicit `--purge-config`.
- Produces: `protocol.ChallengeResponse(challenge string, secret string) string`, `phone-touchpad-plus-probe -url <ws-url> -secret-file <path>`, doctor result categories `SERVICE_STOPPED`, `PHONE_ADDRESS_UNREACHABLE`, `GRAPHICAL_SESSION_UNAVAILABLE`, `AUTHENTICATION_FAILED`, and `OK`; uninstall preserves config unless purging was explicitly requested.

- [ ] **Step 1: Write failing doctor tests for the Review Focus conditions**

  Mock systemd, route, HTTP, session environment, and logs. Assert each named category is distinct; output masks any secret and URL fragment; missing systemd reports unsupported service management without attempting installation or mutation.

- [ ] **Step 2: Write failing uninstall tests**

  Assert default uninstall stops/disables the mocked unit and removes installed binary/unit/data QR while retaining config/secret; `--purge-config` removes only the resolved Phone Touchpad Plus config directory after exact-path validation; `--dry-run` mutates nothing.

- [ ] **Step 3: Verify tests fail**

  Run: `bash tests/scripts/doctor_test.sh && bash tests/scripts/uninstall_test.sh`

  Expected: FAIL because the scripts do not exist.

- [ ] **Step 4: Implement the authenticated probe**

  Move the shared HMAC-SHA256 response calculation into `internal/protocol` and use it from the server integration test and probe. Accept a WebSocket URL without a fragment and a secret-file path, return distinct exit codes for connection and authentication failure, and never echo the secret, challenge response, or complete pairing URL. Add the helper to the installer's staged/atomic binaries.

- [ ] **Step 5: Implement doctor as strictly read-only**

  Check service status, listening port, selected LAN/default route, mDNS resolution, `DISPLAY`, `XAUTHORITY`, required files/modes, the authenticated probe, and recent redacted errors. Do not call enable/start/restart or write any file.

- [ ] **Step 6: Implement conservative uninstall**

  Validate every target is below the resolved temporary or user prefix, stop/disable through the injected systemctl command, remove application artifacts, and retain config unless `--purge-config` is present. Never use recursive deletion on an unresolved or broad path.

- [ ] **Step 7: Verify lifecycle tools**

  Add probe/doctor/uninstall tests to CI. Run: `go test ./internal/protocol ./tools/probe && bash tests/scripts/doctor_test.sh && bash tests/scripts/uninstall_test.sh && shellcheck scripts/*.sh scripts/lib/*.sh tests/scripts/*.sh`

  Expected: PASS and fixture secrets are absent from captured output.

- [ ] **Step 8: Commit**

  ```bash
  git add scripts/doctor.sh scripts/uninstall.sh scripts/install.sh internal/protocol tools/probe main.go live_protocol_integration_test.go tests/scripts .github/workflows/test.yaml
  git commit -m "feat: add redacted diagnostics and uninstall"
  ```

### Task 9: Package the Codex Skill

**Files:**
- Create: `skills/phone-touchpad-plus/SKILL.md`
- Create: `skills/phone-touchpad-plus/scripts/resolve-repo.sh`
- Create: `skills/phone-touchpad-plus/scripts/run-doctor.sh`
- Create: `tests/skill_test.sh`
- Modify: `.github/workflows/test.yaml`

**Interfaces:**
- Consumes: repository lifecycle scripts from Tasks 7-8 and optional `PHONE_TOUCHPAD_PLUS_REPO` override.
- Produces: a discoverable `phone-touchpad-plus` Skill that routes install, pair, status, sensitivity, diagnose, update, and uninstall requests while preserving authorization boundaries.

- [ ] **Step 1: Invoke the required skill-authoring guidance**

  Before editing, read and follow `skill-creator` and `superpowers:writing-skills`. Keep the Skill concise and link to repository scripts rather than duplicating lifecycle logic.

- [ ] **Step 2: Write failing Skill package tests**

  Assert frontmatter name/description exist, referenced scripts resolve from a repository checkout or explicit override, doctor dispatch is read-only, and install/update/restart/uninstall instructions require the appropriate user authorization.

- [ ] **Step 3: Verify tests fail**

  Run: `bash tests/skill_test.sh`

  Expected: FAIL because the Skill package does not exist.

- [ ] **Step 4: Create the Skill and minimal wrappers**

  Document exact trigger cases, supported platform scope, diagnostic-first workflow, script commands, redaction rules, and recovery behavior. `resolve-repo.sh` returns a validated checkout containing `scripts/doctor.sh`; `run-doctor.sh` only delegates to that read-only script.

- [ ] **Step 5: Validate Skill behavior**

  Run the validator supplied by `skill-creator`, then `bash tests/skill_test.sh` and the Skill's doctor wrapper against mocked fixtures. Add the Skill package test to CI.

  Expected: validator and tests PASS without touching the live service.

- [ ] **Step 6: Commit**

  ```bash
  git add skills/phone-touchpad-plus tests/skill_test.sh .github/workflows/test.yaml
  git commit -m "feat: add Phone Touchpad Plus Codex skill"
  ```

### Task 10: Write Public Documentation and Clean Repository Artifacts

**Files:**
- Rewrite: `README.md`
- Create: `README.zh-CN.md`
- Rewrite: `CUSTOMIZATION.md`
- Modify: `.github/workflows/test.yaml`
- Modify or annotate: `desktop/`, `flatpak/`, `snap/` metadata only as needed to state they are inherited and not `v0.1.0` release channels.

**Interfaces:**
- Consumes: stable commands, paths, scope, and diagnostics from Tasks 2-9.
- Produces: English landing page, complete Chinese guide, attribution/change notice, security warning, install/pair/tune/diagnose/update/uninstall commands, and source-only release expectations.

- [ ] **Step 1: Add documentation assertions to the release check**

  Require both READMEs to name Phone Touchpad Plus, `v0.1.0`, upstream `Unrud/remote-touchpad` `v1.5.5`, GPL-3.0-or-later, trusted-LAN/no-TLS warning, Ubuntu 24.04 GNOME X11 validation, unsupported enhanced-gesture platforms, and all lifecycle commands.

- [ ] **Step 2: Verify the existing upstream README fails the assertions**

  Run: `bash tests/check-repository.sh`

  Expected: FAIL with missing fork documentation, not a privacy false positive.

- [ ] **Step 3: Write English and Chinese documentation**

  Keep `README.md` concise and link to `README.zh-CN.md`. In Chinese, document iPhone pairing, reconnect behavior, separate move/scroll sensitivity, gesture map, permissions, troubleshooting categories, safe upgrade/uninstall, and how to install/use the Skill.

- [ ] **Step 4: Generalize customization and legacy packaging notes**

  Remove every developer-specific path from `CUSTOMIZATION.md`; mark inherited Flatpak/Snap/desktop metadata as upstream reference and not a supported Phone Touchpad Plus `v0.1.0` binary channel unless it is fully renamed and tested.

- [ ] **Step 5: Verify public content and links**

  Run: `bash tests/check-repository.sh && rg -n '/home/|192\.168\.|phone-magic-trackpad|Remote Touchpad$' README*.md CUSTOMIZATION.md scripts skills`

  Expected: release check PASS; `rg` returns only intentional upstream attribution or no matches, never local identity/configuration.

- [ ] **Step 6: Commit**

  ```bash
  git add README.md README.zh-CN.md CUSTOMIZATION.md .github/workflows/test.yaml desktop flatpak snap
  git commit -m "docs: prepare Phone Touchpad Plus v0.1.0"
  ```

### Task 11: Final Verification, Fork Publication, and Source Release

**Files:**
- Verify: entire repository, including untracked files.
- Modify: Git remotes and GitHub repository state only after verification.

**Interfaces:**
- Consumes: every previous task and authenticated GitHub CLI access for `ikedamiho41-hue3333333333`.
- Produces: public fork `ikedamiho41-hue3333333333/phone-touchpad-plus`, protected upstream/origin remote layout, green CI, and source tag/release `v0.1.0`.

- [ ] **Step 1: Run local release verification without the live service**

  Run:

  ```bash
  go fmt ./...
  git diff --check
  go test -tags=x11 ./...
  go test -tags=null ./...
  node --test tests/*.test.mjs
  bash tests/run-live-protocol.sh
  bash tests/scripts/install_test.sh
  bash tests/scripts/doctor_test.sh
  bash tests/scripts/uninstall_test.sh
  bash tests/skill_test.sh
  shellcheck scripts/*.sh scripts/lib/*.sh skills/phone-touchpad-plus/scripts/*.sh tests/*.sh tests/scripts/*.sh
  bash tests/check-repository.sh
  ```

  Expected: every command PASS; the only process created is the Null-backend test server, which is cleaned up.

- [ ] **Step 2: Prove the current service was untouched**

  Compare read-only snapshots of the live user unit's active state, unit checksum, binary checksum, listening port, and start timestamp taken immediately before implementation and now.

  Expected: all values are unchanged; do not query process arguments, environment, or any field that could expose the secret.

- [ ] **Step 3: Review the commit series and clean tree**

  Run: `git status --short && git log --oneline --decorate <upstream-base>..HEAD`

  Expected: no untracked or unstaged release files; commits are separated into behavior, identity/security, tests, lifecycle tools, Skill, and docs.

- [ ] **Step 4: Restore GitHub authentication interactively if required**

  Run: `gh auth status`. If invalid, stop and ask the user to complete `gh auth login`; never request or paste a token into chat or a repository file.

- [ ] **Step 5: Create or locate the public fork and make remotes unambiguous**

  Rename the existing upstream URL to remote `upstream`, create/locate the GitHub fork named `phone-touchpad-plus`, and add its URL as `origin`. Verify with `git remote -v` that push targets cannot point to `Unrud/remote-touchpad`.

- [ ] **Step 6: Push the reviewed branch and wait for CI**

  Push the release branch to `origin`, inspect GitHub Actions, and fix failures through new reviewed commits. Do not tag while any required check is pending or failing.

- [ ] **Step 7: Tag and publish the source-only release**

  Create annotated tag `v0.1.0`, push it, and create a GitHub release whose notes state the `v1.5.5` upstream baseline, validated platform, trusted-LAN security boundary, source-build requirement, and deferred platforms/features. Attach no prebuilt binary.

- [ ] **Step 8: Report final evidence**

  Provide the public repository/release links, CI result, exact tag commit, supported scope, and confirmation that the original live service remained unchanged.
