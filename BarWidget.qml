import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button for Finesse. Owns the Jellyfin fetch via native XMLHttpRequest
// (no subprocess fork, no API key in /proc/<pid>/cmdline) so Continue Watching
// is warm when the panel opens; the panel itself is loaded lazily on first open.
//
// Left click: toggle the Continue Watching panel.
// Middle click: open Finesse.
// Right click: refresh now.
BarWidget {
  id: root
  moduleName: "coffeecc.finesse"

  // nf-md-play_box_multiple. Nerd Font glyphs are what Omarchy's bar uses.
  readonly property string glyph: String.fromCodePoint(0xF0D19)

  readonly property string rawFinesseUrl: String(setting("finesseUrl", ""))
  readonly property string rawJellyfinUrl: String(setting("jellyfinUrl", ""))
  readonly property string finesseUrl: Model.finesseBase(rawFinesseUrl)
  readonly property string jellyfinUrl: Model.jellyfinBase(rawJellyfinUrl, rawFinesseUrl)
  readonly property var jellyfinCandidates: Model.jellyfinCandidates(rawJellyfinUrl, rawFinesseUrl)
  readonly property string apiKey: Model.sanitizeApiKey(setting("apiKey", ""))
  readonly property string userName: String(setting("userName", "")).trim()
  readonly property int maxItems: Math.max(1, Math.min(12, parseInt(setting("maxItems", 6), 10) || 6))
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 5), 10) || 5)
  readonly property bool configured: Model.isConfigured(rawFinesseUrl, rawJellyfinUrl, apiKey)

  // Internal fetch state; public `status` stays a live binding so clearing
  // credentials always flips back to "unconfigured".
  property string fetchState: "idle"
  readonly property string status: !configured ? "unconfigured" : fetchState
  property bool refreshing: false
  property string errorText: ""
  property var rows: []
  property string userId: ""
  property string resolvedJellyfinUrl: ""
  property int requestSeq: 0
  property var activeXhr: null
  property bool panelRequested: false

  readonly property string configKey: finesseUrl + "|" + jellyfinUrl + "|" + apiKey + "|" + userName + "|" + maxItems
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  onConfigKeyChanged: {
    abortActive()
    userId = ""
    resolvedJellyfinUrl = ""
    rows = []
    errorText = ""
    refreshing = false
    fetchState = "idle"
    if (configured) configDebounce.restart()
  }

  function abortActive() {
    requestSeq += 1
    timeoutTimer.stop()
    if (activeXhr) {
      var xhr = activeXhr
      activeXhr = null
      xhr.onreadystatechange = null
      try { xhr.abort() } catch (e) {}
    }
  }

  function httpGet(url, seq, onDone) {
    var xhr = new XMLHttpRequest()
    activeXhr = xhr
    timeoutTimer.restart()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (seq !== root.requestSeq) return
      timeoutTimer.stop()
      if (root.activeXhr === xhr) root.activeXhr = null
      onDone(xhr.status, xhr.responseText || "")
    }
    try {
      xhr.open("GET", url)
      xhr.setRequestHeader("Authorization", "MediaBrowser Token=\"" + apiKey + "\"")
      xhr.setRequestHeader("X-Emby-Token", apiKey)
      xhr.setRequestHeader("Accept", "application/json")
      xhr.send()
    } catch (e) {
      if (seq === root.requestSeq) {
        timeoutTimer.stop()
        if (root.activeXhr === xhr) root.activeXhr = null
        onDone(0, "")
      }
    }
  }

  function fetchUsers(candidateIndex, seq) {
    var cands = jellyfinCandidates
    if (!cands || candidateIndex >= cands.length) {
      fail("Jellyfin API not found — check your Jellyfin URL.")
      return
    }
    var base = cands[candidateIndex]
    httpGet(Model.usersUrl(base), seq, function(code, body) {
      if (seq !== root.requestSeq) return
      if (code === 404 && candidateIndex + 1 < cands.length) {
        fetchUsers(candidateIndex + 1, seq)
        return
      }
      if (code < 200 || code >= 300) {
        fail(Model.httpErrorText(code))
        return
      }
      var id = Model.pickUserId(body, root.userName)
      if (id === "") {
        fail(root.userName !== "" ? "No Jellyfin user named " + root.userName : "No Jellyfin users visible to this key")
        return
      }
      root.resolvedJellyfinUrl = base
      root.userId = id
      fetchResume(seq)
    })
  }

  function fetchResume(seq) {
    var base = resolvedJellyfinUrl || jellyfinUrl
    httpGet(Model.resumeUrl(base, userId, maxItems), seq, function(code, body) {
      if (seq !== root.requestSeq) return
      if (code < 200 || code >= 300) {
        fail(Model.httpErrorText(code))
        return
      }
      var parsed = Model.parseResume(body, base)
      if (parsed === null) {
        fail("Unexpected response from Jellyfin")
        return
      }
      if (!Model.rowsEqual(root.rows, parsed)) root.rows = parsed
      root.errorText = ""
      root.refreshing = false
      root.fetchState = "ready"
    })
  }

  function refresh(force) {
    if (!configured) return
    if (refreshing && !force) return
    abortActive()
    var seq = requestSeq
    refreshing = true
    if (rows.length === 0) fetchState = "loading"
    if (userId === "" || resolvedJellyfinUrl === "") {
      fetchUsers(0, seq)
    } else {
      fetchResume(seq)
    }
  }

  function fail(message) {
    errorText = message
    refreshing = false
    fetchState = "error"
  }

  function launch(url) {
    if (url === "") return
    Quickshell.execDetached(["omarchy-launch-webapp", url])
  }

  function openFinesse() { launch(finesseUrl) }
  function play(itemId) { launch(Model.playUrl(finesseUrl, itemId)) }
  function details(itemId) { launch(Model.itemUrl(finesseUrl, itemId)) }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("host" in target) target.host = root
  }

  function ensurePanelLoaded(thenOpen) {
    if (panelLoader.item) {
      if (thenOpen && panelLoader.item.open) panelLoader.item.open()
      return
    }
    pendingOpen = thenOpen
    panelRequested = true
  }

  property bool pendingOpen: false

  function open() {
    ensurePanelLoaded(true)
  }

  function close() {
    pendingOpen = false
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onDestruction: abortActive()

  Timer {
    id: configDebounce
    interval: 250
    repeat: false
    onTriggered: root.refresh(true)
  }

  Timer {
    id: timeoutTimer
    interval: 8000
    repeat: false
    onTriggered: {
      if (root.activeXhr) {
        root.abortActive()
        root.fail("Jellyfin request timed out.")
      }
    }
  }

  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: root.configured
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  Loader {
    id: panelLoader
    active: root.panelRequested
    source: Qt.resolvedUrl("ContinueWatching.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      if (root.pendingOpen) {
        root.pendingOpen = false
        Qt.callLater(function() {
          if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
        })
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    foreground: Color.bar.text
    activeColor: Color.bar.active
    active: false
    dimmed: root.status === "unconfigured" || root.status === "error"
    tooltipText: root.opened ? "" : "Finesse"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.openFinesse()
      else if (b === Qt.RightButton) root.refresh(true)
      else {
        var wasOpen = root.opened
        root.toggle()
        if (!wasOpen) root.refresh(false)
      }
    }
  }
}
