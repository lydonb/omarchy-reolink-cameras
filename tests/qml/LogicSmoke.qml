import QtQuick
import Quickshell
import Quickshell.Io
import "lib/Validation.js" as Validation
import "lib/ReolinkModel.js" as Model
import "lib/CapabilityNormalizer.js" as Capabilities
import "lib/EventNormalizer.js" as Events
import "lib/NotificationCommand.js" as NotificationCommand
import "lib/RequestQueue.js" as RequestQueue

ShellRoot {
  FileView {
    id: matrixFile
    path: Qt.resolvedUrl("fixtures/device-matrix.json")
    printErrors: true
    onLoaded: {
      var matrix = JSON.parse(text())
      assertTrue(Array.isArray(matrix) && matrix.length >= 12, "device matrix is incomplete")
      var ids = ({})
      var allowedTopologies = ["standalone", "nvr", "home-hub"]
      for (var index = 0; index < matrix.length; index += 1) {
        var row = matrix[index]
        assertTrue(row.id && !ids[row.id], "duplicate fixture id")
        ids[row.id] = true
        assertTrue(allowedTopologies.indexOf(row.topology) !== -1, "unknown fixture topology")
        assertTrue(Number.isInteger(row.channels) && row.channels >= 0 && row.channels <= 64,
          "invalid fixture channel count")
        assertTrue(Array.isArray(row.features || []), "fixture features must be an array")
      }
      assertTrue(ids["fixed-poe"] && ids["nvr-four-channel"] && ids["home-hub-battery"],
        "required topology fixtures are missing")
      assertTrue(ids["offline"] && ids["auth-error"] && ids["malformed-response"],
        "required failure fixtures are missing")
      console.info("REOLINK_LOGIC_SMOKE_OK")
      Qt.quit()
    }
    onLoadFailed: function(error) { throw new Error("fixture matrix failed to load: " + error) }
  }

  function assertTrue(value, message) {
    if (!value) throw new Error(message)
  }

  Component.onCompleted: {
    var endpoint = Validation.validateEndpoint({
      address: "192.168.20.10", port: 443, rtspPort: 554,
      transport: "https", tlsMode: "verify", username: "omarchy"
    })
    assertTrue(endpoint.ok, "valid endpoint rejected")
    assertTrue(endpoint.value.id.indexOf("host_") === 0, "stable host id missing")
    assertTrue(!Validation.validateEndpoint({ address: "https://camera/path", username: "admin" }).ok,
      "URL-shaped endpoint accepted")
    assertTrue(Validation.configHasForbiddenSecretKey({ hosts: [{ token: "x" }] }),
      "secret config key accepted")
    var nominalSentinel = ["SUPER_SECRET_", "REOLINK_PASSWORD"].join("")
    assertTrue(Validation.savedFieldDuplicatesSecret({ username: nominalSentinel }, nominalSentinel)
      && Validation.savedFieldDuplicatesSecret({ displayName: nominalSentinel }, nominalSentinel),
      "password duplication in saved fields was accepted")

    var login = Model.loginSession([
      { cmd: "Login", code: 0, value: { Token: { name: "SAFE_TOKEN", leaseTime: 3600 } } }
    ], 1000)
    assertTrue(login.ok && login.expiresAt === 3601000, "login session normalization failed")

    var bootstrap = [
      { cmd: "GetDevInfo", code: 0, value: { DevInfo: { model: "RLC-Test", firmVer: "v1" } } },
      { cmd: "GetAbility", code: 0, value: { Ability: {
        ptzCtrl: { permit: 1 }, ptzPreset: { ver: 1 }, zoomFocus: { ver: 1 },
        whiteLed: { ver: 1 }, audioAlarm: { ver: 1 }, supportAi: {
          people: { ver: 1 }, vehicle: { ver: 1 }
        }, search: { ver: 1 }
      } } },
      { cmd: "GetChannelstatus", code: 0, value: { status: [
        { channel: 0, name: "Front Door", online: 1 }
      ] } },
      { cmd: "GetNetPort", code: 0, value: { NetPort: { rtspPort: { enable: 1 } } } },
      { cmd: "GetEnc", code: 0, value: { Enc: { mainStream: { vType: "h265" }, subStream: { vType: "h264" } } } }
    ]
    var capabilities = Capabilities.normalize(bootstrap)
    assertTrue(capabilities.ptz.enabled && capabilities.ptz.zoom, "PTZ capabilities missing")
    assertTrue(capabilities.spotlight && capabilities.siren, "physical capabilities missing")
    assertTrue(capabilities.stream.clearCodec === "h265", "codec normalization failed")
    assertTrue(Capabilities.channels(bootstrap, "Camera").length === 1, "channel normalization failed")
    var partialPresets = [
      { cmd: "GetPtzPreset", code: 1, error: { rspCode: -9 } },
      { cmd: "GetPtzPreset", code: 0, value: { PtzPreset: [{ id: 2, name: "Porch", enable: 1 }] } }
    ]
    assertTrue(Capabilities.presets(partialPresets, 0, 0).length === 0,
      "failed channel inherited another channel's presets")
    assertTrue(Capabilities.presets(partialPresets, 1, 1).length === 1,
      "successful channel presets were lost after a partial failure")
    var noStreamCapabilities = Capabilities.normalize([
      { cmd: "GetAbility", code: 0, value: { Ability: {} } }
    ])
    assertTrue(!noStreamCapabilities.stream.fluent && !noStreamCapabilities.stream.clear
      && !noStreamCapabilities.stream.rtspEnabled, "unknown streams were enabled")

    var markedOffline = Model.markHostOffline([
      { id: "one", hostId: endpoint.value.id, online: true },
      { id: "two", hostId: "host_other", online: true }
    ], endpoint.value.id)
    assertTrue(!markedOffline[0].online && markedOffline[1].online,
      "host isolation failed while marking cameras offline")
    var cleanupIds = Model.addCleanupHostId([], endpoint.value.id)
    cleanupIds = Model.addCleanupHostId(cleanupIds, endpoint.value.id)
    assertTrue(cleanupIds.length === 1, "failed keyring cleanup identifier was not recoverable")
    assertTrue(Model.removeCleanupHostId(cleanupIds, endpoint.value.id).length === 0,
      "completed keyring cleanup identifier was retained")

    var queue = RequestQueue.insert([], { kind: "status" }, false, 32)
    queue = RequestQueue.insert(queue,
      { kind: "siren-on", coalesceKey: "siren:0" }, true, 32)
    queue = RequestQueue.insert(queue,
      { kind: "siren-off", coalesceKey: "siren:0", safetyOff: true }, true, 32)
    assertTrue(queue[0].kind === "siren-off" && queue[1].kind === "status",
      "safety-off did not supersede stale actuator work")
    var saturated = []
    for (var priorityIndex = 0; priorityIndex < 32; priorityIndex += 1)
      saturated = RequestQueue.insert(saturated, { kind: "priority-" + priorityIndex }, true, 32)
    saturated = RequestQueue.insert(saturated,
      { kind: "siren-off-latest", coalesceKey: "siren:0", safetyOff: true }, true, 32)
    assertTrue(saturated.length === 32 && saturated[0].kind === "siren-off-latest",
      "saturated priority queue delayed the newest safety-off state")
    var distinctSafety = []
    for (var safetyIndex = 0; safetyIndex < 33; safetyIndex += 1)
      distinctSafety = RequestQueue.insert(distinctSafety, {
        kind: "siren-off-" + safetyIndex,
        coalesceKey: "siren:" + safetyIndex,
        safetyOff: true
      }, true, 32)
    assertTrue(distinctSafety.length === 33,
      "distinct safety-off state was evicted at the ordinary queue cap")
    distinctSafety = RequestQueue.insert(distinctSafety, { kind: "status" }, false, 32)
    assertTrue(distinctSafety.length === 33 && distinctSafety[32].safetyOff === true,
      "ordinary work evicted a pending safety-off state")

    var cleanupCapacity = []
    for (var cleanupIndex = 0; cleanupIndex < 64; cleanupIndex += 1)
      cleanupCapacity.push("host_pending_" + cleanupIndex)
    assertTrue(!Model.canStoreCredential(cleanupCapacity, "host_new_pending"),
      "credential store was allowed beyond recoverable cleanup capacity")
    assertTrue(Model.canStoreCredential(cleanupCapacity, "host_pending_63"),
      "credential retry for a tracked cleanup host was blocked")
    assertTrue(Model.canBeginCredentialMutation(false, cleanupCapacity, "host_pending_63"),
      "available serialized credential retry was blocked")
    assertTrue(!Model.canBeginCredentialMutation(true, [], endpoint.value.id),
      "overlapping credential mutation was not rejected")
    var writeAheadReservation = Model.addCleanupHostId([], endpoint.value.id)
    assertTrue(writeAheadReservation.length === 1
      && Model.removeCleanupHostId(writeAheadReservation, endpoint.value.id).length === 0,
      "credential cleanup write-ahead reservation was not reversible")

    var rawEvents = [{ cmd: "GetEvents", code: 0, value: {
      channel: 0, md: { alarm_state: 1 }, ai: { people: { alarm_state: 1 } }
    } }]
    var active = Events.activeStates(rawEvents, endpoint.value.id)
    assertTrue(active.length === 2, "event normalization failed")
    var first = Events.risingEdges({}, active, 20000, 10000)
    var repeated = Events.risingEdges(first.state, active, 21000, 10000)
    assertTrue(first.events.length === 2 && repeated.events.length === 0, "event debounce failed")
    var sentinel = ["SUPER_SECRET_", "REOLINK_PASSWORD"].join("")
    var notice = Events.notification("person", { cameraName: sentinel })
    assertTrue(JSON.stringify(notice).indexOf(sentinel) === -1, "notification leaked endpoint data")
    var notificationCommand = NotificationCommand.build("io.github.rodrix2000.reolink-cameras", notice)
    assertTrue(JSON.stringify(notificationCommand).indexOf(sentinel) === -1,
      "notification process arguments leaked endpoint data")
    assertTrue(notificationCommand[notificationCommand.length - 1] === "{}",
      "notification click could execute something other than opening the UI")
  }
}
