.pragma library

// Pure parsing and formatting for the Ethernet widget. Every function takes
// the raw text printed by the `ethernet` helper script and returns plain data,
// so the panel never parses nmcli output itself.

// "enp4s0:connected:pci" lines -> [{ device, state, bus, label }]
function parseDevices(raw) {
  var devices = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].trim().split(":")
    if (f.length < 3 || !f[0]) continue
    devices.push({ device: f[0], state: f[1] || "none", bus: f[2] })
  }

  // "Built-in" / "USB" reads better than enp0s20f0u1, unless two ports share a bus.
  for (var j = 0; j < devices.length; j++) {
    var d = devices[j]
    var sameBus = devices.filter(function(o) { return o.bus === d.bus }).length
    d.label = sameBus > 1 ? d.device : busLabel(d.bus, d.device)
  }
  return devices
}

function busLabel(bus, device) {
  if (bus === "usb") return "USB"
  if (bus === "pci") return "Built-in"
  return device
}

// The port the panel opens on: the one in use, then one with a cable, then any.
function preferredDevice(devices) {
  for (var i = 0; i < devices.length; i++) if (devices[i].state === "connected") return devices[i].device
  for (var j = 0; j < devices.length; j++) if (cablePresent(devices[j].state)) return devices[j].device
  return devices.length > 0 ? devices[0].device : ""
}

function findDevice(devices, name) {
  for (var i = 0; i < devices.length; i++) if (devices[i].device === name) return devices[i]
  return null
}

// key=value lines -> object
function parseStatus(raw) {
  var status = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var cut = lines[i].indexOf("=")
    if (cut <= 0) continue
    status[lines[i].slice(0, cut)] = lines[i].slice(cut + 1)
  }
  if (!status.state) status.state = "none"
  return status
}

// uuid, device (empty while inactive), method, addresses, gateway, dns, name (tab separated)
function parseProfiles(raw) {
  var profiles = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f.length < 7 || !f[0]) continue
    profiles.push({
      uuid: f[0],
      device: f[1],
      method: f[2],
      addresses: f[3],
      gateway: f[4],
      dns: f[5],
      name: f.slice(6).join("\t")
    })
  }
  return profiles
}

// The profile up on `device` first, then profiles up on other ports, then by name.
function sortProfiles(profiles, device) {
  function rank(p) { return p.device === device && device ? 0 : p.device ? 1 : 2 }
  return profiles.slice().sort(function(a, b) {
    if (rank(a) !== rank(b)) return rank(a) - rank(b)
    return a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
  })
}

function filterProfiles(profiles, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return profiles
  return profiles.filter(function(p) {
    return p.name.toLowerCase().indexOf(q) >= 0 || p.addresses.indexOf(q) >= 0
  })
}

// Cable plugged in, whether or not a profile is up on it.
function cablePresent(state) {
  return state === "connected" || state === "connecting" || state === "disconnected" || state === "disconnecting"
}

function methodSummary(profile) {
  if (!profile) return ""
  if (profile.method === "auto") return "DHCP"
  if (profile.method === "manual") return profile.addresses.split(",")[0] || "Static"
  return profile.method
}

function statusLine(status) {
  switch (status.state) {
  case "connected": return status.speed ? "Connected · " + speedLabel(status.speed) : "Connected"
  case "connecting": return "Connecting"
  case "disconnecting": return "Disconnecting"
  case "disconnected": return "Cable in · no profile up"
  case "unavailable": return "No cable"
  default: return "No Ethernet device"
  }
}

function speedLabel(mbps) {
  var n = parseInt(mbps, 10)
  if (!(n > 0)) return ""
  return n >= 1000 ? (n / 1000) + " Gb/s" : n + " Mb/s"
}

// "10.0.0.5/24, 10.0.0.6/24" -> "10.0.0.5"
function primaryAddress(addresses) {
  return String(addresses || "").split(",")[0].split("/")[0].trim()
}

function fileUrlToPath(url) {
  return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
}
