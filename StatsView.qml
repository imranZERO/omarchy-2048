import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Stats.js" as Stats
import "Numerals.js" as Numerals

// Lifetime stats, drawn over the board. Panel owns the numbers; this only shows
// them and reports button presses.
Rectangle {
  id: root

  property bool shown: false
  property var stats: ({ games: 0, wins: 0, moves: 0, bestTile: 0 })
  property int best: 0
  property string numerals: "Western"
  // Best score per board size, keyed "3" to "6".
  property var bests: ({})
  // "all" shows the lifetime totals, "size" the current board size.
  property string scope: "all"
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
    return Numerals.convert(Number(n).toLocaleString(Qt.locale(), "f", 0), numerals)
  }

  // Only rebuilt while the page is showing: stats and best change on every move,
  // and rebuilding the rows' delegates for a hidden page was measurable.
  property var rows: []

  Binding on rows {
    when: root.shown
    value: {
      var all = root.scope === "all"
      var c = all ? stats : Stats.forSize(stats, size)
      var bestScore = best
      if (all) {
        bestScore = 0
        var keys = Object.keys(bests)
        for (var i = 0; i < keys.length; i++) bestScore = Math.max(bestScore, Number(bests[keys[i]]) || 0)
      }
      return [
        { label: "Games played", value: num(c.games) },
        { label: "Games won", value: num(c.wins) + (c.games > 0 ? "  (" + num(Stats.winRate(c)) + "%)" : "") },
        { label: all ? "Best score" : "Best score, " + num(size) + "×" + num(size), value: num(bestScore) },
        { label: "Best tile", value: c.bestTile > 0 ? num(c.bestTile) : "—" },
        { label: "Total moves", value: num(c.moves) },
        { label: "Moves per game", value: c.games > 0 ? num(Stats.averageMoves(c)) : "—" }
      ]
    }
  }

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

    Item {
      width: parent.width
      height: Math.max(headerLeft.implicitHeight, scopeSwitch.implicitHeight)

      Row {
        id: headerLeft
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
          font.pixelSize: Math.round(Style.font.heading * root.k)
        }
      }

      // This board size or everything, as two segments.
      Row {
        id: scopeSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(Style.space(2) * root.k)

        Repeater {
          model: [{ id: "size", label: root.size + "×" + root.size }, { id: "all", label: "All" }]
          delegate: Rectangle {
            id: seg
            required property var modelData
            readonly property bool on: root.scope === modelData.id
            implicitWidth: segText.implicitWidth + Math.round(Style.space(14) * root.k)
            implicitHeight: segText.implicitHeight + Math.round(Style.space(8) * root.k)
            radius: Style.cornerRadius
            color: on ? Util.alpha(Commons.Color.accent, 0.22)
              : segArea.containsMouse ? Util.alpha(Commons.Color.foreground, 0.1) : "transparent"

            Text {
              id: segText
              anchors.centerIn: parent
              text: seg.modelData.label
              color: seg.on ? Commons.Color.accent : Commons.Color.muted
              font.family: Style.font.family
              font.bold: seg.on
              font.pixelSize: Math.round(Style.font.body * root.k)
            }

            MouseArea {
              id: segArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.scope = seg.modelData.id
            }
          }
        }
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
