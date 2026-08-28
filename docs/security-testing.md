# Security Testing

`tests/security/sentinel-leakage.sh` generates its sentinel at runtime and
checks helper descendants, a deterministic headless mpv stand-in, the real mpv
process when a display is available, private data roots, notification history,
Quickshell/user-journal logs, captured stderr, and process metadata.

The test checks:

- `/proc/<pid>/cmdline`;
- `/proc/<pid>/environ`;
- captured sanitized stderr/output for non-login operations;
- config, cache, and runtime filenames/content;
- mpv argv and mapped scripts;
- private directory/file/socket modes;
- complete same-host playback URL delivery and HTTPS verification flags;
- redirect rejection with a second loopback origin that must see no request;
- hard-kill cleanup of the test keyring item, supervised player, run directory,
  and socket;
- player-wrapper SIGKILL during startup before IPC/status attachment;
- bounded TERM-to-KILL escalation against an mpv stand-in that ignores TERM;
- PTZ Stop delivery after graceful cancellation, wrapper SIGKILL, and a camera
  that applies Start but withholds its HTTP response beyond the pulse deadline.

The fake mpv accepts the private IPC command only when it sees the generated
password or recording token, which proves that both secret media forms crossed
IPC without appearing in argv or environment. It is not a playback substitute;
the graphical local gate separately inspects real mpv mappings for
`/etc/mpv/scripts/mpris.so`.

A successful Login response must carry the new token through the helper's
captured stdout pipe into `Service.qml` memory. That private response pipe is
the sole intentional token channel and is not a log or terminal output path.
