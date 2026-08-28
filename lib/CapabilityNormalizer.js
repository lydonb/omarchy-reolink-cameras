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

function safeText(value, fallback, limit) {
  var text = String(value === undefined || value === null ? fallback || "" : value)
    .replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (!text) text = String(fallback || "").replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  return text.substring(0, Number(limit || 80))
}

function findKey(value, pattern) {
  if (!value || typeof value !== "object") return false
  var stack = [{ value: value, depth: 0 }]
  var visited = 0
  while (stack.length && visited < 4096) {
    var entry = stack.pop()
    var current = entry.value
    if (!current || typeof current !== "object") continue
    for (var key in current) {
      visited += 1
      if (visited > 4096) return false
      var child = current[key]
      if (pattern.test(String(key)) && supported(child)) return true
      if (child && typeof child === "object" && entry.depth < 16)
        stack.push({ value: child, depth: entry.depth + 1 })
    }
  }
  return false
}

function containsText(value, pattern) {
  if (!value || typeof value !== "object") return false
  var stack = [{ value: value, depth: 0 }]
  var visited = 0
  while (stack.length && visited < 4096) {
    var entry = stack.pop()
    var current = entry.value
    if (!current || typeof current !== "object") continue
    for (var key in current) {
      visited += 1
      if (visited > 4096) return false
      var child = current[key]
      if (pattern.test(String(key))
          || (child !== null && typeof child !== "object" && pattern.test(String(child)))) return true
      if (child && typeof child === "object" && entry.depth < 16)
        stack.push({ value: child, depth: entry.depth + 1 })
    }
  }
  return false
}

function channels(response, fallbackName) {
  var channelResult = resultFor(response, "GetChannelstatus")
  var statuses = channelResult && channelResult.code === 0 && channelResult.value
    && Array.isArray(channelResult.value.status) ? channelResult.value.status : []
  var result = []
  var seen = ({})
  for (var index = 0; index < statuses.length && result.length < 64; index += 1) {
    var status = statuses[index] || ({})
    var channelNumber = Number(status.channel === undefined ? index : status.channel)
    if (!Number.isInteger(channelNumber) || channelNumber < 0 || channelNumber > 63
        || seen[String(channelNumber)]) continue
    seen[String(channelNumber)] = true
    result.push({
      channel: channelNumber,
      streamChannel: channelNumber,
      name: safeText(status.name, fallbackName || ("Camera " + (index + 1)), 80),
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
  var hasSubStream = containsText(encoding, /sub/i)
  var hasMainStream = containsText(encoding, /main/i)
  var hasH265 = containsText(encoding, /h265/i)

  return {
    stream: {
      fluent: encResult ? encResult.code === 0 && hasSubStream : false,
      clear: encResult ? encResult.code === 0 && hasMainStream : false,
      clearCodec: hasH265 ? "h265" : "h264",
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
    model: safeText(info.model || info.type, "Reolink device", 80),
    firmware: safeText(info.firmVer || info.firmware, "", 80),
    name: safeText(info.name || info.deviceName, "", 80)
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
