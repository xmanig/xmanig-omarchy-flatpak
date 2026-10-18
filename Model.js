function urlToPath(url) {
  var value = String(url)
  if (value.indexOf("file://") === 0) value = value.substring(7)
  return decodeURIComponent(value)
}

function safeId(value) {
  var id = String(value || "").trim()
  return /^[A-Za-z0-9_.-]+$/.test(id) ? id : ""
}

function text(value) {
  return String(value || "").replace(/[\t\r\n]+/g, " ").trim()
}

function parseJson(textValue) {
  try {
    var value = JSON.parse(String(textValue || ""))
    return Array.isArray(value) ? value : []
  } catch (error) {
    return []
  }
}

function installedApps(textValue) {
  var apps = []
  var values = parseJson(textValue)
  for (var i = 0; i < values.length; i++) {
    var value = values[i]
    var id = safeId(value.application_id)
    if (id === "") continue
    apps.push({
      id: id,
      name: text(value.name) || id,
      version: text(value.version),
      branch: text(value.branch),
      origin: text(value.origin),
      installation: text(value.installation)
    })
  }
  apps.sort(compareApps)
  return apps
}

function searchApps(textValue) {
  var values = parseJson(textValue)
  var byId = {}
  for (var i = 0; i < values.length; i++) {
    var value = values[i]
    var id = safeId(value.application_id)
    var remotes = text(value.remotes).toLocaleLowerCase()
    if (id === "" || remotes.indexOf("flathub") < 0) continue

    var app = {
      id: id,
      name: text(value.name) || id,
      description: text(value.description),
      version: text(value.version),
      branch: text(value.branch),
      remotes: text(value.remotes)
    }
    if (!byId[id] || (app.branch === "stable" && byId[id].branch !== "stable")) byId[id] = app
  }

  var apps = []
  for (var key in byId) apps.push(byId[key])
  apps.sort(compareApps)
  return apps
}

function compareApps(a, b) {
  var byName = a.name.toLocaleLowerCase().localeCompare(b.name.toLocaleLowerCase())
  if (byName !== 0) return byName
  return a.id.localeCompare(b.id)
}

function containsApp(apps, id) {
  for (var i = 0; i < apps.length; i++) {
    if (apps[i].id === id) return true
  }
  return false
}
