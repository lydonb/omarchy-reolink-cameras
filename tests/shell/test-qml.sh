#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d -t omarchy-reolink-qml.XXXXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p -- "$test_root/home" "$test_root/config" "$test_root/cache" "$test_root/runtime" \
  "$test_root/smoke/lib" "$test_root/smoke/fixtures"
chmod 700 -- "$test_root/runtime"
cp -- "$plugin_root/tests/qml/LogicSmoke.qml" "$test_root/smoke/shell.qml"
cp -- "$plugin_root/Service.qml" "$plugin_root/HostRuntime.qml" "$test_root/smoke/"
cp -- "$plugin_root"/lib/*.js "$test_root/smoke/lib/"
cp -- "$plugin_root/tests/fixtures/device-matrix.json" "$test_root/smoke/fixtures/"

log="$test_root/qml.log"
set +e
timeout 5s env -u DISPLAY -u WAYLAND_DISPLAY \
  HOME="$test_root/home" \
  XDG_CONFIG_HOME="$test_root/config" \
  XDG_CACHE_HOME="$test_root/cache" \
  XDG_RUNTIME_DIR="$test_root/runtime" \
  QT_QPA_PLATFORM=minimal QT_QPA_PLATFORMTHEME= \
  quickshell --no-color -p "$test_root/smoke" >"$log" 2>&1
status=$?
set -e
grep -q 'REOLINK_LOGIC_SMOKE_OK' "$log"
[[ $status == 0 || $status == 124 ]]
