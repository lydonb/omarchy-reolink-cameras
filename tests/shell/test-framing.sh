#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

assert_rejected() {
  local helper="$1" mode="$2" output rc
  set +e
  if [[ $mode == multiple ]]; then
    output=$(printf '%s\n%s\n' '{"operation":"load"}' '{"operation":"load"}' | "$helper")
  else
    output=$({
      printf '%s\n' '{"operation":"load"}'
      head -c 1100000 /dev/zero | tr '\0' x
    } | "$helper")
  fi
  rc=$?
  set -e
  ((rc != 0))
  jq -e '.ok == false and (.error.code == "invalid_request" or .error.code == "request_too_large")' \
    <<<"$output" >/dev/null
}

for helper_name in reolink-config reolink-secret reolink-http reolink-player reolink-snapshot-export; do
  helper="$plugin_root/scripts/$helper_name"
  assert_rejected "$helper" multiple
  assert_rejected "$helper" oversized
done
