#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_dir
repo_root=$(cd "${script_dir}/.." && pwd -P)
readonly repo_root
# shellcheck source=scripts/lib/common.sh
source "${script_dir}/lib/common.sh"

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
if [[ "${dry_run}" == true ]]; then
    printf 'Dry run; no files or services will be changed.\n'
    printf 'Application: %s\nConfig: %s\nData: %s\nService: %s\n' \
        "${PTP_APP}" "${PTP_CONFIG_DIR}" "${PTP_DATA_DIR}" "${PTP_UNIT_FILE}"
    exit 0
fi

installation_exists=false
for existing_path in "${PTP_APP}" "${PTP_CONFIG_DIR}" "${PTP_UNIT_FILE}"; do
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
systemctl_command=${PTP_SYSTEMCTL:-systemctl}
ptp_require_command "${go_command}"
ptp_require_command "${systemctl_command}"
for command_name in install mktemp sed sort head od tr; do
    ptp_require_command "${command_name}"
done

required_go=$(awk '$1 == "go" {print $2; exit}' "${repo_root}/go.mod")
actual_go=$("${go_command}" env GOVERSION)
actual_go=${actual_go#go}
if ! ptp_version_ge "${actual_go}" "${required_go}"; then
    ptp_die "Go ${required_go} or newer is required; found ${actual_go}"
    exit 1
fi

if [[ "${PTP_TEST_MODE:-0}" != 1 ]]; then
    [[ "$(uname -s)" == Linux ]] || { ptp_die 'the v0.1.0 installer supports Linux only'; exit 1; }
    [[ "${XDG_SESSION_TYPE:-}" == x11 ]] || { ptp_die 'GNOME X11 session required'; exit 1; }
    [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] || { ptp_die 'GNOME desktop required'; exit 1; }
    [[ -n "${DISPLAY:-}" ]] || { ptp_die 'DISPLAY is unavailable'; exit 1; }
    XAUTHORITY=$(ptp_find_xauthority)
    [[ -n "${XAUTHORITY}" && -r "${XAUTHORITY}" ]] || { ptp_die 'XAUTHORITY is unavailable'; exit 1; }
    export XAUTHORITY
    ptp_require_command pkg-config
    missing_packages=()
    for package_name in x11 xrandr xtst xt; do
        pkg-config --exists "${package_name}" || missing_packages+=("${package_name}")
    done
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        ptp_die "missing X11 build dependencies: ${missing_packages[*]} (Ubuntu packages: libx11-dev libxrandr-dev libxtst-dev libxt-dev)"
        exit 1
    fi
    ptp_require_command curl
fi

stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-install.XXXXXXXX")
cleanup_stage() {
    rm -r -- "${stage_dir}"
}
trap cleanup_stage EXIT INT TERM

stage_app="${stage_dir}/phone-touchpad-plus"
stage_qr_helper="${stage_dir}/phone-touchpad-plus-makeqr"
stage_probe="${stage_dir}/phone-touchpad-plus-probe"
stage_runner="${stage_dir}/run-service.sh"
stage_secret="${stage_dir}/secret"
stage_settings="${stage_dir}/settings.env"
stage_unit="${stage_dir}/phone-touchpad-plus.service"
stage_qr="${stage_dir}/pairing.png"

cd "${repo_root}"
"${go_command}" build -tags=x11 -trimpath -o "${stage_app}" .
"${go_command}" build -trimpath -o "${stage_qr_helper}" ./tools/makeqr
"${go_command}" build -trimpath -o "${stage_probe}" ./tools/probe
[[ "$("${stage_app}" -version)" == 0.1.0 ]] || { ptp_die 'staged application version check failed'; exit 1; }
"${stage_probe}" -help >/dev/null 2>&1 || { ptp_die 'staged probe validation failed'; exit 1; }
if "${stage_qr_helper}" </dev/null >/dev/null 2>&1; then
    ptp_die 'staged QR helper accepted missing input'
    exit 1
fi
install -m 0755 -- "${script_dir}/run-service.sh" "${stage_runner}"

if [[ "${upgrade}" == true ]]; then
    install -m 0600 -- "${PTP_SECRET_FILE}" "${stage_secret}"
    install -m 0600 -- "${PTP_SETTINGS_FILE}" "${stage_settings}"
else
    od -An -N24 -tx1 /dev/urandom | tr -d ' \n' >"${stage_secret}"
    printf '%s\n' 'PTP_BIND_PORT=8765' 'PTP_MOVE_SPEED=1.0' 'PTP_SCROLL_SPEED=1.0' \
        'PTP_SCROLL_INVERT_Y=false' >"${stage_settings}"
    chmod 0600 "${stage_secret}" "${stage_settings}"
fi

runner_replacement=$(ptp_sed_replacement "${PTP_RUNNER}")
binary_replacement=$(ptp_sed_replacement "${PTP_APP}")
secret_replacement=$(ptp_sed_replacement "${PTP_SECRET_FILE}")
settings_replacement=$(ptp_sed_replacement "${PTP_SETTINGS_FILE}")
sed \
    -e "s|@RUNNER@|${runner_replacement}|g" \
    -e "s|@BINARY@|${binary_replacement}|g" \
    -e "s|@SECRET_FILE@|${secret_replacement}|g" \
    -e "s|@SETTINGS_FILE@|${settings_replacement}|g" \
    "${script_dir}/templates/phone-touchpad-plus.service.in" >"${stage_unit}"

install -d -m 0755 "${PTP_INSTALL_DIR}"
install -d -m 0700 "${PTP_CONFIG_DIR}" "${PTP_DATA_DIR}"
install -d -m 0755 "${PTP_SYSTEMD_DIR}"
ptp_atomic_install "${stage_app}" "${PTP_APP}" 0755
ptp_atomic_install "${stage_qr_helper}" "${PTP_QR_HELPER}" 0755
ptp_atomic_install "${stage_probe}" "${PTP_PROBE}" 0755
ptp_atomic_install "${stage_runner}" "${PTP_RUNNER}" 0755
ptp_atomic_install "${stage_secret}" "${PTP_SECRET_FILE}" 0600
ptp_atomic_install "${stage_settings}" "${PTP_SETTINGS_FILE}" 0600
ptp_atomic_install "${stage_unit}" "${PTP_UNIT_FILE}" 0644

environment_names=()
[[ -n "${DISPLAY:-}" ]] && environment_names+=(DISPLAY)
[[ -n "${XAUTHORITY:-}" ]] && environment_names+=(XAUTHORITY)
if [[ ${#environment_names[@]} -gt 0 ]]; then
    "${systemctl_command}" --user import-environment "${environment_names[@]}"
fi
"${systemctl_command}" --user daemon-reload
"${systemctl_command}" --user enable --now phone-touchpad-plus.service

bind_port=$(awk -F= '$1 == "PTP_BIND_PORT" {print $2; exit}' "${PTP_SETTINGS_FILE}")
if [[ ! "${bind_port}" =~ ^[0-9]+$ ]] || ((bind_port < 1 || bind_port > 65535)); then
    ptp_die 'installed settings contain an invalid bind port'
    exit 1
fi
if [[ "${PTP_TEST_MODE:-0}" != 1 ]]; then
    ready=false
    for _ in {1..50}; do
        if curl --fail --silent --show-error --max-time 1 \
            "http://127.0.0.1:${bind_port}/" >/dev/null; then
            ready=true
            break
        fi
        sleep 0.1
    done
    [[ "${ready}" == true ]] || { ptp_die "service did not become reachable on port ${bind_port}"; exit 1; }
fi

mapfile -t pairing_hosts < <("${PTP_APP}" -print-hosts)
[[ ${#pairing_hosts[@]} -gt 0 && -n "${pairing_hosts[0]}" ]] || { ptp_die 'no phone-reachable host found'; exit 1; }
primary_host=${pairing_hosts[0]}
url_host=${primary_host}
[[ "${url_host}" == *:* ]] && url_host="[${url_host}]"
secret_value=$(<"${PTP_SECRET_FILE}")
[[ -n "${secret_value}" ]] || { ptp_die 'secret file is empty'; exit 1; }
pairing_url="http://${url_host}:${bind_port}/#${secret_value}"
[[ "${pairing_url}" == *'#'?* ]] || { ptp_die 'pairing URL fragment is missing'; exit 1; }
printf '%s\n' "${pairing_url}" | "${PTP_QR_HELPER}" "${stage_qr}"
ptp_atomic_install "${stage_qr}" "${PTP_QR_FILE}" 0600

printf 'Pairing URL: %s\nQR code: %s\n' "${pairing_url}" "${PTP_QR_FILE}"
for alternative_host in "${pairing_hosts[@]:1}"; do
    printf 'Alternative host: %s\n' "${alternative_host}"
done
