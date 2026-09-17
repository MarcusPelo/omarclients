import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "marcuspelo.omarclients"

  function toggle() {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "marcuspelo.omarclients"])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : iconText.implicitWidth + button.scaledHorizontalMargin * 2
    tooltipText: "Hyprland clients — search and inspect windows"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Text {
      id: iconText
      anchors.centerIn: parent
      text: "󰖯"
      textFormat: Text.PlainText
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Style.bar.iconFont
      renderType: Text.NativeRendering
    }
  }
}
