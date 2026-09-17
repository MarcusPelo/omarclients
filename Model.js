// Pure data rules for the clients list — filtering, monitor mapping, and
// generic raw-field formatting for the details view.

function buildMonitorMap(monitorsArr) {
  var map = {}
  if (Array.isArray(monitorsArr)) {
    for (var i = 0; i < monitorsArr.length; i++) {
      var m = monitorsArr[i]
      if (m && m.id !== undefined)
        map[String(m.id)] = String(m.name || ("Monitor " + m.id))
    }
  }
  return map
}

function normalizeClients(clientsArr, monitorMap) {
  var out = []
  if (!Array.isArray(clientsArr)) return out
  for (var i = 0; i < clientsArr.length; i++) {
    var c = clientsArr[i] || {}
    var monId = c.monitor !== undefined ? String(c.monitor) : ""
    var ws = c.workspace || {}
    out.push({
      raw: c,
      address: String(c.address || ""),
      title: String(c.title || ""),
      class: String(c.class || ""),
      visible: c.visible === true || c.visible === 1,
      floating: c.floating === true || c.floating === 1,
      fullscreen: c.fullscreen === true || (typeof c.fullscreen === "number" && c.fullscreen !== 0),
      pinned: c.pinned === true || c.pinned === 1,
      monitorId: monId,
      monitorName: monitorMap[monId] || (monId !== "" ? ("Monitor " + monId) : "Unknown"),
      workspaceLabel: (ws.name || ws.id !== undefined) ? String(ws.name || ws.id) : ""
    })
  }
  return out
}

function buildMonitorOptions(clients) {
  var opts = ["All"]
  var seen = {}
  for (var i = 0; i < clients.length; i++) {
    var name = clients[i].monitorName
    if (name && !seen[name]) { seen[name] = true; opts.push(name) }
  }
  return opts
}

function filterClients(clients, searchText, visibleFilter, monitorFilter) {
  var q = String(searchText || "").trim().toLowerCase()
  return clients.filter(function(c) {
    if (visibleFilter === "visible" && !c.visible) return false
    if (visibleFilter === "hidden" && c.visible) return false
    if (monitorFilter && monitorFilter !== "All" && c.monitorName !== monitorFilter) return false
    if (q === "") return true
    return c.title.toLowerCase().indexOf(q) >= 0
      || c.class.toLowerCase().indexOf(q) >= 0
      || c.address.toLowerCase().indexOf(q) >= 0
      || c.workspaceLabel.toLowerCase().indexOf(q) >= 0
  })
}

function findByAddress(clients, address) {
  if (!address) return null
  for (var i = 0; i < clients.length; i++)
    if (clients[i].address === address) return clients[i]
  return null
}

var FIELD_ORDER = [
  "address", "mapped", "visible", "at", "size", "workspace", "floating",
  "monitor", "class", "title", "initialClass", "initialTitle", "pid",
  "pinned", "fullscreen", "fullscreenHandler", "grouped", "tags"
]

function formatFieldValue(key, value) {
  if (value === undefined || value === null) return ""
  if (Array.isArray(value)) {
    if (key === "at" || key === "size" || key === "tags") return value.join(", ")
    if (key === "grouped") return value.length + " grouped"
    return JSON.stringify(value)
  }
  if (typeof value === "object") {
    if (key === "workspace") return (value.name || "") + " (" + value.id + ")"
    return JSON.stringify(value)
  }
  return String(value)
}

// Enumerates every field on the raw hyprctl client object: the documented
// order first, then any unknown/future fields appended.
function rawFieldEntries(raw) {
  var entries = []
  var seen = {}
  for (var i = 0; i < FIELD_ORDER.length; i++) {
    var key = FIELD_ORDER[i]
    if (key in raw) { entries.push({ key: key, value: formatFieldValue(key, raw[key]) }); seen[key] = true }
  }
  for (var k in raw) {
    if (!seen[k]) entries.push({ key: k, value: formatFieldValue(k, raw[k]) })
  }
  return entries
}
