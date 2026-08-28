.pragma library

var allowedCommands = [
  "Logout", "GetDevInfo", "GetAbility", "GetChannelstatus", "GetChnTypeInfo",
  "GetNetPort", "GetEnc", "GetEvents", "GetAiState", "GetMdState", "PtzCtrl",
  "GetPtzPreset", "StartZoomFocus", "GetWhiteLed", "SetWhiteLed",
  "GetAudioAlarm", "SetAudioAlarm", "GetAudioAlarmV20", "SetAudioAlarmV20",
  "Search", "Playback", "Download", "NvrDownload"
]

function command(name, param) {
  if (allowedCommands.indexOf(String(name)) === -1) throw new Error("Command is not allowed")
  return { cmd: String(name), action: 0, param: param || ({}) }
}

function bootstrap() {
  return [
    command("GetDevInfo"),
    command("GetAbility"),
    command("GetChannelstatus"),
    command("GetNetPort"),
    command("GetEnc", { channel: 0 })
  ]
}

function eventBatch(channels) {
  var result = []
  var values = Array.isArray(channels) && channels.length ? channels : [0]
  for (var index = 0; index < values.length && index < 64; index += 1)
    result.push(command("GetEvents", { channel: Number(values[index]) }))
  return result
}

function presetBatch(channels) {
  var result = []
  var values = Array.isArray(channels) && channels.length ? channels : [0]
  for (var index = 0; index < values.length && index < 64; index += 1)
    result.push(command("GetPtzPreset", { channel: Number(values[index]) }))
  return result
}

function ptz(channel, operation, speed, preset) {
  var permitted = ["Stop", "ToPos"]
  if (permitted.indexOf(operation) === -1) throw new Error("PTZ operation is not allowed")
  var param = { channel: Number(channel), op: operation, speed: Math.max(1, Math.min(64, Number(speed || 24))) }
  if (operation === "ToPos") param.id = Math.max(0, Number(preset || 0))
  return [command("PtzCtrl", param)]
}

function zoom(channel, direction) {
  return [command("StartZoomFocus", {
    channel: Number(channel), op: direction > 0 ? "ZoomInc" : "ZoomDec", pos: 0
  })]
}

function spotlight(channel, enabled) {
  return [command("SetWhiteLed", { channel: Number(channel), WhiteLed: { state: enabled ? 1 : 0 } })]
}

function siren(channel, enabled) {
  return [command("SetAudioAlarm", { channel: Number(channel), Audio: { enable: enabled ? 1 : 0 } })]
}

function recordingSearch(channel, start, end) {
  return [command("Search", {
    Search: {
      channel: Number(channel), onlyStatus: 0, streamType: "main",
      StartTime: start, EndTime: end
    }
  })]
}

function apiEnvelope(host, token, body) {
  return {
    operation: "api", hostId: host.id, address: host.address, port: host.port,
    transport: host.transport, tlsMode: host.tlsMode, username: host.username,
    token: token, body: body
  }
}

function loginEnvelope(host) {
  return {
    operation: "login", hostId: host.id, address: host.address, port: host.port,
    transport: host.transport, tlsMode: host.tlsMode, username: host.username
  }
}

function snapshotEnvelope(host, token, channel) {
  return {
    operation: "snapshot", hostId: host.id, address: host.address, port: host.port,
    transport: host.transport, tlsMode: host.tlsMode, username: host.username,
    token: token, channel: Number(channel)
  }
}

function ptzPulseEnvelope(host, token, channel, direction, durationMs) {
  return {
    operation: "ptz-pulse", hostId: host.id, address: host.address, port: host.port,
    transport: host.transport, tlsMode: host.tlsMode, username: host.username,
    token: token, channel: Number(channel), direction: String(direction),
    durationMs: Number(durationMs)
  }
}
