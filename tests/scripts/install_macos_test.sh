#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
readonly repo_root
test_root=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-macos-install-test.XXXXXXXX")
cleanup() {
    rm -r -- "${test_root}"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "missing file $1"
}

assert_mode() {
    local got
    if got=$(stat -f '%Lp' "$1" 2>/dev/null); then
        :
    else
        got=$(stat -c '%a' "$1")
    fi
    [[ "${got}" == "$2" ]] || fail "$1 mode ${got}, want $2"
}

make_test_commands() {
    local root=$1
    mkdir -p "${root}/commands"

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'printf "launchctl %s\\n" "$*" >>"${PTP_TEST_LAUNCHCTL_LOG}"' \
        'exit 0' \
        >"${root}/commands/launchctl"
    chmod 0755 "${root}/commands/launchctl"

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'printf "codesign %s\\n" "$*" >>"${PTP_TEST_CODESIGN_LOG}"' \
        'exit 0' \
        >"${root}/commands/codesign"
    chmod 0755 "${root}/commands/codesign"

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'printf "go %s\\n" "$*" >>"${PTP_TEST_GO_LOG}"' \
        'if [[ "${1:-}" == env && "${2:-}" == GOVERSION ]]; then printf "go1.26.8\\n"; exit 0; fi' \
        'if [[ "${1:-}" != build ]]; then exit 2; fi' \
        'output=""; target=""' \
        'while [[ $# -gt 0 ]]; do' \
        '  if [[ "$1" == -o ]]; then output=$2; shift 2; continue; fi' \
        '  target=$1; shift' \
        'done' \
        'if [[ "${target}" == ./tools/makeqr ]]; then' \
        '  printf "%s\\n" "#!/usr/bin/env bash" "set -euo pipefail" "output=\$1" "IFS= read -r url" "printf %s \"\$url\" >\"\$output\"" >"${output}"' \
        'elif [[ "${target}" == ./tools/probe ]]; then' \
        '  printf "%s\\n" "#!/usr/bin/env bash" "if [[ \"\${1:-}\" == -help ]]; then exit 0; fi" "exit 2" >"${output}"' \
        'else' \
        '  printf "%s\\n" "#!/usr/bin/env bash" "set -euo pipefail" "if [[ \"\${1:-}\" == -version ]]; then printf \"0.1.0\\n\"; exit 0; fi" "if [[ \"\${1:-}\" == -print-hosts ]]; then printf \"192.0.2.10\\n\"; exit 0; fi" "exit 0" >"${output}"' \
        'fi' \
        'chmod 0755 "${output}"' \
        >"${root}/commands/go"
    chmod 0755 "${root}/commands/go"
}

run_install() {
    local root=$1
    shift
    env \
        HOME="${root}/test-home" \
        XDG_CONFIG_HOME="${root}/config" \
        XDG_DATA_HOME="${root}/data" \
        PTP_TEST_MODE=1 \
        PTP_GO="${root}/commands/go" \
        PTP_CODESIGN="${root}/commands/codesign" \
        PTP_LAUNCHCTL="${root}/commands/launchctl" \
        PTP_TEST_CODESIGN_LOG="${root}/codesign.log" \
        PTP_TEST_GO_LOG="${root}/go.log" \
        PTP_TEST_LAUNCHCTL_LOG="${root}/launchctl.log" \
        bash "${repo_root}/scripts/install-macos.sh" --prefix "${root}/prefix" "$@"
}

dry_root="${test_root}/dry"
mkdir -p "${dry_root}/test-home"
make_test_commands "${dry_root}"
run_install "${dry_root}" --dry-run >"${dry_root}/output"
[[ ! -e "${dry_root}/prefix" ]] || fail 'dry-run created install prefix'
[[ ! -e "${dry_root}/config" ]] || fail 'dry-run created config directory'
[[ ! -s "${dry_root}/go.log" ]] || fail 'dry-run invoked Go'
[[ ! -s "${dry_root}/launchctl.log" ]] || fail 'dry-run invoked launchctl'

install_root="${test_root}/install"
mkdir -p "${install_root}/test-home"
make_test_commands "${install_root}"
run_install "${install_root}" >"${install_root}/output"

install_dir="${install_root}/prefix/lib/phone-touchpad-plus"
app_bundle="${install_root}/test-home/Applications/Phone Touchpad Plus.app"
app="${app_bundle}/Contents/MacOS/phone-touchpad-plus"
app_info="${app_bundle}/Contents/Info.plist"
legacy_app="${install_root}/test-home/Applications/Phone Touchpad Plus"
legacy_prefix_app="${install_dir}/phone-touchpad-plus"
qr_helper="${install_dir}/phone-touchpad-plus-makeqr"
probe="${install_dir}/phone-touchpad-plus-probe"
runner="${install_dir}/run-service-macos.sh"
config_dir="${install_root}/config/phone-touchpad-plus"
secret_file="${config_dir}/secret"
settings_file="${config_dir}/settings.env"
launch_agent="${install_root}/test-home/Library/LaunchAgents/com.ikedamiho41.phone-touchpad-plus.plist"
qr_file="${install_root}/data/phone-touchpad-plus/pairing.png"

[[ -d "${app_bundle}" ]] || fail 'macOS application bundle is missing'
for file in "${app}" "${app_info}" "${qr_helper}" "${probe}" "${runner}" "${secret_file}" \
    "${settings_file}" "${launch_agent}" "${qr_file}"; do
    assert_file "${file}"
done
[[ ! -e "${legacy_app}" ]] || fail 'legacy macOS application name remains installed'
[[ ! -e "${legacy_prefix_app}" ]] || fail 'legacy prefix application remains installed'
rg --fixed-strings --quiet '<string>com.ikedamiho41.phone-touchpad-plus</string>' "${app_info}" || \
    fail 'application bundle identifier is missing'
rg --fixed-strings --quiet '<string>phone-touchpad-plus</string>' "${app_info}" || \
    fail 'application bundle executable is missing'
assert_mode "${config_dir}" 700
assert_mode "${secret_file}" 600
assert_mode "${settings_file}" 600
assert_mode "${qr_file}" 600
rg --quiet '^PTP_BIND_PORT=8765$' "${settings_file}" || fail 'default port is not 8765'
rg --quiet '^PTP_MOVE_SPEED=1\.0$' "${settings_file}" || fail 'default move speed is not 1.0'
rg --quiet '^PTP_SCROLL_SPEED=1\.0$' "${settings_file}" || fail 'default scroll speed is not 1.0'
rg --fixed-strings --quiet "${secret_file}" "${launch_agent}" || fail 'LaunchAgent does not reference the secret file'
rg --fixed-strings --quiet "${app}" "${launch_agent}" || fail 'LaunchAgent does not reference the bundled executable'

secret_value=$(<"${secret_file}")
if rg --fixed-strings --quiet "${secret_value}" "${launch_agent}" "${install_root}/output"; then
    fail 'LaunchAgent or installer output exposed the secret'
fi
rg --quiet '^http://192\.0\.2\.10:8765/#.+$' "${qr_file}" || fail 'QR did not receive the complete pairing URL'
rg --quiet 'launchctl bootstrap gui/[0-9]+ ' "${install_root}/launchctl.log" || fail 'LaunchAgent was not bootstrapped'
rg --quiet 'launchctl kickstart -k gui/[0-9]+/com\.ikedamiho41\.phone-touchpad-plus' \
    "${install_root}/launchctl.log" || fail 'LaunchAgent was not started'
rg --quiet 'codesign --force --sign - --identifier com\.ikedamiho41\.phone-touchpad-plus ' \
    "${install_root}/codesign.log" || fail 'application was not signed with its stable identifier'
rg --fixed-strings --quiet \
    'designated => identifier "com.ikedamiho41.phone-touchpad-plus"' \
    "${install_root}/codesign.log" || fail 'application signature requirement is not stable across upgrades'
rg --fixed-strings --quiet 'Phone Touchpad Plus.app' "${install_root}/codesign.log" || \
    fail 'installer did not sign the application bundle'

printf 'isolated macOS install lifecycle tests passed\n'
