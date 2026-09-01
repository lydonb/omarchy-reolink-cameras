pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "lib/ReolinkCommands.js" as Commands
import "lib/ReolinkModel.js" as Model
import "lib/CapabilityNormalizer.js" as Capabilities
import "lib/EventNormalizer.js" as Events
import "lib/PtzTiming.js" as PtzTiming
import "lib/RequestQueue.js" as RequestQueue
import "lib/Time.js" as Time

Item {
  id: root

  required property var host
  required property var service
  required property string helperPath
  required property string playerPath

  property string runtimeState: "starting"
  property string token: ""
  property double tokenExpiresAt: 0
  property string errorMessage: ""
  property var channels: []
  property var capabilities: ({})
  property var edgeState: ({})
  property var requestQueue: []
  property var activeRequest: null
  property string activeInput: ""
  property bool authenticating: false
  property int backoffIndex: 0
  property int ptzChannel: -1
  property double ptzStartedAt: 0
  property bool eventsEnabled: true

  readonly property var backoffIntervals: [2000, 5000, 10000, 30000, 60000]
  readonly property int minimumPtzPulseMs: 300
  readonly property bool ready: runtimeState === "online" || runtimeState === "degraded"

  function enqueue(kind, envelope, callback, priority, coalesceKey, safetyOff) {
    var request = {
      kind: kind,
      input: JSON.stringify(envelope),
      callback: callback,
      coalesceKey: coalesceKey || "",
      safetyOff: safetyOff === true
    }
    requestQueue = RequestQueue.insert(requestQueue, request, priority, 32)
    drain()
  }

  function drain() {
    if (httpProcess.running || activeRequest || !requestQueue.length || !helperPath) return
    var queue = requestQueue.slice()
    activeRequest = queue.shift()
    requestQueue = queue
    activeInput = activeRequest.input
    activeRequest.input = ""
    httpProcess.running = true
  }

  function login() {
    if (authenticating || httpProcess.running) return
    authenticating = true
    runtimeState = "authenticating"
    service.setHostState(host.id, runtimeState, "Signing in")
    enqueue("login", Commands.loginEnvelope(host), function(ok, response, message) {
      root.authenticating = false
      if (!ok) { root.failHost(message || "Authentication failed."); return }
      var session = Model.loginSession(response, Date.now())
      if (!session.ok) { root.failHost(session.error); return }
      root.token = session.token
      root.tokenExpiresAt = session.expiresAt
      root.backoffIndex = 0
      root.bootstrap()
    }, true)
  }

  function ensureSession(callback) {
    if (token && Date.now() + 60000 < tokenExpiresAt) { callback(true); return }
    if (authenticating) { callback(false); return }
    login()
    callback(false)
  }

  function bootstrap() {
    if (!token) { login(); return }
    runtimeState = "discovering"
    service.setHostState(host.id, runtimeState, "Discovering channels and capabilities")
    enqueue("bootstrap", Commands.apiEnvelope(host, token, Commands.bootstrap()), function(ok, response, message) {
      if (!ok) { root.handleApiFailure(message); return }
      var info = Capabilities.deviceInfo(response)
      root.capabilities = Capabilities.normalize(response)
      root.channels = Capabilities.channels(response, host.displayName)
      var cameras = Model.logicalCameras(host, root.channels, root.capabilities, info)
      root.service.updateHostCameras(host.id, cameras)
      root.runtimeState = "online"
      root.errorMessage = ""
      root.backoffIndex = 0
      root.service.setHostState(host.id, root.runtimeState, "")
      if (root.capabilities.ptz.presets) root.discoverPresets()
      if (root.eventsEnabled) eventTimer.restart()
      statusTimer.restart()
      if (root.service.previewActive) root.refreshSelectedSnapshot()
    })
  }

  function refresh() {
    eventsEnabled = true
    if (!token || Date.now() + 60000 >= tokenExpiresAt) login()
    else bootstrap()
  }

  function failHost(message) {
    runtimeState = "offline"
    errorMessage = String(message || "Camera is offline.")
    service.setHostState(host.id, runtimeState, errorMessage)
    service.markHostOffline(host.id)
    var delayIndex = Math.min(backoffIndex, backoffIntervals.length - 1)
    retryTimer.interval = backoffIntervals[delayIndex]
    backoffIndex = Math.min(backoffIndex + 1, backoffIntervals.length - 1)
    retryTimer.restart()
  }

  function handleApiFailure(message) {
    var text = String(message || "Camera request failed.")
    if (/auth|token|login/i.test(text)) {
      token = ""
      tokenExpiresAt = 0
    }
    failHost(text)
  }

  function requestEvents() {
    if (!eventsEnabled || !ready || httpProcess.running || activeRequest || requestQueue.length) return
    if (!token || Date.now() + 60000 >= tokenExpiresAt) { login(); return }
    var channelNumbers = []
    for (var index = 0; index < channels.length; index += 1) channelNumbers.push(channels[index].channel)
    enqueue("events", Commands.apiEnvelope(host, token, Commands.eventBatch(channelNumbers)), function(ok, response, message) {
      if (!ok) {
        var failure = String(message || "Event polling failed.")
        if (/auth|token|login|network|timed out/i.test(failure)) root.handleApiFailure(failure)
        else {
          root.eventsEnabled = false
          eventTimer.stop()
          root.runtimeState = "degraded"
          root.errorMessage = failure
          root.service.setHostState(host.id, root.runtimeState, failure)
        }
        return
      }
      var active = Events.activeStates(response, host.id)
      var edges = Events.risingEdges(root.edgeState, active, Date.now(), 10000)
      root.edgeState = edges.state
      root.service.publishEvents(edges.events)
      if (root.runtimeState !== "online") {
        root.runtimeState = "online"
        root.service.setHostState(host.id, root.runtimeState, "")
      }
    })
  }

  function refreshSelectedSnapshot() {
    var camera = service.selectedCamera
    if (camera && camera.hostId === host.id) requestSnapshot(camera)
  }

  function requestSnapshot(camera) {
    if (!camera || camera.hostId !== host.id || !ready || httpProcess.running || !token) return
    enqueue("snapshot", Commands.snapshotEnvelope(host, token, camera.channel), function(ok, response, message) {
      if (!ok) { root.errorMessage = message; return }
      if (response && response.ok && response.path)
        root.service.updateCamera(camera.id, { snapshotPath: String(response.path), snapshotUpdatedAt: Date.now() })
    })
  }

  function sendControl(kind, body, callback, coalesceKey, safetyOff) {
    if (!ready || !token) { if (callback) callback(false); return }
    enqueue(kind, Commands.apiEnvelope(host, token, body), function(ok, response, message) {
      if (!ok) root.service.lastError = message
      if (callback) callback(ok, response)
    }, true, coalesceKey, safetyOff)
  }

  function startPtz(camera, direction) {
    if (!ready || !token || ptzProcess.running || ptzStopProcess.running) return
    ptzMinimumTimer.stop()
    ptzChannel = camera.channel
    ptzStartedAt = Date.now()
    ptzProcess.canceledSafely = false
    // The E1 Zoom needs about 300 ms at its normal low-medium speed to move
    // reliably from rest. Keep the helper's hard Stop
    // deadline independent from how quickly the camera returns its response.
    ptzProcess.input = JSON.stringify(Commands.ptzPulseEnvelope(host, token, camera.channel, direction, 300, 8))
    ptzProcess.running = true
  }

  function finishPtzStop(channel) {
    ptzMinimumTimer.stop()
    ptzStartedAt = 0
    ptzChannel = -1
    if (ptzProcess.running) {
      ptzProcess.canceledSafely = true
      ptzProcess.running = false
    }
    if (channel < 0 || !token || ptzStopProcess.running) return
    ptzStopProcess.input = JSON.stringify(Commands.apiEnvelope(host, token, Commands.ptz(channel, "Stop", 24, 0)))
    ptzStopProcess.running = true
  }

  function stopPtz(camera, immediate) {
    var channel = camera ? camera.channel : ptzChannel
    var remaining = immediate === true ? 0
      : PtzTiming.remainingMinimum(ptzStartedAt, Date.now(), minimumPtzPulseMs)
    if (channel >= 0 && ptzProcess.running && remaining > 0) {
      ptzMinimumTimer.interval = remaining
      ptzMinimumTimer.restart()
      return
    }
    finishPtzStop(channel)
  }

  function gotoPreset(camera, presetId) {
    sendControl("ptz-preset", Commands.ptz(camera.channel, "ToPos", 24, presetId), null,
      "ptz-preset:" + camera.channel, false)
  }

  function discoverPresets() {
    var channelNumbers = []
    for (var index = 0; index < channels.length; index += 1) channelNumbers.push(channels[index].channel)
    enqueue("presets", Commands.apiEnvelope(host, token, Commands.presetBatch(channelNumbers)), function(ok, response, message) {
      if (!ok) return
      for (var cameraIndex = 0; cameraIndex < root.channels.length; cameraIndex += 1) {
        var channel = root.channels[cameraIndex].channel
        root.service.updateCamera(Model.cameraId(host.id, channel), {
          presets: Capabilities.presets(response, channel, cameraIndex)
        })
      }
    })
  }

  function changeZoom(camera, direction) {
    sendControl("zoom-state", Commands.zoomState(camera.channel), function(ok, response) {
      if (!ok) return
      var currentPosition = Capabilities.zoomPosition(response, camera.channel)
      if (currentPosition < 0) {
        root.service.lastError = "Camera returned an invalid zoom position."
        return
      }
      var targetPosition = Math.max(0, Math.min(255,
        currentPosition + (direction > 0 ? 1 : -1)))
      if (targetPosition === currentPosition) return
      root.sendControl("zoom", Commands.zoom(camera.channel, targetPosition), null,
        "zoom:" + camera.channel, false)
    }, "zoom-state:" + camera.channel, false)
  }

  function setSpotlight(camera, enabled) {
    sendControl(enabled ? "spotlight-on" : "spotlight-off",
      Commands.spotlight(camera.channel, enabled), null,
      "spotlight:" + camera.channel, !enabled)
  }

  function setSiren(camera, enabled) {
    sendControl(enabled ? "siren-on" : "siren-off",
      Commands.siren(camera.channel, enabled), null,
      "siren:" + camera.channel, !enabled)
  }

  function searchRecordings(camera) {
    if (!ready || !token) return
    var range = Time.todayRange(new Date())
    enqueue("recordings", Commands.apiEnvelope(host, token,
      Commands.recordingSearch(camera.channel, range.start, range.end)), function(ok, response, message) {
      if (!ok) { root.service.lastError = message; return }
      root.service.recordings = Model.parseRecordings(response, host.id, camera.channel)
    })
  }

  function openEventRecording(event) {
    if (!event || event.hostId !== host.id) {
      service.notice = ""
      service.lastError = "The selected event does not belong to this camera host."
      return
    }
    if (!ready || !token) {
      service.notice = ""
      service.lastError = "The event camera is not ready for recording playback."
      return
    }
    if (playerProcess.running) {
      service.notice = ""
      service.lastError = "Close the current camera player before opening another event."
      return
    }
    var range = Time.aroundRange(Number(event.timestamp), 300, 300)
    enqueue("event-recording", Commands.apiEnvelope(host, token,
      Commands.recordingSearch(Number(event.channel), range.start, range.end)), function(ok, response, message) {
      root.service.notice = ""
      if (!ok) { root.service.lastError = message; return }
      var matches = Model.parseRecordings(response, host.id, Number(event.channel))
      var recording = Model.recordingForEvent(matches, event, 300000)
      if (!recording) {
        root.service.lastError = "No playable recording was found near this event."
        return
      }
      root.playRecording(recording)
    }, true, "event-recording:" + Number(event.channel), false)
  }

  function playRecording(recording) {
    if (!recording || !recording.playbackPath || String(recording.playbackPath).charAt(0) !== "/") {
      service.lastError = "This recording does not provide a playable local media path."
      return false
    }
    if (playerProcess.running || !token) {
      service.lastError = playerProcess.running
        ? "Close the current camera player before opening another recording."
        : "The camera session is not ready for recording playback."
      return false
    }
    playerProcess.input = JSON.stringify({
      kind: "recording", hostId: host.id, address: host.address,
      transport: host.transport, tlsMode: host.tlsMode, port: host.port, token: token,
      playbackPath: String(recording.playbackPath)
    })
    playerProcess.running = true
    return true
  }

  Component.onCompleted: Qt.callLater(login)
  Component.onDestruction: {
    eventTimer.stop()
    statusTimer.stop()
    retryTimer.stop()
    ptzMinimumTimer.stop()
    ptzStartedAt = 0
    if (ptzProcess.running) {
      ptzProcess.canceledSafely = true
      ptzProcess.running = false
    }
    ptzChannel = -1
    httpProcess.running = false
    playerProcess.running = false
    token = ""
  }

  Process {
    id: httpProcess
    command: ["/usr/bin/bash", root.helperPath]
    stdinEnabled: true
    stdout: StdioCollector { id: httpOutput; waitForEnd: true }
    onStarted: { write(root.activeInput + "\n"); root.activeInput = "" }
    onExited: function(exitCode, exitStatus) {
      var request = root.activeRequest
      root.activeRequest = null
      var response = null
      try { response = JSON.parse(String(httpOutput.text || "")) } catch (error) {}
      var ok = exitStatus === 0 && exitCode === 0 && response !== null
      var message = ok ? "" : response && response.error
        ? String(response.error.message) : "Camera request failed."
      if (request && request.callback) request.callback(ok, response, message)
      Qt.callLater(root.drain)
    }
  }

  Process {
    id: playerProcess
    property string input: ""
    command: ["/usr/bin/bash", root.playerPath]
    stdinEnabled: true
    stdout: StdioCollector { id: playerOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      if (exitStatus === 0 && exitCode === 0) return
      var response = null
      try { response = JSON.parse(String(playerOutput.text || "")) } catch (error) {}
      root.service.lastError = response && response.error
        ? String(response.error.message) : "Could not play recording."
    }
  }

  Process {
    id: ptzProcess
    property string input: ""
    property bool canceledSafely: false
    command: ["/usr/bin/bash", root.helperPath]
    stdinEnabled: true
    stdout: StdioCollector { id: ptzOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      root.ptzChannel = -1
      if (canceledSafely) { canceledSafely = false; return }
      if (exitStatus === 0 && exitCode === 0) return
      var parsed = null
      try { parsed = JSON.parse(String(ptzOutput.text || "")) } catch (error) {}
      root.service.lastError = parsed && parsed.error
        ? String(parsed.error.message) : "PTZ safety operation failed."
    }
  }

  Process {
    id: ptzStopProcess
    property string input: ""
    command: ["/usr/bin/bash", root.helperPath]
    stdinEnabled: true
    stdout: StdioCollector { id: ptzStopOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      if (exitStatus === 0 && exitCode === 0) return
      var parsed = null
      try { parsed = JSON.parse(String(ptzStopOutput.text || "")) } catch (error) {}
      root.service.lastError = parsed && parsed.error
        ? String(parsed.error.message) : "Could not stop PTZ movement."
    }
  }

  Timer { id: eventTimer; interval: 2500; repeat: true; onTriggered: root.requestEvents() }
  Timer { id: statusTimer; interval: 30000; repeat: true; onTriggered: root.bootstrap() }
  Timer {
    id: snapshotTimer
    interval: 5000
    repeat: true
    running: root.service.previewActive && root.ready
    onTriggered: root.refreshSelectedSnapshot()
  }
  Timer { id: retryTimer; repeat: false; onTriggered: root.login() }
  Timer {
    id: ptzMinimumTimer
    repeat: false
    onTriggered: root.finishPtzStop(root.ptzChannel)
  }
}
