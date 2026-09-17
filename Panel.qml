import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property string searchText: ""
  property string visibleFilter: "all"   // "all" | "visible" | "hidden"
  property string monitorFilter: "All"
  property string selectedAddress: ""
  property bool loading: false
  property string lastError: ""

  property var rawClients: []
  property var monitorMap: ({})
  property var monitorOptions: ["All"]
  property var _pendingMonitors: null
  property var _pendingClients: null

  readonly property color onScrim: "white"
  readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.58)
  readonly property color onScrimUrgent: "#ff6b6b"
  readonly property color onScrimGood: "#63d675"

  readonly property var filteredClients:
    Model.filterClients(root.rawClients, root.searchText, root.visibleFilter, root.monitorFilter)
  readonly property var selectedClient: Model.findByAddress(root.rawClients, root.selectedAddress)

  function open(payloadJson) {
    opened = true
    refresh()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
    selectedAddress = ""
  }

  function toggle() { if (opened) close(); else open() }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "marcuspelo.omarclients")
    else close()
  }

  function selectClient(address) { selectedAddress = address }

  function refresh() {
    loading = true
    lastError = ""
    _pendingMonitors = null
    _pendingClients = null
    monitorsProcess.running = false
    monitorsProcess.running = true
    clientsProcess.running = false
    clientsProcess.running = true
  }

  function _tryCombine() {
    if (_pendingMonitors === null || _pendingClients === null) return
    monitorMap = _pendingMonitors
    var normalized = Model.normalizeClients(_pendingClients, monitorMap)
    rawClients = normalized
    monitorOptions = Model.buildMonitorOptions(normalized)
    if (selectedAddress !== "" && !Model.findByAddress(normalized, selectedAddress))
      selectedAddress = ""
    loading = false
  }

  // This Hyprland build parses `hyprctl dispatch <name> <args>` as Lua
  // (`hl.dispatch(...)`), so the classic "focuswindow address:0x.." string
  // syntax is rejected. The Lua dispatcher API instead takes structured
  // tables: hl.dsp.focus({window = "address:0x.."}) and
  // hl.dsp.window.close({address = "0x.."}).
  function focusWindow(address) {
    if (!/^0x[0-9a-fA-F]+$/.test(address)) return
    Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({window = "address:' + address + '"})'])
    root.dismiss()
  }

  function closeWindow(address) {
    if (!/^0x[0-9a-fA-F]+$/.test(address)) return
    Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.window.close({address = "' + address + '"})'])
    if (selectedAddress === address) selectedAddress = ""
    closeRefreshTimer.restart()
  }

  Timer {
    id: closeRefreshTimer
    interval: 350
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: monitorsProcess
    running: false
    command: ["hyprctl", "-j", "monitors"]
    stdout: StdioCollector {
      id: monitorsStdout
      waitForEnd: true
      onStreamFinished: {
        var map = {}
        try { map = Model.buildMonitorMap(JSON.parse(String(text || ""))) }
        catch (error) { map = {} }
        root._pendingMonitors = map
        root._tryCombine()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root._pendingMonitors === null) {
        root._pendingMonitors = {}
        root._tryCombine()
      }
    }
  }

  Process {
    id: clientsProcess
    running: false
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      id: clientsStdout
      waitForEnd: true
      onStreamFinished: {
        var arr = []
        try {
          arr = JSON.parse(String(text || ""))
          if (!Array.isArray(arr)) arr = []
        } catch (error) {
          arr = []
          root.lastError = "Could not parse hyprctl clients output"
        }
        root._pendingClients = arr
        root._tryCombine()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root._pendingClients === null) {
        root._pendingClients = []
        root.lastError = "hyprctl clients failed (exit " + exitCode + ")"
        root._tryCombine()
      }
    }
  }

  PanelWindow {
    id: clientsWindow
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-omarclients"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.86)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.dismiss()
      Keys.onPressed: function(event) {
        if (String(event.text || "") === "/") {
          searchField.forceActiveFocus()
          event.accepted = true
        }
      }

      Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(64), Style.space(1200))
        height: Math.min(parent.height - Style.space(64), Style.space(780))
        radius: Style.cornerRadius
        color: Qt.rgba(0.055, 0.055, 0.065, 0.98)
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(1, 1, 1, 0.15)

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(24)
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(titleCol.implicitHeight, headerButtons.implicitHeight)

            Column {
              id: titleCol
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Clients"
                textFormat: Text.PlainText
                color: root.onScrim
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
              }

              Text {
                text: root.loading
                  ? "Loading…"
                  : (root.filteredClients.length + " of " + root.rawClients.length + " windows")
                textFormat: Text.PlainText
                color: root.onScrimDim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: headerButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Button {
                text: "Refresh"
                foreground: root.onScrim
                fontFamily: Style.font.family
                bordered: true
                enabled: !root.loading
                onClicked: root.refresh()
              }

              Button {
                text: "Close  Esc"
                foreground: root.onScrim
                fontFamily: Style.font.family
                bordered: true
                onClicked: root.dismiss()
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: searchField.implicitHeight

            TextField {
              id: searchField
              anchors.left: parent.left
              width: parent.width
              text: root.searchText
              maximumLength: 120
              placeholderText: "Search title, class, address, workspace…  /"
              foreground: root.onScrim
              font.family: Style.font.family
              onTextChanged: root.searchText = text
              Keys.onEscapePressed: {
                if (text !== "") text = ""
                else keyCatcher.forceActiveFocus()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(14)

            Row {
              spacing: Style.space(4)

              Button {
                text: "All"; bordered: true; foreground: root.onScrim
                fontFamily: Style.font.family
                active: root.visibleFilter === "all"
                onClicked: root.visibleFilter = "all"
              }
              Button {
                text: "Visible"; bordered: true; foreground: root.onScrim
                fontFamily: Style.font.family
                active: root.visibleFilter === "visible"
                onClicked: root.visibleFilter = "visible"
              }
              Button {
                text: "Hidden"; bordered: true; foreground: root.onScrim
                fontFamily: Style.font.family
                active: root.visibleFilter === "hidden"
                onClicked: root.visibleFilter = "hidden"
              }
            }

            Row {
              spacing: Style.space(4)

              Repeater {
                model: root.monitorOptions
                delegate: Button {
                  required property var modelData
                  text: modelData
                  bordered: true
                  foreground: root.onScrim
                  fontFamily: Style.font.family
                  active: root.monitorFilter === modelData
                  onClicked: root.monitorFilter = modelData
                }
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            width: parent.width
            text: root.lastError
            textFormat: Text.PlainText
            color: root.onScrimUrgent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            id: body
            width: parent.width
            height: parent.height - y - footerHint.implicitHeight - Style.space(12)
            spacing: Style.space(16)

            ListView {
              id: clientsList
              width: details.visible ? (body.width - details.width - body.spacing) : body.width
              height: parent.height
              clip: true
              spacing: Style.space(4)
              model: root.filteredClients
              boundsBehavior: Flickable.StopAtBounds

              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Text {
                anchors.centerIn: parent
                visible: !root.loading && root.filteredClients.length === 0
                text: root.rawClients.length === 0 ? "No windows found" : "No windows match the current filters"
                textFormat: Text.PlainText
                color: root.onScrimDim
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              delegate: Rectangle {
                id: row
                required property var modelData
                width: clientsList.width
                height: Style.space(56)
                radius: Style.space(6)
                color: root.selectedAddress === modelData.address
                  ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectClient(row.modelData.address)
                }

                Rectangle {
                  id: dot
                  width: Style.space(8); height: Style.space(8); radius: Style.space(4)
                  anchors.left: parent.left; anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  color: row.modelData.visible ? root.onScrimGood : root.onScrimDim
                }

                Column {
                  anchors.left: dot.right; anchors.leftMargin: Style.space(10)
                  anchors.right: badges.left; anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: row.modelData.title !== "" ? row.modelData.title : "(untitled)"
                    textFormat: Text.PlainText
                    color: root.onScrim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: row.modelData.class + " · " + row.modelData.workspaceLabel
                      + " · " + row.modelData.monitorName
                    textFormat: Text.PlainText
                    color: root.onScrimDim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: badges
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Text { visible: row.modelData.floating; text: "F"; textFormat: Text.PlainText; color: root.onScrimDim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  Text { visible: row.modelData.fullscreen; text: "FS"; textFormat: Text.PlainText; color: root.onScrimDim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  Text { visible: row.modelData.pinned; text: "P"; textFormat: Text.PlainText; color: root.onScrimDim; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                }
              }
            }

            Rectangle {
              id: details
              visible: root.selectedAddress !== ""
              width: Style.space(420)
              height: parent.height
              radius: Style.space(8)
              color: Qt.rgba(1, 1, 1, 0.04)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.12)

              Column {
                anchors.fill: parent
                anchors.margins: Style.space(14)
                spacing: Style.space(10)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(detailsTitle.implicitHeight, actionsRow.implicitHeight)

                  Text {
                    id: detailsTitle
                    anchors.left: parent.left
                    anchors.right: actionsRow.left
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.selectedClient ? (root.selectedClient.title !== "" ? root.selectedClient.title : "(untitled)") : ""
                    textFormat: Text.PlainText
                    color: root.onScrim
                    font.bold: true
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    elide: Text.ElideRight
                  }

                  Row {
                    id: actionsRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Button {
                      text: "Focar"; bordered: true; foreground: root.onScrim
                      fontFamily: Style.font.family
                      onClicked: root.focusWindow(root.selectedAddress)
                    }
                    Button {
                      text: "Fechar"; bordered: true; foreground: root.onScrimUrgent
                      fontFamily: Style.font.family
                      onClicked: root.closeWindow(root.selectedAddress)
                    }
                  }
                }

                Flickable {
                  width: parent.width
                  height: parent.height - Style.space(40)
                  clip: true
                  contentHeight: fieldsColumn.implicitHeight
                  boundsBehavior: Flickable.StopAtBounds

                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  Column {
                    id: fieldsColumn
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                      model: root.selectedClient ? Model.rawFieldEntries(root.selectedClient.raw) : []
                      delegate: Row {
                        required property var modelData
                        width: fieldsColumn.width
                        spacing: Style.space(8)

                        Text {
                          width: Style.space(120)
                          text: modelData.key
                          textFormat: Text.PlainText
                          color: root.onScrimDim
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          width: fieldsColumn.width - Style.space(128)
                          text: modelData.value
                          textFormat: Text.PlainText
                          color: root.onScrim
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          wrapMode: Text.WordWrap
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            id: footerHint
            width: parent.width
            text: "/ Search · Esc close/clear · Click a window for details"
            textFormat: Text.PlainText
            color: root.onScrimDim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
