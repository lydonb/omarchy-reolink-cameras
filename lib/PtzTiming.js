.pragma library

function remainingMinimum(startedAt, nowValue, minimumMs) {
  var started = Number(startedAt || 0)
  var now = Number(nowValue || 0)
  var minimum = Math.max(0, Number(minimumMs || 0))
  if (started <= 0 || now <= 0 || !isFinite(started) || !isFinite(now) || !isFinite(minimum))
    return 0
  return Math.max(0, Math.ceil(minimum - Math.max(0, now - started)))
}
