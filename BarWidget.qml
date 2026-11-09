import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button for Finesse. Owns the Jellyfin fetch so the Continue Watching
// list is already warm when the panel opens; the panel only renders it.
//
// Left click: toggle the Continue Watching panel.
// Middle click: open Finesse.
// Right click: refresh now.
BarWidget {
  id: root
  moduleName: "coffeecc.finesse"

  // nf-md-play_box_multiple. Nerd Font glyphs are what Omarchy's bar uses.
  readonly property string glyph: String.fromCodePoint(0xF0D19)

  readonly property string finesseUrl: Model.finesseBase(setting("finesseUrl", ""))
  readonly property string jellyfinUrl: Model.jellyfinBase(setting("jellyfinUrl", ""), setting("finesseUrl", ""))
  readonly property string apiKey: String(setting("apiKey", "")).trim()
  readonly property string userName: String(setting("userName", "")).trim()
  readonly property int maxItems: Math.max(1, Math.min(12, parseInt(setting("maxItems", 6), 10) || 6))
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 5), 10) || 5)
  readonly property bool configured: Model.isConfigured(setting("finesseUrl", ""), setting("jellyfinUrl", ""), apiKey)

  // "idle" | "loading" | "ready" | "error" | "unconfigured"
  property string status: configured ? "idle" : "unconfigured"
  property string errorText: ""
  property var rows: []
  property string userId: ""
  property string requestKey: ""

  readonly property string configKey: jellyfinUrl + "|" + apiKey + "|" + userName + "|" + maxItems
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  onConfigKeyChanged: {
    userId = ""
    rows = []
    status = configured ? "idle" : "unconfigured"
    if (configured) Qt.callLater(refresh)
  }

  function curlCommand(url) {
    return ["curl", "-fsS", "--max-time", "8",
      "-H", "X-Emby-Token: " + apiKey,
      "-H", "Accept: application/json",
      url]
  }

  function refresh() {
    if (!configured) { status = "unconfigured"; return }
    if (usersProc.running || resumeProc.running) return
    if (rows.length === 0) status = "loading"
    requestKey = configKey
    if (userId === "") {
      usersProc.command = curlCommand(Model.usersUrl(jellyfinUrl))
      usersProc.running = true
    } else {
      resumeProc.command = curlCommand(Model.resumeUrl(jellyfinUrl, userId, maxItems))
      resumeProc.running = true
    }
  }

  function fail(message) {
    errorText = message
    status = "error"
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

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Process {
    id: usersProc
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: usersProc.output = text
    }
    onExited: function(exitCode) {
      var out = usersProc.output
      usersProc.output = ""
      if (root.requestKey !== root.configKey) { Qt.callLater(root.refresh); return }
      if (exitCode !== 0) { root.fail("Can't reach Jellyfin (curl exit " + exitCode + ")"); return }
      var id = Model.pickUserId(out, root.userName)
      if (id === "") {
        root.fail(root.userName !== "" ? "No Jellyfin user named " + root.userName : "No Jellyfin users visible to this key")
        return
      }
      root.userId = id
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: resumeProc
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: resumeProc.output = text
    }
    onExited: function(exitCode) {
      var out = resumeProc.output
      resumeProc.output = ""
      if (root.requestKey !== root.configKey) { Qt.callLater(root.refresh); return }
      if (exitCode !== 0) { root.fail("Can't reach Jellyfin (curl exit " + exitCode + ")"); return }
      var parsed = Model.parseResume(out, root.jellyfinUrl)
      if (parsed === null) { root.fail("Unexpected response from Jellyfin"); return }
      root.rows = parsed
      root.errorText = ""
      root.status = "ready"
    }
  }

  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: root.configured
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("ContinueWatching.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
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
      else if (b === Qt.RightButton) root.refresh()
      else {
        var wasOpen = root.opened
        root.toggle()
        if (!wasOpen) root.refresh()
      }
    }
  }
}
