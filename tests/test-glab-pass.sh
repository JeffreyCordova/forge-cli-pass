#!/bin/sh

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

target=${GLAB_PASS_UNDER_TEST:-"$repo_root/src/glab-pass"}
fixture_bin="$script_dir/fixtures/bin"
original_path=$PATH
TEST_SHELL_KIND=${TEST_SHELL_KIND:-dash}

REAL_MKTEMP=$(command -v mktemp) || exit 1
REAL_SHA256SUM=$(command -v sha256sum) || exit 1
REAL_CHMOD=$(command -v chmod) || exit 1
REAL_RM=$(command -v rm) || exit 1

suite_start "glab-pass under $TEST_SHELL_KIND"

setup_case() {
  CASE_DIR="$SUITE_ROOT/case-$TEST_TOTAL"

  mkdir -p \
    "$CASE_DIR/home" \
    "$CASE_DIR/work" \
    "$CASE_DIR/xdg-runtime"

  STDOUT_FILE="$CASE_DIR/stdout"
  STDERR_FILE="$CASE_DIR/stderr"

  FAKE_PASS_CALL_LOG="$CASE_DIR/pass-called"
  FAKE_PASS_ENTRY_LOG="$CASE_DIR/pass-entry"
  FAKE_PASS_PAYLOAD_FILE="$CASE_DIR/pass-payload"

  FAKE_PASS_WRITEBACK_CALL_LOG="$CASE_DIR/pass-writeback-called"
  FAKE_PASS_WRITEBACK_ENTRY_LOG="$CASE_DIR/pass-writeback-entry"
  FAKE_PASS_WRITEBACK_PAYLOAD_FILE="$CASE_DIR/pass-writeback-payload"

  FAKE_GLAB_CALLED_LOG="$CASE_DIR/glab-called"
  FAKE_GLAB_CONFIG_DIR_LOG="$CASE_DIR/glab-config-dir"
  FAKE_GLAB_CONFIG_PATH_LOG="$CASE_DIR/glab-config-path"
  FAKE_GLAB_CONFIG_SEEN_FILE="$CASE_DIR/glab-config-seen"
  FAKE_GLAB_DIR_MODE_LOG="$CASE_DIR/glab-dir-mode"
  FAKE_GLAB_FILE_MODE_LOG="$CASE_DIR/glab-file-mode"
  FAKE_GLAB_ARGC_LOG="$CASE_DIR/glab-argc"
  FAKE_GLAB_ARGS_LOG="$CASE_DIR/glab-args"
  FAKE_GLAB_MUTATION_FILE="$CASE_DIR/glab-mutation"
  FAKE_GLAB_READY_LOG="$CASE_DIR/glab-ready"
  FAKE_GLAB_SIGNAL_LOG="$CASE_DIR/glab-signal"

  FAKE_MKTEMP_ARGS_LOG="$CASE_DIR/mktemp-args"
  FAKE_MKTEMP_PATH_LOG="$CASE_DIR/mktemp-path"

  FAKE_SHA256SUM_COUNT_FILE="$CASE_DIR/sha256sum-count"
  FAKE_CHMOD_COUNT_FILE="$CASE_DIR/chmod-count"
  FAKE_RM_RUNTIME_CALL_LOG="$CASE_DIR/rm-runtime-called"

  WRAPPER_PID_FILE="$CASE_DIR/wrapper-pid"
  SIGNALER_ERROR_FILE="$CASE_DIR/signaler-error"

  cat >"$FAKE_PASS_PAYLOAD_FILE" <<'EOF'
hosts:
  gitlab.example:
    token: fake-initial-access-token
    refresh_token: fake-initial-refresh-token
EOF

  cat >"$FAKE_GLAB_MUTATION_FILE" <<'EOF'
hosts:
  gitlab.example:
    token: fake-mutated-access-token
    refresh_token: fake-mutated-refresh-token
EOF

  HOME="$CASE_DIR/home"
  XDG_RUNTIME_DIR="$CASE_DIR/xdg-runtime"
  PATH="$fixture_bin:$original_path"

  FAKE_PASS_MODE='show-ok'
  FAKE_PASS_STATUS=1
  FAKE_PASS_INSERT_MODE='insert-ok'
  FAKE_PASS_INSERT_STATUS=1

  FAKE_GLAB_MODE='unchanged'
  FAKE_GLAB_STATUS=0
  FAKE_GLAB_SIGNAL_ACTION='unchanged'
  FAKE_GLAB_SIGNAL_CHILD_STATUS=

  FAKE_MKTEMP_MODE='ok'
  FAKE_MKTEMP_STATUS=1

  FAKE_SHA256SUM_FAIL_ON_CALL=0
  FAKE_SHA256SUM_STATUS=1

  FAKE_CHMOD_FAIL_ON_CALL=0
  FAKE_CHMOD_STATUS=1

  FAKE_RM_RUNTIME_MODE='ok'
  FAKE_RM_RUNTIME_STATUS=1

  export \
    HOME \
    XDG_RUNTIME_DIR \
    PATH \
    REAL_MKTEMP \
    REAL_SHA256SUM \
    REAL_CHMOD \
    REAL_RM \
    FAKE_PASS_CALL_LOG \
    FAKE_PASS_ENTRY_LOG \
    FAKE_PASS_PAYLOAD_FILE \
    FAKE_PASS_WRITEBACK_CALL_LOG \
    FAKE_PASS_WRITEBACK_ENTRY_LOG \
    FAKE_PASS_WRITEBACK_PAYLOAD_FILE \
    FAKE_GLAB_CALLED_LOG \
    FAKE_GLAB_CONFIG_DIR_LOG \
    FAKE_GLAB_CONFIG_PATH_LOG \
    FAKE_GLAB_CONFIG_SEEN_FILE \
    FAKE_GLAB_DIR_MODE_LOG \
    FAKE_GLAB_FILE_MODE_LOG \
    FAKE_GLAB_ARGC_LOG \
    FAKE_GLAB_ARGS_LOG \
    FAKE_GLAB_MUTATION_FILE \
    FAKE_GLAB_READY_LOG \
    FAKE_GLAB_SIGNAL_LOG \
    FAKE_MKTEMP_ARGS_LOG \
    FAKE_MKTEMP_PATH_LOG \
    FAKE_SHA256SUM_COUNT_FILE \
    FAKE_CHMOD_COUNT_FILE \
    FAKE_RM_RUNTIME_CALL_LOG \
    WRAPPER_PID_FILE \
    SIGNALER_ERROR_FILE \
    FAKE_PASS_MODE \
    FAKE_PASS_STATUS \
    FAKE_PASS_INSERT_MODE \
    FAKE_PASS_INSERT_STATUS \
    FAKE_GLAB_MODE \
    FAKE_GLAB_STATUS \
    FAKE_GLAB_SIGNAL_ACTION \
    FAKE_GLAB_SIGNAL_CHILD_STATUS \
    FAKE_MKTEMP_MODE \
    FAKE_MKTEMP_STATUS \
    FAKE_SHA256SUM_FAIL_ON_CALL \
    FAKE_SHA256SUM_STATUS \
    FAKE_CHMOD_FAIL_ON_CALL \
    FAKE_CHMOD_STATUS \
    FAKE_RM_RUNTIME_MODE \
    FAKE_RM_RUNTIME_STATUS

  unset FORGE_CLI_PASS_GITLAB_ENTRY
  unset GLAB_CONFIG_DIR
}

set_wrapper_command() {
  case $TEST_SHELL_KIND in
  dash)
    set -- dash "$target" "$@"
    ;;

  bash-posix)
    set -- bash --posix "$target" "$@"
    ;;

  busybox-ash)
    set -- busybox ash "$target" "$@"
    ;;

  *)
    printf 'tests: unknown TEST_SHELL_KIND: %s\n' \
      "$TEST_SHELL_KIND" >&2
    return 125
    ;;
  esac

  WRAPPER_COMMAND_COUNT=$#
  WRAPPER_COMMAND=$*
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
    busybox ash "$target" "$@"
    ;;

  *)
    printf 'tests: unknown TEST_SHELL_KIND: %s\n' \
      "$TEST_SHELL_KIND" >&2
    return 125
    ;;
  esac >"$STDOUT_FILE" 2>"$STDERR_FILE"

  RUN_STATUS=$?
}

run_wrapper_with_signal() {
  signal_name=$1
  shift

  (
    attempt=0

    while [ ! -s "$WRAPPER_PID_FILE" ] ||
      [ ! -e "$FAKE_GLAB_READY_LOG" ]; do
      attempt=$((attempt + 1))

      if [ "$attempt" -gt 200 ]; then
        printf 'signal helper timed out waiting for glab\n' \
          >"$SIGNALER_ERROR_FILE"

        if [ -s "$WRAPPER_PID_FILE" ]; then
          wrapper_pid=$(cat -- "$WRAPPER_PID_FILE")
          kill -TERM "$wrapper_pid" 2>/dev/null || :
        fi

        exit 1
      fi

      sleep 0.05
    done

    wrapper_pid=$(cat -- "$WRAPPER_PID_FILE")

    kill -s "$signal_name" "$wrapper_pid" || {
      printf 'signal helper failed to send %s\n' "$signal_name" \
        >"$SIGNALER_ERROR_FILE"
      exit 1
    }
  ) &

  signaler_pid=$!

  case $TEST_SHELL_KIND in
  dash)
    sh -c '
                printf "%s" "$$" >"$WRAPPER_PID_FILE"
                exec "$@"
            ' sh dash "$target" "$@"
    ;;

  bash-posix)
    sh -c '
                printf "%s" "$$" >"$WRAPPER_PID_FILE"
                exec "$@"
            ' sh bash --posix "$target" "$@"
    ;;

  busybox-ash)
    sh -c '
                printf "%s" "$$" >"$WRAPPER_PID_FILE"
                exec "$@"
            ' sh busybox ash "$target" "$@"
    ;;

  *)
    return 125
    ;;
  esac >"$STDOUT_FILE" 2>"$STDERR_FILE"

  RUN_STATUS=$?

  wait "$signaler_pid"
  SIGNALER_STATUS=$?
}

read_runtime_path() {
  [ -s "$FAKE_MKTEMP_PATH_LOG" ] || {
    printf '    assertion failed: mktemp path was not recorded\n' >&2
    return 1
  }

  cat -- "$FAKE_MKTEMP_PATH_LOG"
}

assert_runtime_removed() {
  runtime_path=$(read_runtime_path) || return 1

  [ ! -e "$runtime_path" ] ||
    fail_assertion "runtime directory was not removed: $runtime_path"
}

assert_runtime_exists() {
  runtime_path=$(read_runtime_path) || return 1

  [ -e "$runtime_path" ] ||
    fail_assertion "expected runtime directory to remain: $runtime_path"
}

remove_failed_cleanup_artifact() {
  runtime_path=$(read_runtime_path) || return 1
  "$REAL_RM" -rf -- "$runtime_path"
}

test_default_entry_and_staging_contract() {
  setup_case

  GLAB_CONFIG_DIR="$CASE_DIR/ambient-config"
  export GLAB_CONFIG_DIR

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_file_equals \
    'forge-cli-pass/gitlab/oauth-config' \
    "$FAKE_PASS_ENTRY_LOG" \
    'default GitLab pass entry should be selected' || return 1

  expected_mktemp_arguments='1=-d
2=/tmp/glab-pass.XXXXXX'

  assert_file_equals \
    "$expected_mktemp_arguments" \
    "$FAKE_MKTEMP_ARGS_LOG" \
    'mktemp should use the accepted /tmp template' || return 1

  runtime_path=$(read_runtime_path) || return 1

  case $runtime_path in
  /tmp/glab-pass.*)
    ;;

  *)
    fail_assertion \
      "runtime path is not beneath /tmp/glab-pass.*: $runtime_path"
    return 1
    ;;
  esac

  assert_file_equals \
    "$runtime_path" \
    "$FAKE_GLAB_CONFIG_DIR_LOG" \
    'GLAB_CONFIG_DIR should point to the private runtime directory' ||
    return 1

  assert_file_equals \
    '700' \
    "$FAKE_GLAB_DIR_MODE_LOG" \
    'runtime directory should have mode 0700' || return 1

  assert_file_equals \
    '600' \
    "$FAKE_GLAB_FILE_MODE_LOG" \
    'staged config should have mode 0600' || return 1

  assert_runtime_removed
}

test_explicit_entry_override() {
  setup_case

  FORGE_CLI_PASS_GITLAB_ENTRY='work/gitlab/oauth-config'
  export FORGE_CLI_PASS_GITLAB_ENTRY

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_file_equals \
    'work/gitlab/oauth-config' \
    "$FAKE_PASS_ENTRY_LOG"
}

test_empty_override_is_rejected_before_staging() {
  setup_case

  FORGE_CLI_PASS_GITLAB_ENTRY=''
  export FORGE_CLI_PASS_GITLAB_ENTRY

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_MKTEMP_PATH_LOG" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'FORGE_CLI_PASS_GITLAB_ENTRY is set but empty' \
    "$STDERR_FILE"
}

test_newline_override_is_rejected() {
  setup_case

  FORGE_CLI_PASS_GITLAB_ENTRY='work/gitlab
oauth-config'
  export FORGE_CLI_PASS_GITLAB_ENTRY

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_MKTEMP_PATH_LOG" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'contains a newline' \
    "$STDERR_FILE"
}

test_complete_config_is_restored() {
  setup_case

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_files_equal \
    "$FAKE_PASS_PAYLOAD_FILE" \
    "$FAKE_GLAB_CONFIG_SEEN_FILE" \
    'glab should receive the complete opaque config payload'
}

test_parent_arguments_are_preserved() {
  setup_case

  run_wrapper \
    api \
    projects/example \
    --method \
    GET \
    --field \
    'value with spaces' \
    ''

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_file_equals \
    '7' \
    "$FAKE_GLAB_ARGC_LOG" || return 1

  expected_arguments='1=api
2=projects/example
3=--method
4=GET
5=--field
6=value with spaces
7='

  assert_file_equals \
    "$expected_arguments" \
    "$FAKE_GLAB_ARGS_LOG" \
    'parent argument boundaries should be preserved'
}

test_unchanged_state_is_not_written_back() {
  setup_case

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_not_exists \
    "$FAKE_PASS_WRITEBACK_CALL_LOG" \
    'unchanged state should not be written back' || return 1

  assert_runtime_removed
}

test_changed_state_is_written_back_after_success() {
  setup_case

  FAKE_GLAB_MODE='change'

  run_wrapper repo view

  assert_equals '0' "$RUN_STATUS" || return 1

  assert_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_file_equals \
    'forge-cli-pass/gitlab/oauth-config' \
    "$FAKE_PASS_WRITEBACK_ENTRY_LOG" || return 1

  assert_files_equal \
    "$FAKE_GLAB_MUTATION_FILE" \
    "$FAKE_PASS_WRITEBACK_PAYLOAD_FILE" \
    'complete changed state should be persisted' || return 1

  assert_runtime_removed
}

test_changed_state_is_written_back_after_parent_failure() {
  setup_case

  FAKE_GLAB_MODE='change'
  FAKE_GLAB_STATUS=23

  run_wrapper repo view

  assert_equals \
    '23' \
    "$RUN_STATUS" \
    'clean parent failure should be preserved exactly' || return 1

  assert_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_files_equal \
    "$FAKE_GLAB_MUTATION_FILE" \
    "$FAKE_PASS_WRITEBACK_PAYLOAD_FILE" || return 1

  assert_runtime_removed
}

test_pass_failure_prevents_parent_execution_and_cleans_up() {
  setup_case

  FAKE_PASS_MODE='show-fail'
  FAKE_PASS_STATUS=7

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'failed to read credential entry' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_empty_initial_config_is_rejected() {
  setup_case

  : >"$FAKE_PASS_PAYLOAD_FILE"

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'credential entry is empty' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_mktemp_failure_prevents_credential_access() {
  setup_case

  FAKE_MKTEMP_MODE='fail'

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'failed to create runtime directory' \
    "$STDERR_FILE"
}

test_directory_permission_failure_prevents_parent_execution() {
  setup_case

  FAKE_CHMOD_FAIL_ON_CALL=1

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'failed to protect runtime directory' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_initial_fingerprint_failure_prevents_parent_execution() {
  setup_case

  FAKE_SHA256SUM_FAIL_ON_CALL=1

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'failed to fingerprint initial GitLab state' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_missing_post_command_config_is_wrapper_failure() {
  setup_case

  FAKE_GLAB_MODE='remove'

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_file_contains \
    'staged GitLab configuration is missing' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_empty_post_command_config_is_wrapper_failure() {
  setup_case

  FAKE_GLAB_MODE='empty'

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_file_contains \
    'staged GitLab configuration is empty' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_nonregular_post_command_config_is_wrapper_failure() {
  setup_case

  FAKE_GLAB_MODE='nonregular'

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_file_contains \
    'staged GitLab configuration is not a regular file' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_post_command_fingerprint_failure_is_wrapper_failure() {
  setup_case

  FAKE_SHA256SUM_FAIL_ON_CALL=2

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_file_contains \
    'failed to fingerprint staged GitLab state' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_writeback_failure_is_wrapper_failure() {
  setup_case

  FAKE_GLAB_MODE='change'
  FAKE_PASS_INSERT_MODE='insert-fail'

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_file_contains \
    'failed to persist changed GitLab authentication state' \
    "$STDERR_FILE" || return 1

  assert_file_not_contains \
    'fake-mutated-access-token' \
    "$STDERR_FILE" \
    'diagnostics must not disclose credential material' || return 1

  assert_runtime_removed
}

test_cleanup_failure_overrides_parent_status() {
  setup_case

  FAKE_GLAB_STATUS=23
  FAKE_RM_RUNTIME_MODE='fail'

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_exists "$FAKE_RM_RUNTIME_CALL_LOG" || return 1
  assert_runtime_exists || return 1

  assert_file_contains \
    'glab exited with status 23' \
    "$STDERR_FILE" || return 1

  assert_file_contains \
    'failed to remove runtime directory' \
    "$STDERR_FILE" || return 1

  remove_failed_cleanup_artifact
}

test_writeback_and_cleanup_failures_are_both_reported() {
  setup_case

  FAKE_GLAB_MODE='change'
  FAKE_GLAB_STATUS=23
  FAKE_PASS_INSERT_MODE='insert-fail'
  FAKE_RM_RUNTIME_MODE='fail'

  run_wrapper repo view

  assert_equals '1' "$RUN_STATUS" || return 1

  assert_file_contains \
    'glab exited with status 23' \
    "$STDERR_FILE" || return 1

  assert_file_contains \
    'failed to persist changed GitLab authentication state' \
    "$STDERR_FILE" || return 1

  assert_file_contains \
    'failed to remove runtime directory' \
    "$STDERR_FILE" || return 1

  assert_runtime_exists || return 1
  remove_failed_cleanup_artifact
}

test_auth_status_is_allowed() {
  setup_case

  run_wrapper auth status

  assert_equals '0' "$RUN_STATUS" || return 1
  assert_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_exists "$FAKE_GLAB_CALLED_LOG"
}

test_auth_login_is_rejected_before_staging() {
  setup_case

  run_wrapper auth login

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_MKTEMP_PATH_LOG" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'unsupported credential-management command: auth login' \
    "$STDERR_FILE"
}

test_auth_status_token_display_is_rejected() {
  setup_case

  run_wrapper auth status --show-token

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_MKTEMP_PATH_LOG" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'credential disclosure is outside the wrapper compatibility contract' \
    "$STDERR_FILE"
}

test_unknown_auth_subcommand_is_rejected() {
  setup_case

  run_wrapper auth future-command

  assert_equals '1' "$RUN_STATUS" || return 1
  assert_not_exists "$FAKE_PASS_CALL_LOG" || return 1
  assert_not_exists "$FAKE_MKTEMP_PATH_LOG" || return 1
  assert_not_exists "$FAKE_GLAB_CALLED_LOG" || return 1

  assert_file_contains \
    'unsupported credential-management command: auth future-command' \
    "$STDERR_FILE"
}

test_hup_preserves_signal_status_with_unchanged_state() {
  setup_case

  FAKE_GLAB_MODE='wait-signal'
  FAKE_GLAB_SIGNAL_ACTION='unchanged'

  run_wrapper_with_signal HUP repo view

  assert_equals '0' "$SIGNALER_STATUS" || return 1
  assert_equals '129' "$RUN_STATUS" || return 1
  assert_file_equals 'HUP' "$FAKE_GLAB_SIGNAL_LOG" || return 1
  assert_not_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_runtime_removed
}

test_int_writes_back_changed_signal_state() {
  setup_case

  FAKE_GLAB_MODE='wait-signal'
  FAKE_GLAB_SIGNAL_ACTION='change'

  run_wrapper_with_signal INT repo view

  assert_equals '0' "$SIGNALER_STATUS" || return 1
  assert_equals '130' "$RUN_STATUS" || return 1
  assert_file_equals 'INT' "$FAKE_GLAB_SIGNAL_LOG" || return 1

  assert_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_files_equal \
    "$FAKE_GLAB_MUTATION_FILE" \
    "$FAKE_PASS_WRITEBACK_PAYLOAD_FILE" || return 1

  assert_runtime_removed
}

test_term_retains_durable_state_after_empty_signal_state() {
  setup_case

  FAKE_GLAB_MODE='wait-signal'
  FAKE_GLAB_SIGNAL_ACTION='empty'

  run_wrapper_with_signal TERM repo view

  assert_equals '0' "$SIGNALER_STATUS" || return 1
  assert_equals '143' "$RUN_STATUS" || return 1
  assert_file_equals 'TERM' "$FAKE_GLAB_SIGNAL_LOG" || return 1
  assert_not_exists "$FAKE_PASS_WRITEBACK_CALL_LOG" || return 1

  assert_file_contains \
    'interrupted GitLab state is empty' \
    "$STDERR_FILE" || return 1

  assert_file_contains \
    'reauthentication may be required' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_signal_writeback_failure_preserves_signal_status() {
  setup_case

  FAKE_GLAB_MODE='wait-signal'
  FAKE_GLAB_SIGNAL_ACTION='change'
  FAKE_PASS_INSERT_MODE='insert-fail'

  run_wrapper_with_signal TERM repo view

  assert_equals '0' "$SIGNALER_STATUS" || return 1
  assert_equals '143' "$RUN_STATUS" || return 1

  assert_file_contains \
    'failed to persist changed GitLab authentication state' \
    "$STDERR_FILE" || return 1

  assert_file_not_contains \
    'fake-mutated-access-token' \
    "$STDERR_FILE" || return 1

  assert_runtime_removed
}

test_signal_cleanup_failure_preserves_signal_status() {
  setup_case

  FAKE_GLAB_MODE='wait-signal'
  FAKE_GLAB_SIGNAL_ACTION='unchanged'
  FAKE_RM_RUNTIME_MODE='fail'

  run_wrapper_with_signal HUP repo view

  assert_equals '0' "$SIGNALER_STATUS" || return 1
  assert_equals '129' "$RUN_STATUS" || return 1
  assert_exists "$FAKE_RM_RUNTIME_CALL_LOG" || return 1

  assert_file_contains \
    'failed to remove runtime directory' \
    "$STDERR_FILE" || return 1

  assert_runtime_exists || return 1
  remove_failed_cleanup_artifact
}

run_test \
  'uses the default entry and accepted staging contract' \
  test_default_entry_and_staging_contract

run_test \
  'uses an explicit GitLab pass-entry override' \
  test_explicit_entry_override

run_test \
  'rejects an explicitly empty entry override before staging' \
  test_empty_override_is_rejected_before_staging

run_test \
  'rejects a newline in the entry override' \
  test_newline_override_is_rejected

run_test \
  'restores the complete opaque GitLab config' \
  test_complete_config_is_restored

run_test \
  'preserves parent argument order and boundaries' \
  test_parent_arguments_are_preserved

run_test \
  'does not write back unchanged state' \
  test_unchanged_state_is_not_written_back

run_test \
  'writes back changed state after parent success' \
  test_changed_state_is_written_back_after_success

run_test \
  'writes back changed state after ordinary parent failure' \
  test_changed_state_is_written_back_after_parent_failure

run_test \
  'cleans up after pass retrieval failure' \
  test_pass_failure_prevents_parent_execution_and_cleans_up

run_test \
  'rejects an empty initial GitLab config' \
  test_empty_initial_config_is_rejected

run_test \
  'handles runtime-directory creation failure' \
  test_mktemp_failure_prevents_credential_access

run_test \
  'handles runtime-directory permission failure' \
  test_directory_permission_failure_prevents_parent_execution

run_test \
  'handles initial fingerprint failure' \
  test_initial_fingerprint_failure_prevents_parent_execution

run_test \
  'rejects a missing post-command config' \
  test_missing_post_command_config_is_wrapper_failure

run_test \
  'rejects an empty post-command config' \
  test_empty_post_command_config_is_wrapper_failure

run_test \
  'rejects a non-regular post-command config' \
  test_nonregular_post_command_config_is_wrapper_failure

run_test \
  'handles post-command fingerprint failure' \
  test_post_command_fingerprint_failure_is_wrapper_failure

run_test \
  'handles required writeback failure' \
  test_writeback_failure_is_wrapper_failure

run_test \
  'lets cleanup failure override an ordinary parent status' \
  test_cleanup_failure_overrides_parent_status

run_test \
  'reports simultaneous writeback and cleanup failures' \
  test_writeback_and_cleanup_failures_are_both_reported

run_test \
  'allows auth status' \
  test_auth_status_is_allowed

run_test \
  'rejects auth login before credential staging' \
  test_auth_login_is_rejected_before_staging

run_test \
  'rejects auth status token disclosure' \
  test_auth_status_token_display_is_rejected

run_test \
  'rejects unknown auth subcommands' \
  test_unknown_auth_subcommand_is_rejected

run_test \
  'preserves HUP status with unchanged state' \
  test_hup_preserves_signal_status_with_unchanged_state

run_test \
  'writes back eligible changed state after INT' \
  test_int_writes_back_changed_signal_state

run_test \
  'retains durable state when TERM leaves an empty config' \
  test_term_retains_durable_state_after_empty_signal_state

run_test \
  'preserves signal status after signal-time writeback failure' \
  test_signal_writeback_failure_preserves_signal_status

run_test \
  'preserves signal status after signal-time cleanup failure' \
  test_signal_cleanup_failure_preserves_signal_status

suite_finish
