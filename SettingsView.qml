pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The settings page, drawn in place of the board. It only shows `values` and
// reports edits through changed(key, value); Panel decides how to save them.
Rectangle {
  id: root

  property bool shown: false
  // Current value of every setting, by key.
  property var values: ({})
  property real uiScale: 1.0

  readonly property real k: Math.max(0.8, uiScale)

  signal changed(string key, var value)
  signal closeRequested()

  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  border.width: 1
  border.color: Util.alpha(Commons.Color.foreground, 0.15)
  opacity: shown ? 1 : 0
  visible: opacity > 0

  Behavior on opacity {
    NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
  }

  // Swallow clicks so the board underneath stays put.
  MouseArea {
    anchors.fill: parent
    enabled: root.visible
    acceptedButtons: Qt.AllButtons
  }

  readonly property var onOff: [{ label: "Off", value: false }, { label: "On", value: true }]

  // What the page offers. Volume only appears while sound is on.
  readonly property var rows: {
    var list = [
      { key: "openAs", label: "Open as", kind: "choice", options: [
        { label: "Dropdown", value: "Dropdown" }, { label: "Window", value: "Window" } ] },
      { key: "scale", label: "Window scale", kind: "stepper", min: 60, max: 200, step: 10, suffix: "%" },
      { key: "boardSize", label: "Board size", kind: "choice", options: [
        { label: "3×3", value: 3 }, { label: "4×4", value: 4 },
        { label: "5×5", value: 5 }, { label: "6×6", value: 6 } ] },
      { key: "palette", label: "Tile colors", kind: "choice", options: [
        { label: "Theme", value: "Theme" }, { label: "Classic", value: "Classic" }, { label: "Mono", value: "Mono" } ] },
      { key: "animationSpeed", label: "Animations", kind: "choice", options: [
        { label: "Off", value: "Off" }, { label: "Fast", value: "Fast" },
        { label: "Normal", value: "Normal" }, { label: "Slow", value: "Slow" } ] },
      { key: "sound", label: "Sound", kind: "choice", options: onOff }
    ]
    if (values.sound === true)
      list.push({ key: "soundVolume", label: "Volume", kind: "stepper", min: 10, max: 100, step: 10, suffix: "%" })
    return list
  }

  // Wide enough for the longest row (label plus four-way picker).
  implicitWidth: Math.round(Style.space(310) * k)
  implicitHeight: content.implicitHeight + Math.round(Style.space(32) * k)

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Math.round(Style.space(16) * root.k)
    spacing: Math.round(Style.space(9) * root.k)

    Row {
      spacing: Math.round(Style.space(8) * root.k)

      Button {
        iconText: String.fromCodePoint(0xF004D)
        iconSize: Math.round(Style.font.icon * root.k)
        tooltipText: "Back"
        onClicked: root.closeRequested()
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Settings"
        color: Commons.Color.accent
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Math.round(Style.font.display * root.k)
      }
    }

    Repeater {
      model: root.rows
      delegate: Item {
        id: row
        required property var modelData
        width: parent.width
        height: Math.max(labelText.implicitHeight, control.implicitHeight)

        Text {
          id: labelText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.label
          color: Commons.Color.muted
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.body * root.k)
        }

        Loader {
          id: control
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          sourceComponent: row.modelData.kind === "stepper" ? stepperComponent : choiceComponent
        }

        Component {
          id: choiceComponent

          Row {
            spacing: Math.round(Style.space(4) * root.k)

            Repeater {
              model: row.modelData.options
              delegate: Rectangle {
                id: choice
                required property var modelData
                readonly property bool selected: choice.modelData.value === root.values[row.modelData.key]

                implicitWidth: choiceText.implicitWidth + Math.round(Style.space(18) * root.k)
                implicitHeight: choiceText.implicitHeight + Math.round(Style.space(10) * root.k)
                radius: Style.cornerRadius
                color: selected
                  ? Util.alpha(Commons.Color.accent, 0.85)
                  : Util.alpha(Commons.Color.foreground, choiceArea.containsMouse ? 0.16 : 0.07)

                Text {
                  id: choiceText
                  anchors.centerIn: parent
                  text: choice.modelData.label
                  color: choice.selected ? Commons.Color.background : Commons.Color.foreground
                  font.family: Style.font.family
                  font.bold: choice.selected
                  font.pixelSize: Math.round(Style.font.bodySmall * root.k)
                }

                MouseArea {
                  id: choiceArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.changed(row.modelData.key, choice.modelData.value)
                }
              }
            }
          }
        }

        Component {
          id: stepperComponent

          Row {
            id: stepper
            spacing: Math.round(Style.space(4) * root.k)

            readonly property real current: Number(root.values[row.modelData.key])

            function nudge(direction) {
              var next = Math.max(row.modelData.min, Math.min(row.modelData.max, current + direction * row.modelData.step))
              if (next !== current) root.changed(row.modelData.key, next)
            }

            StepButton {
              glyph: "−"
              enabled: stepper.current > row.modelData.min
              onActivated: stepper.nudge(-1)
            }

            Item {
              implicitWidth: Math.round(Style.space(54) * root.k)
              // As tall as the step buttons beside it, so the label centers on them.
              implicitHeight: Math.round(Style.space(24) * root.k)

              Text {
                anchors.centerIn: parent
                text: stepper.current + row.modelData.suffix
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.bold: true
                font.pixelSize: Math.round(Style.font.bodySmall * root.k)
              }
            }

            StepButton {
              glyph: "+"
              enabled: stepper.current < row.modelData.max
              onActivated: stepper.nudge(1)
            }
          }
        }
      }
    }
  }

  component StepButton: Rectangle {
    id: step
    property string glyph: ""
    signal activated()

    implicitWidth: Math.round(Style.space(26) * root.k)
    implicitHeight: Math.round(Style.space(24) * root.k)
    radius: Style.cornerRadius
    opacity: enabled ? 1 : 0.35
    color: Util.alpha(Commons.Color.foreground, stepArea.containsMouse && enabled ? 0.16 : 0.07)

    Text {
      anchors.centerIn: parent
      text: step.glyph
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.round(Style.font.body * root.k)
    }

    MouseArea {
      id: stepArea
      anchors.fill: parent
      enabled: step.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: step.activated()
    }
  }
}
