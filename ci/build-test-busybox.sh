#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

busybox_version='1.36.1'
busybox_sha256='b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314'

output=${1:-}

if [ -z "$output" ]; then
  printf '%s\n' \
    'usage: ci/build-test-busybox.sh OUTPUT_PATH' >&2
  exit 1
fi

case $output in
/*)
  ;;

*)
  output=$PWD/$output
  ;;
esac

if [ "${output##*/}" != 'busybox' ]; then
  printf '%s\n' \
    'build-test-busybox: output filename must be busybox' \
    "build-test-busybox: received: $output" >&2
  exit 1
fi

build_root=$(
  mktemp -d \
    "${TMPDIR:-/tmp}/forge-cli-pass-busybox.XXXXXX"
) || {
  printf '%s\n' \
    'build-test-busybox: failed to create build directory' >&2
  exit 1
}

cleanup() {
  rm -rf -- "$build_root" || :
}

trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

archive_name="busybox-$busybox_version.tar.bz2"
archive="$build_root/$archive_name"
source_dir="$build_root/busybox-$busybox_version"
source_url="https://busybox.net/downloads/$archive_name"

printf 'Downloading BusyBox %s...\n' "$busybox_version"

curl \
  --fail \
  --location \
  --proto '=https' \
  --retry 3 \
  --retry-delay 1 \
  --show-error \
  --silent \
  --tlsv1.2 \
  --output "$archive" \
  "$source_url"

(
  cd -- "$build_root"

  printf '%s  %s\n' \
    "$busybox_sha256" \
    "$archive_name" |
    sha256sum -c -
)

tar \
  -xjf "$archive" \
  -C "$build_root"

(
  cd -- "$source_dir"

  make defconfig >/dev/null

  # The traffic-control applet is unrelated to the test shell and may fail
  # to compile against host kernel headers that omit obsolete CBQ symbols.
  #
  # The three shell execution features are disabled so external commands
  # selected through PATH remain authoritative for failure injection.
  sed -i \
    -e 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' \
    -e 's/^CONFIG_FEATURE_PREFER_APPLETS=y$/# CONFIG_FEATURE_PREFER_APPLETS is not set/' \
    -e 's/^CONFIG_FEATURE_SH_STANDALONE=y$/# CONFIG_FEATURE_SH_STANDALONE is not set/' \
    -e 's/^CONFIG_FEATURE_SH_NOFORK=y$/# CONFIG_FEATURE_SH_NOFORK is not set/' \
    .config

  make oldconfig </dev/null >/dev/null

  grep -qx \
    'CONFIG_BUSYBOX=y' \
    .config || {
    printf '%s\n' \
      'build-test-busybox: busybox applet was not enabled' >&2
    exit 1
  }

  grep -qx \
    'CONFIG_ASH=y' \
    .config || {
    printf '%s\n' \
      'build-test-busybox: ash applet was not enabled' >&2
    exit 1
  }

  grep -qx \
    '# CONFIG_TC is not set' \
    .config || {
    printf '%s\n' \
      'build-test-busybox: TC must be disabled' >&2
    exit 1
  }

  grep -qx \
    '# CONFIG_FEATURE_PREFER_APPLETS is not set' \
    .config || {
    printf '%s\n' \
      'build-test-busybox: FEATURE_PREFER_APPLETS must be disabled' \
      >&2
    exit 1
  }

  grep -qx \
    '# CONFIG_FEATURE_SH_STANDALONE is not set' \
    .config || {
    printf '%s\n' \
      'build-test-busybox: FEATURE_SH_STANDALONE must be disabled' \
      >&2
    exit 1
  }

  grep -qx \
    '# CONFIG_FEATURE_SH_NOFORK is not set' \
    .config || {
    printf '%s\n' \
      'build-test-busybox: FEATURE_SH_NOFORK must be disabled' \
      >&2
    exit 1
  }

  make -j2
)

output_dir=$(dirname -- "$output")

mkdir -p -- "$output_dir"

install \
  -m 0755 \
  "$source_dir/busybox" \
  "$output"

"$output" ash -c ':' || {
  printf '%s\n' \
    'build-test-busybox: built executable cannot run ash' >&2
  exit 1
}

probe_dir="$build_root/path-probe"

mkdir -p -- "$probe_dir"

cat >"$probe_dir/sha256sum" <<'EOF'
#!/bin/sh
printf '%s\n' 'fixture-sha256sum'
EOF

chmod 755 "$probe_dir/sha256sum"

probe_output=$(
  PATH="$probe_dir:$PATH" \
    "$output" ash -c \
    'sha256sum /dev/null'
)

if [ "$probe_output" != 'fixture-sha256sum' ]; then
  printf '%s\n' \
    'build-test-busybox: built ash does not honor PATH precedence' \
    >&2
  exit 1
fi

printf 'Built compatible test BusyBox: %s\n' "$output"
