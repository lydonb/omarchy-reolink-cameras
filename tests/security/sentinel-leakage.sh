#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d -t omarchy-reolink-security.XXXXXXXX)
server_pid=""
mpv_pid=""
helper_pid=""
host_id="host_security_fixture_$$"
original_path=$PATH
real_home=${HOME:?HOME is required}
real_runtime=${XDG_RUNTIME_DIR:-}
test_started=$(date +%s)

cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
  [[ -n $helper_pid ]] && kill "$helper_pid" 2>/dev/null || true
  [[ -n $mpv_pid ]] && kill "$mpv_pid" 2>/dev/null || true
  secret-tool clear application omarchy-reolink host-id "$host_id" kind password >/dev/null 2>&1 || true
  rm -rf -- "$test_root"
}
trap cleanup EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_RUNTIME_DIR="$test_root/runtime"
export FAKE_CAMERA_TRACE="$test_root/camera.trace"
mkdir -p -- "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 -- "$XDG_RUNTIME_DIR"

password=$(printf '%s' 'SUPER_SECRET_' 'REOLINK_PASSWORD')
token=$(printf '%s' 'SUPER_SECRET_' 'REOLINK_TOKEN')
jq -cn --arg hostId "$host_id" --arg password "$password" \
  '{operation:"store",hostId:$hostId,password:$password}' \
  | "$plugin_root/scripts/reolink-secret" | jq -e '.ok == true' >/dev/null

contains_value() {
  local file="$1" value="$2"
  [[ -r $file ]] || return 1
  grep -aFqf <(printf '%s\n' "$value") "$file"
}

assert_clean_file() {
  local file="$1" value="$2" label="$3"
  if contains_value "$file" "$value"; then
    echo "sentinel leaked through $label" >&2
    return 1
  fi
}

descendants() {
  local parent="$1" child
  printf '%s\n' "$parent"
  while IFS= read -r child; do
    [[ -n $child ]] || continue
    descendants "$child"
  done < <(pgrep -P "$parent" 2>/dev/null || true)
}

assert_process_tree_clean() {
  local root_pid="$1" value="$2" pid
  while IFS= read -r pid; do
    [[ $pid =~ ^[0-9]+$ ]] || continue
    assert_clean_file "/proc/$pid/cmdline" "$value" "process argv" || return 1
    assert_clean_file "/proc/$pid/environ" "$value" "process environment" || return 1
  done < <(descendants "$root_pid" | sort -u)
}

wait_for_socket() {
  local require_verified=${1:-yes} socket=""
  for _ in {1..100}; do
    socket=$(find "$XDG_RUNTIME_DIR/omarchy-reolink" -type s -print -quit 2>/dev/null || true)
    [[ -n $socket && ( $require_verified == no || -f $socket.verified ) ]] \
      && { printf '%s\n' "$socket"; return 0; }
    sleep 0.02
  done
  return 1
}

stop_player_tree() {
  local old_mpv_pid=$mpv_pid
  [[ -n $helper_pid ]] && kill -KILL "$helper_pid" 2>/dev/null || true
  [[ -n $helper_pid ]] && wait "$helper_pid" 2>/dev/null || true
  if [[ -n $old_mpv_pid ]]; then
    for _ in {1..100}; do
      kill -0 "$old_mpv_pid" 2>/dev/null || break
      sleep 0.02
    done
    ! kill -0 "$old_mpv_pid" 2>/dev/null
  fi
  if [[ -d $XDG_RUNTIME_DIR/omarchy-reolink ]]; then
    for _ in {1..100}; do
      find "$XDG_RUNTIME_DIR/omarchy-reolink" -mindepth 1 -print -quit | grep -q . || break
      sleep 0.02
    done
    ! find "$XDG_RUNTIME_DIR/omarchy-reolink" -mindepth 1 -print -quit | grep -q .
  fi
  helper_pid=""
  mpv_pid=""
}

run_fake_player_probe() {
  local payload="$1" sentinel="$2" label="$3" ignore_term="${4:-0}" output
  output="$test_root/$label.out"
  printf '%s\n' "$payload" | env PATH="$plugin_root/tests/fakes/bin:$original_path" \
    REOLINK_FAKE_IGNORE_TERM="$ignore_term" \
    "$plugin_root/scripts/reolink-player" >"$output" 2>"$test_root/$label.err" &
  helper_pid=$!
  local socket
  socket=$(wait_for_socket)
  [[ -S $socket && ! -L $socket ]]
  [[ $(stat -c %u -- "$socket") == $(id -u) ]]
  [[ $(stat -c %a -- "$socket") == 600 ]]
  assert_process_tree_clean "$helper_pid" "$sentinel"
  for _ in {1..100}; do
    [[ -s $output ]] && break
    sleep 0.02
  done
  mpv_pid=$(jq -r '.pid // 0' "$output")
  [[ $mpv_pid =~ ^[0-9]+$ ]] && ((mpv_pid > 1)) && kill -0 "$mpv_pid"
  ! tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fq '://'
  tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fxq -- '--no-config'
  tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fxq -- '--load-scripts=no'
  tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fxq -- '--terminal=no'
  stop_player_tree
}

run_startup_kill_probe() {
  local payload="$1" worker_pid="" startup_mpv_pid=""
  printf '%s\n' "$payload" | env PATH="$plugin_root/tests/fakes/bin:$original_path" \
    "$plugin_root/scripts/reolink-player" >"$test_root/startup-kill.out" \
    2>"$test_root/startup-kill.err" &
  helper_pid=$!
  for _ in {1..100}; do
    worker_pid=$(pgrep -P "$helper_pid" -f 'reolink-player.*--worker' | head -1 || true)
    [[ $worker_pid =~ ^[0-9]+$ ]] && break
    sleep 0.01
  done
  [[ $worker_pid =~ ^[0-9]+$ ]] && kill -0 "$worker_pid"
  for _ in {1..100}; do
    startup_mpv_pid=$(pgrep -P "$worker_pid" -f 'tests/fakes/bin/mpv' | head -1 || true)
    [[ $startup_mpv_pid =~ ^[0-9]+$ ]] && break
    sleep 0.01
  done
  [[ $startup_mpv_pid =~ ^[0-9]+$ ]] && kill -0 "$startup_mpv_pid"
  [[ ! -s $test_root/startup-kill.out ]]
  kill -KILL "$helper_pid"
  wait "$helper_pid" 2>/dev/null || true
  helper_pid=""
  for _ in {1..150}; do
    kill -0 "$startup_mpv_pid" 2>/dev/null || break
    sleep 0.02
  done
  ! kill -0 "$startup_mpv_pid" 2>/dev/null
  for _ in {1..150}; do
    [[ ! -d $XDG_RUNTIME_DIR/omarchy-reolink ]] \
      || ! find "$XDG_RUNTIME_DIR/omarchy-reolink" -mindepth 1 -print -quit | grep -q . \
      && break
    sleep 0.02
  done
  [[ ! -d $XDG_RUNTIME_DIR/omarchy-reolink ]] \
    || ! find "$XDG_RUNTIME_DIR/omarchy-reolink" -mindepth 1 -print -quit | grep -q .
}

port=$((40000 + RANDOM % 1500))
socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" \
  "EXEC:$plugin_root/tests/shell/fake-camera-handler" >/dev/null 2>&1 &
server_pid=$!
sleep 0.1
kill -0 "$server_pid"

login_payload=$(printf '{"operation":"login","hostId":"%s","address":"127.0.0.1","port":%s,"transport":"http","tlsMode":"verify","username":"admin"}' \
  "$host_id" "$port")
"$plugin_root/scripts/reolink-http" < <(printf '%s' "$login_payload") \
  >"$test_root/login.out" 2>"$test_root/login.err" &
helper_pid=$!
sleep 0.2
assert_process_tree_clean "$helper_pid" "$password"
wait "$helper_pid"
assert_clean_file "$test_root/login.out" "$password" "login response"
assert_clean_file "$test_root/login.err" "$password" "login stderr"

api_payload=$(printf '{"operation":"api","hostId":"%s","address":"127.0.0.1","port":%s,"transport":"http","tlsMode":"verify","username":"admin","token":"%s","body":[{"cmd":"GetDevInfo","action":0,"param":{"testDelay":true}}]}' \
  "$host_id" "$port" "$token")
"$plugin_root/scripts/reolink-http" < <(printf '%s' "$api_payload") \
  >"$test_root/api.out" 2>"$test_root/api.err" &
helper_pid=$!
sleep 0.2
assert_process_tree_clean "$helper_pid" "$token"
wait "$helper_pid"
assert_clean_file "$test_root/api.out" "$token" "API response"
assert_clean_file "$test_root/api.err" "$token" "API stderr"
grep -Fxq 'password-received' "$FAKE_CAMERA_TRACE"
grep -Fxq 'token-received' "$FAKE_CAMERA_TRACE"

ptz_trace_lines=$(wc -l <"$FAKE_CAMERA_TRACE")
ptz_payload=$(printf '{"operation":"ptz-pulse","hostId":"%s","address":"127.0.0.1","port":%s,"transport":"http","tlsMode":"verify","username":"admin","token":"%s","channel":0,"direction":"Down","durationMs":1500}' \
  "$host_id" "$port" "$token")
"$plugin_root/scripts/reolink-http" < <(printf '%s\n' "$ptz_payload") \
  >"$test_root/ptz.out" 2>"$test_root/ptz.err" &
helper_pid=$!
for _ in {1..100}; do
  tail -n "+$((ptz_trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Down' && break
  sleep 0.02
done
tail -n "+$((ptz_trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Down'
assert_process_tree_clean "$helper_pid" "$token"
kill -KILL "$helper_pid"
wait "$helper_pid" 2>/dev/null || true
helper_pid=""
for _ in {1..150}; do
  tail -n "+$((ptz_trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Stop' && break
  sleep 0.02
done
tail -n "+$((ptz_trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Stop'
unset ptz_payload

player_payload=$(printf '{"kind":"live","hostId":"%s","address":"127.0.0.1","username":"admin","rtspPort":554,"channel":0,"stream":"sub"}' "$host_id")
run_startup_kill_probe "$player_payload"
run_fake_player_probe "$player_payload" "$password" fake-live
run_fake_player_probe "$player_payload" "$password" fake-live-ignore-term 1

recording_payload=$(printf '{"kind":"recording","hostId":"%s","address":"127.0.0.1","transport":"https","tlsMode":"verify","port":443,"token":"%s","playbackPath":"/mnt/recordings/front-door.mp4"}' \
  "$host_id" "$token")
run_fake_player_probe "$recording_payload" "$token" fake-recording

if [[ ${REOLINK_SKIP_REAL_MPV:-0} != 1 && -n ${WAYLAND_DISPLAY:-${DISPLAY:-}} ]]; then
  printf '%s\n' "$player_payload" | env PATH="$original_path" \
    "$plugin_root/scripts/reolink-player" >"$test_root/player.out" 2>"$test_root/player.err" &
  helper_pid=$!
  socket=$(wait_for_socket no)
  [[ -S $socket && $(stat -c %a -- "$socket") == 600 ]]
  for _ in {1..100}; do
    [[ -s $test_root/player.out ]] && break
    sleep 0.02
  done
  mpv_pid=$(jq -r '.pid // 0' "$test_root/player.out")
  [[ $mpv_pid =~ ^[0-9]+$ ]] && kill -0 "$mpv_pid"
  assert_clean_file "/proc/$mpv_pid/cmdline" "$password" "mpv argv"
  assert_clean_file "/proc/$mpv_pid/environ" "$password" "mpv environment"
  ! tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fq 'rtsp://'
  tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fxq -- '--no-config'
  tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fxq -- '--load-scripts=no'
  tr '\0' '\n' <"/proc/$mpv_pid/cmdline" | grep -Fxq -- '--terminal=no'
  ! grep -Fq '/etc/mpv/scripts/mpris.so' "/proc/$mpv_pid/maps"
  stop_player_tree
fi

runtime_dir="$XDG_RUNTIME_DIR/omarchy-reolink"
[[ ! -d $runtime_dir || $(stat -c %a -- "$runtime_dir") == 700 ]]
if [[ -d $runtime_dir ]]; then
  ! find "$runtime_dir" -mindepth 1 -print -quit | grep -q .
fi

while IFS= read -r file; do
  assert_clean_file "$file" "$password" "private runtime/config file"
  assert_clean_file "$file" "$token" "private runtime/config file"
done < <(find "$test_root" -type f -print)

while IFS= read -r path; do
  if grep -aFqf <(printf '%s\n%s\n' "$password" "$token") <<<"$path"; then
    echo "sentinel leaked through a filename" >&2
    exit 1
  fi
done < <(find "$test_root" -print)

if [[ -n $real_runtime && -d $real_runtime/quickshell ]]; then
  while IFS= read -r log_file; do
    assert_clean_file "$log_file" "$password" "Quickshell log"
    assert_clean_file "$log_file" "$token" "Quickshell log"
  done < <(find "$real_runtime/quickshell" -type f -name 'log.log' -print 2>/dev/null)
fi
if [[ -d $real_home/.local/state/omarchy/notifications ]]; then
  while IFS= read -r notification_file; do
    assert_clean_file "$notification_file" "$password" "notification history"
    assert_clean_file "$notification_file" "$token" "notification history"
  done < <(find "$real_home/.local/state/omarchy/notifications" -type f -print)
fi
if command -v journalctl >/dev/null 2>&1; then
  if journalctl --user --since "@$test_started" --no-pager 2>/dev/null \
      | grep -aFqf <(printf '%s\n%s\n' "$password" "$token"); then
    echo "sentinel leaked through user journal logs" >&2
    exit 1
  fi
fi

printf '%s\n' "{\"operation\":\"clear\",\"hostId\":\"$host_id\"}" \
  | "$plugin_root/scripts/reolink-secret" | jq -e '.ok == true' >/dev/null
printf '%s\n' "{\"operation\":\"exists\",\"hostId\":\"$host_id\"}" \
  | "$plugin_root/scripts/reolink-secret" | jq -e '.ok == true and .exists == false' >/dev/null

unset password token login_payload api_payload player_payload recording_payload
