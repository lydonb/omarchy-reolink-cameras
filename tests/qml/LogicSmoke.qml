import QtQuick
import Quickshell
import Quickshell.Io
import "lib/Validation.js" as Validation
import "lib/ReolinkModel.js" as Model
import "lib/CapabilityNormalizer.js" as Capabilities
import "lib/EventNormalizer.js" as Events
import "lib/NotificationCommand.js" as NotificationCommand
import "lib/RequestQueue.js" as RequestQueue
import "lib/ReolinkCommands.js" as Commands
import "lib/Time.js" as Time

ShellRoot {
  Service {
    id: serviceUnderTest
  }

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
    var tlsFailure = Model.loginProcessResult({
      ok: false, error: { code: "tls_error", message: "Camera TLS verification or negotiation failed." }
    }, 1000, false)
    assertTrue(!tlsFailure.ok
      && tlsFailure.error === "Camera TLS verification or negotiation failed.",
      "camera helper failure was hidden behind a generic authentication error")

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
    var deepAbility = ({})
    var deepCursor = deepAbility
    for (var depthIndex = 0; depthIndex < 128; depthIndex += 1) {
      deepCursor.nested = ({})
      deepCursor = deepCursor.nested
    }
    deepCursor.search = { ver: 1 }
    var deepCapabilities = Capabilities.normalize([
      { cmd: "GetAbility", code: 0, value: deepAbility }
    ])
    assertTrue(!deepCapabilities.recordings,
      "unbounded capability traversal accepted a deeply nested camera response")
    var excessiveStatuses = []
    for (var statusIndex = 0; statusIndex < 80; statusIndex += 1)
      excessiveStatuses.push({ channel: statusIndex, name: "Camera\u0000" + "x".repeat(100), online: 1 })
    var boundedChannels = Capabilities.channels([
      { cmd: "GetChannelstatus", code: 0, value: { status: excessiveStatuses } }
    ], "Fallback")
    assertTrue(boundedChannels.length === 64 && boundedChannels[0].name.length <= 80
      && boundedChannels[0].name.indexOf("\u0000") === -1,
      "camera discovery did not bound or sanitize channel metadata")
    var boundedInfo = Capabilities.deviceInfo([
      { cmd: "GetDevInfo", code: 0, value: { DevInfo: { model: "m".repeat(200) + "\u0000" } } }
    ])
    assertTrue(boundedInfo.model.length === 80 && boundedInfo.model.indexOf("\u0000") === -1,
      "device metadata was not bounded and sanitized")

    var eventTime = new Date(2026, 7, 28, 16, 1, 30).getTime()
    var eventRange = Time.aroundRange(eventTime, 300, 300)
    assertTrue(eventRange.start.hour === 15 && eventRange.start.min === 56
      && eventRange.end.hour === 16 && eventRange.end.min === 6,
      "event recording search range was not centered on the event")
    var midnightRange = Time.aroundRange(new Date(2026, 7, 28, 0, 1, 0).getTime(), 300, 300)
    assertTrue(midnightRange.start.day === 27 && midnightRange.end.day === 28,
      "event recording range did not cross midnight safely")
    var recordingResponse = [{ cmd: "Search", code: 0, value: { SearchResult: { File: [
      {
        name: "/mnt/reolink/early.mp4", type: "main",
        StartTime: { year: 2026, mon: 8, day: 28, hour: 15, min: 58, sec: 0 },
        EndTime: { year: 2026, mon: 8, day: 28, hour: 16, min: 0, sec: 0 }
      },
      {
        name: "/mnt/reolink/event.mp4", type: "main",
        StartTime: { year: 2026, mon: 8, day: 28, hour: 16, min: 1, sec: 0 },
        EndTime: { year: 2026, mon: 8, day: 28, hour: 16, min: 2, sec: 0 }
      },
      {
        name: "unplayable.mp4", type: "main",
        StartTime: { year: 2026, mon: 8, day: 28, hour: 16, min: 1, sec: 20 },
        EndTime: { year: 2026, mon: 8, day: 28, hour: 16, min: 1, sec: 40 }
      },
      {
        name: "/mnt/reolink/bad\u0000recording.mp4", type: "main\u0000spoof",
        StartTime: { year: 2026, mon: 8, day: 28, hour: 16, min: 1, sec: 20 },
        EndTime: { year: 2026, mon: 8, day: 28, hour: 16, min: 1, sec: 40 }
      },
      {
        name: "Mp4Record/2026-08-28/relative.mp4", type: "main",
        StartTime: { year: 2026, mon: 8, day: 28, hour: 12, min: 0, sec: 0 },
        EndTime: { year: 2026, mon: 8, day: 28, hour: 12, min: 1, sec: 0 }
      },
      {
        name: "Mp4Record/../private.mp4", type: "main",
        StartTime: { year: 2026, mon: 8, day: 28, hour: 12, min: 0, sec: 0 },
        EndTime: { year: 2026, mon: 8, day: 28, hour: 12, min: 1, sec: 0 }
      }
    ] } } }]
    var parsedRecordings = Model.parseRecordings(recordingResponse, endpoint.value.id, 0)
    assertTrue(parsedRecordings.length === 6
      && parsedRecordings[1].playbackPath === "/mnt/reolink/event.mp4"
      && parsedRecordings[4].playbackPath === "/Mp4Record/2026-08-28/relative.mp4"
      && parsedRecordings[5].playbackPath === ""
      && parsedRecordings[1].startMs > 0,
      "Reolink Search filename was not normalized as a playable recording")
    assertTrue(parsedRecordings[3].playbackPath === ""
      && parsedRecordings[3].name.indexOf("\u0000") === -1
      && parsedRecordings[3].type.indexOf("\u0000") === -1,
      "malformed recording metadata crossed the playback or display boundary")
    var matchingEvent = {
      hostId: endpoint.value.id, channel: 0, type: "person", timestamp: eventTime
    }
    var matchedRecording = Model.recordingForEvent(parsedRecordings, matchingEvent, 300000)
    assertTrue(matchedRecording && matchedRecording.name === "/mnt/reolink/event.mp4",
      "containing recording was not selected for the event")
    assertTrue(Model.recordingForEvent(parsedRecordings, {
      hostId: "host_other", channel: 0, timestamp: eventTime
    }, 300000) === null, "event matching crossed host boundaries")
    assertTrue(Model.recordingForEvent(parsedRecordings, {
      hostId: endpoint.value.id, channel: 1, timestamp: eventTime
    }, 300000) === null, "event matching crossed channel boundaries")
    assertTrue(Model.recordingForEvent(parsedRecordings, {
      hostId: endpoint.value.id, channel: 0, timestamp: eventTime + 3600000
    }, 300000) === null, "event matching exceeded its bounded time window")
    assertTrue(Model.recordingForEvent([parsedRecordings[2]], matchingEvent, 300000) === null,
      "event matching accepted a non-absolute playback source")
    var searchBody = Commands.recordingSearch(0, eventRange.start, eventRange.end)
    assertTrue(JSON.stringify(searchBody).indexOf("eventType") === -1,
      "recording search sent a nonstandard Reolink event filter")

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
    var deepEventValue = ({ channel: 0 })
    var deepEventCursor = deepEventValue
    for (var eventDepth = 0; eventDepth < 128; eventDepth += 1) {
      deepEventCursor.nested = ({})
      deepEventCursor = deepEventCursor.nested
    }
    deepEventCursor.people = { alarm_state: 1 }
    assertTrue(Events.activeStates([
      { cmd: "GetEvents", code: 0, value: deepEventValue }
    ], endpoint.value.id).length === 0,
      "unbounded event traversal accepted a deeply nested camera response")
    assertTrue(Events.activeStates([
      { cmd: "GetEvents", code: 0, value: { channel: 64, md: { alarm_state: 1 } } }
    ], endpoint.value.id).length === 0,
      "event normalization accepted an invalid camera channel")
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

    serviceUnderTest.events = [
      { id: "person-1", type: "person", viewed: false },
      { id: "motion-1", type: "motion", viewed: true }
    ]
    serviceUnderTest.notificationQueue = [{ headline: "Person detected" }]
    assertTrue(serviceUnderTest.unseenCount === 1, "unseen event fixture was not counted")
    serviceUnderTest.clearEvents()
    assertTrue(serviceUnderTest.events.length === 0 && serviceUnderTest.unseenCount === 0,
      "clearing recent events did not reset the badge")
    assertTrue(serviceUnderTest.notificationQueue.length === 0,
      "clearing recent events retained queued notifications")
  }
}
