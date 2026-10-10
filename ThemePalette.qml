import QtQuick
import Quickshell.Io
import qs.Commons as Commons

// The active theme's hue palette, which the shell's Color singleton does not
// expose (it only keeps foreground, background, accent, urgent and muted).
// Reads theme/colors.toml directly and re-reads it when the theme changes.
//
// Themes name their hues either by role (red, orange, ...) or ANSI slot
// (color1 ... color6), so both are accepted. Anything the theme lacks is
// derived from its accent by rotating the hue.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  // Warm to cool, one per tile level from 8 up to 512.
  property var ramp: derivedRamp()
  // Hue for each step, left to right.
  readonly property var hues: ["yellow", "orange", "red", "magenta", "blue", "cyan", "green"]
  // Where each hue lives in an ANSI-style colors.toml.
  readonly property var ansi: ({ red: "color1", green: "color2", yellow: "color3", blue: "color4", magenta: "color5", cyan: "color6" })
  // Approximate hue (0..1) for deriving a missing color from the accent.
  readonly property var hueAngle: ({ red: 0.0, orange: 0.07, yellow: 0.14, green: 0.33, cyan: 0.5, blue: 0.6, magenta: 0.85 })

  function derivedColor(name) {
    var a = Commons.Color.accent
    var s = Math.max(0.45, a.hslSaturation)
    var l = Math.min(0.62, Math.max(0.42, a.hslLightness))
    return Qt.hsla(hueAngle[name], s, l, 1)
  }

  function derivedRamp() {
    var out = []
    for (var i = 0; i < hues.length; i++) out.push(derivedColor(hues[i]))
    return out
  }

  function parse(raw) {
    var found = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) found[m[1]] = m[2]
    }

    var next = []
    for (var h = 0; h < hues.length; h++) {
      var name = hues[h]
      var hex = found[name] || (ansi[name] ? found[ansi[name]] : undefined)
      if (hex) next.push(hex)
      else if (name === "orange" && (found.red || found.color1) && (found.yellow || found.color3))
        next.push(mix(found.red || found.color1, found.yellow || found.color3))
      else next.push(derivedColor(name))
    }
    ramp = next
  }

  function mix(a, b) {
    var ca = Qt.color(a)
    var cb = Qt.color(b)
    return Qt.rgba((ca.r + cb.r) / 2, (ca.g + cb.g) / 2, (ca.b + cb.b) / 2, 1)
  }

  FileView {
    id: colorsFile
    path: Commons.Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.parse(text())
    onLoadFailed: root.ramp = root.derivedRamp()
  }

  // The shell is told about a theme switch by IPC, not by a file watch, so key
  // off the colors it already tracks. Wait a beat for the new files to land.
  Timer {
    id: reloadTimer
    interval: 250
    onTriggered: colorsFile.reload()
  }

  Connections {
    target: Commons.Color
    function onAccentChanged() { reloadTimer.restart() }
    function onBackgroundChanged() { reloadTimer.restart() }
    function onForegroundChanged() { reloadTimer.restart() }
  }
}
