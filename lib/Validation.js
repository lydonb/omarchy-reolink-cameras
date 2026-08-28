.pragma library

function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

function hasControlCharacters(value) {
  return /[\u0000-\u001f\u007f]/.test(text(value))
}

function validAddress(value) {
  var address = text(value).trim()
  if (address.length < 1 || address.length > 253 || hasControlCharacters(address)) return false
  if (!/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(address)) return false
  if (address.indexOf("..") !== -1 || address.indexOf(".-") !== -1 || address.indexOf("-.") !== -1) return false
  return address.indexOf("://") === -1 && address.indexOf("/") === -1
    && address.indexOf("?") === -1 && address.indexOf("#") === -1
    && address.indexOf("@") === -1
}

function validUsername(value) {
  var username = text(value)
  return username.length >= 1 && username.length <= 64
    && /^[A-Za-z0-9._@+-]+$/.test(username)
}

function port(value, fallback) {
  var parsed = Number(value === undefined || value === null || value === "" ? fallback : value)
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 65535 ? parsed : 0
}

function cleanDisplayName(value, fallback) {
  var result = text(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
  if (result.length > 80) result = result.substring(0, 80)
  return result || fallback
}

function fnv1a(value) {
  var hash = 0x811c9dc5
  for (var index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return ("00000000" + hash.toString(16)).slice(-8)
}

function stableHostId(endpoint) {
  var material = [endpoint.transport, endpoint.address.toLowerCase(), endpoint.port, endpoint.username].join("|")
  return "host_" + fnv1a(material)
}

function validateEndpoint(input) {
  var details = input || ({})
  var transport = text(details.transport || "https").toLowerCase()
  var tlsMode = text(details.tlsMode || "verify").toLowerCase()
  var address = text(details.address).trim()
  var username = text(details.username).trim()
  var endpointPort = port(details.port, transport === "https" ? 443 : 80)
  var rtspPort = port(details.rtspPort, 554)

  if (!validAddress(address)) return { ok: false, error: "Enter a bare camera IP address or hostname without a URL path." }
  if (transport !== "https" && transport !== "http") return { ok: false, error: "Transport must be HTTPS or HTTP." }
  if (tlsMode !== "verify" && tlsMode !== "insecure") return { ok: false, error: "TLS mode must verify certificates or be explicitly insecure." }
  if (!endpointPort || !rtspPort) return { ok: false, error: "Ports must be between 1 and 65535." }
  if (!validUsername(username)) return { ok: false, error: "Enter a valid local Reolink username." }

  var value = {
    address: address,
    port: endpointPort,
    rtspPort: rtspPort,
    transport: transport,
    tlsMode: tlsMode,
    username: username,
    displayName: cleanDisplayName(details.displayName, address)
  }
  value.id = stableHostId(value)
  return { ok: true, value: value }
}

function savedFieldDuplicatesSecret(input, secret) {
  var value = text(secret)
  if (!value) return false
  var details = input || ({})
  return value === text(details.address).trim()
    || value === text(details.username).trim()
    || value === text(details.displayName).trim()
}

function configHasForbiddenSecretKey(value) {
  if (value === null || value === undefined) return false
  if (Array.isArray(value)) {
    for (var arrayIndex = 0; arrayIndex < value.length; arrayIndex += 1)
      if (configHasForbiddenSecretKey(value[arrayIndex])) return true
    return false
  }
  if (typeof value !== "object") return false
  for (var key in value) {
    if (/password|token|secret|mediaurl/i.test(key)) return true
    if (configHasForbiddenSecretKey(value[key])) return true
  }
  return false
}
