pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Game.js" as Game
import "Numerals.js" as Numerals

// The page the title opens: the game modes, and the keys. Panel owns the mode;
// this only shows it and reports the one picked.
Rectangle {
  id: root

  property bool shown: false
  property string mode: "Classic"
  property int size: 4
  property string numerals: "Western"
  // Today's best Daily score on this board size, 0 if none yet.
  property int dailyBest: 0
  property real uiScale: 1.0

  signal chosen(string mode)
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
  // Rises into place as it fades in, and sinks as it fades out; driven by the
  // opacity above, so it costs no animation of its own.
  transform: Translate { y: Math.round(Style.space(10) * root.uiScale * (1 - root.opacity)) }

  // Swallow clicks so the board underneath stays put.
  MouseArea {
    anchors.fill: parent
    enabled: root.visible
    acceptedButtons: Qt.AllButtons
  }

  function num(n) { return Numerals.format(n, numerals) }
  function goal(m) { return Numerals.convert(Game.goalFor(size, m), numerals) }

  // One short line each, so the page fits in the board's height; the README has
  // the full rules.
  readonly property var modes: [
    { id: "Classic", name: "Classic", about: "Reach " + goal("Classic") },
    { id: "Fibonacci", name: "Fibonacci", about: Numerals.convert("3 + 5 = 8", numerals) },
    { id: "Evil", name: "Evil", about: "Tiles fight back" },
    { id: "Daily", name: "Daily", about: dailyBest > 0 ? "Today's best " + num(dailyBest) : "Same game for all" }
  ]

  readonly property var keys: [
    { key: "↑↓←→", label: "move" },
    { key: "U", label: "undo" },
    { key: "R", label: "new game" },
    { key: "T", label: "stats" },
    { key: "O", label: "settings" },
    { key: "M", label: "modes" },
    { key: "Esc", label: "back" },
    { key: "Q", label: "close" }
  ]

  implicitHeight: content.implicitHeight + Math.round(Style.space(32) * uiScale)

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Math.round(Style.space(16) * root.uiScale)
    spacing: Math.round(Style.space(8) * root.uiScale)

    Row {
      spacing: Math.round(Style.space(8) * root.uiScale)

      Button {
        iconText: String.fromCodePoint(0xF004D)
        iconSize: Math.round(Style.font.icon * root.uiScale)
        tooltipText: "Back"
        onClicked: root.closeRequested()
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Modes"
        color: Commons.Color.accent
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Math.round(Style.font.heading * root.uiScale)
      }
    }

    Grid {
      id: modeGrid
      width: parent.width
      columns: 2
      columnSpacing: Math.round(Style.space(6) * root.uiScale)
      rowSpacing: Math.round(Style.space(6) * root.uiScale)

      Repeater {
        model: root.modes
        delegate: Rectangle {
          id: card
          required property var modelData
          readonly property bool on: root.mode === modelData.id

          width: (modeGrid.width - modeGrid.columnSpacing) / 2
          height: cardText.implicitHeight + Math.round(Style.space(10) * root.uiScale)
          radius: Style.cornerRadius
          color: on ? Util.alpha(Commons.Color.accent, 0.16)
            : cardArea.containsMouse ? Util.alpha(Commons.Color.foreground, 0.1)
            : Util.alpha(Commons.Color.foreground, 0.05)
          border.width: on ? Math.max(1, Math.round(root.uiScale)) : 0
          border.color: Util.alpha(Commons.Color.accent, 0.6)

          Column {
            id: cardText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Math.round(Style.space(8) * root.uiScale)
            anchors.rightMargin: Math.round(Style.space(8) * root.uiScale)

            Text {
              width: parent.width
              text: card.modelData.name
              elide: Text.ElideRight
              color: card.on ? Commons.Color.accent : Commons.Color.foreground
              font.family: Style.font.family
              font.bold: true
              font.pixelSize: Math.round(Style.font.body * root.uiScale)
            }

            Text {
              width: parent.width
              text: card.modelData.about
              elide: Text.ElideRight
              color: Util.alpha(Commons.Color.foreground, 0.65)
              font.family: Style.font.family
              font.pixelSize: Math.round(Style.font.caption * root.uiScale)
            }
          }

          MouseArea {
            id: cardArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.chosen(card.modelData.id)
          }
        }
      }
    }

    Item { width: 1; height: Math.round(Style.space(2) * root.uiScale) }

    Text {
      text: "KEYS"
      color: Commons.Color.muted
      font.family: Style.font.family
      font.bold: true
      font.letterSpacing: 1
      font.pixelSize: Math.round(Style.font.caption * root.uiScale)
    }

    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Math.round(Style.space(12) * root.uiScale)
      rowSpacing: Math.round(Style.space(6) * root.uiScale)

      Repeater {
        model: root.keys
        delegate: KeyHint {
          required property var modelData
          width: (parent.width - parent.columnSpacing) / 2
          key: modelData.key
          label: modelData.label
          uiScale: root.uiScale
        }
      }
    }
  }
}
