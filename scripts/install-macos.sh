#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_dir
repo_root=$(cd "${script_dir}/.." && pwd -P)
readonly repo_root
# shellcheck source=scripts/lib/common.sh
source "${script_dir}/lib/common.sh"

readonly launch_agent_label=com.ikedamiho41.phone-touchpad-plus
dry_run=false
upgrade=false
prefix="${HOME}/.local"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --upgrade) upgrade=true; shift ;;
        --prefix) prefix=${2:-}; shift 2 ;;
        --help)
            printf 'usage: %s [--dry-run] [--upgrade] [--prefix PATH]\n' "$0"
            exit 0
            ;;
        *) ptp_die "unknown argument: $1"; exit 2 ;;
    esac
done

ptp_resolve_paths "${prefix}"
PTP_LEGACY_APP="${PTP_APP}"
PTP_APPLICATIONS_DIR="${HOME}/Applications"
PTP_APP="${PTP_APPLICATIONS_DIR}/Phone Touchpad Plus"
PTP_RUNNER="${PTP_INSTALL_DIR}/run-service-macos.sh"
PTP_LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
PTP_LAUNCH_AGENT_FILE="${PTP_LAUNCH_AGENT_DIR}/${launch_agent_label}.plist"
PTP_LOG_DIR="${HOME}/Library/Logs/Phone Touchpad Plus"
PTP_STDOUT_LOG="${PTP_LOG_DIR}/service.log"
PTP_STDERR_LOG="${PTP_LOG_DIR}/service-error.log"

if [[ "${dry_run}" == true ]]; then
    printf 'Dry run; no files or services will be changed.\n'
    printf 'Application: %s\nConfig: %s\nData: %s\nLaunchAgent: %s\n' \
        "${PTP_APP}" "${PTP_CONFIG_DIR}" "${PTP_DATA_DIR}" "${PTP_LAUNCH_AGENT_FILE}"
    exit 0
fi

installation_exists=false
for existing_path in "${PTP_APP}" "${PTP_LEGACY_APP}" "${PTP_CONFIG_DIR}" "${PTP_LAUNCH_AGENT_FILE}"; do
    [[ -e "${existing_path}" ]] && installation_exists=true
done
if [[ "${installation_exists}" == true && "${upgrade}" != true ]]; then
    ptp_die 'an installation already exists; rerun with --upgrade to preserve its configuration'
    exit 1
fi
if [[ "${upgrade}" == true && ! -f "${PTP_SECRET_FILE}" ]]; then
    ptp_die 'upgrade requested but the existing secret file is missing'
    exit 1
fi

go_command=${PTP_GO:-go}
codesign_command=${PTP_CODESIGN:-codesign}
launchctl_command=${PTP_LAUNCHCTL:-launchctl}
ptp_require_command "${go_command}"
ptp_require_command "${codesign_command}"
ptp_require_command "${launchctl_command}"
for command_name in awk curl head install mktemp od sed tr; do
    ptp_require_command "${command_name}"
done

if [[ "${PTP_TEST_MODE:-0}" != 1 && "$(uname -s)" != Darwin ]]; then
    ptp_die 'the macOS installer requires Darwin'
    exit 1
fi

required_go=$(awk '$1 == "go" {print $2; exit}' "${repo_root}/go.mod")
actual_go=$("${go_command}" env GOVERSION)
actual_go=${actual_go#go}
if ! ptp_version_ge "${actual_go}" "${required_go}"; then
    ptp_die "Go ${required_go} or newer is required; found ${actual_go}"
    exit 1
fi

stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-macos-install.XXXXXXXX")
cleanup_stage() {
    rm -r -- "${stage_dir}"
}
trap cleanup_stage EXIT INT TERM

stage_app="${stage_dir}/phone-touchpad-plus"
stage_qr_helper="${stage_dir}/phone-touchpad-plus-makeqr"
stage_probe="${stage_dir}/phone-touchpad-plus-probe"
stage_runner="${stage_dir}/run-service-macos.sh"
stage_secret="${stage_dir}/secret"
stage_settings="${stage_dir}/settings.env"
stage_launch_agent="${stage_dir}/${launch_agent_label}.plist"
stage_qr="${stage_dir}/pairing.png"

cd "${repo_root}"
"${go_command}" build -trimpath -o "${stage_app}" .
"${go_command}" build -trimpath -o "${stage_qr_helper}" ./tools/makeqr
"${go_command}" build -trimpath -o "${stage_probe}" ./tools/probe
"${codesign_command}" --force --sign - --identifier "${launch_agent_label}" "${stage_app}"
"${codesign_command}" --verify --strict "${stage_app}"
[[ "$("${stage_app}" -version)" == 0.1.0 ]] || { ptp_die 'staged application version check failed'; exit 1; }
"${stage_probe}" -help >/dev/null 2>&1 || { ptp_die 'staged probe validation failed'; exit 1; }
if "${stage_qr_helper}" </dev/null >/dev/null 2>&1; then
    ptp_die 'staged QR helper accepted missing input'
    exit 1
fi
install -m 0755 -- "${script_dir}/run-service-macos.sh" "${stage_runner}"

if [[ "${upgrade}" == true ]]; then
    install -m 0600 -- "${PTP_SECRET_FILE}" "${stage_secret}"
    install -m 0600 -- "${PTP_SETTINGS_FILE}" "${stage_settings}"
else
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n' >"${stage_secret}"
    printf '%s\n' 'PTP_BIND_PORT=8765' 'PTP_MOVE_SPEED=1.0' 'PTP_SCROLL_SPEED=1.0' >"${stage_settings}"
    chmod 0600 "${stage_secret}" "${stage_settings}"
fi

xml_replacement() {
    ptp_sed_replacement "$(ptp_xml_escape "$1")"
}
runner_replacement=$(xml_replacement "${PTP_RUNNER}")
binary_replacement=$(xml_replacement "${PTP_APP}")
secret_replacement=$(xml_replacement "${PTP_SECRET_FILE}")
settings_replacement=$(xml_replacement "${PTP_SETTINGS_FILE}")
stdout_replacement=$(xml_replacement "${PTP_STDOUT_LOG}")
stderr_replacement=$(xml_replacement "${PTP_STDERR_LOG}")
sed \
    -e "s|@RUNNER@|${runner_replacement}|g" \
    -e "s|@BINARY@|${binary_replacement}|g" \
    -e "s|@SECRET_FILE@|${secret_replacement}|g" \
    -e "s|@SETTINGS_FILE@|${settings_replacement}|g" \
    -e "s|@STDOUT_LOG@|${stdout_replacement}|g" \
    -e "s|@STDERR_LOG@|${stderr_replacement}|g" \
    "${script_dir}/templates/${launch_agent_label}.plist.in" >"${stage_launch_agent}"

bind_port=$(awk -F= '$1 == "PTP_BIND_PORT" {print $2; exit}' "${stage_settings}")
if [[ ! "${bind_port}" =~ ^[0-9]+$ ]] || ((bind_port < 1 || bind_port > 65535)); then
    ptp_die 'staged settings contain an invalid bind port'
    exit 1
fi
hosts_file="${stage_dir}/hosts"
"${stage_app}" -print-hosts >"${hosts_file}"
IFS= read -r primary_host <"${hosts_file}"
[[ -n "${primary_host}" ]] || { ptp_die 'no phone-reachable host found'; exit 1; }
url_host=${primary_host}
[[ "${url_host}" == *:* ]] && url_host="[${url_host}]"
secret_value=$(<"${stage_secret}")
[[ -n "${secret_value}" ]] || { ptp_die 'secret file is empty'; exit 1; }
pairing_address="http://${url_host}:${bind_port}/"
printf '%s#%s\n' "${pairing_address}" "${secret_value}" | "${stage_qr_helper}" "${stage_qr}"

install -d -m 0755 "${PTP_INSTALL_DIR}" "${PTP_APPLICATIONS_DIR}" "${PTP_LAUNCH_AGENT_DIR}" "${PTP_LOG_DIR}"
install -d -m 0700 "${PTP_CONFIG_DIR}" "${PTP_DATA_DIR}"
ptp_atomic_install "${stage_app}" "${PTP_APP}" 0755
ptp_atomic_install "${stage_qr_helper}" "${PTP_QR_HELPER}" 0755
ptp_atomic_install "${stage_probe}" "${PTP_PROBE}" 0755
ptp_atomic_install "${stage_runner}" "${PTP_RUNNER}" 0755
ptp_atomic_install "${stage_secret}" "${PTP_SECRET_FILE}" 0600
ptp_atomic_install "${stage_settings}" "${PTP_SETTINGS_FILE}" 0600
ptp_atomic_install "${stage_launch_agent}" "${PTP_LAUNCH_AGENT_FILE}" 0644
ptp_atomic_install "${stage_qr}" "${PTP_QR_FILE}" 0600
if [[ "${PTP_LEGACY_APP}" != "${PTP_APP}" ]]; then
    rm -f -- "${PTP_LEGACY_APP}"
fi

launch_domain="gui/$(id -u)"
"${launchctl_command}" bootout "${launch_domain}/${launch_agent_label}" >/dev/null 2>&1 || true
"${launchctl_command}" bootstrap "${launch_domain}" "${PTP_LAUNCH_AGENT_FILE}"
"${launchctl_command}" enable "${launch_domain}/${launch_agent_label}"
"${launchctl_command}" kickstart -k "${launch_domain}/${launch_agent_label}"

if [[ "${PTP_TEST_MODE:-0}" != 1 ]]; then
    ready=false
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50; do
        if curl --fail --silent --show-error --max-time 1 "http://127.0.0.1:${bind_port}/" >/dev/null; then
            ready=true
            break
        fi
        sleep 0.1
    done
    [[ "${ready}" == true ]] || { ptp_die "service did not become reachable on port ${bind_port}"; exit 1; }
fi

printf 'Phone Touchpad Plus is installed and running.\n'
printf 'Pairing address: %s (secret hidden)\n' "${pairing_address}"
printf 'Pairing QR code: %s\n' "${PTP_QR_FILE}"
