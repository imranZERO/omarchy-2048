import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Numerals.js" as Numerals

// One board tile. Position comes from col/row and is animated by the Behaviors
// below, so moving a tile is just changing those two numbers. New tiles play
// their entrance (spawn / merge pop / undo fade) once, when they are created.
Item {
  id: root

  required property int value
  required property int col
  required property int row
  required property string kind     // "static" | "spawn" | "merge" | "restore"
  required property bool dying      // sliding into a merge, about to be removed
  required property int fx          // 0 none, 1 glow ring, 2 double ring (new best tile)

  property int cell: 64
  property int gap: 10
  property int slideMs: 110
  property int popMs: 200
  property int spawnMs: 200
  // "Theme", "Classic" or "Mono"
  property string paletteMode: "Theme"
  // The digits the value is drawn with; see Numerals.js.
  property string numerals: "Western"
  // The theme's hue palette (a ThemePalette), set by Board.
  property var palette: null

  x: gap + col * (cell + gap)
  y: gap + row * (cell + gap)
  width: cell
  height: cell
  z: dying ? 0 : (kind === "merge" ? 2 : 1)

  // Squash and stretch: how far the tile still has to go, so it is longest at the
  // start of a slide and relaxes as it lands. Derived from the position the
  // Behaviors below are animating, so it costs no animation object of its own.
  readonly property real remainX: Math.abs(x - (gap + col * (cell + gap)))
  readonly property real remainY: Math.abs(y - (gap + row * (cell + gap)))
  readonly property real stretch: Math.min(1, Math.max(remainX, remainY) / (cell + gap))
  readonly property bool stretchH: remainX >= remainY

  // A blocked move: 0 rests, 1 is the full nudge toward (nudgeDx, nudgeDy).
  property real nudge: 0
  property real nudgeDx: 0
  property real nudgeDy: 0
  property var nudgeAnim: null

  transform: Translate { x: root.nudge * root.nudgeDx; y: root.nudge * root.nudgeDy }

  // Called by Board for a move that did nothing. Tiles nearest the wall react
  // first, so the nudge travels back across the board.
  function nudgeToward(dx, dy, delay) {
    nudgeDx = dx
    nudgeDy = dy
    if (!nudgeAnim) nudgeAnim = nudgeComp.createObject(root)
    nudgeAnim.delay = delay
    nudgeAnim.restart()
  }

  // Animations are made when a tile needs them and destroy themselves when they
  // stop. A tile is created on most moves and most never use most of these, so
  // building all of them up front was a measurable share of a move's cost.
  Component {
    id: nudgeComp
    SequentialAnimation {
      property alias delay: nudgeDelay.duration
      PauseAnimation { id: nudgeDelay }
      NumberAnimation { target: root; property: "nudge"; to: 1; duration: root.popMs * 0.275; easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "nudge"; to: -0.3; duration: root.popMs * 0.45; easing.type: Easing.InOutQuad }
      NumberAnimation { target: root; property: "nudge"; to: 0; duration: root.popMs * 0.45; easing.type: Easing.InOutQuad }
    }
  }

  Behavior on x { NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }
  Behavior on y { NumberAnimation { duration: root.slideMs; easing.type: Easing.OutCubic } }

  // ---- colors ---------------------------------------------------------------

  function channel(c) {
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
  }

  function luminance(c) {
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
  }

  function contrast(a, b) {
    var la = luminance(a)
    var lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  readonly property int level: Math.round(Math.log(value) / Math.LN2)

  // Five digits do not fit a small cell, so 16384 and up read as 16K, 32K, 64K, 128K.
  readonly property string label: Numerals.convert(value >= 16384 ? (value / 1024) + "K" : String(value), numerals)

  readonly property var classicFills: ({
    1: "#eee4da", 2: "#ede0c8", 3: "#f2b179", 4: "#f59563", 5: "#f67c5f", 6: "#f65e3b",
    7: "#edcf72", 8: "#edcc61", 9: "#edc850", 10: "#edc53f", 11: "#edc22e"
  })

  // Theme: 2 and 4 are neutral washes, 8 to 512 walk the theme's hues warm to
  // cool, 1024 is a deepened accent, 2048 flips to the foreground with an
  // accent outline, anything higher is urgent with a foreground outline.
  function themeFill() {
    var bg = Commons.Color.popups.background
    if (level <= 1) return Qt.tint(bg, Util.alpha(Commons.Color.foreground, 0.12))
    if (level === 2) return Qt.tint(bg, Util.alpha(Commons.Color.foreground, 0.22))
    if (level <= 9) {
      var ramp = palette ? palette.ramp : null
      var hue = ramp && ramp[level - 3] !== undefined ? ramp[level - 3] : Commons.Color.accent
      return Qt.tint(bg, Util.alpha(hue, 0.92))
    }
    if (level === 10) return Qt.tint(Commons.Color.accent, Util.alpha(Commons.Color.foreground, 0.45))
    if (level === 11) return Commons.Color.foreground
    return Commons.Color.urgent
  }

  // Mono: one hue, the accent, getting stronger with every doubling.
  function monoFill() {
    var t = Math.min(1, (level - 1) / 10)
    var base = Qt.tint(Commons.Color.popups.background, Util.alpha(Commons.Color.accent, 0.15 + 0.85 * t))
    if (level > 11) return Qt.tint(base, Util.alpha(Commons.Color.urgent, 0.6))
    return base
  }

  function classicFill() {
    return level > 11 ? "#3c3a32" : (classicFills[level] || "#3c3a32")
  }

  readonly property color fillColor:
    paletteMode === "Classic" ? classicFill()
      : paletteMode === "Mono" ? monoFill()
      : themeFill()

  readonly property color textColor: {
    if (paletteMode === "Classic") return level <= 2 ? "#776e65" : "#f9f6f2"
    return contrast(fillColor, Commons.Color.foreground) >= contrast(fillColor, Commons.Color.background)
      ? Commons.Color.foreground : Commons.Color.background
  }

  readonly property bool outlined: paletteMode !== "Classic" && level >= 11
  readonly property color outlineColor:
    paletteMode === "Theme" && level === 11 ? Commons.Color.accent : Commons.Color.foreground

  // ---- visuals --------------------------------------------------------------

  Rectangle {
    id: face
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.fillColor
    border.width: root.outlined ? Math.max(1, Math.round(root.cell * 0.04)) : 0
    border.color: root.outlineColor
    transformOrigin: Item.Center
    transform: Scale {
      origin.x: face.width / 2
      origin.y: face.height / 2
      xScale: 1 + (root.stretchH ? 0.12 : -0.06) * root.stretch
      yScale: 1 + (root.stretchH ? -0.06 : 0.12) * root.stretch
    }
    scale: root.kind === "spawn" || root.kind === "merge" ? 0 : 1
    opacity: 1

    Text {
      anchors.centerIn: parent
      text: root.label
      color: root.textColor
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: {
        var n = root.label.length
        var f = n <= 2 ? 0.45 : n === 3 ? 0.38 : n === 4 ? 0.30 : 0.24
        // The usual size, unless the label would be wider than the tile.
        var fit = 0.86 / (n * Numerals.width(root.numerals))
        return Math.max(8, Math.round(root.cell * Math.min(f, fit)))
      }
    }
  }

  // New tile: wait for the slide to land, then scale in.
  Component {
    id: spawnComp
    SequentialAnimation {
      running: true
      onStopped: destroy()
      PauseAnimation { duration: root.slideMs }
      NumberAnimation {
        target: face; property: "scale"; from: 0; to: 1
        duration: root.spawnMs; easing.type: Easing.OutBack
      }
    }
  }

  // Merge result: wait for the slide, overshoot to 1.2, settle at 1.
  Component {
    id: popComp
    SequentialAnimation {
      running: true
      onStopped: destroy()
      PauseAnimation { duration: root.slideMs }
      NumberAnimation {
        target: face; property: "scale"; from: 0; to: 1.2
        duration: root.popMs * 0.5; easing.type: Easing.OutQuad
      }
      NumberAnimation {
        target: face; property: "scale"; to: 1
        duration: root.popMs * 0.5; easing.type: Easing.InOutQuad
      }
    }
  }

  // A white flash as the merged tile pops, fading as it settles.
  Component {
    id: flashComp
    Rectangle {
      id: flash
      anchors.fill: parent
      radius: face.radius
      color: "white"
      opacity: 0
      SequentialAnimation {
        running: true
        onStopped: flash.destroy()
        PauseAnimation { duration: root.slideMs }
        NumberAnimation { target: flash; property: "opacity"; from: 0.4; to: 0; duration: root.popMs * 1.2; easing.type: Easing.OutQuad }
      }
    }
  }

  // An expanding ring for a big merge, drawn behind the face so it reads as a
  // pulse leaving the tile.
  Component {
    id: ringComp
    Rectangle {
      id: ring
      property real delayMs: 0
      property real grow: 1.7
      property real startOpacity: 0.9
      property real thickness: 0.045
      property real lifeMs: 480
      z: -1
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "transparent"
      border.width: Math.max(2, Math.round(root.cell * thickness))
      border.color: root.fillColor
      opacity: 0
      transformOrigin: Item.Center
      SequentialAnimation {
        running: true
        onStopped: ring.destroy()
        PauseAnimation { duration: ring.delayMs }
        ParallelAnimation {
          NumberAnimation { target: ring; property: "scale"; from: 1; to: ring.grow; duration: ring.lifeMs; easing.type: Easing.OutCubic }
          NumberAnimation { target: ring; property: "opacity"; from: ring.startOpacity; to: 0; duration: ring.lifeMs; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  // 2048 glows in the accent (the Classic palette's gold), bigger tiles in their own color.
  readonly property color glowColor: paletteMode === "Classic" ? "#edc22e" : level === 11 ? Commons.Color.accent : fillColor

  // A soft halo for 2048 and up: two stacked outlines of falling opacity, which
  // reads as a glow without a blur. Made once, only for tiles that earn it.
  Component {
    id: glowComp
    Item {
      anchors.fill: parent
      z: -2
      Repeater {
        model: [{ s: 1.1, a: 0.07 }, { s: 1.045, a: 0.14 }]
        delegate: Rectangle {
          required property var modelData
          anchors.fill: parent
          scale: modelData.s
          radius: Style.cornerRadius
          color: Util.alpha(root.glowColor, modelData.a)
        }
      }
    }
  }

  // Merge source: slide into the target cell, then fade away under the pop.
  Component {
    id: dyingComp
    SequentialAnimation {
      running: true
      onStopped: destroy()
      PauseAnimation { duration: root.slideMs * 0.8 }
      NumberAnimation {
        target: face; property: "opacity"; to: 0
        duration: root.popMs * 0.6; easing.type: Easing.OutQuad
      }
    }
  }

  // Tile put back by undo: a quick fade and scale-up so the board does not just snap.
  Component {
    id: restoreComp
    ParallelAnimation {
      running: true
      onStopped: destroy()
      NumberAnimation {
        target: face; property: "opacity"; from: 0.25; to: 1
        duration: root.popMs * 0.8; easing.type: Easing.OutQuad
      }
      NumberAnimation {
        target: face; property: "scale"; from: 0.85; to: 1
        duration: root.popMs * 0.8; easing.type: Easing.OutBack
      }
    }
  }

  onDyingChanged: if (dying) dyingComp.createObject(root)

  Component.onCompleted: {
    if (level >= 11) glowComp.createObject(face)
    if (kind === "spawn") spawnComp.createObject(root)
    else if (kind === "merge") {
      popComp.createObject(root)
      if (popMs > 0) {
        flashComp.createObject(face)
        if (fx > 0) ringComp.createObject(root, { delayMs: slideMs + popMs * 0.3, lifeMs: popMs * 2.4 })
        if (fx > 1) ringComp.createObject(root, {
          delayMs: slideMs + popMs * 0.9, grow: 2.2, startOpacity: 0.7, thickness: 0.035, lifeMs: popMs * 2.6
        })
      }
    } else if (kind === "restore") restoreComp.createObject(root)
  }
}
