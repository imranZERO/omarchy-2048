import QtQuick
import qs.Commons
import qs.Commons as Commons

// A labelled number. flash(delta) floats a "+N" up from the box and pulses the
// number, for a move that scored.
Rectangle {
  id: box

  property string title: ""
  property int value: 0
  property real uiScale: 1.0
  // Animation time multiplier; 0 turns the effect off.
  property real speed: 1.0
  // No background of its own, for use inside a shared container.
  property bool plain: false

  readonly property real k: Math.max(0.6, uiScale)

  function flash(delta) {
    if (speed <= 0 || Style.duration(1) === 0) return
    gainComponent.createObject(box, { text: "+" + delta })
    pulse.restart()
  }

  implicitWidth: Math.max(Math.round(Style.space(50) * k), label.implicitWidth + Math.round(Style.space(14) * k))
  implicitHeight: label.implicitHeight + Math.round(Style.space(4) * k)
  radius: Style.cornerRadius
  color: plain ? "transparent" : Util.alpha(Commons.Color.foreground, 0.08)

  Column {
    id: label
    anchors.centerIn: parent

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: box.title
      color: Commons.Color.muted
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.max(8, Math.round((Style.font.caption - 1) * box.k))
    }

    Text {
      id: number
      anchors.horizontalCenter: parent.horizontalCenter
      text: Number(box.value).toLocaleString(Qt.locale(), "f", 0)
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.round((Style.font.title - 1) * box.k)
      transformOrigin: Item.Center

      SequentialAnimation {
        id: pulse
        NumberAnimation { target: number; property: "scale"; to: 1.15; duration: Style.duration(80 * box.speed); easing.type: Easing.OutQuad }
        NumberAnimation { target: number; property: "scale"; to: 1.0; duration: Style.duration(120 * box.speed); easing.type: Easing.InOutQuad }
      }
    }
  }

  Component {
    id: gainComponent

    Text {
      id: gain
      x: (box.width - implicitWidth) / 2
      y: 0
      color: Commons.Color.accent
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.round(Style.font.title * box.k)

      ParallelAnimation {
        running: true
        NumberAnimation {
          target: gain; property: "y"; from: 0; to: -Math.round(Style.space(16) * box.k)
          duration: Style.duration(600 * box.speed); easing.type: Easing.InCubic
        }
        NumberAnimation {
          target: gain; property: "opacity"; from: 1; to: 0
          duration: Style.duration(600 * box.speed); easing.type: Easing.InCubic
        }
        onFinished: gain.destroy()
      }
    }
  }
}
