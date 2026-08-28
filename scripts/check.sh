#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$plugin_root"

search_extended() {
  if [[ ${REOLINK_FORCE_GREP:-0} != 1 ]] && command -v rg >/dev/null 2>&1; then rg -n "$@"
  else grep -Ern "$@"
  fi
}

search_fixed() {
  if [[ ${REOLINK_FORCE_GREP:-0} != 1 ]] && command -v rg >/dev/null 2>&1; then rg -F -- "$@"
  else grep -F -- "$@"
  fi
}

echo "== JSON and repository structure =="
jq -e '.schemaVersion == 1 and .id == "io.github.rodrix2000.reolink-cameras"' manifest.json >/dev/null
[[ -f preview.png && $(stat -c %s -- preview.png) -gt 0 ]]
for fixture in tests/fixtures/*.json; do jq -e . "$fixture" >/dev/null; done
if find . -path ./.git -prune -o -type l -print -quit | grep -q .; then
  echo "error: symlinks are not allowed in an Omarchy plugin" >&2
  exit 1
fi

echo "== Shell syntax =="
bash -n scripts/* tests/shell/* tests/security/*.sh tests/fakes/bin/mpv

echo "== Static security policy =="
if search_extended '(^|[^[:alnum:]_])eval([[:space:]]|$)|set[[:space:]]+-x|curl[[:space:]]+-v|/tmp/|--script=' \
  Service.qml HostRuntime.qml BarWidget.qml Panel.qml lib scripts/reolink-*; then
  echo "error: forbidden runtime pattern found" >&2
  exit 1
fi
search_fixed '--no-config' scripts/reolink-player >/dev/null
search_fixed '--load-scripts=no' scripts/reolink-player >/dev/null
search_fixed '--terminal=no' scripts/reolink-player >/dev/null
! search_extended 'python|node|npm|mosquitto|go2rtc|docker|qt6-multimedia|home-assistant' \
  Service.qml HostRuntime.qml BarWidget.qml Panel.qml lib scripts/reolink-*

if command -v omarchy >/dev/null 2>&1; then
  echo "== Omarchy manifest =="
  omarchy plugin validate .
fi

if [[ ${REOLINK_PORTABLE_ONLY:-0} != 1 && -x /usr/lib/qt6/bin/qmllint && -n ${OMARCHY_PATH:-} ]]; then
  echo "== Required QML lint command =="
  lint_log=$(mktemp -t omarchy-reolink-qmllint.XXXXXXXX)
  trap 'rm -f -- "$lint_log"' EXIT
  if ! PATH="/usr/lib/qt6/bin:$PATH" qmllint -I "$OMARCHY_PATH/shell" \
    Service.qml BarWidget.qml Panel.qml HostRuntime.qml >"$lint_log" 2>&1; then
    cat "$lint_log" >&2
    exit 1
  fi
  echo "== Strict import-aware QML lint =="
  if ! /usr/lib/qt6/bin/qmllint -W 0 \
    --signal-handler-parameters info --missing-property info \
    -i "$OMARCHY_PATH/shell/Ui/qmldir" \
    -i "$OMARCHY_PATH/shell/Commons/qmldir" \
    Service.qml BarWidget.qml Panel.qml HostRuntime.qml >"$lint_log" 2>&1; then
    cat "$lint_log" >&2
    exit 1
  fi
  rm -f -- "$lint_log"
  trap - EXIT
fi

echo "== Portable config test =="
tests/shell/test-config.sh

echo "== Exact request framing =="
tests/shell/test-framing.sh

echo "== Snapshot export =="
tests/shell/test-export.sh

if [[ ${REOLINK_PORTABLE_ONLY:-0} != 1 && -n $(command -v quickshell || true) ]]; then
  echo "== QML logic smoke =="
  tests/shell/test-qml.sh
fi

if [[ ${REOLINK_PORTABLE_ONLY:-0} != 1 && -n $(command -v secret-tool || true) \
    && -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  echo "== CGI helper integration =="
  tests/shell/test-http.sh
  echo "== Sentinel leakage and mpv isolation =="
  tests/security/sentinel-leakage.sh
fi

echo "All available checks passed."
