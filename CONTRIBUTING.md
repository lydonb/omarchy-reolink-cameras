# Contributing

Keep the plugin local, small, native, auditable, and fast.

## Rules

- Do not add a runtime package without an accepted dependency ADR under
  `docs/adr/`.
- Do not add Python, Node/npm, MQTT, go2rtc, Docker, Qt Multimedia, a database,
  a web server, or a Reolink daemon to solve convenience.
- Never put a password, token, or credential URL in argv, environment, config,
  logs, notifications, screenshots, fixture filenames, or test output.
- Do not add generic shell execution, remote download/execute, cross-origin
  redirects, telemetry, or a network listener.
- Keep host failure, capabilities, and request queues isolated.

## Before a pull request

```bash
./scripts/check.sh
```

For hardware changes, also complete the relevant checklist in
`docs/hardware-testing.md` and report only sanitized device metadata.
