.pragma library

function pad(value) { return String(value).padStart(2, "0") }

function cgiTime(dateValue) {
  var date = dateValue instanceof Date ? dateValue : new Date(dateValue)
  return {
    year: date.getFullYear(), mon: date.getMonth() + 1, day: date.getDate(),
    hour: date.getHours(), min: date.getMinutes(), sec: date.getSeconds()
  }
}

function todayRange(nowValue) {
  var now = nowValue instanceof Date ? nowValue : new Date(nowValue || Date.now())
  var start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0)
  var end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59)
  return { start: cgiTime(start), end: cgiTime(end) }
}

function aroundRange(timestamp, beforeSeconds, afterSeconds) {
  var center = Number(timestamp || Date.now())
  var before = Math.max(0, Math.min(3600, Number(beforeSeconds || 120))) * 1000
  var after = Math.max(0, Math.min(3600, Number(afterSeconds || 120))) * 1000
  return {
    start: cgiTime(new Date(center - before)),
    end: cgiTime(new Date(center + after))
  }
}

function relative(timestamp, nowValue) {
  var delta = Math.max(0, Number(nowValue || Date.now()) - Number(timestamp || 0))
  if (delta < 10000) return "just now"
  if (delta < 60000) return Math.floor(delta / 1000) + "s ago"
  if (delta < 3600000) return Math.floor(delta / 60000) + "m ago"
  if (delta < 86400000) return Math.floor(delta / 3600000) + "h ago"
  return Math.floor(delta / 86400000) + "d ago"
}

function clock(timestamp) {
  var date = new Date(Number(timestamp || Date.now()))
  return Qt.formatTime(date, "h:mm AP")
}
