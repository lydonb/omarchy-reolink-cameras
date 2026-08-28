# Protocol and Security Spike

Date: 2026-08-28

## Outcome

The stock Omarchy surface is sufficient. No dependency ADR is needed.

The spike proves the local adapter shape with a loopback fake Reolink endpoint,
real curl, real Secret Service, real mpv, private Unix IPC, response limits,
and sentinel inspection. Real-camera firmware validation remains an explicit
hardware gate rather than an inferred success.

## CGI adapter

- One bounded newline-framed JSON request envelope enters on stdin. This is
  required because Quickshell's process write channel stays open.
- Endpoint, port, TLS mode, username, channel, operation, and every batch
  command are validated against allowlists.
- Login retrieves the password itself from Secret Service.
- Curl receives the login body and token-bearing URL through inherited private
  descriptors. It never receives a secret in argv or environment.
- Proxy bypass is forced and redirects are not followed.
- Non-2xx HTTP status, authentication rows, all-failed batches, and failed
  physical commands are normalized as failures; optional discovery rows may
  fail without hiding otherwise verified capabilities.
- Redirect targets are never followed, transport failures retain structured
  error JSON, and every returned row must carry a numeric Reolink status code.
- JSON is capped at 1 MiB; recording metadata at 2 MiB; JPEG at 20 MiB.
- Snapshots are created as mode-0600 temporary files inside the mode-0700
  cache, checked for JPEG magic, then atomically renamed.
- Directional PTZ starts an argv/environment-clean Stop guardian before the
  camera command. It survives wrapper SIGKILL and enforces the same 1.5-second
  maximum deadline through its inherited private request pipe.

The current direct endpoint is `/cgi-bin/api.cgi`. Firmware requiring a
different fixed CGI path must be proven on hardware before adding a narrowly
validated compatibility option.

## Playback adapter

- Live input contains only host/channel/quality metadata.
- The helper retrieves the password and builds the documented
  `Preview_<channel>_<main|sub>` URL in memory.
- mpv starts idle without a URL using `--no-config`, `--load-scripts=no`,
  `--terminal=no`, and silent logging.
- The URL reaches mpv only as a JSON `loadfile` command over a private socket
  in a private per-player directory under `$XDG_RUNTIME_DIR/omarchy-reolink`.
- The controller remains alive for mpv's lifetime and terminates the player on
  shell/plugin teardown, avoiding untracked player windows.
- A narrow watchdog receives only controller/player PIDs and runtime paths;
  it survives controller SIGKILL long enough to terminate mpv and remove IPC.
- HTTPS recordings explicitly set mpv TLS verification from the saved host
  policy instead of inheriting mpv's insecure default.
- Tests inspect the real mpv command line and mappings to confirm that
  `/etc/mpv/scripts/mpris.so` is not loaded.

## Known protocol risks to test on hardware

- session lease/refresh behavior and HTTP-200 authentication errors;
- partial batch failures and firmware-specific ability shapes;
- NVR/Home Hub channel and logical-lens mapping;
- Snap token authentication on older firmware;
- GetEvents vs older GetAiState/GetMdState variants;
- SetAudioAlarm vs V20 siren variants;
- recording Search/Playback response and same-host media path shapes;
- Clear stream unavailable on specific 4K recorder hardware;
- self-signed HTTPS certificate UX;
- camera-specific PTZ timing beyond the bounded 1.2-second helper failsafe.

Unsupported commands are expected to degrade without affecting snapshots,
live playback, other capabilities, or other hosts.
