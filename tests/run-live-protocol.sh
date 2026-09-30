#!/usr/bin/env bash
set -euo pipefail

readonly test_port=18765
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
readonly repo_root
readonly go_command=${1:-go}
test_dir=""
server_pid=""

port_is_open() {
    (exec 3<>"/dev/tcp/127.0.0.1/${test_port}") >/dev/null 2>&1
}

cleanup() {
    if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
        kill "${server_pid}"
        wait "${server_pid}" 2>/dev/null || true
    fi
    if [[ -n "${test_dir}" && -d "${test_dir}" ]]; then
        rm -r -- "${test_dir}"
    fi
}
trap cleanup EXIT INT TERM

if port_is_open; then
    printf 'test port %s is already occupied\n' "${test_port}" >&2
    exit 1
fi

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/phone-touchpad-plus-protocol.XXXXXXXX")
chmod 0700 "${test_dir}"
secret_file="${test_dir}/secret"
server_binary="${test_dir}/phone-touchpad-plus-test-server"
server_log="${test_dir}/server.log"
printf '%s\n' 'integration-test-secret' >"${secret_file}"
chmod 0600 "${secret_file}"

cd "${repo_root}"
"${go_command}" build -tags=null -o "${server_binary}" .
"${server_binary}" \
    -bind "127.0.0.1:${test_port}" \
    -secret-file "${secret_file}" \
    -show-pairing=false >"${server_log}" 2>&1 &
server_pid=$!

ready=false
for _ in {1..100}; do
    if ! kill -0 "${server_pid}" 2>/dev/null; then
        printf 'test server exited before becoming ready\n' >&2
        sed -n '1,80p' "${server_log}" >&2
        exit 1
    fi
    if curl --fail --silent --show-error --max-time 1 \
        "http://127.0.0.1:${test_port}/" >/dev/null; then
        ready=true
        break
    fi
    sleep 0.1
done
if [[ "${ready}" != true ]]; then
    printf 'test server did not become ready\n' >&2
    exit 1
fi

PTP_INTEGRATION_SECRET_FILE="${secret_file}" \
    "${go_command}" test -tags='null integration' -run '^TestLiveProtocol$' .

kill "${server_pid}"
wait "${server_pid}" 2>/dev/null || true
server_pid=""
if port_is_open; then
    printf 'test server still owns port %s after cleanup\n' "${test_port}" >&2
    exit 1
fi
