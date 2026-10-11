pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// The playfield. Owns a ListModel of tiles keyed by stable ids, so a move
// only edits positions and the Tile Behaviors do the animating. It knows
// nothing about the rules: Panel feeds it the event list from Game.move().
Item {
  id: root

  property int size: 4
  // 1.0 is the default window; Panel's "scale" setting.
  property real uiScale: 1.0
  // Animation time multiplier; 0 turns the animations off.
  property real speed: 1.0
  // "Theme", "Classic" or "Mono"
  property string paletteMode: "Theme"
  // The theme's hue palette (a ThemePalette), handed to each tile.
  property var palette: null

  // Bigger boards get smaller cells so the window does not balloon.
  readonly property var cellBase: ({ 3: 88, 4: 64, 5: 54, 6: 46 })
  readonly property var gapBase: ({ 3: 10, 4: 10, 5: 8, 6: 8 })
  readonly property int cell: Math.max(16, Math.round(Style.space(cellBase[size] || 64) * uiScale))
  readonly property int gap: Math.max(3, Math.round(Style.space(gapBase[size] || 10) * uiScale))
  readonly property int side: size * cell + (size + 1) * gap

  readonly property int slideMs: Style.duration(Math.round(110 * speed))
  readonly property int popMs: Style.duration(Math.round(200 * speed))
  readonly property int spawnMs: Style.duration(Math.round(200 * speed))

  // "" while playing, "over" or "won" when the overlay should show.
  property string endState: ""

  signal swiped(int dir)
  signal newGameRequested()
  signal keepGoingRequested()

  width: side
  height: side

  // ---- tile bookkeeping -----------------------------------------------------

  ListModel { id: tilesModel }

  function indexOfTile(tid) {
    for (var i = 0; i < tilesModel.count; i++)
      if (tilesModel.get(i).tid === tid) return i
    return -1
  }

  function purgeDying() {
    for (var i = tilesModel.count - 1; i >= 0; i--)
      if (tilesModel.get(i).dying) tilesModel.remove(i)
  }

  // Replace everything with `list` ([{id, value, x, y}]). Fresh delegates start
  // in place, so nothing slides in from the corner. `kind` is "static", or
  // "restore" to fade the tiles in (used by undo).
  function rebuild(list, kind) {
    dyingTimer.stop()
    bumpAnim.stop()
    bump = 0
    tilesModel.clear()
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      tilesModel.append({ tid: t.id, value: t.value, col: t.x, row: t.y, kind: kind || "static", dying: false, fx: 0 })
    }
  }

  // Animate one move. `res` is the result of Game.move().
  function applyMove(res) {
    // Anything still fading from the previous move goes now, so mashing keys
    // stays crisp instead of piling up.
    purgeDying()

    var i
    for (i = 0; i < res.moves.length; i++) {
      var m = res.moves[i]
      var mi = indexOfTile(m.id)
      if (mi < 0) continue
      tilesModel.setProperty(mi, "col", m.x)
      tilesModel.setProperty(mi, "row", m.y)
    }

    for (i = 0; i < res.merges.length; i++) {
      var g = res.merges[i]
      for (var j = 0; j < g.fromIds.length; j++) {
        var si = indexOfTile(g.fromIds[j])
        if (si < 0) continue
        tilesModel.setProperty(si, "col", g.x)
        tilesModel.setProperty(si, "row", g.y)
        tilesModel.setProperty(si, "dying", true)
      }
      // Rings for the big ones; two when it is the best tile of the game.
      var fx = g.value >= 128 ? (g.newMax ? 2 : 1) : 0
      tilesModel.append({ tid: g.id, value: g.value, col: g.x, row: g.y, kind: "merge", dying: false, fx: fx })
    }

    if (res.spawned) {
      var s = res.spawned
      tilesModel.append({ tid: s.id, value: s.value, col: s.x, row: s.y, kind: "spawn", dying: false, fx: 0 })
    }

    dyingTimer.restart()
  }

  // A move that did nothing: nudge the tiles toward `dir` and let them spring
  // back, like pushing against a wall.
  property real bump: 0
  property real bumpDx: 0
  property real bumpDy: 0

  function bumpToward(dir) {
    if (speed <= 0 || Style.duration(1) === 0) return
    var d = Math.max(3, Math.round(cell * 0.12))
    bumpDx = dir === 1 ? d : dir === 3 ? -d : 0
    bumpDy = dir === 2 ? d : dir === 0 ? -d : 0
    bumpAnim.restart()
  }

  SequentialAnimation {
    id: bumpAnim
    NumberAnimation { target: root; property: "bump"; to: 1; duration: 55 * root.speed; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "bump"; to: -0.3; duration: 90 * root.speed; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "bump"; to: 0; duration: 90 * root.speed; easing.type: Easing.InOutQuad }
  }

  // Enter/Space: whatever the overlay's main button is.
  function activatePrimary() {
    if (endState === "won") keepGoingRequested()
    else if (endState === "over") newGameRequested()
  }

  Timer {
    id: dyingTimer
    interval: root.slideMs + root.popMs
    onTriggered: root.purgeDying()
  }

  // ---- background -----------------------------------------------------------

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Commons.Color.foreground, 0.06)
  }

  Repeater {
    model: root.size * root.size
    delegate: Rectangle {
      required property int index
      x: root.gap + (index % root.size) * (root.cell + root.gap)
      y: root.gap + Math.floor(index / root.size) * (root.cell + root.gap)
      width: root.cell
      height: root.cell
      radius: Style.cornerRadius
      color: Util.alpha(Commons.Color.foreground, 0.07)
    }
  }

  // ---- tiles ----------------------------------------------------------------

  Item {
    width: parent.width
    height: parent.height
    x: root.bump * root.bumpDx
    y: root.bump * root.bumpDy

    Repeater {
      model: tilesModel
      delegate: Tile {
        palette: root.palette
        paletteMode: root.paletteMode
        cell: root.cell
        gap: root.gap
        slideMs: root.slideMs
        popMs: root.popMs
        spawnMs: root.spawnMs
      }
    }
  }

  // ---- swipe input ----------------------------------------------------------

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    property point origin: Qt.point(0, 0)
    readonly property real threshold: Style.space(24) * Math.max(0.6, root.uiScale)

    onPressed: function(mouse) { origin = Qt.point(mouse.x, mouse.y) }
    onReleased: function(mouse) {
      var dx = mouse.x - origin.x
      var dy = mouse.y - origin.y
      if (Math.max(Math.abs(dx), Math.abs(dy)) < threshold) return
      if (Math.abs(dx) > Math.abs(dy)) root.swiped(dx > 0 ? 1 : 3)
      else root.swiped(dy > 0 ? 2 : 0)
    }
  }

  // ---- end-of-game overlay --------------------------------------------------

  // Latest non-empty state, so the text does not blank out while fading.
  property string shownState: ""
  property bool overlayOn: false

  onEndStateChanged: {
    if (endState === "") {
      overlayTimer.stop()
      overlayOn = false
    } else {
      shownState = endState
      overlayTimer.restart()
    }
  }

  Timer {
    id: overlayTimer
    interval: Style.duration(Math.round(250 * root.speed))
    onTriggered: root.overlayOn = root.endState !== ""
  }

  Rectangle {
    id: overlay
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Commons.Color.popups.background, 0.78)
    opacity: root.overlayOn ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(Math.round(300 * root.speed)); easing.type: Easing.OutCubic }
    }

    // Keep clicks and swipes from reaching the board underneath.
    MouseArea {
      anchors.fill: parent
      enabled: overlay.visible
      acceptedButtons: Qt.AllButtons
    }

    Column {
      anchors.centerIn: parent
      spacing: Math.round(Style.space(14) * Math.max(0.6, root.uiScale))

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.shownState === "won" ? "You win!" : "Game over!"
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.bold: true
        font.pixelSize: Math.round(Style.font.display * Math.max(0.6, root.uiScale))
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(Style.space(10) * Math.max(0.6, root.uiScale))

        OverlayButton {
          visible: root.shownState === "won"
          label: "Keep going"
          primary: true
          onActivated: root.keepGoingRequested()
        }

        OverlayButton {
          label: "Try again"
          primary: root.shownState !== "won"
          onActivated: root.newGameRequested()
        }
      }
    }
  }

  component OverlayButton: Rectangle {
    id: btn
    property string label: ""
    property bool primary: false
    signal activated()

    readonly property real k: Math.max(0.6, root.uiScale)

    implicitWidth: btnText.implicitWidth + Math.round(Style.space(24) * k)
    implicitHeight: btnText.implicitHeight + Math.round(Style.space(12) * k)
    radius: Style.cornerRadius
    color: primary
      ? Util.alpha(Commons.Color.accent, area.containsMouse ? 0.9 : 0.75)
      : Util.alpha(Commons.Color.foreground, area.containsMouse ? 0.18 : 0.1)

    Text {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      color: btn.primary ? Commons.Color.background : Commons.Color.foreground
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.round(Style.font.body * btn.k)
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }
}
