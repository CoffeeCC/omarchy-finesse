.pragma library

// Pure helpers for the Finesse bar widget. No QML types in here so the logic
// can be exercised from node (see tests/model.test.mjs).

function trimSlash(value) {
  return String(value || "").trim().replace(/\/+$/, "")
}

function sanitizeApiKey(value) {
  return String(value || "").replace(/[\r\n]+/g, "").trim()
}

function withScheme(value) {
  var url = trimSlash(value)
  if (url === "") return ""
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(url)) return /^https?:\/\//i.test(url) ? url : ""
  // "javascript:", "file:" etc. without slashes. A colon followed by a digit
  // is a port ("media.lan:8096"), not a scheme.
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:(?!\d)/.test(url)) return ""
  return "https://" + url
}

function originOf(url) {
  var m = /^(https?:\/\/[^\/?#]+)/i.exec(String(url || ""))
  return m ? m[1] : ""
}

function finesseBase(settingValue) {
  return withScheme(settingValue)
}

// Jellyfin lives at the Finesse origin in the usual reverse-proxy layout
// (Finesse at /finesse, Jellyfin at /), so that's the fallback.
function jellyfinBase(jellyfinSetting, finesseSetting) {
  var explicit = withScheme(jellyfinSetting)
  if (explicit !== "") return explicit
  return originOf(finesseBase(finesseSetting))
}

// Ordered Jellyfin base URL candidates to probe. Finesse v3 bundles Jellyfin
// behind /jellyfin on the same origin, while legacy nginx setups put Jellyfin
// at the origin root. Explicit jellyfinUrl is used as-is.
function jellyfinCandidates(jellyfinSetting, finesseSetting) {
  var explicit = withScheme(jellyfinSetting)
  if (explicit !== "") return [explicit]
  var finesse = finesseBase(finesseSetting)
  var origin = originOf(finesse)
  if (origin === "") return []
  if (/\/finesse$/i.test(finesse)) return [origin + "/jellyfin", origin]
  return [origin]
}

function isConfigured(finesseSetting, jellyfinSetting, apiKey) {
  return finesseBase(finesseSetting) !== ""
    && jellyfinBase(jellyfinSetting, finesseSetting) !== ""
    && sanitizeApiKey(apiKey) !== ""
}

function playUrl(finesseSetting, itemId) {
  var base = finesseBase(finesseSetting)
  if (base === "" || !itemId) return ""
  return base + "/play/" + encodeURIComponent(itemId)
}

function itemUrl(finesseSetting, itemId) {
  var base = finesseBase(finesseSetting)
  if (base === "" || !itemId) return ""
  return base + "/item/" + encodeURIComponent(itemId)
}

function usersUrl(jfBase) {
  return jfBase + "/Users"
}

function resumeUrl(jfBase, userId, limit) {
  return jfBase + "/Users/" + encodeURIComponent(userId) + "/Items/Resume"
    + "?Limit=" + Math.max(1, Math.min(24, parseInt(limit, 10) || 6))
    + "&MediaTypes=Video"
    + "&Fields=PrimaryImageAspectRatio"
    + "&EnableImageTypes=Primary,Thumb,Backdrop"
    + "&ImageTypeLimit=1"
}

// Pick the user to show: matching name (case-insensitive), else the first
// non-disabled user. Returns "" when nothing usable came back.
function pickUserId(raw, userName) {
  var users
  try { users = JSON.parse(String(raw || "")) } catch (e) { return "" }
  if (!Array.isArray(users) || users.length === 0) return ""
  var want = String(userName || "").trim().toLowerCase()
  var i
  if (want !== "") {
    for (i = 0; i < users.length; i++) {
      if (users[i] && users[i].Id && String(users[i].Name || "").trim().toLowerCase() === want) return String(users[i].Id)
    }
    return ""
  }
  for (i = 0; i < users.length; i++) {
    var u = users[i]
    if (u && u.Id && !(u.Policy && u.Policy.IsDisabled)) return String(u.Id)
  }
  return ""
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

function episodeCode(item) {
  var s = Number(item.ParentIndexNumber)
  var e = Number(item.IndexNumber)
  if (item.ParentIndexNumber === undefined || item.ParentIndexNumber === null
      || item.IndexNumber === undefined || item.IndexNumber === null) return ""
  if (!Number.isFinite(s) || !Number.isFinite(e) || s < 0 || e < 0) return ""
  return "S" + pad2(Math.floor(s)) + "E" + pad2(Math.floor(e))
}

function formatRemaining(ticksLeft) {
  var ticks = Number(ticksLeft || 0)
  if (!Number.isFinite(ticks) || ticks <= 0) return ""
  var minutes = Math.round(ticks / 600000000)
  if (minutes <= 0) return "<1m left"
  if (minutes < 60) return minutes + "m left"
  var h = Math.floor(minutes / 60)
  var m = minutes % 60
  return h + "h" + (m > 0 ? " " + m + "m" : "") + " left"
}

function imgPath(jfBase, itemId, kind, tag) {
  return jfBase + "/Items/" + encodeURIComponent(String(itemId))
    + "/Images/" + kind + "?fillHeight=96&quality=85&tag=" + encodeURIComponent(String(tag))
}

// 16:9 art for the row thumbnail: episode still / thumb / backdrop / poster.
function thumbUrl(jfBase, item) {
  var tags = item.ImageTags || {}
  if (tags.Thumb) return imgPath(jfBase, item.Id, "Thumb", tags.Thumb)
  if (item.Type === "Episode" && tags.Primary) return imgPath(jfBase, item.Id, "Primary", tags.Primary)
  if (item.ParentThumbItemId && item.ParentThumbImageTag) return imgPath(jfBase, item.ParentThumbItemId, "Thumb", item.ParentThumbImageTag)
  if (item.BackdropImageTags && item.BackdropImageTags.length > 0) return imgPath(jfBase, item.Id, "Backdrop", item.BackdropImageTags[0])
  if (item.ParentBackdropItemId && item.ParentBackdropImageTags && item.ParentBackdropImageTags.length > 0) return imgPath(jfBase, item.ParentBackdropItemId, "Backdrop", item.ParentBackdropImageTags[0])
  if (tags.Primary) return imgPath(jfBase, item.Id, "Primary", tags.Primary)
  return ""
}

// Normalize the /Items/Resume response into flat rows the panel can bind to.
// Returns null when the payload isn't a Jellyfin item list.
function parseResume(raw, jfBase) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return null }
  var items = parsed && Array.isArray(parsed.Items) ? parsed.Items : null
  if (!items) return null
  var rows = []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (!it || !it.Id) continue
    var data = it.UserData || {}
    var total = Number(it.RunTimeTicks || 0)
    var pos = Number(data.PlaybackPositionTicks || 0)
    if (!Number.isFinite(total) || total < 0) total = 0
    if (!Number.isFinite(pos) || pos < 0) pos = 0
    var fallbackPct = Number(data.PlayedPercentage || 0)
    if (!Number.isFinite(fallbackPct)) fallbackPct = 0
    var pct = total > 0
      ? Math.max(0, Math.min(1, pos / total))
      : Math.max(0, Math.min(1, fallbackPct / 100))
    var isEpisode = it.Type === "Episode"
    var code = isEpisode ? episodeCode(it) : ""
    rows.push({
      id: String(it.Id),
      title: isEpisode && it.SeriesName ? String(it.SeriesName) : String(it.Name || ""),
      subtitle: isEpisode
        ? (code !== "" ? code + " · " : "") + String(it.Name || "")
        : (it.ProductionYear ? String(it.ProductionYear) : ""),
      progress: pct,
      remaining: total > 0 ? formatRemaining(total - pos) : "",
      image: thumbUrl(jfBase, it)
    })
  }
  return rows
}

function rowsEqual(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    var x = a[i], y = b[i]
    if (x.id !== y.id || x.title !== y.title || x.subtitle !== y.subtitle
        || x.progress !== y.progress || x.remaining !== y.remaining || x.image !== y.image) {
      return false
    }
  }
  return true
}

function httpErrorText(status) {
  var code = Number(status || 0)
  if (code === 401 || code === 403) return "Jellyfin rejected the API key — check your widget settings."
  if (code === 404) return "Jellyfin API not found — check your Jellyfin URL."
  if (code >= 500) return "Jellyfin returned an error (HTTP " + code + ")."
  if (code > 0) return "Unexpected response from Jellyfin (HTTP " + code + ")."
  return "Can't reach Jellyfin — check your connection and server URL."
}
