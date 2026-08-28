.pragma library

function build(pluginId, notification) {
  var value = notification || ({})
  return [
    "omarchy", "notification", "send", "--app-name", "Reolink Cameras", "-g", "󰄀",
    String(value.headline || "Camera event"), String(value.body || "Open Reolink Cameras"),
    "--exec", "omarchy-shell", "shell", "summon", String(pluginId), "{}"
  ]
}
