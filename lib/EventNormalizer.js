.pragma library

var knownTypes = ["motion", "person", "vehicle", "visitor", "package", "pet", "bicycle", "crying", "crossline", "intrusion", "linger", "tamper"]

function alarmState(value) {
  if (value === true || value === 1 || value === "1") return true
  if (!value || typeof value !== "object") return false
  return Number(value.alarm_state || value.alarmState || value.state || 0) !== 0
}

function canonicalType(key) {
  var value = String(key || "").toLowerCase()
  if (/people|person/.test(value)) return "person"
  if (/vehicle/.test(value)) return "vehicle"
  if (/visitor|doorbell/.test(value)) return "visitor"
  if (/package/.test(value)) return "package"
  if (/dog_cat|pet|animal/.test(value)) return "pet"
  if (/bicycle/.test(value)) return "bicycle"
  if (/cry/.test(value)) return "crying"
  if (/cross/.test(value)) return "crossline"
  if (/intrusion/.test(value)) return "intrusion"
  if (/linger/.test(value)) return "linger"
  if (/tamper/.test(value)) return "tamper"
  if (/md|motion/.test(value)) return "motion"
  return ""
}

function collect(value, output) {
  if (!value || typeof value !== "object") return
  for (var key in value) {
    var type = canonicalType(key)
    if (type && alarmState(value[key])) output[type] = true
    if (typeof value[key] === "object") collect(value[key], output)
  }
}

function activeStates(response, hostId) {
  var result = []
  var rows = Array.isArray(response) ? response : []
  for (var index = 0; index < rows.length; index += 1) {
    var row = rows[index] || ({})
    if (row.code !== 0 || ["GetEvents", "GetAiState", "GetMdState"].indexOf(row.cmd) === -1) continue
    var value = row.value || ({})
    var channel = Number(value.channel === undefined && row.param ? row.param.channel : value.channel || 0)
    var detected = ({})
    collect(value, detected)
    for (var type in detected) if (detected[type]) result.push({
      key: hostId + ":" + channel + ":" + type,
      hostId: hostId,
      channel: channel,
      type: type
    })
  }
  return result
}

function risingEdges(previousState, active, nowMs, cooldownMs) {
  var previous = previousState || ({})
  var next = ({})
  var events = []
  var now = Number(nowMs || Date.now())
  var cooldown = Math.max(0, Number(cooldownMs || 10000))

  for (var index = 0; index < active.length; index += 1) {
    var state = active[index]
    var old = previous[state.key] || ({ active: false, lastEventAt: 0 })
    var lastEventAt = Number(old.lastEventAt || 0)
    if (!old.active && now - lastEventAt >= cooldown) {
      var event = ({})
      for (var key in state) event[key] = state[key]
      event.id = state.key + ":" + now
      event.timestamp = now
      event.viewed = false
      events.push(event)
      lastEventAt = now
    }
    next[state.key] = { active: true, lastEventAt: lastEventAt }
  }

  for (var oldKey in previous) if (!next[oldKey])
    next[oldKey] = { active: false, lastEventAt: Number(previous[oldKey].lastEventAt || 0) }
  return { state: next, events: events }
}

function label(type) {
  var value = String(type || "motion")
  return value.charAt(0).toUpperCase() + value.slice(1)
}

function notification(type) {
  var canonical = canonicalType(type) || "motion"
  return {
    headline: label(canonical) + " detected",
    body: "Open Reolink Cameras",
    clickPayload: "{}"
  }
}
