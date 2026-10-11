pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import "Numerals.js" as Numerals

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
  // The digits numbers are drawn with; see Numerals.js.
  property string numerals: "Western"
  // The theme's hue palette (a ThemePalette), handed to each tile.
  property var palette: null

  // Bigger boards get smaller cells so the window does not balloon.
  readonly property var cellBase: ({ 3: 88, 4: 64, 5: 54, 6: 46 })
  readonly property var gapBase: ({ 3: 10, 4: 10, 5: 8, 6: 8 })
  readonly property int cell: Math.max(16, Math.round(Style.space(cellBase[size] || 64) * uiScale))
  readonly property int gap: Math.max(3, Math.round(Style.space(gapBase[size] || 10) * uiScale))
  readonly property real k: Math.max(0.6, uiScale)
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
    thumpAnim.stop()
    thumpScale = 1
    burstAnim.stop()
    burst.running = false
    comboAnim.stop()
    comboBadge.opacity = 0
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

    // Big merges make the whole board thump as the tile lands.
    var thump = 0
    for (i = 0; i < res.merges.length; i++) {
      if (res.merges[i].value >= 128) thump = Math.max(thump, res.merges[i].newMax ? 0.03 : 0.015)
    }
    if (thump > 0) thumpBoard(thump)

    // The move that reached the goal: confetti from the tile that did it.
    if (res.won) {
      var top = res.merges[0]
      for (i = 1; i < res.merges.length; i++) if (res.merges[i].value > top.value) top = res.merges[i]
      celebrate(top.x, top.y)
    }

    if (res.spawned) {
      var s = res.spawned
      tilesModel.append({ tid: s.id, value: s.value, col: s.x, row: s.y, kind: "spawn", dying: false, fx: 0 })
    }

    dyingTimer.restart()
  }

  // A move that did nothing: nudge the tiles toward `dir` and let them spring
  // back, like pushing against a wall. The ones at the wall go first.
  function bumpToward(dir) {
    if (speed <= 0 || Style.duration(1) === 0) return
    var d = Math.max(3, Math.round(cell * 0.12))
    var dx = dir === 1 ? d : dir === 3 ? -d : 0
    var dy = dir === 2 ? d : dir === 0 ? -d : 0
    for (var i = 0; i < tilesModel.count; i++) {
      var item = tileRepeater.itemAt(i)
      if (!item) continue
      var rank = dir === 1 ? size - 1 - item.col : dir === 3 ? item.col
        : dir === 2 ? size - 1 - item.row : item.row
      item.nudgeToward(dx, dy, Math.round(rank * 28 * speed))
    }
  }

  property real thumpScale: 1

  function thumpBoard(amount) {
    if (speed <= 0 || Style.duration(1) === 0) return
    thumpTo = 1 + amount
    thumpAnim.restart()
  }

  property real thumpTo: 1.015

  SequentialAnimation {
    id: thumpAnim
    PauseAnimation { duration: root.slideMs }
    NumberAnimation { target: root; property: "thumpScale"; to: root.thumpTo; duration: 70 * root.speed; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "thumpScale"; to: 1; duration: 200 * root.speed; easing.type: Easing.OutBack }
  }

  // ---- combo badge ----------------------------------------------------------

  // A badge on the board's top edge for a streak of scoring moves.
  function showCombo(n) {
    if (speed <= 0 || Style.duration(1) === 0) return
    comboText.text = "COMBO ×" + Numerals.convert(n, numerals)
    comboAnim.restart()
  }

  Rectangle {
    id: comboBadge
    z: 5
    anchors.horizontalCenter: parent.horizontalCenter
    y: -Math.round(height * 0.55)
    width: comboText.implicitWidth + Math.round(Style.space(14) * root.k)
    height: comboText.implicitHeight + Math.round(Style.space(6) * root.k)
    radius: height / 2
    color: Commons.Color.accent
    opacity: 0
    visible: opacity > 0
    transformOrigin: Item.Center

    Text {
      id: comboText
      anchors.centerIn: parent
      color: Commons.Color.background
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Math.round(Style.font.caption * root.k)
    }
  }

  SequentialAnimation {
    id: comboAnim
    ScriptAction { script: { comboBadge.opacity = 1; comboBadge.scale = 0.6 } }
    NumberAnimation { target: comboBadge; property: "scale"; to: 1.18; duration: 90 * root.speed; easing.type: Easing.OutQuad }
    NumberAnimation { target: comboBadge; property: "scale"; to: 1; duration: 140 * root.speed; easing.type: Easing.OutBack }
    PauseAnimation { duration: 650 * root.speed }
    NumberAnimation { target: comboBadge; property: "opacity"; to: 0; duration: 250 * root.speed }
  }

  // ---- win confetti ----------------------------------------------------------

  // A burst of small squares from the cell (col, row). One animated number drives
  // every piece along its own arc, so the cost is the pieces being drawn for
  // about a second, once per game.
  function celebrate(col, row) {
    if (speed <= 0 || Style.duration(1) === 0) return
    burst.ox = gap + col * (cell + gap) + cell / 2
    burst.oy = gap + row * (cell + gap) + cell / 2
    burstAnim.restart()
  }

  Item {
    id: burst
    z: 4
    property real ox: 0
    property real oy: 0
    // 0 to 1 over the burst; the pieces exist only while it runs.
    property real t: 0
    property bool running: false
    readonly property var colors: {
      var c = [Commons.Color.accent, Commons.Color.urgent, Commons.Color.foreground]
      var ramp = root.palette ? root.palette.ramp : null
      return ramp ? c.concat(ramp) : c
    }

    Repeater {
      model: burst.running ? 28 : 0
      delegate: Rectangle {
        id: piece
        required property int index
        // Spread by the golden angle, so any count fans out evenly.
        readonly property real angle: index * 2.399963
        readonly property real fling: root.cell * (1.6 + 1.8 * ((index * 0.618) % 1))
        readonly property real sz: Math.max(3, Math.round(root.cell * (0.08 + 0.07 * ((index * 0.37) % 1))))
        width: sz
        height: sz
        radius: index % 3 === 0 ? sz / 2 : 1
        color: burst.colors[index % burst.colors.length]
        x: burst.ox + Math.cos(angle) * fling * burst.t - sz / 2
        y: burst.oy + Math.sin(angle) * fling * burst.t + root.cell * 2.2 * burst.t * burst.t - sz / 2
        rotation: index * 37 + burst.t * 300 * (index % 2 ? 1 : -1)
        opacity: 1 - burst.t * burst.t * burst.t
      }
    }
  }

  SequentialAnimation {
    id: burstAnim
    // Let the tile land first.
    PauseAnimation { duration: root.slideMs + root.popMs * 0.4 }
    ScriptAction { script: { burst.t = 0; burst.running = true } }
    NumberAnimation { target: burst; property: "t"; from: 0; to: 1; duration: 1100 * root.speed; easing.type: Easing.OutQuad }
    ScriptAction { script: burst.running = false }
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
    scale: root.thumpScale

    // After a game over the board goes grey and dim behind the overlay. The layer
    // exists only while that is showing, so play never pays for it.
    layer.enabled: root.overlayOn && root.shownState === "over"
    layer.effect: MultiEffect {
      saturation: -0.85
      brightness: -0.08
    }

    Repeater {
      id: tileRepeater
      model: tilesModel
      delegate: Tile {
        palette: root.palette
        paletteMode: root.paletteMode
        numerals: root.numerals
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

  // What the overlay reports; Panel sets these when a game ends or is won.
  property int endScore: 0
  property int endMoves: 0
  property int endTile: 0
  property bool endBest: false
  // The score counting up to endScore while the overlay opens.
  property real shownScore: 0

  function num(n) { return Numerals.convert(Number(n).toLocaleString(Qt.locale(), "f", 0), numerals) }

  onOverlayOnChanged: {
    if (!overlayOn) return
    if (speed <= 0 || Style.duration(1) === 0) { shownScore = endScore; return }
    countAnim.restart()
  }

  NumberAnimation {
    id: countAnim
    target: root
    property: "shownScore"
    from: 0
    to: root.endScore
    duration: 750 * root.speed
    easing.type: Easing.OutCubic
  }

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
    color: Util.alpha(Commons.Color.popups.background, 0.92)
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
      scale: root.overlayOn ? 1 : 0.85
      Behavior on scale {
        NumberAnimation { duration: Style.duration(Math.round(350 * root.speed)); easing.type: Easing.OutBack }
      }
      spacing: Math.round(Style.space(14) * Math.max(0.6, root.uiScale))

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.shownState === "won" ? "You win!" : "Game over"
        color: Util.alpha(Commons.Color.foreground, 0.8)
        font.family: Style.font.family
        font.bold: true
        font.letterSpacing: 1
        font.capitalization: Font.AllUppercase
        font.pixelSize: Math.round(Style.font.body * Math.max(0.6, root.uiScale))
      }

      // The score, counting up, and what it took.
      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(Style.space(2) * Math.max(0.6, root.uiScale))

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.num(Math.round(root.shownScore))
          color: Commons.Color.accent
          font.family: Style.font.family
          font.bold: true
          font.pixelSize: Math.round(Style.font.display * 1.7 * Math.max(0.6, root.uiScale))
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "points in " + root.num(root.endMoves) + (root.endMoves === 1 ? " move" : " moves")
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Math.round(Style.font.body * Math.max(0.6, root.uiScale))
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(Style.space(6) * Math.max(0.6, root.uiScale))

        Rectangle {
          visible: root.endTile > 0
          implicitWidth: tileChip.implicitWidth + Math.round(Style.space(14) * Math.max(0.6, root.uiScale))
          implicitHeight: tileChip.implicitHeight + Math.round(Style.space(6) * Math.max(0.6, root.uiScale))
          width: implicitWidth
          height: implicitHeight
          radius: height / 2
          color: Util.alpha(Commons.Color.foreground, 0.14)
          border.width: 1
          border.color: Util.alpha(Commons.Color.foreground, 0.3)

          Text {
            id: tileChip
            anchors.centerIn: parent
            text: "Best tile " + root.endTile
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.caption * Math.max(0.6, root.uiScale))
          }
        }

        Rectangle {
          visible: root.endBest
          implicitWidth: bestChip.implicitWidth + Math.round(Style.space(14) * Math.max(0.6, root.uiScale))
          implicitHeight: bestChip.implicitHeight + Math.round(Style.space(6) * Math.max(0.6, root.uiScale))
          width: implicitWidth
          height: implicitHeight
          radius: height / 2
          color: Commons.Color.accent

          Text {
            id: bestChip
            anchors.centerIn: parent
            text: "New best!"
            color: Commons.Color.background
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Math.round(Style.font.caption * Math.max(0.6, root.uiScale))
          }
        }
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

    implicitWidth: btnText.implicitWidth + Math.round(Style.space(32) * k)
    implicitHeight: btnText.implicitHeight + Math.round(Style.space(16) * k)
    radius: Style.cornerRadius
    scale: area.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutQuad } }
    // Solid fills, so the labels stay readable over whatever is behind the overlay.
    color: primary
      ? (area.containsMouse ? Qt.lighter(Commons.Color.accent, 1.15) : Commons.Color.accent)
      : Util.alpha(Commons.Color.foreground, area.containsMouse ? 0.24 : 0.16)
    border.width: primary ? 0 : 1
    border.color: Util.alpha(Commons.Color.foreground, 0.35)

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
