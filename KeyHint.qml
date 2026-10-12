import QtQuick
import qs.Commons
import qs.Commons as Commons

// A key cap and what the key does, for the key list on the Modes page: [U] undo
Row {
  id: root

  property string key: ""
  property string label: ""
  property real uiScale: 1.0

  spacing: Math.round(Style.space(4) * uiScale)

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(keyText.implicitWidth + Math.round(Style.space(8) * root.uiScale), height)
    height: keyText.implicitHeight + Math.round(Style.space(1) * root.uiScale)
    radius: Math.max(2, Style.cornerRadius)
    color: Util.alpha(Commons.Color.foreground, 0.1)

    Text {
      id: keyText
      anchors.centerIn: parent
      text: root.key
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.max(8, Math.round((Style.font.caption - 2) * root.uiScale))
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: Commons.Color.muted
    font.family: Style.font.family
    font.pixelSize: Math.max(8, Math.round((Style.font.caption - 2) * root.uiScale))
  }
}
