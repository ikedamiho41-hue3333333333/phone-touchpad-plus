#!/usr/bin/env bash

ptp_log() {
    printf 'phone-touchpad-plus: %s\n' "$*" >&2
}

ptp_die() {
    ptp_log "$*"
    return 1
}

ptp_require_command() {
    command -v "$1" >/dev/null 2>&1 || ptp_die "required command not found: $1"
}

ptp_version_ge() {
    local actual=$1
    local required=$2
    local first
    first=$(printf '%s\n%s\n' "${required}" "${actual}" | sort -V | head -n 1)
    [[ "${first}" == "${required}" ]]
}

ptp_validate_path() {
    local path=$1
    [[ -n "${path}" && "${path}" == /* && "${path}" != *$'\n'* && "${path}" != *'"'* ]]
}

# Globals are the path contract consumed by lifecycle scripts that source this file.
# shellcheck disable=SC2034
ptp_resolve_paths() {
    local prefix=$1
    ptp_validate_path "${prefix}" || ptp_die "prefix must be an absolute path without quotes or newlines"
    : "${HOME:?HOME must be set}"
    PTP_INSTALL_DIR="${prefix}/lib/phone-touchpad-plus"
    PTP_APP="${PTP_INSTALL_DIR}/phone-touchpad-plus"
    PTP_QR_HELPER="${PTP_INSTALL_DIR}/phone-touchpad-plus-makeqr"
    PTP_PROBE="${PTP_INSTALL_DIR}/phone-touchpad-plus-probe"
    PTP_RUNNER="${PTP_INSTALL_DIR}/run-service.sh"
    PTP_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/phone-touchpad-plus"
    PTP_SECRET_FILE="${PTP_CONFIG_DIR}/secret"
    PTP_SETTINGS_FILE="${PTP_CONFIG_DIR}/settings.env"
    PTP_DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/phone-touchpad-plus"
    PTP_QR_FILE="${PTP_DATA_DIR}/pairing.png"
    PTP_SYSTEMD_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
    PTP_UNIT_FILE="${PTP_SYSTEMD_DIR}/phone-touchpad-plus.service"
}

ptp_atomic_install() {
    local source=$1
    local destination=$2
    local mode=$3
    local temporary
    temporary=$(mktemp "${destination}.tmp.XXXXXXXX")
    if ! install -m "${mode}" -- "${source}" "${temporary}"; then
        rm -f -- "${temporary}"
        return 1
    fi
    if ! mv -f -- "${temporary}" "${destination}"; then
        rm -f -- "${temporary}"
        return 1
    fi
}

ptp_sed_replacement() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

ptp_redact_line() {
    local line=$1
    local secret=${2:-}
    if [[ -n "${secret}" ]]; then
        line=${line//"${secret}"/***}
    fi
    printf '%s\n' "${line}" | sed -E 's|#[^[:space:]]*|#***|g'
}

ptp_find_xauthority() {
    if [[ -n "${XAUTHORITY:-}" && -r "${XAUTHORITY}" ]]; then
        printf '%s\n' "${XAUTHORITY}"
        return 0
    fi
    if [[ -r "${HOME}/.Xauthority" ]]; then
        printf '%s\n' "${HOME}/.Xauthority"
        return 0
    fi
    local runtime_root=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    if [[ -d "${runtime_root}" ]]; then
        find "${runtime_root}" -maxdepth 3 -type f -name '*Xauthority*' -readable -print -quit
    fi
}
