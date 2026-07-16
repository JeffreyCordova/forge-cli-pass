#!/bin/sh

set -u

script_dir=$(
  CDPATH= cd -- "$(dirname -- "$0")" &&
    pwd -P
) || exit 1

BUSYBOX=${BUSYBOX:-busybox}
export BUSYBOX

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'tests: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

require_executable() {
  executable=$1

  case $executable in
  */*)
    [ -x "$executable" ] || {
      printf 'tests: required executable is unavailable: %s\n' \
        "$executable" >&2
      exit 1
    }
    ;;

  *)
    require_command "$executable"
    ;;
  esac
}

busybox_honors_fixture_path() {
  probe_dir=$(
    mktemp -d \
      "${TMPDIR:-/tmp}/forge-cli-pass-busybox-probe.XXXXXX"
  ) || return 1

  cat >"$probe_dir/sha256sum" <<'EOF'
#!/bin/sh
printf '%s\n' 'fixture-sha256sum'
EOF

  chmod 755 "$probe_dir/sha256sum" || {
    rm -rf -- "$probe_dir"
    return 1
  }

  probe_output=$(
    PATH="$probe_dir:$PATH" \
      "$BUSYBOX" ash -c \
      'sha256sum /dev/null' 2>/dev/null
  )
  probe_status=$?

  rm -rf -- "$probe_dir"

  [ "$probe_status" -eq 0 ] &&
    [ "$probe_output" = 'fixture-sha256sum' ]
}

require_command dash
require_command bash
require_executable "$BUSYBOX"
require_command cmp
require_command mktemp
require_command sha256sum
require_command stat
require_command chmod
require_command rm

"$BUSYBOX" ash -c ':' >/dev/null 2>&1 || {
  printf 'tests: BusyBox ash is unavailable\n' >&2
  exit 1
}

busybox_honors_fixture_path || {
  printf '%s\n' \
    'tests: the selected BusyBox ash executes internal applets before PATH fixtures' \
    'tests: the glab-pass failure-injection matrix requires a BusyBox build that honors PATH precedence' \
    'tests: set BUSYBOX to the path of a compatible BusyBox executable' >&2

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
  "$BUSYBOX" ash

printf '\n'

if [ "$overall_status" -eq 0 ]; then
  printf 'All shell-matrix tests passed.\n'
else
  printf 'One or more shell-matrix tests failed.\n' >&2
fi

exit "$overall_status"
