#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly repo_root
cd "${repo_root}"

if [[ "${1:-}" == "--self-test" ]]; then
    fixture="tests/privacy-self-test.txt"
    cleanup_self_test() {
        rm -f -- "${fixture}"
    }
    trap cleanup_self_test EXIT INT TERM
    printf '/%s/%s/projects/private-file\n' 'home' 'private-person' >"${fixture}"
    if "${BASH_SOURCE[0]}"; then
        printf 'privacy self-test did not detect its fixture\n' >&2
        exit 1
    fi
    cleanup_self_test
    trap - EXIT INT TERM
    "${BASH_SOURCE[0]}"
    printf 'repository privacy self-test passed\n'
    exit 0
fi

repository_files=()
while IFS= read -r -d '' file; do
    repository_files[${#repository_files[@]}]=${file}
done < <(git ls-files --cached --others --exclude-standard -z)
text_files=()
for file in "${repository_files[@]}"; do
    if [[ -f "${file}" ]]; then
        text_files+=("${file}")
    fi
done
if [[ ${#text_files[@]} -eq 0 ]]; then
    printf 'repository scan found no files\n' >&2
    exit 1
fi

failed=false
report_pattern() {
    local label=$1
    local pattern=$2
    local matches
    matches=$(rg --line-number --no-heading --color=never --regexp "${pattern}" -- "${text_files[@]}" || true)
    if [[ -n "${matches}" ]]; then
        printf '%s found:\n%s\n' "${label}" "${matches}" >&2
        failed=true
    fi
}

report_pattern 'personal home path' '/(home|Users)/[[:alnum:]_.-]+/'
report_pattern 'private key material' 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY'
report_pattern 'live service command' 'ExecStart=.*phone-'"magic-trackpad"

hex_matches=$(rg --line-number --no-heading --color=never \
    --regexp '(^|[^[:xdigit:]])[[:xdigit:]]{32,}([^[:xdigit:]]|$)' \
    -- "${text_files[@]}" || true)
if [[ -n "${hex_matches}" ]]; then
    unexpected_hex=$(printf '%s\n' "${hex_matches}" | \
        rg -v '^flatpak/[^:]+:[0-9]+:[[:space:]]*commit:' || true)
    if [[ -n "${unexpected_hex}" ]]; then
        printf 'secret-shaped hexadecimal value found:\n%s\n' "${unexpected_hex}" >&2
        failed=true
    fi
fi

url_secret_matches=$(rg --line-number --no-heading --color=never \
    --regexp 'https?://[^[:space:]]+/#([[:alnum:]+/_-]{16,})' \
    -- "${text_files[@]}" || true)
if [[ -n "${url_secret_matches}" ]]; then
    unexpected_url_secret=$(printf '%s\n' "${url_secret_matches}" | rg -v 'TEST-FIXTURE' || true)
    if [[ -n "${unexpected_url_secret}" ]]; then
        printf 'secret-bearing URL fragment found:\n%s\n' "${unexpected_url_secret}" >&2
        failed=true
    fi
fi

private_matches=$(rg --line-number --no-heading --color=never \
    --regexp '(^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|169\.254\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)' \
    -- "${text_files[@]}" || true)
if [[ -n "${private_matches}" ]]; then
    unexpected_private=$(printf '%s\n' "${private_matches}" | rg -v '^host_test\.go:' || true)
    if [[ -n "${unexpected_private}" ]]; then
        printf 'private network address found:\n%s\n' "${unexpected_private}" >&2
        failed=true
    fi
fi

private_user=${PTP_PRIVATE_USERNAME:-$(id -un)}
if [[ -n "${private_user}" && "${private_user}" != root && "${private_user}" != runner ]]; then
    user_matches=$(
        rg --line-number --no-heading --color=never --fixed-strings \
            "/Users/${private_user}/" -- "${text_files[@]}" || true
        rg --line-number --no-heading --color=never --fixed-strings \
            "/home/${private_user}/" -- "${text_files[@]}" || true
    )
    if [[ -n "${user_matches}" ]]; then
        printf 'local operating-system username found:\n%s\n' "${user_matches}" >&2
        failed=true
    fi
fi

private_hostname=${PTP_PRIVATE_HOSTNAME:-$(hostname 2>/dev/null || true)}
if [[ -n "${private_hostname}" ]]; then
    hostname_matches=$(rg --line-number --no-heading --color=never --fixed-strings \
        "${private_hostname}" -- "${text_files[@]}" || true)
    if [[ -n "${hostname_matches}" ]]; then
        printf 'local hostname found:\n%s\n' "${hostname_matches}" >&2
        failed=true
    fi
fi

for file in "${repository_files[@]}"; do
    lower_file=$(printf '%s' "${file}" | tr '[:upper:]' '[:lower:]')
    if [[ "${lower_file}" =~ (^|/)(pairing|qr-code)[^/]*\.png$ ]]; then
        printf 'generated pairing QR file found: %s\n' "${file}" >&2
        failed=true
    fi
done

require_documentation() {
    local file=$1
    local pattern=$2
    local label=$3
    if [[ ! -f "${file}" ]] || ! rg --ignore-case --quiet "${pattern}" "${file}"; then
        printf '%s is missing from %s\n' "${label}" "${file}" >&2
        failed=true
    fi
}

for readme in README.md README.zh-CN.md; do
    require_documentation "${readme}" 'Phone Touchpad Plus' 'product name'
    require_documentation "${readme}" 'v0\.1\.0' 'release version'
    require_documentation "${readme}" 'Unrud/remote-touchpad.*(v?1\.5\.5|1\.5\.5)' 'upstream version attribution'
    require_documentation "${readme}" 'GPL-3\.0-or-later' 'license identifier'
    require_documentation "${readme}" '(trusted (local network|LAN)|可信局域网)' 'trusted-LAN restriction'
    require_documentation "${readme}" '(no TLS|without TLS|不提供 TLS|没有 TLS)' 'no-TLS warning'
    require_documentation "${readme}" 'Ubuntu 24\.04.*GNOME X11' 'validated platform'
    require_documentation "${readme}" '(Windows|macOS|Wayland).*(enhanced gestures|增强手势)' 'unsupported enhanced-gesture scope'
    require_documentation "${readme}" 'scripts/install\.sh' 'install command'
    require_documentation "${readme}" 'scripts/doctor\.sh' 'doctor command'
    require_documentation "${readme}" 'scripts/install\.sh.*--upgrade' 'upgrade command'
    require_documentation "${readme}" 'scripts/uninstall\.sh' 'uninstall command'
    require_documentation "${readme}" 'skills/phone-touchpad-plus' 'Skill installation path'
done

for document in README.md README.zh-CN.md CUSTOMIZATION.md; do
    while IFS= read -r markdown_match; do
        link=${markdown_match#](}
        link=${link%)}
        case "${link}" in
            http://*|https://*|'#'*) continue ;;
        esac
        link=${link%%#*}
        if [[ -n "${link}" && ! -e "$(dirname "${document}")/${link}" ]]; then
            printf 'broken local link in %s: %s\n' "${document}" "${link}" >&2
            failed=true
        fi
    done < <(rg --only-matching '\]\([^)]+\)' "${document}" || true)
done

[[ -f COPYING ]] || { printf 'COPYING is missing\n' >&2; failed=true; }
if ! rg --quiet 'Unrud/remote-touchpad' README.md CUSTOMIZATION.md; then
    printf 'upstream attribution is missing\n' >&2
    failed=true
fi
if ! rg --quiet '2026-09-29' CHANGELOG.md CUSTOMIZATION.md; then
    printf 'fork modification date is missing\n' >&2
    failed=true
fi

if [[ "${failed}" == true ]]; then
    exit 1
fi
printf 'repository privacy and attribution checks passed (%d files)\n' "${#repository_files[@]}"
