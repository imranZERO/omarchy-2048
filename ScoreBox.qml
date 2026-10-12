import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Numerals.js" as Numerals

// A labelled number. flash(delta) floats a "+N" up from the box and pulses the
// number, for a move that scored.
Rectangle {
  id: box

  property string title: ""
  property int value: 0
  property real uiScale: 1.0
  property string numerals: "Western"
  // Animation time multiplier; 0 turns the effect off.
  property real speed: 1.0
  // No background of its own, for use inside a shared container.
  property bool plain: false

  readonly property bool animated: speed > 0 && Style.duration(1) > 0

  function flash(delta) {
    if (!animated) return
    gainComponent.createObject(box, { text: "+" + Numerals.convert(delta, box.numerals) })
    pulse.restart()
  }

  // A bigger pulse and a flash of the accent color, for a new best score.
  function celebrate() {
    if (!animated) return
    celebrateAnim.restart()
  }

  // Padding of about 3 px above and below and 5 px either side, so the text sits
  // evenly in the card instead of being tight vertically and roomy sideways.
  implicitWidth: Math.max(Math.round(Style.space(48) * uiScale), label.implicitWidth + Math.round(Style.space(10) * uiScale))
  implicitHeight: label.implicitHeight + Math.round(Style.space(6) * uiScale)
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
      font.pixelSize: Math.max(8, Math.round((Style.font.caption - 1) * box.uiScale))
    }

    Text {
      id: number
      anchors.horizontalCenter: parent.horizontalCenter
      text: Numerals.format(box.value, box.numerals)
      property real hot: 0
      color: Qt.tint(Commons.Color.foreground, Util.alpha(Commons.Color.accent, hot))
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.round((Style.font.title - 1) * box.uiScale)

      ParallelAnimation {
        id: celebrateAnim
        SequentialAnimation {
          NumberAnimation { target: number; property: "scale"; to: 1.35; duration: Style.duration(110 * box.speed); easing.type: Easing.OutQuad }
          NumberAnimation { target: number; property: "scale"; to: 1.0; duration: Style.duration(320 * box.speed); easing.type: Easing.OutBack }
        }
        SequentialAnimation {
          NumberAnimation { target: number; property: "hot"; to: 1; duration: Style.duration(80 * box.speed) }
          PauseAnimation { duration: Style.duration(500 * box.speed) }
          NumberAnimation { target: number; property: "hot"; to: 0; duration: Style.duration(500 * box.speed); easing.type: Easing.InOutQuad }
        }
      }

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
      font.pixelSize: Math.round(Style.font.title * box.uiScale)

      ParallelAnimation {
        running: true
        NumberAnimation {
          target: gain; property: "y"; from: 0; to: -Math.round(Style.space(16) * box.uiScale)
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
