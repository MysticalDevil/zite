#!/usr/bin/env sh
set -eu

export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$PWD/.zig-cache}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-$PWD/.zig-cache}"

zig test --dep zite -Mtests=tests/itest_direct.zig \
  -Mbuild_options=tests/build_options.zig \
  --dep build_options -Mzite=src/root.zig -lc -lsqlite3 "$@"
