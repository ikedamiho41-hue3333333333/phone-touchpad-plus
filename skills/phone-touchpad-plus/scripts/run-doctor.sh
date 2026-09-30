#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_dir
repo=$(bash "${script_dir}/resolve-repo.sh")
exec bash "${repo}/scripts/doctor.sh" "$@"

