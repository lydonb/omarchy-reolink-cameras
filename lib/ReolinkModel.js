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

function parseRecordings(response, hostId, channel) {
  var rows = Array.isArray(response) ? response : []
  var recordings = []
  for (var index = 0; index < rows.length; index += 1) {
    var value = rows[index] && rows[index].code === 0 ? rows[index].value : null
    var files = value && value.SearchResult && Array.isArray(value.SearchResult.File)
      ? value.SearchResult.File : value && Array.isArray(value.files) ? value.files : []
    for (var fileIndex = 0; fileIndex < files.length && recordings.length < 200; fileIndex += 1) {
      var file = files[fileIndex] || ({})
      recordings.push({
        id: hostId + ":" + channel + ":" + fileIndex + ":" + String(file.name || file.filename || ""),
        hostId: hostId,
        channel: Number(channel),
        name: String(file.name || file.filename || "Recording"),
        start: file.StartTime || file.start || null,
        end: file.EndTime || file.end || null,
        type: String(file.type || file.event || "recording"),
        playbackPath: String(file.Playback || file.playback || file.path || "")
      })
    }
  }
  return recordings
}
