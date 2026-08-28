.pragma library

function insert(queue, request, priority, limit) {
  var values = Array.isArray(queue) ? queue.slice() : []
  request.priority = priority === true

  // Only the newest requested state for a physical actuator is useful. This
  // prevents stale siren/spotlight/zoom work from accumulating behind polling.
  if (request.coalesceKey) {
    var coalesced = []
    for (var candidateIndex = 0; candidateIndex < values.length; candidateIndex += 1)
      if (values[candidateIndex].coalesceKey !== request.coalesceKey)
        coalesced.push(values[candidateIndex])
    values = coalesced
  }

  if (request.safetyOff === true) {
    values.unshift(request)
  } else if (request.priority) {
    var insertionIndex = 0
    while (insertionIndex < values.length
        && (values[insertionIndex].safetyOff === true || values[insertionIndex].priority === true))
      insertionIndex += 1
    values.splice(insertionIndex, 0, request)
  } else {
    values.push(request)
  }

  var maximum = Number(limit || 32)
  while (values.length > maximum) {
    var discardIndex = -1
    if (request.priority) {
      for (var index = values.length - 1; index >= 0; index -= 1) {
        if (values[index].safetyOff !== true && values[index].priority !== true) {
          discardIndex = index
          break
        }
      }
    }
    if (discardIndex < 0) {
      for (var fallbackIndex = values.length - 1; fallbackIndex >= 0; fallbackIndex -= 1) {
        if (values[fallbackIndex].safetyOff !== true) {
          discardIndex = fallbackIndex
          break
        }
      }
    }
    // Safety-off has a bounded key space (siren/spotlight per channel) and is
    // never evicted. It may temporarily exceed the ordinary work queue cap.
    if (discardIndex < 0) break
    values.splice(discardIndex, 1)
  }
  return values
}
