.pragma library

function defaultConfig() {
  return {
    version: 1,
    hosts: [],
    cleanupHostIds: [],
    preferences: { notify: { visitor: true, person: true, vehicle: true, package: true, motion: false } }
  }
}

function addCleanupHostId(values, hostId) {
  var result = []
  var source = Array.isArray(values) ? values : []
  for (var index = 0; index < source.length; index += 1)
    if (String(source[index]) !== String(hostId)) result.push(String(source[index]))
  result.push(String(hostId))
  return result
}

function removeCleanupHostId(values, hostId) {
  var result = []
  var source = Array.isArray(values) ? values : []
  for (var index = 0; index < source.length; index += 1)
    if (String(source[index]) !== String(hostId)) result.push(String(source[index]))
  return result
}

function canStoreCredential(values, hostId) {
  var source = Array.isArray(values) ? values : []
  if (source.length < 64) return true
  for (var index = 0; index < source.length; index += 1)
    if (String(source[index]) === String(hostId)) return true
  return false
}

function canBeginCredentialMutation(inProgress, values, hostId) {
  return inProgress !== true && canStoreCredential(values, hostId)
}

function loginSession(response, nowMs) {
  var row = Array.isArray(response) && response.length ? response[0] : null
  var token = row && row.code === 0 && row.value && row.value.Token ? row.value.Token : null
  if (!token || !token.name) return { ok: false, error: "Authentication failed." }
  var leaseSeconds = Math.max(60, Number(token.leaseTime || 3600))
  return {
    ok: true,
    token: String(token.name),
    expiresAt: Number(nowMs || Date.now()) + leaseSeconds * 1000
  }
}

function loginProcessResult(response, nowMs, processOk) {
  if (processOk === true) return loginSession(response, nowMs)
  var message = response && response.error && response.error.message
    ? String(response.error.message) : "Camera test failed."
  return { ok: false, error: message }
}

function cameraId(hostId, channel) {
  return "cam_" + String(hostId).substring(5) + "_" + Number(channel)
}

function logicalCameras(host, channels, capabilities, deviceInfo) {
  var result = []
  for (var index = 0; index < channels.length; index += 1) {
    var channel = channels[index]
    result.push({
      id: cameraId(host.id, channel.channel),
      hostId: host.id,
      channel: Number(channel.channel),
      streamChannel: Number(channel.streamChannel),
      name: String(channel.name || host.displayName),
      online: channel.online !== false,
      sleeping: channel.sleep === true,
      model: deviceInfo.model,
      firmware: deviceInfo.firmware,
      capabilities: capabilities,
      presets: [],
      snapshotPath: "",
      snapshotUpdatedAt: 0
    })
  }
  return result
}

function replaceHostCameras(cameras, hostId, replacements) {
  var result = []
  var values = Array.isArray(cameras) ? cameras : []
  for (var index = 0; index < values.length; index += 1)
    if (values[index].hostId !== hostId) result.push(values[index])
  for (var replacementIndex = 0; replacementIndex < replacements.length; replacementIndex += 1)
    result.push(replacements[replacementIndex])
  return result
}

function updateCamera(cameras, cameraIdValue, patch) {
  var result = []
  for (var index = 0; index < cameras.length; index += 1) {
    var camera = cameras[index]
    if (camera.id !== cameraIdValue) { result.push(camera); continue }
    var next = ({})
    for (var key in camera) next[key] = camera[key]
    for (var patchKey in patch) next[patchKey] = patch[patchKey]
    result.push(next)
  }
  return result
}

function markHostOffline(cameras, hostId) {
  var result = []
  var values = Array.isArray(cameras) ? cameras : []
  for (var index = 0; index < values.length; index += 1) {
    var camera = values[index]
    if (camera.hostId !== hostId) { result.push(camera); continue }
    var copy = ({})
    for (var key in camera) copy[key] = camera[key]
    copy.online = false
    result.push(copy)
  }
  return result
}

function safeRecordingLabel(value, fallback, limit) {
  var text = String(value === undefined || value === null ? fallback || "" : value)
    .replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  return text.substring(0, Number(limit || 256)) || String(fallback || "Recording")
}

function safePlaybackPath(value) {
  var path = String(value || "")
  if (path.length < 1 || path.length > 4096
      || /[\u0000-\u001f\u007f]/.test(path) || path.indexOf("://") !== -1
      || path.indexOf("\\") !== -1 || path.indexOf("#") !== -1) return ""

  var absolute = path.charAt(0) === "/"
  var segments = path.split("/")
  var firstSegment = absolute ? 1 : 0
  if ((!absolute && segments.length < 2) || segments.length <= firstSegment) return ""
  for (var index = firstSegment; index < segments.length; index += 1) {
    if (!segments[index] || segments[index] === "." || segments[index] === "..") return ""
  }
  return absolute ? path : "/" + path
}

function parseRecordings(response, hostId, channel) {
  var rows = Array.isArray(response) ? response : []
  var recordings = []
  for (var index = 0; index < rows.length; index += 1) {
    var value = rows[index] && rows[index].code === 0 ? rows[index].value : null
    var files = value && value.SearchResult && Array.isArray(value.SearchResult.File)
      ? value.SearchResult.File : value && Array.isArray(value.files) ? value.files : []
    for (var fileIndex = 0; fileIndex < files.length && recordings.length < 200; fileIndex += 1) {
      var file = files[fileIndex] || ({})
      var sourceName = String(file.name || file.filename || "Recording")
      var rawName = safeRecordingLabel(sourceName, "Recording", 256)
      var explicitPath = safePlaybackPath(file.Playback || file.playback || file.path || "")
      var playbackPath = explicitPath || safePlaybackPath(sourceName)
      recordings.push({
        id: hostId + ":" + channel + ":" + fileIndex + ":" + rawName,
        hostId: hostId,
        channel: Number(channel),
        name: rawName,
        start: file.StartTime || file.start || null,
        end: file.EndTime || file.end || null,
        startMs: recordingTimestamp(file.StartTime || file.start || null),
        endMs: recordingTimestamp(file.EndTime || file.end || null),
        type: safeRecordingLabel(file.type || file.event, "recording", 64),
        playbackPath: playbackPath
      })
    }
  }
  return recordings
}

function recordingTimestamp(value) {
  if (typeof value === "number") return value < 100000000000 ? value * 1000 : value
  if (typeof value === "string") {
    var parsed = Date.parse(value)
    return isNaN(parsed) ? 0 : parsed
  }
  if (!value || typeof value !== "object") return 0
  var year = Number(value.year || 0)
  var month = Number(value.mon || value.month || 0)
  var day = Number(value.day || 0)
  if (year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) return 0
  return new Date(year, month - 1, day, Number(value.hour || 0),
    Number(value.min || value.minute || 0), Number(value.sec || value.second || 0)).getTime()
}

function recordingForEvent(recordings, event, maximumDistanceMs) {
  var values = Array.isArray(recordings) ? recordings : []
  var target = event || ({})
  var eventTime = Number(target.timestamp || 0)
  if (!eventTime) return null
  var limit = Math.max(0, Number(maximumDistanceMs || 300000))
  var best = null
  var bestDistance = Number.MAX_VALUE
  for (var index = 0; index < values.length; index += 1) {
    var recording = values[index] || ({})
    if (recording.hostId !== target.hostId || Number(recording.channel) !== Number(target.channel)
        || String(recording.playbackPath || "").charAt(0) !== "/") continue
    var start = Number(recording.startMs || recordingTimestamp(recording.start))
    var end = Number(recording.endMs || recordingTimestamp(recording.end) || start)
    if (!start) continue
    var distance = eventTime >= start && eventTime <= Math.max(start, end)
      ? 0 : Math.min(Math.abs(eventTime - start), Math.abs(eventTime - Math.max(start, end)))
    if (distance < bestDistance || (distance === bestDistance && best
        && (start < Number(best.startMs || 0)
          || (start === Number(best.startMs || 0) && String(recording.id) < String(best.id))))) {
      best = recording
      bestDistance = distance
    }
  }
  return best && bestDistance <= limit ? best : null
}
