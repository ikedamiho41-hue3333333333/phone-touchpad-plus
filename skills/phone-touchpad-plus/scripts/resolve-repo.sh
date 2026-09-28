#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_dir
candidate=${PHONE_TOUCHPAD_PLUS_REPO:-"${script_dir}/../../.."}

if [[ -z "${candidate}" || "${candidate}" == *$'\n'* || ! -d "${candidate}" ]]; then
    printf 'Phone Touchpad Plus repository not found\n' >&2
    exit 1
fi
repo=$(cd "${candidate}" && pwd -P)
if [[ ! -f "${repo}/go.mod" || ! -r "${repo}/scripts/doctor.sh" ]]; then
    printf 'Not a validated Phone Touchpad Plus checkout\n' >&2
    exit 1
fi
printf '%s\n' "${repo}"

