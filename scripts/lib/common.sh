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
    awk -v actual="${actual}" -v required="${required}" 'BEGIN {
        actual_count = split(actual, actual_parts, ".")
        required_count = split(required, required_parts, ".")
        count = actual_count > required_count ? actual_count : required_count
        for (i = 1; i <= count; i++) {
            actual_part = actual_parts[i] + 0
            required_part = required_parts[i] + 0
            if (actual_part > required_part) exit 0
            if (actual_part < required_part) exit 1
        }
        exit 0
    }'
}

ptp_xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e 's/'"'"'/\&apos;/g'
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
