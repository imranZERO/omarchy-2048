import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// SCORE and BEST in one capsule, with a thin divider between them. The capsule is
// also a button: clicking it emits clicked(), which Panel uses to open the stats.
Rectangle {
  id: root

  property int score: 0
  property int best: 0
  property real uiScale: 1.0
  property string numerals: "Western"
  // Animation time multiplier; 0 turns the effects off.
  property real speed: 1.0
  // True while the page it opens is showing.
  property bool active: false
  property string tooltipText: ""

  signal clicked()

  // A scoring move: float the points up from the score and pulse it.
  function flash(delta) { scoreCell.flash(delta) }

  // A new best score: pulse the best number.
  function celebrate() { bestCell.celebrate() }

  implicitWidth: cells.implicitWidth
  implicitHeight: cells.implicitHeight
  radius: Style.cornerRadius
  // The theme's hover fill is the same 8% as this card's idle fill, which would make
  // hovering invisible, so hover is a clearly stronger fill plus the theme's hover border.
  color: area.pressed ? Style.pressedFill
    : active ? Style.selectedFill
    : area.containsMouse ? Util.alpha(Commons.Color.foreground, 0.14)
    : Util.alpha(Commons.Color.foreground, 0.08)
  border.width: area.containsMouse ? 1 : 0
  border.color: Style.hoverBorderColor

  Behavior on color { ColorAnimation { duration: Style.duration(120) } }

  Row {
    id: cells

    ScoreBox {
      id: scoreCell
      plain: true
      title: "SCORE"
      value: root.score
      numerals: root.numerals
      uiScale: root.uiScale
      speed: root.speed
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: scoreCell.height * 0.55
      color: Util.alpha(Commons.Color.foreground, 0.15)
    }

    ScoreBox {
      id: bestCell
      plain: true
      title: "BEST"
      value: root.best
      numerals: root.numerals
      uiScale: root.uiScale
      speed: root.speed
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  ToolTip {
    visible: area.containsMouse && root.tooltipText !== ""
    text: root.tooltipText
    delay: 400
    padding: 0

    background: Rectangle {
      color: Commons.Color.tooltip.background
      border.width: 1
      border.color: Commons.Color.tooltip.border
    }

    contentItem: Text {
      text: root.tooltipText
      color: Commons.Color.tooltip.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      leftPadding: Style.spacing.controlPaddingX
      rightPadding: Style.spacing.controlPaddingX
      topPadding: Style.spacing.controlPaddingY
      bottomPadding: Style.spacing.controlPaddingY
    }
  }
}
