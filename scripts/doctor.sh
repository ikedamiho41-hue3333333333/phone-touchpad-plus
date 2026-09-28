#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_dir
# shellcheck source=scripts/lib/common.sh
source "${script_dir}/lib/common.sh"

prefix="${HOME}/.local"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) prefix=${2:-}; shift 2 ;;
        --help) printf 'usage: %s [--prefix PATH]\n' "$0"; exit 0 ;;
        *) ptp_die "unknown argument: $1"; exit 2 ;;
    esac
done
ptp_resolve_paths "${prefix}"

report_failure() {
    printf 'STATUS: %s\n' "$1"
    printf '%s\n' "$2"
    exit 1
}

systemctl_command=${PTP_SYSTEMCTL:-systemctl}
curl_command=${PTP_CURL:-curl}
journalctl_command=${PTP_JOURNALCTL:-journalctl}
command -v "${systemctl_command}" >/dev/null 2>&1 || \
    report_failure SERVICE_MANAGER_UNAVAILABLE 'The user service manager is unavailable.'

for required_path in "${PTP_APP}" "${PTP_PROBE}" "${PTP_SECRET_FILE}" \
    "${PTP_SETTINGS_FILE}" "${PTP_UNIT_FILE}"; do
    [[ -e "${required_path}" ]] || \
        report_failure INSTALLATION_INCOMPLETE 'One or more installed files are missing.'
done
[[ -x "${PTP_APP}" && -x "${PTP_PROBE}" && -r "${PTP_SECRET_FILE}" && -r "${PTP_SETTINGS_FILE}" ]] || \
    report_failure INSTALLATION_INCOMPLETE 'Installed files have unusable permissions.'
if [[ "$(stat -c '%a' "${PTP_CONFIG_DIR}")" != 700 || \
      "$(stat -c '%a' "${PTP_SECRET_FILE}")" != 600 || \
      "$(stat -c '%a' "${PTP_SETTINGS_FILE}")" != 600 ]]; then
    report_failure INSTALLATION_INCOMPLETE 'Private configuration permissions are unsafe.'
fi

if ! "${systemctl_command}" --user is-active --quiet phone-touchpad-plus.service >/dev/null 2>&1; then
    report_failure SERVICE_STOPPED 'The Phone Touchpad Plus user service is not running.'
fi
if [[ -z "${DISPLAY:-}" || -z "${XAUTHORITY:-}" || ! -r "${XAUTHORITY}" ]]; then
    report_failure GRAPHICAL_SESSION_UNAVAILABLE 'The X11 graphical session is unavailable.'
fi

bind_port=$(awk -F= '$1 == "PTP_BIND_PORT" {print $2; exit}' "${PTP_SETTINGS_FILE}")
if [[ ! "${bind_port}" =~ ^[0-9]+$ ]] || ((bind_port < 1 || bind_port > 65535)); then
    report_failure INSTALLATION_INCOMPLETE 'The configured bind port is invalid.'
fi
if ! mapfile -t reachable_hosts < <("${PTP_APP}" -print-hosts 2>/dev/null) || \
    [[ ${#reachable_hosts[@]} -eq 0 || -z "${reachable_hosts[0]}" ]]; then
    report_failure PHONE_ADDRESS_UNREACHABLE 'No phone-reachable local address was found.'
fi
command -v "${curl_command}" >/dev/null 2>&1 || \
    report_failure PHONE_ADDRESS_UNREACHABLE 'The local service could not be checked.'
if ! "${curl_command}" --fail --silent --max-time 2 "http://127.0.0.1:${bind_port}/" >/dev/null 2>&1; then
    report_failure PHONE_ADDRESS_UNREACHABLE 'The local web service is not reachable.'
fi

set +e
"${PTP_PROBE}" -url "ws://127.0.0.1:${bind_port}/ws" -secret-file "${PTP_SECRET_FILE}" >/dev/null 2>&1
probe_status=$?
set -e
case ${probe_status} in
    0) ;;
    4) report_failure AUTHENTICATION_FAILED 'The installed secret did not authenticate.' ;;
    *) report_failure PHONE_ADDRESS_UNREACHABLE 'The WebSocket service is not reachable.' ;;
esac

printf 'STATUS: OK\n'
printf 'The service, graphical session, local address, and authentication are healthy.\n'
if command -v "${journalctl_command}" >/dev/null 2>&1; then
    secret_value=$(<"${PTP_SECRET_FILE}")
    printf 'Recent service logs (redacted):\n'
    while IFS= read -r log_line; do
        ptp_redact_line "${log_line}" "${secret_value}"
    done < <("${journalctl_command}" --user -u phone-touchpad-plus.service -n 20 --no-pager 2>/dev/null || true)
fi
