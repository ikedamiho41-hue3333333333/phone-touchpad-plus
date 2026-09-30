#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
# shellcheck source=scripts/lib/common.sh
source "${repo_root}/scripts/lib/common.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

escaped=$(ptp_xml_escape 'a&<>"'"'"'')
[[ "${escaped}" == 'a&amp;&lt;&gt;&quot;&apos;' ]] || \
    fail "XML escaping produced ${escaped}"

ptp_version_ge 1.26.8 1.26.0 || fail 'newer patch release was rejected'
ptp_version_ge 1.26 1.26.0 || fail 'equivalent shortened version was rejected'
if ptp_version_ge 1.25.9 1.26.0; then
    fail 'older minor release was accepted'
fi

printf 'portable lifecycle helper tests passed\n'
