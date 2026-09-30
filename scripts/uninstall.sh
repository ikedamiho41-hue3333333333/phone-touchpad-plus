#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_dir
# shellcheck source=scripts/lib/common.sh
source "${script_dir}/lib/common.sh"

dry_run=false
purge_config=false
prefix="${HOME}/.local"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --purge-config) purge_config=true; shift ;;
        --prefix) prefix=${2:-}; shift 2 ;;
        --help)
            printf 'usage: %s [--dry-run] [--purge-config] [--prefix PATH]\n' "$0"
            exit 0
            ;;
        *) ptp_die "unknown argument: $1"; exit 2 ;;
    esac
done
ptp_resolve_paths "${prefix}"

validate_managed_directory() {
    local path=$1
    local parent=$2
    local leaf=$3
    local resolved_path resolved_parent
    resolved_path=$(realpath -m -- "${path}")
    resolved_parent=$(realpath -m -- "${parent}")
    [[ "${resolved_parent}" != / && "${resolved_path}" == "${resolved_parent}/${leaf}" ]] || {
        ptp_die "refusing unexpected managed path: ${path}"
        exit 1
    }
}

resolved_prefix=$(realpath -m -- "${prefix}")
config_home=${XDG_CONFIG_HOME:-${HOME}/.config}
data_home=${XDG_DATA_HOME:-${HOME}/.local/share}
validate_managed_directory "${PTP_INSTALL_DIR}" "${resolved_prefix}/lib" phone-touchpad-plus
validate_managed_directory "${PTP_DATA_DIR}" "${data_home}" phone-touchpad-plus
validate_managed_directory "${PTP_SYSTEMD_DIR}" "${config_home}/systemd" user
validate_managed_directory "${PTP_CONFIG_DIR}" "${config_home}" phone-touchpad-plus

if [[ "${dry_run}" == true ]]; then
    printf 'Dry run; the service and these installed files would be removed:\n'
    printf '%s\n' "${PTP_APP}" "${PTP_QR_HELPER}" "${PTP_PROBE}" "${PTP_RUNNER}" \
        "${PTP_UNIT_FILE}" "${PTP_QR_FILE}"
    if [[ "${purge_config}" == true ]]; then
        printf 'Configuration would also be removed: %s\n' "${PTP_CONFIG_DIR}"
    else
        printf 'Configuration would be preserved: %s\n' "${PTP_CONFIG_DIR}"
    fi
    exit 0
fi

systemctl_command=${PTP_SYSTEMCTL:-systemctl}
if command -v "${systemctl_command}" >/dev/null 2>&1; then
    "${systemctl_command}" --user disable --now phone-touchpad-plus.service >/dev/null 2>&1 || true
fi
rm -f -- "${PTP_APP}" "${PTP_QR_HELPER}" "${PTP_PROBE}" "${PTP_RUNNER}" \
    "${PTP_UNIT_FILE}" "${PTP_QR_FILE}"
rmdir -- "${PTP_INSTALL_DIR}" "${PTP_DATA_DIR}" 2>/dev/null || true
if command -v "${systemctl_command}" >/dev/null 2>&1; then
    "${systemctl_command}" --user daemon-reload >/dev/null 2>&1 || true
fi

if [[ "${purge_config}" == true ]]; then
    [[ ! -e "${PTP_CONFIG_DIR}" ]] || rm -r -- "${PTP_CONFIG_DIR}"
    printf 'Removed application and configuration.\n'
else
    printf 'Removed application; preserved configuration in %s\n' "${PTP_CONFIG_DIR}"
fi
