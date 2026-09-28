#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
readonly repo_root
test_root=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-doctor-test.XXXXXXXX")
trap 'rm -r -- "${test_root}"' EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_fixture() {
    local root=$1
    local prefix="${root}/prefix/lib/phone-touchpad-plus"
    local config="${root}/config/phone-touchpad-plus"
    mkdir -p "${prefix}" "${config}" "${root}/config/systemd/user" "${root}/runtime"
    chmod 0700 "${config}"
    touch "${root}/runtime/Xauthority"
    printf '%s\n' 'diagnostic-fixture-secret' >"${config}/secret"
    printf '%s\n' 'PTP_BIND_PORT=18767' 'PTP_MOVE_SPEED=1.0' 'PTP_SCROLL_SPEED=1.0' >"${config}/settings.env"
    chmod 0600 "${config}/secret" "${config}/settings.env"
    printf '[Service]\n' >"${root}/config/systemd/user/phone-touchpad-plus.service"

    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'if [[ "${1:-}" == -print-hosts ]]; then printf "192.0.2.20\nphone-touchpad-plus.example\n"; exit "${PTP_HOST_RESULT:-0}"; fi' \
        'exit 0' >"${prefix}/phone-touchpad-plus"
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'exit "${PTP_PROBE_RESULT:-0}"' >"${prefix}/phone-touchpad-plus-probe"
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "systemctl %s\\n" "$*" >>"${PTP_COMMAND_LOG}"' \
        'if [[ "$*" == *"is-active"* ]]; then [[ "${PTP_SERVICE_STATE:-active}" == active ]]; exit; fi' \
        'exit 0' >"${root}/systemctl"
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'exit "${PTP_CURL_RESULT:-0}"' >"${root}/curl"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "old pairing URL http://host.invalid:8765/#diagnostic-fixture-secret\n" # TEST-FIXTURE' \
        >"${root}/journalctl"
    chmod 0755 "${prefix}/phone-touchpad-plus" "${prefix}/phone-touchpad-plus-probe" \
        "${root}/systemctl" "${root}/curl" "${root}/journalctl"
}

run_doctor() {
    local root=$1
    shift
    set +e
    doctor_output=$(env \
        HOME="${root}/home" \
        XDG_CONFIG_HOME="${root}/config" \
        XDG_DATA_HOME="${root}/data" \
        XDG_RUNTIME_DIR="${root}/runtime" \
        DISPLAY="${PTP_TEST_DISPLAY-:99}" \
        XAUTHORITY="${root}/runtime/Xauthority" \
        PTP_SYSTEMCTL="${PTP_TEST_SYSTEMCTL-${root}/systemctl}" \
        PTP_CURL="${root}/curl" \
        PTP_JOURNALCTL="${root}/journalctl" \
        PTP_COMMAND_LOG="${root}/commands.log" \
        PTP_SERVICE_STATE="${PTP_TEST_SERVICE_STATE-active}" \
        PTP_CURL_RESULT="${PTP_TEST_CURL_RESULT-0}" \
        PTP_PROBE_RESULT="${PTP_TEST_PROBE_RESULT-0}" \
        bash "${repo_root}/scripts/doctor.sh" --prefix "${root}/prefix" "$@" 2>&1)
    doctor_status=$?
    set -e
}

assert_category() {
    local expected=$1
    [[ ${doctor_status} -ne 0 || "${expected}" == OK ]] || fail "${expected} unexpectedly returned success"
    [[ "${doctor_output}" == *"${expected}"* ]] || fail "missing ${expected}: ${doctor_output}"
    [[ "${doctor_output}" != *'diagnostic-fixture-secret'* ]] || fail 'doctor leaked secret'
    [[ "${doctor_output}" != *'#diagnostic'* ]] || fail 'doctor leaked URL fragment'
}

for category in SERVICE_STOPPED GRAPHICAL_SESSION_UNAVAILABLE PHONE_ADDRESS_UNREACHABLE AUTHENTICATION_FAILED OK; do
    root="${test_root}/${category}"
    make_fixture "${root}"
    unset PTP_TEST_SERVICE_STATE PTP_TEST_DISPLAY PTP_TEST_CURL_RESULT PTP_TEST_PROBE_RESULT PTP_TEST_SYSTEMCTL
    case "${category}" in
        SERVICE_STOPPED) PTP_TEST_SERVICE_STATE=inactive ;;
        GRAPHICAL_SESSION_UNAVAILABLE) PTP_TEST_DISPLAY='' ;;
        PHONE_ADDRESS_UNREACHABLE) PTP_TEST_CURL_RESULT=1 ;;
        AUTHENTICATION_FAILED) PTP_TEST_PROBE_RESULT=4 ;;
    esac
    run_doctor "${root}"
    assert_category "${category}"
    if [[ -f "${root}/commands.log" ]] && rg --quiet '(enable|start|restart|stop|disable)' "${root}/commands.log"; then
        fail "doctor issued a mutating systemctl command for ${category}"
    fi
done

root="${test_root}/unsafe-mode"
make_fixture "${root}"
chmod 0644 "${root}/config/phone-touchpad-plus/secret"
unset PTP_TEST_SERVICE_STATE PTP_TEST_DISPLAY PTP_TEST_CURL_RESULT PTP_TEST_PROBE_RESULT PTP_TEST_SYSTEMCTL
run_doctor "${root}"
assert_category INSTALLATION_INCOMPLETE

root="${test_root}/manager-missing"
make_fixture "${root}"
PTP_TEST_SYSTEMCTL="${root}/missing-systemctl"
unset PTP_TEST_SERVICE_STATE PTP_TEST_DISPLAY PTP_TEST_CURL_RESULT PTP_TEST_PROBE_RESULT
run_doctor "${root}"
assert_category SERVICE_MANAGER_UNAVAILABLE

printf 'read-only doctor classifications passed\n'
