#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly repo_root
skill_dir="${repo_root}/skills/phone-touchpad-plus"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-skill-test.XXXXXXXX")
trap 'rm -r -- "${test_root}"' EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

skill_file="${skill_dir}/SKILL.md"
resolver="${skill_dir}/scripts/resolve-repo.sh"
doctor_wrapper="${skill_dir}/scripts/run-doctor.sh"
for required_file in "${skill_file}" "${resolver}" "${doctor_wrapper}"; do
    [[ -f "${required_file}" ]] || fail "missing Skill file: ${required_file}"
done

rg --quiet '^name: phone-touchpad-plus$' "${skill_file}" || fail 'frontmatter name is missing'
rg --quiet '^description: Use when .*(install|pair|sensitivity|diagnos|update|uninstall)' "${skill_file}" || \
    fail 'description does not expose concrete trigger cases'
rg --quiet 'Ubuntu 24\.04.*GNOME X11' "${skill_file}" || fail 'supported desktop scope is missing'
rg --quiet 'iPhone.*Safari.*trusted (local network|LAN)' "${skill_file}" || fail 'phone/network scope is missing'
rg --quiet '\| Diagnose or view status \| No \|' "${skill_file}" || fail 'read-only diagnosis policy is missing'
for protected_action in 'Install or update' 'Change sensitivity and restart' 'Change firewall rules' 'Uninstall'; do
    rg --quiet "\\| ${protected_action} \\| Yes \\|" "${skill_file}" || \
        fail "authorization policy is missing for ${protected_action}"
done
rg --quiet 'Never print.*(secret|pairing URL fragment)' "${skill_file}" || fail 'redaction policy is missing'

default_repo=$(bash "${resolver}")
[[ "${default_repo}" == "${repo_root}" ]] || fail "default resolver returned ${default_repo}"

fixture_repo="${test_root}/fixture-repo"
mkdir -p "${fixture_repo}/scripts"
touch "${fixture_repo}/go.mod"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >"${PTP_SKILL_CALL_LOG}"' \
    'printf "STATUS: OK\n"' >"${fixture_repo}/scripts/doctor.sh"
chmod 0755 "${fixture_repo}/scripts/doctor.sh"

resolved_override=$(PHONE_TOUCHPAD_PLUS_REPO="${fixture_repo}" bash "${resolver}")
[[ "${resolved_override}" == "${fixture_repo}" ]] || fail 'explicit repository override did not resolve'
if PHONE_TOUCHPAD_PLUS_REPO="${test_root}/missing" bash "${resolver}" >/dev/null 2>&1; then
    fail 'resolver accepted an invalid checkout'
fi

wrapper_output=$(PHONE_TOUCHPAD_PLUS_REPO="${fixture_repo}" \
    PTP_SKILL_CALL_LOG="${test_root}/doctor-call.log" \
    bash "${doctor_wrapper}" --prefix "${test_root}/prefix")
[[ "${wrapper_output}" == 'STATUS: OK' ]] || fail 'doctor wrapper did not return doctor output'
[[ "$(<"${test_root}/doctor-call.log")" == "--prefix ${test_root}/prefix" ]] || \
    fail 'doctor wrapper did not preserve arguments'
if rg --quiet '(systemctl|install\.sh|uninstall\.sh|restart|enable|disable|rm[[:space:]])' "${doctor_wrapper}"; then
    fail 'doctor wrapper contains mutating operations'
fi

printf 'Phone Touchpad Plus Skill package tests passed\n'
