import QtQuick
import qs.Commons
import qs.Commons as Commons

// The bar icon: a small solid chip with 2048 cut out of it, short and wide so
// the digits stay legible at icon size. Set `tint` to the bar's icon color so it
// matches the icons around it.
Rectangle {
  id: root

  property color tint: Commons.Color.foreground

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

  width: Math.round(Style.bar.iconCanvas * 1.25)
  height: Math.round(Style.bar.iconCanvas * 0.75)
  // Follow the theme's rounding, but never so much that it stops looking like a tile.
  radius: Math.min(Math.round(height * 0.2), Math.max(2, Style.cornerRadius))
  color: tint

  // Whichever of the theme's two text colors reads better on the tile.
  readonly property color ink:
    contrast(color, Commons.Color.background) >= contrast(color, Commons.Color.foreground)
      ? Commons.Color.background : Commons.Color.foreground

  Text {
    anchors.centerIn: parent
    text: "2048"
    color: root.ink
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Math.round(root.height * 0.62)
  }
}
