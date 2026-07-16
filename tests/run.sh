#!/bin/sh

set -u

script_dir=$(
  CDPATH= cd -- "$(dirname -- "$0")" &&
    pwd -P
) || exit 1

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'tests: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

require_command dash
require_command bash
require_command busybox
require_command cmp
require_command mktemp
require_command sha256sum
require_command stat

busybox ash -c ':' >/dev/null 2>&1 || {
  printf 'tests: BusyBox ash is unavailable\n' >&2
  exit 1
}

overall_status=0

run_matrix_entry() {
  label=$1
  shell_kind=$2
  shift 2

  printf '\n== %s ==\n' "$label"

  TEST_SHELL_KIND=$shell_kind
  export TEST_SHELL_KIND

  for test_script in \
    "$script_dir/test-gh-pass.sh" \
    "$script_dir/test-glab-pass.sh"; do
    "$@" "$test_script" ||
      overall_status=1
  done
}

run_matrix_entry \
  'Dash' \
  'dash' \
  dash

run_matrix_entry \
  'Bash in POSIX mode' \
  'bash-posix' \
  bash --posix

run_matrix_entry \
  'BusyBox ash' \
  'busybox-ash' \
  busybox ash

printf '\n'

if [ "$overall_status" -eq 0 ]; then
  printf 'All shell-matrix tests passed.\n'
else
  printf 'One or more shell-matrix tests failed.\n' >&2
fi

exit "$overall_status"
