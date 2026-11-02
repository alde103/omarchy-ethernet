.pragma library

// Pure parsing and formatting for the Ethernet widget. Every function takes
// the raw text printed by the `ethernet` helper script and returns plain data,
// so the panel never parses nmcli output itself.

// "enp4s0:connected" -> { device: "enp4s0", state: "connected" }
function parseState(raw) {
  var line = String(raw || "").trim()
  var cut = line.lastIndexOf(":")
  if (cut < 0) return { device: "", state: "none" }
  return { device: line.slice(0, cut), state: line.slice(cut + 1) || "none" }
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

// uuid, active, method, addresses, gateway, dns, name (tab separated)
function parseProfiles(raw) {
  var profiles = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f.length < 7 || !f[0]) continue
    profiles.push({
      uuid: f[0],
      active: f[1] === "yes",
      method: f[2],
      addresses: f[3],
      gateway: f[4],
      dns: f[5],
      name: f.slice(6).join("\t")
    })
  }
  profiles.sort(function(a, b) {
    if (a.active !== b.active) return a.active ? -1 : 1
    return a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
  })
  return profiles
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
