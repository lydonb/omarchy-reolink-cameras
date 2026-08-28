# Hardware Testing

Public 0.1.x builds are protocol-validation releases until this matrix records
sanitized real-device results.

| Topology | Required before V1 | Status |
| --- | --- | --- |
| Powered standalone camera | Yes | Pending |
| NVR or Home Hub channel path | Yes when hardware is available | Pending |
| PTZ camera | Preferred | Pending |
| Doorbell/person/visitor events | Preferred | Pending |
| Dual lens | Preferred | Pending |

For each device test:

- HTTPS verified/self-signed/HTTP behavior;
- Login, lease refresh, GetDevInfo, GetAbility, channels, and encoding;
- snapshot and private cache modes;
- Fluent and Clear mpv playback;
- physical event rising edge/debounce/notification latency;
- offline/reboot/password-change recovery;
- supported PTZ/zoom/spotlight/siren safety;
- bounded recording search and same-host playback;
- one failed host while a second host remains usable;
- shell reload, disable/enable, and no orphan helper/socket;
- a 24-hour poll/live/reconnect soak before V1.

Never attach request dumps containing credentials, session tokens, or media
URLs. Report model, hardware revision, firmware, topology, and sanitized
capability results only.
