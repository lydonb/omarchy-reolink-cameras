#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d -t omarchy-reolink-config.XXXXXXXX)
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
mkdir -p -- "$HOME"

valid='{"operation":"save","config":{"version":1,"hosts":[{"id":"host_fixture","address":"192.168.1.2","port":443,"rtspPort":554,"transport":"https","tlsMode":"verify","username":"admin","displayName":"Front"}],"cleanupHostIds":[],"preferences":{"notify":{"motion":false}}}}'
printf '%s' "$valid" | "$plugin_root/scripts/reolink-config" | jq -e '.ok == true' >/dev/null

config_path="$XDG_CONFIG_HOME/omarchy-reolink/config.json"
[[ $(stat -c %a -- "${config_path%/*}") == 700 ]]
[[ $(stat -c %a -- "$config_path") == 600 ]]
printf '%s' '{"operation":"load"}' | "$plugin_root/scripts/reolink-config" \
  | jq -e '.hosts[0].id == "host_fixture"' >/dev/null

for forbidden_key in token credential auth pass apiKey url; do
  invalid=$(jq -cn --arg key "$forbidden_key" '{operation:"save",config:{
    version:1,hosts:[],cleanupHostIds:[],preferences:{notify:{motion:false}}
  }} | .config[$key]="forbidden"')
  if printf '%s\n' "$invalid" | "$plugin_root/scripts/reolink-config" >/dev/null 2>&1; then
    echo "config helper accepted unknown field: $forbidden_key" >&2
    exit 1
  fi
done

invalid_port=$(jq -c '.config.hosts[0].port=443.5' <<<"$valid")
! printf '%s\n' "$invalid_port" | "$plugin_root/scripts/reolink-config" >/dev/null 2>&1
invalid_address=$(jq -c '.config.hosts[0].address="https://camera.invalid/path"' <<<"$valid")
! printf '%s\n' "$invalid_address" | "$plugin_root/scripts/reolink-config" >/dev/null 2>&1
duplicate_cleanup=$(jq -c '.config.cleanupHostIds=["host_fixture","host_fixture"]' <<<"$valid")
! printf '%s\n' "$duplicate_cleanup" | "$plugin_root/scripts/reolink-config" >/dev/null 2>&1

printf '%s' '{"operation":"clear"}' | "$plugin_root/scripts/reolink-config" | jq -e '.ok == true' >/dev/null
[[ ! -e $config_path ]]

outside="$test_root/outside-config"
mkdir -- "$outside"
rmdir "$XDG_CONFIG_HOME/omarchy-reolink"
ln -s -- "$outside" "$XDG_CONFIG_HOME/omarchy-reolink"
if printf '%s\n' "$valid" | "$plugin_root/scripts/reolink-config" >/dev/null 2>&1; then
  echo "config helper followed a managed-directory symlink" >&2
  exit 1
fi
[[ ! -e $outside/config.json ]]
unlink "$XDG_CONFIG_HOME/omarchy-reolink"

bad_bus="unix:path=$test_root/missing-secret-service"
if printf '%s\n' '{"operation":"exists","hostId":"host_fixture"}' \
    | DBUS_SESSION_BUS_ADDRESS="$bad_bus" "$plugin_root/scripts/reolink-secret" >/dev/null 2>&1; then
  echo "secret helper reported backend failure as absence" >&2
  exit 1
fi
if printf '%s\n' '{"operation":"clear","hostId":"host_fixture"}' \
    | DBUS_SESSION_BUS_ADDRESS="$bad_bus" "$plugin_root/scripts/reolink-secret" >/dev/null 2>&1; then
  echo "secret helper reported backend failure as a successful clear" >&2
  exit 1
fi

http_lookup='{"operation":"login","hostId":"host_fixture","address":"127.0.0.1","port":1,"transport":"http","tlsMode":"verify","username":"admin"}'
set +e
http_lookup_error=$(printf '%s\n' "$http_lookup" \
  | DBUS_SESSION_BUS_ADDRESS="$bad_bus" "$plugin_root/scripts/reolink-http")
http_lookup_rc=$?
set -e
((http_lookup_rc != 0))
jq -e '.error.code == "secret_lookup_failed"' <<<"$http_lookup_error" >/dev/null

export XDG_RUNTIME_DIR="$test_root/runtime"
mkdir -m 700 -- "$XDG_RUNTIME_DIR"
player_lookup='{"kind":"live","hostId":"host_fixture","address":"127.0.0.1","username":"admin","rtspPort":554,"channel":0,"stream":"sub"}'
set +e
player_lookup_error=$(printf '%s\n' "$player_lookup" \
  | DBUS_SESSION_BUS_ADDRESS="$bad_bus" "$plugin_root/scripts/reolink-player")
player_lookup_rc=$?
set -e
((player_lookup_rc != 0))
jq -e '.error.code == "secret_lookup_failed"' <<<"$player_lookup_error" >/dev/null
