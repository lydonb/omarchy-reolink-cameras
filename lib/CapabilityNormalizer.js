.pragma library

function items(response) {
  return Array.isArray(response) ? response : []
}

function resultFor(response, commandName) {
  var values = items(response)
  for (var index = 0; index < values.length; index += 1)
    if (values[index] && values[index].cmd === commandName) return values[index]
  return null
}

function supported(value) {
  if (value === true || value === 1 || value === "1") return true
  if (!value || typeof value !== "object") return false
  if (Number(value.permit || 0) > 0 || Number(value.ver || 0) > 0 || Number(value.support || 0) > 0) return true
  return false
}

function findKey(value, pattern) {
  if (!value || typeof value !== "object") return false
  for (var key in value) {
    if (pattern.test(key) && supported(value[key])) return true
    if (findKey(value[key], pattern)) return true
  }
  return false
}

function channels(response, fallbackName) {
  var channelResult = resultFor(response, "GetChannelstatus")
  var statuses = channelResult && channelResult.code === 0 && channelResult.value
    && Array.isArray(channelResult.value.status) ? channelResult.value.status : []
  var result = []
  for (var index = 0; index < statuses.length; index += 1) {
    var status = statuses[index] || ({})
    result.push({
      channel: Number(status.channel === undefined ? index : status.channel),
      streamChannel: Number(status.channel === undefined ? index : status.channel),
      name: String(status.name || fallbackName || ("Camera " + (index + 1))),
      online: status.online === undefined ? true : Number(status.online) !== 0,
      sleep: Number(status.sleep || 0) !== 0
    })
  }
  if (!result.length) result.push({ channel: 0, streamChannel: 0, name: fallbackName || "Camera", online: true, sleep: false })
  return result
}

function normalize(response) {
  var abilityResult = resultFor(response, "GetAbility")
  var abilities = abilityResult && abilityResult.code === 0 ? (abilityResult.value || ({})) : ({})
  var encResult = resultFor(response, "GetEnc")
  var encoding = encResult && encResult.code === 0 ? (encResult.value || ({})) : ({})
  var netResult = resultFor(response, "GetNetPort")
  var ports = netResult && netResult.code === 0 ? (netResult.value || ({})) : ({})
  var encText = JSON.stringify(encoding).toLowerCase()

  return {
    stream: {
      fluent: encResult ? encResult.code === 0 && encText.indexOf("sub") !== -1 : false,
      clear: encResult ? encResult.code === 0 && encText.indexOf("main") !== -1 : false,
      clearCodec: encText.indexOf("h265") !== -1 ? "h265" : "h264",
      rtspEnabled: !!(netResult && netResult.code === 0 && ports.NetPort
        && ports.NetPort.rtspPort && Number(ports.NetPort.rtspPort.enable || 0) !== 0)
    },
    snapshot: true,
    recordings: findKey(abilities, /search|playback|download/i),
    events: {
      motion: findKey(abilities, /md|motion/i),
      person: findKey(abilities, /people|person/i),
      vehicle: findKey(abilities, /vehicle/i),
      visitor: findKey(abilities, /visitor|doorbell/i),
      package: findKey(abilities, /package/i),
      pet: findKey(abilities, /dog_cat|pet|animal/i)
    },
    ptz: {
      enabled: findKey(abilities, /ptz/i),
      presets: findKey(abilities, /preset/i),
      zoom: findKey(abilities, /zoom|focus/i)
    },
    spotlight: findKey(abilities, /whiteled|floodlight|spotlight/i),
    siren: findKey(abilities, /audioalarm|siren/i)
  }
}

function deviceInfo(response) {
  var result = resultFor(response, "GetDevInfo")
  var value = result && result.code === 0 ? (result.value || ({})) : ({})
  var info = value.DevInfo || value
  return {
    model: String(info.model || info.type || "Reolink device"),
    firmware: String(info.firmVer || info.firmware || ""),
    name: String(info.name || info.deviceName || "")
  }
}

function presets(response, channel, fallbackIndex) {
  var rows = items(response)
  var candidates = []
  for (var index = 0; index < rows.length; index += 1)
    if (rows[index] && rows[index].cmd === "GetPtzPreset")
      candidates.push(rows[index])
  var row = null
  for (var candidateIndex = 0; candidateIndex < candidates.length; candidateIndex += 1) {
    var candidateValue = candidates[candidateIndex].value || ({})
    if (Number(candidateValue.channel) === Number(channel)) { row = candidates[candidateIndex]; break }
  }
  if (!row && candidates.length > Number(fallbackIndex || 0)) row = candidates[Number(fallbackIndex || 0)]
  if (!row || row.code !== 0) return []
  var value = row ? (row.value || ({})) : ({})
  var source = Array.isArray(value.PtzPreset) ? value.PtzPreset
    : Array.isArray(value.Preset) ? value.Preset
    : Array.isArray(value.presets) ? value.presets : []
  var result = []
  for (var presetIndex = 0; presetIndex < source.length && result.length < 32; presetIndex += 1) {
    var preset = source[presetIndex] || ({})
    if (preset.enable !== undefined && Number(preset.enable) === 0) continue
    var presetId = Number(preset.id === undefined ? presetIndex : preset.id)
    if (!Number.isInteger(presetId) || presetId < 0 || presetId > 255) continue
    result.push({ id: presetId, name: String(preset.name || ("Preset " + presetId)).substring(0, 64) })
  }
  return result
}
