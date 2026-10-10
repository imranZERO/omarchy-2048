import QtQuick
import qs.Commons
import qs.Ui

// A square icon button for the header row. `glyph` is a Nerd Font code point;
// set tooltipText and onClicked where it is used.
Button {
  property int glyph: 0
  property real uiScale: 1.0

  readonly property real k: Math.max(0.6, uiScale)

  iconText: String.fromCodePoint(glyph)
  iconSize: Math.max(8, Math.round(Style.font.icon * k))
  // Borderless: it only shows a fill on hover, or while its page is open.
  bordered: false
  width: Math.round(Style.space(26) * k)
  height: width
}
