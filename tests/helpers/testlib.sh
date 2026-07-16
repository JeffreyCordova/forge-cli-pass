#!/bin/sh

TEST_TOTAL=0
TEST_FAILED=0

suite_start() {
  suite_name=$1

  SUITE_ROOT=$(
    mktemp -d "${TMPDIR:-/tmp}/forge-cli-pass-tests.XXXXXX"
  ) || {
    printf 'tests: failed to create suite directory\n' >&2
    exit 1
  }

  export SUITE_ROOT

  trap 'rm -rf -- "$SUITE_ROOT"' EXIT HUP INT TERM

  printf 'Suite: %s\n' "$suite_name"
}

fail_assertion() {
  printf '    assertion failed: %s\n' "$1" >&2
  return 1
}

assert_equals() {
  expected=$1
  actual=$2
  description=${3:-values differ}

  if [ "$expected" != "$actual" ]; then
    printf '    assertion failed: %s\n' "$description" >&2
    printf '      expected: <%s>\n' "$expected" >&2
    printf '      actual:   <%s>\n' "$actual" >&2
    return 1
  fi
}

assert_file_equals() {
  expected=$1
  file=$2
  description=${3:-unexpected file content}

  [ -f "$file" ] || {
    printf '    assertion failed: expected file does not exist: %s\n' \
      "$file" >&2
    return 1
  }

  actual=$(cat -- "$file") || {
    printf '    assertion failed: could not read file: %s\n' \
      "$file" >&2
    return 1
  }

  assert_equals "$expected" "$actual" "$description"
}

assert_file_contains() {
  needle=$1
  file=$2
  description=${3:-expected text was not found}

  [ -f "$file" ] || {
    printf '    assertion failed: expected file does not exist: %s\n' \
      "$file" >&2
    return 1
  }

  content=$(cat -- "$file") || {
    printf '    assertion failed: could not read file: %s\n' \
      "$file" >&2
    return 1
  }

  case $content in
  *"$needle"*)
    return 0
    ;;
  *)
    printf '    assertion failed: %s\n' "$description" >&2
    printf '      missing text: <%s>\n' "$needle" >&2
    return 1
    ;;
  esac
}

assert_exists() {
  path=$1
  description=${2:-expected path does not exist}

  [ -e "$path" ] || fail_assertion "$description: $path"
}

assert_not_exists() {
  path=$1
  description=${2:-unexpected path exists}

  [ ! -e "$path" ] || fail_assertion "$description: $path"
}

assert_file_not_contains() {
  needle=$1
  file=$2
  description=${3:-unexpected text was found}

  [ -f "$file" ] || {
    printf '    assertion failed: expected file does not exist: %s\n' \
      "$file" >&2
    return 1
  }

  content=$(cat -- "$file") || {
    printf '    assertion failed: could not read file: %s\n' \
      "$file" >&2
    return 1
  }

  case $content in
  *"$needle"*)
    printf '    assertion failed: %s\n' "$description" >&2
    printf '      unexpected text: <%s>\n' "$needle" >&2
    return 1
    ;;

  *)
    return 0
    ;;
  esac
}

assert_files_equal() {
  expected_file=$1
  actual_file=$2
  description=${3:-files differ}

  [ -f "$expected_file" ] || {
    printf '    assertion failed: expected source file does not exist: %s\n' \
      "$expected_file" >&2
    return 1
  }

  [ -f "$actual_file" ] || {
    printf '    assertion failed: compared file does not exist: %s\n' \
      "$actual_file" >&2
    return 1
  }

  if ! cmp -s "$expected_file" "$actual_file"; then
    printf '    assertion failed: %s\n' "$description" >&2
    printf '      expected file: %s\n' "$expected_file" >&2
    printf '      actual file:   %s\n' "$actual_file" >&2
    return 1
  fi
}

run_test() {
  test_name=$1
  test_function=$2

  TEST_TOTAL=$((TEST_TOTAL + 1))

  if ("$test_function"); then
    printf '  ok %d - %s\n' "$TEST_TOTAL" "$test_name"
  else
    TEST_FAILED=$((TEST_FAILED + 1))
    printf '  not ok %d - %s\n' "$TEST_TOTAL" "$test_name" >&2
  fi
}

suite_finish() {
  passed=$((TEST_TOTAL - TEST_FAILED))

  printf '\n%d passed; %d failed; %d total\n' \
    "$passed" \
    "$TEST_FAILED" \
    "$TEST_TOTAL"

  [ "$TEST_FAILED" -eq 0 ]
}
