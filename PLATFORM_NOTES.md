# Platform Notes

Validated on 2026-08-28 against the installed Omarchy 4.0.1-1 checkout at
`/usr/share/omarchy` before implementation began.

## Shell and plugin contract

- Omarchy runs one long-lived Quickshell process from
  `/usr/share/omarchy/shell`.
- Third-party plugins are Git repositories with `manifest.json` at the root.
- Installed third-party plugins live at
  `~/.config/omarchy/plugins/<manifest-id>` and run as unsandboxed user code.
- The third-party namespace must not begin with `omarchy.`. This project uses
  `io.github.rodrix2000.reolink-cameras`.
- A persistent singleton plus bar UI is supported with
  `kinds: ["service", "bar-widget"]` and the entry point keys `service` and
  `barWidget`. `keepLoaded` is not used because it only affects separately
  declared panel/overlay/menu loader entries.
- The shell injects `shell`, `manifest`, `omarchyPath`, `barWidgetRegistry`, and
  `pluginRegistry` when those properties exist on a service.
- A bar widget retrieves its singleton with
  `bar.shell.serviceFor(moduleName)`. `firstPartyServiceFor` is only a
  compatibility alias and is not used here.
- `Bar.findPanelWidget` requires a popup-bearing widget root to expose
  `open()`, `close()`, and `opened`. The stock Clock and Weather plugins load a
  nested `Panel.qml` from their `bar-widget` entry point, so this plugin follows
  that pattern without declaring a separate `panel` kind.
- Saving under `~/.config/omarchy/plugins` triggers the local plugin watcher.
  `omarchy-shell shell rescanPlugins` remains the explicit fallback.

Validated source files:

- `/usr/share/omarchy/shell/README.md`
- `/usr/share/omarchy/shell/plugins/README.md`
- `/usr/share/omarchy/shell/shell.qml`
- `/usr/share/omarchy/shell/services/PluginRegistry.qml`
- `/usr/share/omarchy/shell/plugins/services/media/manifest.json`
- `/usr/share/omarchy/shell/plugins/services/media/Service.qml`
- `/usr/share/omarchy/shell/plugins/services/media/BarWidget.qml`
- `/usr/share/omarchy/shell/plugins/panels/weather/BarWidget.qml`
- `/usr/share/omarchy/shell/plugins/panels/weather/Panel.qml`

## QML and process boundaries

- `Quickshell.Io.Process` accepts an argument array in `command`.
- Setting `stdinEnabled: true` and calling `write()` in `onStarted` provides the
  stock secret-safe stdin boundary. Quickshell does not expose a close-stdin
  method here, so helpers consume exactly one bounded newline-framed JSON value
  and reject an immediately queued trailing frame before acting.
  Omarchy's Network panel uses the same write boundary for an enterprise Wi-Fi
  passphrase.
- `StdioCollector { waitForEnd: true }` is suitable only where the helper
  enforces its own response cap. Long-running or unbounded output must not be
  attached to a collector.
- `FileView` supports private config reads and watches, but it cannot create a
  missing parent or atomically write a new file. A narrow helper owns config
  directory creation, validation, modes, and atomic replacement.
- `qs.Ui.Panel` plus `qs.Ui.KeyboardPanel` is the current keyboard-accessible
  anchored popup pattern. It preserves bar popup coordination and Escape/focus
  behavior.

## Notifications

`/usr/share/omarchy/bin/omarchy-notification-send` is present. It uses typed
D-Bus arguments and accepts an optional `--exec` argv vector without shell
re-parsing. Notification text and click payload are fixed from a local event
allowlist; clicks only summon the plugin UI and expose no physical action.

## Stock dependency inventory

No package was installed for this project.

| Capability | Installed path/version |
| --- | --- |
| Omarchy | `/usr/share/omarchy`, 4.0.1-1 |
| Quickshell | `/usr/bin/quickshell`, 0.3.1-1 |
| Bash | `/usr/bin/bash` |
| curl | `/usr/bin/curl`, 8.21.0 |
| jq | `/usr/bin/jq`, 1.8.2 |
| Secret Service CLI | `/usr/bin/secret-tool`, libsecret 0.21.7-1 |
| mpv | `/usr/bin/mpv`, 0.41.0 |
| socat | `/usr/bin/socat`, 1.8.1.3 |
| qmllint | `/usr/lib/qt6/bin/qmllint`, from stock `qt6-declarative` |

`qmllint` is installed outside the interactive `PATH`; project checks resolve
`/usr/lib/qt6/bin/qmllint` explicitly when `command -v qmllint` is empty.

## Validation commands

From the repository root:

```bash
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" \
  Service.qml BarWidget.qml Panel.qml HostRuntime.qml
bash -n scripts/* tests/shell/*.sh
```

The installed `qmllint` resolves Omarchy singleton modules more reliably when
the project check also supplies the `Ui/qmldir` and `Commons/qmldir` import
files; `scripts/check.sh` contains the exact local command used by CI.
