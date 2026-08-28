# Security Policy

## Reporting

Please use GitHub's private security-advisory flow for vulnerabilities. Do not
put camera addresses, usernames, passwords, session tokens, snapshots,
recording URLs, or event images in a public issue.

## Trust boundary

Omarchy plugins run as unsandboxed user code inside the long-lived shell. This
repository intentionally has no updater, telemetry, remote code loading,
installer, daemon, server, or runtime package download.

## Secrets

Passwords use Secret Service attributes:

```text
application = omarchy-reolink
host-id = host_...
kind = password
```

Session tokens are memory-only. The captured stdout pipe from a successful
login helper to `Service.qml` is the sole intentional token transport. It is
not forwarded to a terminal or log. This is the necessary exception to the
otherwise blanket rule that tokens never appear in helper output.

Every helper rejects ignored top-level fields and validates string types and
control characters before extracting values into Bash. Camera-provided object
traversal, channel inventories, event states, metadata, and recording lists are
bounded before they enter the long-lived QML shell.

Before storing a password, the service durably writes its non-secret host ID
to the cleanup ledger. The ID is removed only in the same committed config
update as a validated host, or after Secret Service confirms the password was
cleared. A shell crash therefore leaves a visible, retryable cleanup record.

Never include a secret in a bug report. Use the built-in sentinel tests.

## Network guidance

Use verified HTTPS where possible. Self-signed HTTPS and HTTP require explicit
selection. RTSP is normally unencrypted; keep cameras on a trusted LAN/VLAN,
avoid port forwarding, and use firewall isolation for higher-security setups.

## Physical controls

Notification actions only open the UI. Siren activation requires confirmation.
PTZ sends Stop on pointer release/cancel and through an independent safety
deadline inside the CGI helper. An orphan-safe guardian is the sole network
actor for each directional pulse and owns the ordered Start-to-Stop sequence,
even if Quickshell hard-kills its wrapper. Release also uses an independent
Stop request.
Directional movement is rejected by the generic API path and can run only
through that bounded pulse helper. Physical actuator requests are coalesced by
camera and actuator; safety-off supersedes stale queued work and is sent next
after the single in-flight request completes. In-flight generic CGI requests
are never killed, avoiding a late orphaned ON arriving after OFF.
Unsupported controls are not rendered.
