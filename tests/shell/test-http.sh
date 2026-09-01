#!/usr/bin/env bash
set -euo pipefail

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d -t omarchy-reolink-http.XXXXXXXX)
server_pid=""
redirect_pid=""
tls_pid=""
ptz_pid=""
host_id="host_http_fixture_$$"

cleanup() {
  [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null || true
  [[ -n $redirect_pid ]] && kill "$redirect_pid" 2>/dev/null || true
  [[ -n $tls_pid ]] && kill "$tls_pid" 2>/dev/null || true
  [[ -n $ptz_pid ]] && kill "$ptz_pid" 2>/dev/null || true
  secret-tool clear application omarchy-reolink host-id "$host_id" kind password >/dev/null 2>&1 || true
  rm -rf -- "$test_root"
}
trap cleanup EXIT

export HOME="$test_root/home"
export XDG_CACHE_HOME="$test_root/cache"
export FAKE_CAMERA_TRACE="$test_root/ptz.trace"
mkdir -p -- "$HOME"

password=$(printf '%s' 'SUPER_SECRET_' 'REOLINK_PASSWORD')
printf '%s' "$password" | secret-tool store --label='Omarchy Reolink HTTP fixture' \
  application omarchy-reolink host-id "$host_id" kind password >/dev/null
unset password

port=$((38000 + RANDOM % 1000))
redirect_port=$((41000 + RANDOM % 1000))
tls_port=$((43000 + RANDOM % 1000))
redirect_trace="$test_root/redirect.trace"
FAKE_REDIRECT_RECEIVER_TRACE="$redirect_trace" socat "TCP-LISTEN:$redirect_port,bind=127.0.0.1,reuseaddr,fork" \
  "EXEC:$plugin_root/tests/shell/fake-camera-handler" >/dev/null 2>&1 &
redirect_pid=$!
FAKE_REDIRECT_URL="http://127.0.0.1:$redirect_port/capture" \
  socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" \
  "EXEC:$plugin_root/tests/shell/fake-camera-handler" >/dev/null 2>&1 &
server_pid=$!
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=localhost' \
  -keyout "$test_root/tls.key" -out "$test_root/tls.crt" >/dev/null 2>&1
openssl s_server -quiet -accept "127.0.0.1:$tls_port" \
  -cert "$test_root/tls.crt" -key "$test_root/tls.key" -www >/dev/null 2>&1 &
tls_pid=$!
sleep 0.1
kill -0 "$server_pid"
kill -0 "$redirect_pid"
kill -0 "$tls_pid"

assert_error_code() {
  local payload="$1" expected="$2" output rc
  set +e
  output=$(printf '%s\n' "$payload" | "$plugin_root/scripts/reolink-http")
  rc=$?
  set -e
  ((rc != 0))
  jq -e --arg expected "$expected" '.ok == false and .error.code == $expected' <<<"$output" >/dev/null
}

base=$(jq -cn --arg hostId "$host_id" --argjson port "$port" '{
  hostId:$hostId,address:"127.0.0.1",port:$port,transport:"http",tlsMode:"verify",username:"admin"
}')

assert_error_code "$(jq -c '. + {operation:"login",ignored:"value"}' <<<"$base")" invalid_request
assert_error_code "$(jq -c '. + {operation:"login"} | .address="127.0.0.1\u0000.invalid"' <<<"$base")" invalid_request

missing_secret=$(jq -c '.hostId="host_missing_fixture" | .operation="login"' <<<"$base")
assert_missing_output=""
set +e
assert_missing_output=$(printf '%s\n' "$missing_secret" | "$plugin_root/scripts/reolink-http")
assert_missing_rc=$?
set -e
((assert_missing_rc != 0))
jq -e '.error.code == "secret_missing"' <<<"$assert_missing_output" >/dev/null

login=$(jq -c '. + {operation:"login"}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http")
jq -e '.[0].value.Token.name == "SAFE_SESSION_TOKEN"' <<<"$login" >/dev/null
assert_error_code "$(jq -c '. + {operation:"login",username:"wrong"}' <<<"$base")" authentication_failed
assert_error_code "$(jq -c '. + {operation:"login",username:"malformed"}' <<<"$base")" invalid_response

api=$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[
  {cmd:"GetDevInfo",action:0,param:{}},
  {cmd:"GetAbility",action:0,param:{}},
  {cmd:"GetChannelstatus",action:0,param:{}},
  {cmd:"GetNetPort",action:0,param:{}},
  {cmd:"GetEnc",action:0,param:{channel:0}}
]}' <<<"$base" | "$plugin_root/scripts/reolink-http")
jq -e 'map(.cmd) | index("GetChannelstatus") != null' <<<"$api" >/dev/null

zoom_state=$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[
  {cmd:"GetZoomFocus",action:0,param:{channel:0}}
]}' <<<"$base" | "$plugin_root/scripts/reolink-http")
jq -e '.[0].value.ZoomFocus.zoom.pos == 14' <<<"$zoom_state" >/dev/null

zoom_result=$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[
  {cmd:"StartZoomFocus",action:0,param:{ZoomFocus:{channel:0,op:"ZoomPos",pos:15}}}
]}' <<<"$base" | "$plugin_root/scripts/reolink-http")
jq -e '.[0].code == 0' <<<"$zoom_result" >/dev/null
grep -Fxq 'ZoomPos:15' "$FAKE_CAMERA_TRACE"

snapshot=$(jq -c '. + {operation:"snapshot",token:"SAFE_SESSION_TOKEN",channel:0}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http")
snapshot_path=$(jq -r '.path' <<<"$snapshot")
[[ -f $snapshot_path && $(stat -c %a -- "$snapshot_path") == 600 ]]
[[ $(stat -c %a -- "${snapshot_path%/*}") == 700 ]]
[[ $(od -An -tx1 -N2 -- "$snapshot_path" | tr -d ' \n') == ffd8 ]]

if jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"ArbitraryShell",action:0,param:{}}]}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" >/dev/null 2>&1; then
  echo "HTTP helper accepted a command outside its allowlist" >&2
  exit 1
fi

if jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"Login",action:0,param:{User:{userName:"admin",password:"injected"}}}]}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" >/dev/null 2>&1; then
  echo "HTTP helper accepted caller-supplied Login credentials" >&2
  exit 1
fi
if jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"Download",action:0,param:{}}]}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" >/dev/null 2>&1; then
  echo "HTTP helper accepted an unused recording command" >&2
  exit 1
fi

assert_error_code "$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetAiState",action:0,param:{channel:0}}]}' <<<"$base")" http_error
[[ ! -s $redirect_trace ]]

auth_error=$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetMdState",action:0,param:{channel:0}}]}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" 2>/dev/null || true)
jq -e '.error.code == "authentication_failed"' <<<"$auth_error" >/dev/null

if jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"PtzCtrl",action:0,param:{channel:0,op:"Start",speed:99,arbitrary:"value"}}]}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" >/dev/null 2>&1; then
  echo "HTTP helper accepted unsafe physical-command parameters" >&2
  exit 1
fi
if jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"PtzCtrl",action:0,param:{channel:0,op:"Right",speed:24}}]}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" >/dev/null 2>&1; then
  echo "HTTP helper allowed directional PTZ outside the bounded pulse operation" >&2
  exit 1
fi

ptz_result=$(jq -c '. + {operation:"ptz-pulse",token:"SAFE_SESSION_TOKEN",channel:0,direction:"Left",durationMs:100,speed:8}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http")
jq -e '.ok == true' <<<"$ptz_result" >/dev/null
grep -Fxq 'Left' "$FAKE_CAMERA_TRACE"
grep -Fxq 'Stop' "$FAKE_CAMERA_TRACE"

trace_lines=$(wc -l <"$FAKE_CAMERA_TRACE")
deadline_started=$(date +%s%3N)
deadline_result=$(jq -c '. + {operation:"ptz-pulse",token:"SAFE_SESSION_TOKEN",channel:0,direction:"Down",durationMs:200,speed:8}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" 2>/dev/null || true)
deadline_elapsed=$(($(date +%s%3N) - deadline_started))
jq -e '.ok == true' <<<"$deadline_result" >/dev/null
((deadline_elapsed < 2000))
for _ in {1..100}; do
  tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Stop' && break
  sleep 0.02
done
deadline_trace=$(tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE")
[[ $(sed -n '1p' <<<"$deadline_trace") == Down ]]
[[ $(sed -n '2p' <<<"$deadline_trace") == Stop ]]

trace_lines=$(wc -l <"$FAKE_CAMERA_TRACE")
jq -c '. + {operation:"ptz-pulse",token:"SAFE_SESSION_TOKEN",channel:0,direction:"Right",durationMs:1500,speed:8}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" >"$test_root/ptz-cancel.out" &
ptz_pid=$!
for _ in {1..100}; do
  tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE" 2>/dev/null | grep -Fxq 'Right' && break
  sleep 0.02
done
tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Right'
kill -TERM "$ptz_pid"
wait "$ptz_pid" 2>/dev/null || true
ptz_pid=""
for _ in {1..100}; do
  tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Stop' && break
  sleep 0.02
done
cancel_trace=$(tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE")
[[ $(sed -n '1p' <<<"$cancel_trace") == Right ]]
[[ $(sed -n '2p' <<<"$cancel_trace") == Stop ]]
sleep 0.2

trace_lines=$(wc -l <"$FAKE_CAMERA_TRACE")
jq -c '. + {operation:"ptz-pulse",token:"SAFE_SESSION_TOKEN",channel:0,direction:"Up",durationMs:1500,speed:8}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" >"$test_root/ptz-hard-kill.out" &
ptz_pid=$!
for _ in {1..100}; do
  guardian_pid=$(pgrep -P "$ptz_pid" -f 'reolink-http' | head -1 || true)
  [[ $guardian_pid =~ ^[0-9]+$ ]] && break
  sleep 0.02
done
[[ $guardian_pid =~ ^[0-9]+$ ]] && kill -0 "$guardian_pid"
# Kill the wrapper before the delayed fake camera has observed Start. The
# surviving guardian must still serialize the eventual Up then Stop requests.
! tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Up'
kill -KILL "$ptz_pid"
wait "$ptz_pid" 2>/dev/null || true
ptz_pid=""
for _ in {1..150}; do
  tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE" | grep -Fxq 'Stop' && break
  sleep 0.02
done
hard_kill_trace=$(tail -n "+$((trace_lines + 1))" "$FAKE_CAMERA_TRACE")
[[ $(sed -n '1p' <<<"$hard_kill_trace") == Up ]]
grep -Fxq 'Stop' <<<"$hard_kill_trace"

assert_error_code "$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetChnTypeInfo",action:0,param:{channel:0}}]}' <<<"$base")" response_too_large
assert_error_code "$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetAudioAlarm",action:0,param:{channel:0}}]}' <<<"$base")" invalid_response
http_status_error=$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetWhiteLed",action:0,param:{channel:0}}]}' <<<"$base" \
  | "$plugin_root/scripts/reolink-http" 2>/dev/null || true)
jq -e '.error.code == "http_error" and .error.message == "Camera returned HTTP status 500."' \
  <<<"$http_status_error" >/dev/null
assert_error_code "$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetPtzPreset",action:0,param:{channel:0}}]}' <<<"$base")" invalid_response
assert_error_code "$(jq -c --argjson port "$tls_port" '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetDevInfo",action:0,param:{}}]} | .transport="https" | .port=$port' <<<"$base")" tls_error
assert_error_code "$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetDevInfo",action:0,param:{}}]} | .port=1' <<<"$base")" network_error
assert_error_code "$(jq -c '. + {operation:"api",token:"SAFE_SESSION_TOKEN",body:[{cmd:"GetAudioAlarmV20",action:0,param:{channel:0}}]}' <<<"$base")" timeout

mkdir -p -- "$test_root/symlink-cache" "$test_root/outside-snapshots"
ln -s -- "$test_root/outside-snapshots" "$test_root/symlink-cache/omarchy-reolink"
if jq -c '. + {operation:"snapshot",token:"SAFE_SESSION_TOKEN",channel:0}' <<<"$base" \
  | XDG_CACHE_HOME="$test_root/symlink-cache" "$plugin_root/scripts/reolink-http" >/dev/null 2>&1; then
  echo "HTTP helper followed a managed snapshot symlink" >&2
  exit 1
fi
[[ -z $(find "$test_root/outside-snapshots" -type f -print -quit) ]]

if printf '%s' '{"operation":"login","hostId":"host_bad","address":"https://evil.example/path","port":443,"transport":"https","tlsMode":"verify","username":"admin"}' \
  | "$plugin_root/scripts/reolink-http" >/dev/null 2>&1; then
  echo "HTTP helper accepted a URL-shaped host" >&2
  exit 1
fi
