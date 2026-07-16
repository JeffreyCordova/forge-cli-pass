#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -u

script_dir=$(
  CDPATH= cd -- "$(dirname -- "$0")" &&
    pwd -P
) || exit 1

repo_root=$(
  CDPATH= cd -- "$script_dir/.." &&
    pwd -P
) || exit 1

. "$script_dir/helpers/testlib.sh"

MAKE=${MAKE:-make}
original_path=$PATH

suite_start 'installation and development links'

create_forbidden_commands() {
  forbidden_bin=$1

  mkdir -p "$forbidden_bin" || return 1

  cat >"$forbidden_bin/forbidden-command" <<'EOF'
#!/bin/sh

set -u

: "${FORBIDDEN_COMMAND_LOG:?}"

printf '%s\n' "${0##*/}" >>"$FORBIDDEN_COMMAND_LOG"
exit 97
EOF

  chmod 755 "$forbidden_bin/forbidden-command" || return 1

  for command_name in \
    pass \
    gh \
    glab \
    gpg \
    curl \
    wget \
    sudo \
    doas; do
    ln -s \
      forbidden-command \
      "$forbidden_bin/$command_name" ||
      return 1
  done
}

setup_case() {
  CASE_DIR="$SUITE_ROOT/case-$TEST_TOTAL"

  mkdir -p "$CASE_DIR" || return 1

  STDOUT_FILE="$CASE_DIR/stdout"
  STDERR_FILE="$CASE_DIR/stderr"

  FORBIDDEN_COMMAND_LOG="$CASE_DIR/forbidden-command-log"
  FORBIDDEN_BIN="$CASE_DIR/forbidden-bin"

  create_forbidden_commands "$FORBIDDEN_BIN" || return 1

  PATH="$FORBIDDEN_BIN:$original_path"

  export \
    PATH \
    FORBIDDEN_COMMAND_LOG
}

run_make() {
  "$MAKE" \
    --no-print-directory \
    -C "$repo_root" \
    "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"

  RUN_STATUS=$?
}

assert_mode() {
  expected_mode=$1
  path=$2
  description=${3:-unexpected filesystem mode}

  actual_mode=$(stat -c '%a' -- "$path") || {
    printf '    assertion failed: could not inspect mode: %s\n' \
      "$path" >&2
    return 1
  }

  assert_equals \
    "$expected_mode" \
    "$actual_mode" \
    "$description"
}

assert_no_forbidden_commands() {
  assert_not_exists \
    "$FORBIDDEN_COMMAND_LOG" \
    'installation invoked a prohibited credential, network, or privilege command'
}

test_staged_install() {
  setup_case

  staging_root="$CASE_DIR/staging"

  run_make \
    install \
    DESTDIR="$staging_root" \
    PREFIX=/usr

  assert_equals \
    '0' \
    "$RUN_STATUS" \
    'staged installation should succeed' || return 1

  installed_dir="$staging_root/usr/bin"
  installed_gh="$installed_dir/gh-pass"
  installed_glab="$installed_dir/glab-pass"

  assert_exists "$installed_gh" || return 1
  assert_exists "$installed_glab" || return 1

  assert_files_equal \
    "$repo_root/src/gh-pass" \
    "$installed_gh" \
    'installed gh-pass should match its canonical source' || return 1

  assert_files_equal \
    "$repo_root/src/glab-pass" \
    "$installed_glab" \
    'installed glab-pass should match its canonical source' || return 1

  assert_mode \
    '755' \
    "$installed_gh" \
    'installed gh-pass should have mode 0755' || return 1

  assert_mode \
    '755' \
    "$installed_glab" \
    'installed glab-pass should have mode 0755' || return 1

  assert_no_forbidden_commands
}

test_prefix_with_spaces() {
  setup_case

  prefix="$CASE_DIR/prefix with spaces"

  run_make \
    install \
    PREFIX="$prefix"

  assert_equals \
    '0' \
    "$RUN_STATUS" \
    'installation should support a quoted prefix containing spaces' ||
    return 1

  assert_exists "$prefix/bin/gh-pass" || return 1
  assert_exists "$prefix/bin/glab-pass" || return 1

  assert_no_forbidden_commands
}

test_custom_bindir() {
  setup_case

  custom_bindir="$CASE_DIR/custom command directory"

  run_make \
    install \
    BINDIR="$custom_bindir"

  assert_equals \
    '0' \
    "$RUN_STATUS" \
    'installation should honor an explicit BINDIR' || return 1

  assert_exists "$custom_bindir/gh-pass" || return 1
  assert_exists "$custom_bindir/glab-pass" || return 1

  assert_no_forbidden_commands
}

test_uninstall_has_narrow_scope() {
  setup_case

  prefix="$CASE_DIR/prefix"
  bindir="$prefix/bin"

  run_make \
    install \
    PREFIX="$prefix"

  assert_equals '0' "$RUN_STATUS" || return 1

  printf '%s\n' 'unrelated file' >"$bindir/unrelated"

  run_make \
    uninstall \
    PREFIX="$prefix"

  assert_equals \
    '0' \
    "$RUN_STATUS" \
    'normal uninstall should succeed' || return 1

  assert_not_exists \
    "$bindir/gh-pass" \
    'normal uninstall should remove gh-pass' || return 1

  assert_not_exists \
    "$bindir/glab-pass" \
    'normal uninstall should remove glab-pass' || return 1

  assert_exists \
    "$bindir/unrelated" \
    'normal uninstall must retain unrelated files' || return 1

  assert_exists \
    "$bindir" \
    'normal uninstall must retain the binary directory' || return 1

  assert_no_forbidden_commands
}

test_dev_install_creates_absolute_links() {
  setup_case

  prefix="$CASE_DIR/dev-prefix"
  bindir="$prefix/bin"

  run_make \
    dev-install \
    PREFIX="$prefix"

  assert_equals \
    '0' \
    "$RUN_STATUS" \
    'development installation should succeed' || return 1

  [ -L "$bindir/gh-pass" ] || {
    printf '    assertion failed: gh-pass is not a symbolic link\n' >&2
    return 1
  }

  [ -L "$bindir/glab-pass" ] || {
    printf '    assertion failed: glab-pass is not a symbolic link\n' >&2
    return 1
  }

  gh_target=$(readlink -- "$bindir/gh-pass") || return 1
  glab_target=$(readlink -- "$bindir/glab-pass") || return 1

  assert_equals \
    "$repo_root/src/gh-pass" \
    "$gh_target" \
    'gh-pass should link to the current physical checkout' || return 1

  assert_equals \
    "$repo_root/src/glab-pass" \
    "$glab_target" \
    'glab-pass should link to the current physical checkout' || return 1

  case $gh_target in
  /*)
    ;;
  *)
    fail_assertion 'gh-pass development link is not absolute'
    return 1
    ;;
  esac

  case $glab_target in
  /*)
    ;;
  *)
    fail_assertion 'glab-pass development link is not absolute'
    return 1
    ;;
  esac

  run_make \
    dev-install \
    PREFIX="$prefix"

  assert_equals \
    '0' \
    "$RUN_STATUS" \
    'development installation should be idempotent for expected links' ||
    return 1

  assert_no_forbidden_commands
}

test_dev_install_refuses_regular_file() {
  setup_case

  prefix="$CASE_DIR/dev-prefix"
  bindir="$prefix/bin"

  mkdir -p "$bindir"
  printf '%s\n' 'operator-owned file' >"$bindir/gh-pass"

  run_make \
    dev-install \
    PREFIX="$prefix"

  assert_nonzero \
    "$RUN_STATUS" \
    'development installation should reject an existing regular file' ||
    return 1

  assert_file_equals \
    'operator-owned file' \
    "$bindir/gh-pass" \
    'development installation must not replace the existing file' ||
    return 1

  assert_not_exists \
    "$bindir/glab-pass" \
    'development installation should stop after the conflict' || return 1

  assert_file_contains \
    'refusing to replace existing path' \
    "$STDERR_FILE" || return 1

  assert_no_forbidden_commands
}

test_dev_uninstall_removes_only_matching_links() {
  setup_case

  prefix="$CASE_DIR/dev-prefix"
  bindir="$prefix/bin"

  run_make \
    dev-install \
    PREFIX="$prefix"

  assert_equals '0' "$RUN_STATUS" || return 1

  unrelated_target="$CASE_DIR/unrelated-target"
  printf '%s\n' 'unrelated target' >"$unrelated_target"

  rm -f -- "$bindir/glab-pass"
  ln -s -- "$unrelated_target" "$bindir/glab-pass"

  run_make \
    dev-uninstall \
    PREFIX="$prefix"

  assert_nonzero \
    "$RUN_STATUS" \
    'a mismatched development link should produce failure' || return 1

  assert_not_exists \
    "$bindir/gh-pass" \
    'matching gh-pass link should be removed' || return 1

  [ -L "$bindir/glab-pass" ] || {
    printf '    assertion failed: unrelated glab-pass link was removed\n' \
      >&2
    return 1
  }

  retained_target=$(readlink -- "$bindir/glab-pass") || return 1

  assert_equals \
    "$unrelated_target" \
    "$retained_target" \
    'unrelated symbolic link should remain unchanged' || return 1

  assert_file_contains \
    'refusing to remove unrelated symbolic link' \
    "$STDERR_FILE" || return 1

  assert_no_forbidden_commands
}

test_dev_uninstall_retains_copied_installation() {
  setup_case

  prefix="$CASE_DIR/prefix"
  bindir="$prefix/bin"

  run_make \
    install \
    PREFIX="$prefix"

  assert_equals '0' "$RUN_STATUS" || return 1

  run_make \
    dev-uninstall \
    PREFIX="$prefix"

  assert_nonzero \
    "$RUN_STATUS" \
    'development uninstall should reject copied installations' ||
    return 1

  [ -f "$bindir/gh-pass" ] && [ ! -L "$bindir/gh-pass" ] || {
    printf '    assertion failed: copied gh-pass was altered\n' >&2
    return 1
  }

  [ -f "$bindir/glab-pass" ] && [ ! -L "$bindir/glab-pass" ] || {
    printf '    assertion failed: copied glab-pass was altered\n' >&2
    return 1
  }

  assert_file_contains \
    'retained non-symlink path' \
    "$STDERR_FILE" || return 1

  assert_no_forbidden_commands
}

run_test \
  'supports staged installation through DESTDIR' \
  test_staged_install

run_test \
  'supports an installation prefix containing spaces' \
  test_prefix_with_spaces

run_test \
  'honors an explicit binary directory' \
  test_custom_bindir

run_test \
  'normal uninstall removes only project command paths' \
  test_uninstall_has_narrow_scope

run_test \
  'development installation creates absolute checkout links' \
  test_dev_install_creates_absolute_links

run_test \
  'development installation refuses an existing regular file' \
  test_dev_install_refuses_regular_file

run_test \
  'development uninstall removes only matching checkout links' \
  test_dev_uninstall_removes_only_matching_links

run_test \
  'development uninstall retains copied installations' \
  test_dev_uninstall_retains_copied_installation

suite_finish
