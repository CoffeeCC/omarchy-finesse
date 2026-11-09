import QtQuick
import qs.Commons
import qs.Ui

// Continue Watching popup. All data comes from the host BarWidget; this file
// is presentation plus keyboard navigation.
Panel {
  id: root
  moduleName: "coffeecc.finesse"
  manageIpc: false

  property var anchorItem: null
  property var host: null
  property int cursor: 0

  readonly property var rows: host ? host.rows : []
  readonly property string status: host ? host.status : "unconfigured"
  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.65)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int smallFont: Style.font.bodySmall
  readonly property int thumbHeight: Style.space(48)
  readonly property int thumbWidth: Math.round(thumbHeight * 16 / 9)

  readonly property string emptyText: {
    if (status === "unconfigured") return "Set your Finesse URL and Jellyfin API key in the widget settings."
    if (status === "error") return host ? host.errorText : "Something went wrong"
    if (status === "loading" || status === "idle") return "Loading…"
    return "Nothing in progress. Go start something."
  }

  function open() {
    cursor = 0
    root.controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    cursor = Math.max(0, Math.min(rows.length - 1, cursor + delta))
  }

  function activate(index) {
    if (!host || index < 0 || index >= rows.length) return
    host.play(rows[index].id)
    root.close()
  }

  onRowsChanged: if (cursor >= rows.length) cursor = Math.max(0, rows.length - 1)

  KeyboardPanel {
    id: card
    anchorItem: root.anchorItem
    owner: root.host || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: card.fittedContentWidth(Style.space(360))
    contentHeight: card.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy) }
      onActivateRequested: root.activate(root.cursor)
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          height: titleText.implicitHeight
          spacing: Style.space(8)

          Text {
            id: titleText
            text: "Continue Watching"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            verticalAlignment: Text.AlignVCenter
          }
        }

        Text {
          visible: root.rows.length === 0
          width: parent.width
          text: root.emptyText
          color: root.dim
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.rows

          Rectangle {
            id: rowItem
            required property var modelData
            required property int index

            readonly property bool current: index === root.cursor

            width: column.width
            height: root.thumbHeight + Style.space(8)
            radius: Math.min(Style.cornerRadius, Style.space(6))
            color: current || hover.containsMouse
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
              : "transparent"

            MouseArea {
              id: hover
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onEntered: root.cursor = rowItem.index
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton && root.host) {
                  root.host.details(rowItem.modelData.id)
                  root.close()
                } else {
                  root.activate(rowItem.index)
                }
              }
            }

            Rectangle {
              id: thumbFrame
              x: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: root.thumbWidth
              height: root.thumbHeight
              radius: Math.min(Style.cornerRadius, Style.space(4))
              clip: true
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

              SizedImage {
                anchors.fill: parent
                url: rowItem.modelData.image
                crop: true
                visible: rowItem.modelData.image !== ""
              }

              // Watched-progress strip along the bottom of the thumbnail.
              Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: Math.max(2, Style.space(3))
                width: parent.width * rowItem.modelData.progress
                color: Color.accent
              }
            }

            Column {
              anchors.left: thumbFrame.right
              anchors.leftMargin: Style.space(10)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: rowItem.modelData.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: rowItem.current
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: rowItem.modelData.subtitle
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.smallFont
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                text: rowItem.modelData.remaining
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: root.smallFont
              }
            }
          }
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Open Finesse"
            foreground: root.foreground
            accent: Color.accent
            selected: true
            enabled: root.host ? root.host.finesseUrl !== "" : false
            onClicked: {
              if (root.host) root.host.openFinesse()
              root.close()
            }
          }

          Button {
            text: "Refresh"
            foreground: root.foreground
            accent: Color.accent
            visible: root.status !== "unconfigured"
            onClicked: if (root.host) root.host.refresh()
          }
        }
      }
    }
  }
}
