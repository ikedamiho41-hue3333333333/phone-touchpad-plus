#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
readonly repo_root
test_root=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-uninstall-test.XXXXXXXX")
trap 'rm -r -- "${test_root}"' EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_fixture() {
    local root=$1
    local install_dir="${root}/prefix/lib/phone-touchpad-plus"
    local config_dir="${root}/config/phone-touchpad-plus"
    local data_dir="${root}/data/phone-touchpad-plus"
    mkdir -p "${install_dir}" "${config_dir}" "${data_dir}" "${root}/config/systemd/user"
    touch "${install_dir}/phone-touchpad-plus" \
        "${install_dir}/phone-touchpad-plus-makeqr" \
        "${install_dir}/phone-touchpad-plus-probe" \
        "${install_dir}/run-service.sh" \
        "${config_dir}/secret" "${config_dir}/settings.env" \
        "${data_dir}/pairing.png" \
        "${root}/config/systemd/user/phone-touchpad-plus.service"
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'printf "systemctl %s\\n" "$*" >>"${PTP_COMMAND_LOG}"' \
        >"${root}/systemctl"
    chmod 0755 "${root}/systemctl"
}

run_uninstall() {
    local root=$1
    shift
    env \
        HOME="${root}/home" \
        XDG_CONFIG_HOME="${root}/config" \
        XDG_DATA_HOME="${root}/data" \
        PTP_SYSTEMCTL="${root}/systemctl" \
        PTP_COMMAND_LOG="${root}/commands.log" \
        bash "${repo_root}/scripts/uninstall.sh" --prefix "${root}/prefix" "$@"
}

dry_root="${test_root}/dry"
make_fixture "${dry_root}"
before_dry=$(find "${dry_root}" -type f -printf '%P\n' | sort)
run_uninstall "${dry_root}" --dry-run >/dev/null
after_dry=$(find "${dry_root}" -type f -printf '%P\n' | sort)
[[ "${before_dry}" == "${after_dry}" ]] || fail 'dry-run removed files'
[[ ! -e "${dry_root}/commands.log" ]] || fail 'dry-run called systemctl'

unsafe_root="${test_root}/unsafe"
make_fixture "${unsafe_root}"
mv "${unsafe_root}/prefix/lib/phone-touchpad-plus" "${unsafe_root}/outside"
ln -s "${unsafe_root}/outside" "${unsafe_root}/prefix/lib/phone-touchpad-plus"
if run_uninstall "${unsafe_root}" >/dev/null 2>&1; then
    fail 'uninstall accepted an install directory symlink outside the prefix'
fi
[[ -f "${unsafe_root}/outside/phone-touchpad-plus" ]] || fail 'unsafe validation removed external application'
[[ ! -e "${unsafe_root}/commands.log" ]] || fail 'unsafe validation called systemctl'

root="${test_root}/default"
make_fixture "${root}"
run_uninstall "${root}" >/dev/null
[[ -f "${root}/config/phone-touchpad-plus/secret" ]] || fail 'default uninstall removed secret'
[[ -f "${root}/config/phone-touchpad-plus/settings.env" ]] || fail 'default uninstall removed settings'
[[ ! -e "${root}/prefix/lib/phone-touchpad-plus/phone-touchpad-plus" ]] || fail 'application remains'
[[ ! -e "${root}/config/systemd/user/phone-touchpad-plus.service" ]] || fail 'unit remains'
[[ ! -e "${root}/data/phone-touchpad-plus/pairing.png" ]] || fail 'pairing QR remains'
rg --quiet 'disable --now phone-touchpad-plus.service' "${root}/commands.log" || fail 'service was not disabled'

run_uninstall "${root}" --purge-config >/dev/null
[[ ! -e "${root}/config/phone-touchpad-plus" ]] || fail 'purge left configuration behind'
[[ -d "${root}/config" ]] || fail 'purge removed configuration parent'

printf 'conservative uninstall lifecycle tests passed\n'
