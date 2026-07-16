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

target=${GH_PASS_UNDER_TEST:-"$repo_root/src/gh-pass"}
fixture_bin="$script_dir/fixtures/bin"
original_path=$PATH
TEST_SHELL_KIND=${TEST_SHELL_KIND:-dash}
BUSYBOX=${BUSYBOX:-busybox}

suite_start "gh-pass under $TEST_SHELL_KIND"

setup_case() {
  CASE_DIR="$SUITE_ROOT/case-$TEST_TOTAL"

  mkdir -p \
    "$CASE_DIR/home" \
    "$CASE_DIR/work"

  STDOUT_FILE="$CASE_DIR/stdout"
  STDERR_FILE="$CASE_DIR/stderr"

  FAKE_PASS_CALL_LOG="$CASE_DIR/pass-called"
  FAKE_PASS_ENTRY_LOG="$CASE_DIR/pass-entry"
  FAKE_PASS_PAYLOAD_FILE="$CASE_DIR/pass-payload"

  FAKE_GH_CALLED_LOG="$CASE_DIR/gh-called"
  FAKE_GH_TOKEN_LOG="$CASE_DIR/gh-token"
  FAKE_GH_TOKEN_SET_LOG="$CASE_DIR/gh-token-set"
  FAKE_GH_ARGC_LOG="$CASE_DIR/gh-argc"
  FAKE_GH_ARGS_LOG="$CASE_DIR/gh-args"

  FAKE_PASS_MODE='show-ok'
  FAKE_PASS_STATUS=1
  FAKE_GH_STATUS=0

  HOME="$CASE_DIR/home"
  PATH="$fixture_bin:$original_path"

  export \
    HOME \
    PATH \
    FAKE_PASS_CALL_LOG \
    FAKE_PASS_ENTRY_LOG \
    FAKE_PASS_PAYLOAD_FILE \
    FAKE_GH_CALLED_LOG \
    FAKE_GH_TOKEN_LOG \
    FAKE_GH_TOKEN_SET_LOG \
    FAKE_GH_ARGC_LOG \
    FAKE_GH_ARGS_LOG \
    FAKE_PASS_MODE \
    FAKE_PASS_STATUS \
    FAKE_GH_STATUS

  unset FORGE_CLI_PASS_GITHUB_ENTRY
  unset GH_TOKEN

  printf '%s\n' \
    'default-test-token' \
    'operator note' >"$FAKE_PASS_PAYLOAD_FILE"
}

run_wrapper() {
  case $TEST_SHELL_KIND in
  dash)
    dash "$target" "$@"
    ;;

  bash-posix)
    bash --posix "$target" "$@"
    ;;

  busybox-ash)
    "$BUSYBOX" ash "$target" "$@"
    ;;

  *)
    printf 'tests: unknown TEST_SHELL_KIND: %s\n' \
      "$TEST_SHELL_KIND" >&2
    return 125
    ;;
  esac >"$STDOUT_FILE" 2>"$STDERR_FILE"

  RUN_STATUS=$?
}

test_default_entry() {
  setup_case
  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" \
    'ordinary invocation should succeed' || return 1

  assert_file_equals \
    'forge-cli-pass/github/token' \
    "$FAKE_PASS_ENTRY_LOG" \
    'default pass entry should be selected' || return 1

  assert_exists "$FAKE_GH_CALLED_LOG" \
    'gh should be invoked'
}

test_explicit_entry_override() {
  setup_case

  FORGE_CLI_PASS_GITHUB_ENTRY='work/github/token'
  export FORGE_CLI_PASS_GITHUB_ENTRY

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_file_equals \
    'work/github/token' \
    "$FAKE_PASS_ENTRY_LOG" \
    'explicit pass entry should be selected'
}

test_override_with_spaces_is_one_argument() {
  setup_case

  FORGE_CLI_PASS_GITHUB_ENTRY='work credentials/github token'
  export FORGE_CLI_PASS_GITHUB_ENTRY

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_file_equals \
    'work credentials/github token' \
    "$FAKE_PASS_ENTRY_LOG" \
    'entry containing spaces should remain one argument'
}

test_empty_override_fails_before_dependency_use() {
  setup_case

  FORGE_CLI_PASS_GITHUB_ENTRY=''
  export FORGE_CLI_PASS_GITHUB_ENTRY

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" \
    'empty override should return wrapper failure' || return 1

  assert_not_exists "$FAKE_PASS_CALL_LOG" \
    'pass should not be invoked' || return 1

  assert_not_exists "$FAKE_GH_CALLED_LOG" \
    'gh should not be invoked' || return 1

  assert_file_contains \
    'FORGE_CLI_PASS_GITHUB_ENTRY is set but empty' \
    "$STDERR_FILE"
}

test_newline_override_is_rejected() {
  setup_case

  FORGE_CLI_PASS_GITHUB_ENTRY='work/github
token'
  export FORGE_CLI_PASS_GITHUB_ENTRY

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1

  assert_not_exists "$FAKE_PASS_CALL_LOG" \
    'pass should not be invoked for invalid configuration' || return 1

  assert_not_exists "$FAKE_GH_CALLED_LOG" \
    'gh should not be invoked for invalid configuration' || return 1

  assert_file_contains \
    'contains a newline' \
    "$STDERR_FILE"
}

test_carriage_return_override_is_rejected() {
  setup_case

  FORGE_CLI_PASS_GITHUB_ENTRY=$(printf 'work/github\rtoken')
  export FORGE_CLI_PASS_GITHUB_ENTRY

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1

  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_GH_CALLED_LOG" || return 1

  assert_file_contains \
    'contains a carriage return' \
    "$STDERR_FILE"
}

test_pass_failure_prevents_parent_execution() {
  setup_case

  FAKE_PASS_MODE='show-fail'
  FAKE_PASS_STATUS=7

  export FAKE_PASS_MODE FAKE_PASS_STATUS

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" \
    'credential retrieval failure should be a wrapper failure' ||
    return 1

  assert_not_exists "$FAKE_GH_CALLED_LOG" \
    'gh should not run after pass failure' || return 1

  assert_file_contains \
    'failed to read credential entry' \
    "$STDERR_FILE"
}

test_empty_first_line_is_rejected() {
  setup_case

  printf '\n%s\n' 'operator note' >"$FAKE_PASS_PAYLOAD_FILE"

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" \
    'empty first line should be rejected' || return 1

  assert_not_exists "$FAKE_GH_CALLED_LOG" \
    'gh should not receive an empty token' || return 1

  assert_file_contains \
    'credential entry has an empty first line' \
    "$STDERR_FILE"
}

test_only_first_line_is_injected() {
  setup_case

  printf '%s\n' \
    'selected-token' \
    'ignored note' \
    'ignored metadata' >"$FAKE_PASS_PAYLOAD_FILE"

  GH_TOKEN='ambient-token'
  export GH_TOKEN

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_file_equals \
    'x' \
    "$FAKE_GH_TOKEN_SET_LOG" \
    'GH_TOKEN should be present in the parent environment' || return 1

  assert_file_equals \
    'selected-token' \
    "$FAKE_GH_TOKEN_LOG" \
    'pass token should replace any ambient GH_TOKEN value'
}

test_parent_arguments_are_preserved() {
  setup_case

  run_wrapper \
    repo \
    view \
    'owner/repo' \
    --json \
    'name,url' \
    '' \
    '*?[abc]'

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_file_equals \
    '7' \
    "$FAKE_GH_ARGC_LOG" \
    'parent argument count should be preserved' || return 1

  expected_arguments='1=repo
2=view
3=owner/repo
4=--json
5=name,url
6=
7=*?[abc]'

  assert_file_equals \
    "$expected_arguments" \
    "$FAKE_GH_ARGS_LOG" \
    'parent argument order and boundaries should be preserved'
}

test_exact_parent_status_is_preserved() {
  setup_case

  FAKE_GH_STATUS=23
  export FAKE_GH_STATUS

  run_wrapper repo view

  assert_equals \
    '23' \
    "$RUN_STATUS" \
    'gh exit status should be returned exactly'
}

test_auth_status_is_allowed() {
  setup_case

  run_wrapper auth status

  assert_equals '0' "$RUN_STATUS" || return 1
  assert_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_exists "$FAKE_GH_CALLED_LOG"
}

test_auth_token_is_rejected() {
  setup_case

  run_wrapper auth token

  assert_equals '1' "$RUN_STATUS" || return 1

  assert_not_exists "$FAKE_PASS_CALL_LOG" \
    'rejected command should not access pass' || return 1

  assert_not_exists "$FAKE_GH_CALLED_LOG" \
    'rejected command should not invoke gh' || return 1

  assert_file_contains \
    'unsupported credential-management command: auth token' \
    "$STDERR_FILE"
}

test_auth_status_show_token_is_rejected() {
  setup_case

  run_wrapper auth status --show-token

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_GH_CALLED_LOG" || return 1

  assert_file_contains \
    'credential disclosure is outside the wrapper compatibility contract' \
    "$STDERR_FILE"
}

test_auth_status_short_token_flag_is_rejected() {
  setup_case

  run_wrapper auth status -t

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_GH_CALLED_LOG"
}

test_unknown_auth_subcommand_is_rejected() {
  setup_case

  run_wrapper auth future-command

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_GH_CALLED_LOG" || return 1

  assert_file_contains \
    'unsupported credential-management command: auth future-command' \
    "$STDERR_FILE"
}

test_auth_text_outside_auth_namespace_is_forwarded() {
  setup_case

  run_wrapper api repos/example/auth/status

  assert_equals '0' "$RUN_STATUS" || return 1
  assert_exists "$FAKE_GH_CALLED_LOG" || return 1

  expected_arguments='1=api
2=repos/example/auth/status'

  assert_file_equals \
    "$expected_arguments" \
    "$FAKE_GH_ARGS_LOG" \
    'auth-like text belonging to another command should be forwarded'
}

run_test \
  'uses the documented default pass entry' \
  test_default_entry

run_test \
  'uses an explicit pass-entry override' \
  test_explicit_entry_override

run_test \
  'passes an entry containing spaces as one argument' \
  test_override_with_spaces_is_one_argument

run_test \
  'rejects an explicitly empty entry override' \
  test_empty_override_fails_before_dependency_use

run_test \
  'rejects a newline in the entry override' \
  test_newline_override_is_rejected

run_test \
  'rejects a carriage return in the entry override' \
  test_carriage_return_override_is_rejected

run_test \
  'does not invoke gh after pass retrieval failure' \
  test_pass_failure_prevents_parent_execution

run_test \
  'rejects an empty credential first line' \
  test_empty_first_line_is_rejected

run_test \
  'injects only the credential first line' \
  test_only_first_line_is_injected

run_test \
  'preserves parent argument order and boundaries' \
  test_parent_arguments_are_preserved

run_test \
  'preserves the exact parent exit status' \
  test_exact_parent_status_is_preserved

run_test \
  'allows auth status' \
  test_auth_status_is_allowed

run_test \
  'rejects auth token before credential retrieval' \
  test_auth_token_is_rejected

run_test \
  'rejects auth status --show-token' \
  test_auth_status_show_token_is_rejected

run_test \
  'rejects auth status -t' \
  test_auth_status_short_token_flag_is_rejected

run_test \
  'rejects unknown auth subcommands' \
  test_unknown_auth_subcommand_is_rejected

run_test \
  'does not misclassify auth-like ordinary arguments' \
  test_auth_text_outside_auth_namespace_is_forwarded

suite_finish
