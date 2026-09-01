# Changelog

## Unreleased

- Place the camera panel at the screen's right margin instead of forcing it to
  the center or leaving space for neighboring bar widgets.
- Add an in-panel **Clear events** action that removes recent camera events,
  resets the unseen badge, and drops notifications that are still queued.

## 0.2.6 - 2026-08-28

- Document the exact Omarchy removal command, MIT licensing, and the project's
  independent status for marketplace submission.
- Replace the hardware-tested private LAN address in the public setup example
  with a generic private LAN address.

## 0.2.5 - 2026-08-28

- Replace the interface concept with a sanitized capture of the real panel and
  identify the new CCTV/security-camera icon in setup instructions.
- Clarify that devices without a visible username or User Management screen
  may still use lowercase `admin` with a separately configured device password.

## 0.2.4 - 2026-08-28

- Replace the generic camera glyph with the distinct CCTV/security-camera icon
  across the bar widget and panel states.

## 0.2.3 - 2026-08-28

- Normalize safe relative `Mp4Record/...` search results before playback for
  Reolink firmware that omits the leading slash.
- Reject empty and traversal path segments at both the QML model and hardened
  player boundaries.

## 0.2.2 - 2026-08-28

- Size panel tabs from the usable content width and elide long camera, event,
  and endpoint labels so every control remains inside the panel.

## 0.2.1 - 2026-08-28

- Reject ignored or malformed helper fields before Bash extraction and remove
  unused recording commands from the generic camera API allowlist.
- Bound camera capability, channel, device metadata, event, and response
  traversal so a malformed host cannot exhaust or destabilize the shell.
- Sanitize camera-supplied recording labels and reject unsafe playback paths
  before they reach the hardened player.

## 0.2.0 - 2026-08-28

- Document working HTTPS/self-signed, RTSP, local-account, and HTTP redirect
  setup paths for Reolink devices.
- Make event **View** search a bounded window on the event's exact host and
  channel, select the containing or nearest playable recording, and open it
  through the hardened mpv helper.
- Accept the absolute `name` returned by Reolink recording searches as the
  playback path when no dedicated path field is present.
- Split snapshot refresh from **Save Photo** and export private JPEG copies to
  the XDG Pictures directory under `Reolink/YYYY-MM-DD`.

## 0.1.2 - 2026-08-28

- Include the bounded numeric HTTP response status in camera transport errors
  so hardware validation can distinguish redirects, authorization failures,
  and unavailable CGI endpoints.

## 0.1.1 - 2026-08-28

- Preserve structured camera-helper failures in the Add flow so TLS,
  networking, and protocol errors are not mislabeled as authentication
  failures.

## 0.1.0 - 2026-08-28

- Add the stock-Omarchy service and bar-widget architecture.
- Add Secret Service configuration, host/channel discovery, snapshot preview,
  hardened mpv playback, event polling, controls, and recording search.
- Add fixture, QML, helper, leakage, and local Omarchy validation gates.
- Add FIFO physical-control ordering, teardown-safe PTZ, explicit recording TLS
  verification, structured transport errors, and recoverable keyring cleanup.
- Mark public real-hardware compatibility validation as pending.
