import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Stats.js" as Stats

// Lifetime stats, drawn over the board. Panel owns the numbers; this only shows
// them and reports button presses.
Rectangle {
  id: root

  property bool shown: false
  property var stats: ({ games: 0, wins: 0, moves: 0, bestTile: 0 })
  property int best: 0
  property int size: 4
  property real uiScale: 1.0

  readonly property real k: Math.max(0.8, uiScale)

  signal closeRequested()
  signal resetRequested()

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

  function num(n) {
    return Number(n).toLocaleString(Qt.locale(), "f", 0)
  }

  readonly property var rows: [
    { label: "Games played", value: num(stats.games) },
    { label: "Games won", value: num(stats.wins) + (stats.games > 0 ? "  (" + Stats.winRate(stats) + "%)" : "") },
    { label: "Best score, " + size + "×" + size, value: num(best) },
    { label: "Best tile", value: stats.bestTile > 0 ? num(stats.bestTile) : "—" },
    { label: "Total moves", value: num(stats.moves) },
    { label: "Moves per game", value: stats.games > 0 ? num(Stats.averageMoves(stats)) : "—" }
  ]

  // Armed by the first click on Reset; the second click within 3s confirms.
  property bool confirmReset: false

  onShownChanged: if (!shown) confirmReset = false

  Timer {
    interval: 3000
    running: root.confirmReset
    onTriggered: root.confirmReset = false
  }

  // Tall enough for the rows and buttons, whatever the board size; Panel sizes
  // the board's slot to at least this.
  implicitHeight: content.implicitHeight + buttons.implicitHeight + Math.round(Style.space(48) * k)

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Math.round(Style.space(16) * root.k)
    spacing: Math.round(Style.space(10) * root.k)

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
        text: "Stats"
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
        height: Math.max(labelText.implicitHeight, valueText.implicitHeight)

        Text {
          id: labelText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.label
          color: Commons.Color.muted
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.body * root.k)
        }

        Text {
          id: valueText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.value
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: Math.round(Style.font.subtitle * root.k)
        }
      }
    }
  }

  Row {
    id: buttons
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Math.round(Style.space(16) * root.k)
    spacing: Math.round(Style.space(8) * root.k)

    Button {
      text: root.confirmReset ? "Really reset?" : "Reset stats"
      bordered: true
      fontSize: Math.round(Style.font.body * root.k)
      onClicked: {
        if (root.confirmReset) { root.confirmReset = false; root.resetRequested() }
        else root.confirmReset = true
      }
    }
  }
}
