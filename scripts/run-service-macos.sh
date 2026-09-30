#!/usr/bin/env bash
set -euo pipefail

binary=""
secret_file=""
settings_file=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --binary) binary=${2:-}; shift 2 ;;
        --secret-file) secret_file=${2:-}; shift 2 ;;
        --settings) settings_file=${2:-}; shift 2 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ -x "${binary}" ]] || { printf 'application binary is not executable\n' >&2; exit 1; }
[[ -r "${secret_file}" ]] || { printf 'secret file is not readable\n' >&2; exit 1; }
[[ -r "${settings_file}" ]] || { printf 'settings file is not readable\n' >&2; exit 1; }

bind_port=8765
move_speed=1.0
scroll_speed=1.0
while IFS='=' read -r key value; do
    case "${key}" in
        PTP_BIND_PORT) bind_port=${value} ;;
        PTP_MOVE_SPEED) move_speed=${value} ;;
        PTP_SCROLL_SPEED) scroll_speed=${value} ;;
        ''|'#'*) ;;
        *) printf 'unsupported setting: %s\n' "${key}" >&2; exit 1 ;;
    esac
done <"${settings_file}"

if [[ ! "${bind_port}" =~ ^[0-9]+$ ]] || ((bind_port < 1 || bind_port > 65535)); then
    printf 'invalid bind port\n' >&2
    exit 1
fi
[[ "${move_speed}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf 'invalid move speed\n' >&2; exit 1; }
[[ "${scroll_speed}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { printf 'invalid scroll speed\n' >&2; exit 1; }

exec "${binary}" \
    -bind ":${bind_port}" \
    -secret-file "${secret_file}" \
    -show-pairing=false \
    -move-speed "${move_speed}" \
    -scroll-speed "${scroll_speed}"
