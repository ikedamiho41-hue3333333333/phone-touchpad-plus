#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
readonly repo_root
test_root=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-install-test.XXXXXXXX")
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
    got=$(stat -c '%a' "$1")
    [[ "${got}" == "$2" ]] || fail "$1 mode ${got}, want $2"
}

make_mocks() {
    local root=$1
    mkdir -p "${root}/mocks"
    # The single-quoted lines are source code for the generated test double.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'printf "systemctl %s\\n" "$*" >>"${PTP_TEST_SYSTEMCTL_LOG}"' \
        >"${root}/mocks/systemctl"
    chmod 0755 "${root}/mocks/systemctl"

    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'printf "go %s\\n" "$*" >>"${PTP_TEST_GO_LOG}"' \
        'if [[ "${1:-}" == env && "${2:-}" == GOVERSION ]]; then printf "go1.26.0\\n"; exit 0; fi' \
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
        '  version=0.1.0' \
        '  [[ "${PTP_MOCK_BAD_VERSION:-0}" == 1 ]] && version=9.9.9' \
        '  printf "%s\\n" "#!/usr/bin/env bash" "set -euo pipefail" "if [[ \"\${1:-}\" == -version ]]; then printf \"${version}\\n\"; exit 0; fi" "if [[ \"\${1:-}\" == -print-hosts ]]; then printf \"192.0.2.10\\nphone-touchpad-plus.example\\n\"; exit 0; fi" "exit 0" >"${output}"' \
        'fi' \
        'chmod 0755 "${output}"' \
        >"${root}/mocks/go"
    chmod 0755 "${root}/mocks/go"
}

run_install() {
    local root=$1
    shift
    env \
        HOME="${root}/home" \
        XDG_CONFIG_HOME="${root}/config" \
        XDG_DATA_HOME="${root}/data" \
        XDG_RUNTIME_DIR="${root}/runtime" \
        DISPLAY=:99 \
        XAUTHORITY="${root}/runtime/Xauthority" \
        PTP_TEST_MODE=1 \
        PTP_SYSTEMCTL="${root}/mocks/systemctl" \
        PTP_GO="${root}/mocks/go" \
        PTP_TEST_SYSTEMCTL_LOG="${root}/systemctl.log" \
        PTP_TEST_GO_LOG="${root}/go.log" \
        bash "${repo_root}/scripts/install.sh" --prefix "${root}/prefix" "$@"
}

dry_root="${test_root}/dry"
mkdir -p "${dry_root}/home" "${dry_root}/runtime"
touch "${dry_root}/runtime/Xauthority"
make_mocks "${dry_root}"
run_install "${dry_root}" --dry-run >"${dry_root}/output"
[[ ! -e "${dry_root}/prefix" ]] || fail 'dry-run created install prefix'
[[ ! -e "${dry_root}/config" ]] || fail 'dry-run created config directory'
[[ ! -s "${dry_root}/go.log" ]] || fail 'dry-run invoked Go'
[[ ! -s "${dry_root}/systemctl.log" ]] || fail 'dry-run invoked systemctl'

install_root="${test_root}/install"
mkdir -p "${install_root}/home" "${install_root}/runtime"
touch "${install_root}/runtime/Xauthority"
make_mocks "${install_root}"
run_install "${install_root}" >"${install_root}/output"

app="${install_root}/prefix/lib/phone-touchpad-plus/phone-touchpad-plus"
qr_helper="${install_root}/prefix/lib/phone-touchpad-plus/phone-touchpad-plus-makeqr"
probe="${install_root}/prefix/lib/phone-touchpad-plus/phone-touchpad-plus-probe"
runner="${install_root}/prefix/lib/phone-touchpad-plus/run-service.sh"
config_dir="${install_root}/config/phone-touchpad-plus"
secret_file="${config_dir}/secret"
settings_file="${config_dir}/settings.env"
unit="${install_root}/config/systemd/user/phone-touchpad-plus.service"
qr_file="${install_root}/data/phone-touchpad-plus/pairing.png"

for file in "${app}" "${qr_helper}" "${probe}" "${runner}" "${secret_file}" "${settings_file}" "${unit}" "${qr_file}"; do
    assert_file "${file}"
done
assert_mode "${config_dir}" 700
assert_mode "${secret_file}" 600
assert_mode "${qr_file}" 600
rg --quiet '^PTP_MOVE_SPEED=1\.0$' "${settings_file}" || fail 'default move speed is not 1.0'
rg --quiet '^PTP_SCROLL_SPEED=1\.0$' "${settings_file}" || fail 'default scroll speed is not 1.0'
rg --quiet -- '--secret-file' "${unit}" || fail 'unit does not reference a secret file'
secret_value=$(<"${secret_file}")
if rg --fixed-strings --quiet "${secret_value}" "${unit}"; then
    fail 'unit contains secret content'
fi

before_reinstall=$(sha256sum "${app}" "${secret_file}" "${settings_file}" "${unit}")
if run_install "${install_root}" >"${install_root}/reinstall-output" 2>&1; then
    fail 'normal reinstall unexpectedly succeeded'
fi
after_reinstall=$(sha256sum "${app}" "${secret_file}" "${settings_file}" "${unit}")
[[ "${before_reinstall}" == "${after_reinstall}" ]] || fail 'normal reinstall mutated files'

printf '%s\n' 'PTP_BIND_PORT=18766' 'PTP_MOVE_SPEED=1.7' 'PTP_SCROLL_SPEED=0.8' >"${settings_file}"
chmod 0600 "${settings_file}"
secret_before=$(<"${secret_file}")
run_install "${install_root}" --upgrade >"${install_root}/upgrade-output"
[[ "$(<"${secret_file}")" == "${secret_before}" ]] || fail 'upgrade replaced the secret'
rg --quiet '^PTP_MOVE_SPEED=1\.7$' "${settings_file}" || fail 'upgrade replaced move speed'
rg --quiet '^PTP_SCROLL_SPEED=0\.8$' "${settings_file}" || fail 'upgrade replaced scroll speed'
rg --quiet ':18766/#' "${install_root}/upgrade-output" || fail 'pairing URL ignored preserved bind port'

app_before=$(sha256sum "${app}")
unit_before=$(sha256sum "${unit}")
if PTP_MOCK_BAD_VERSION=1 run_install "${install_root}" --upgrade \
    >"${install_root}/bad-upgrade-output" 2>&1; then
    fail 'bad staged binary unexpectedly installed'
fi
[[ "$(sha256sum "${app}")" == "${app_before}" ]] || fail 'bad upgrade replaced application'
[[ "$(sha256sum "${unit}")" == "${unit_before}" ]] || fail 'bad upgrade replaced unit'

printf 'isolated install lifecycle tests passed\n'
