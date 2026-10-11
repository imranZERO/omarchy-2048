.pragma library

// Digits in other writing systems. Only the ten digits are swapped, so "12,345"
// keeps its separators and "16K" keeps its K. Pure functions, no QML.
//
// Kanji is the positional form (2048 reads 二〇四八), not the counting form, so a
// number keeps one glyph per digit and fits a tile.

var SETS = {
  Western: "0123456789",
  Bengali: "০১২৩৪৫৬৭৮৯",
  Devanagari: "०१२३४५६७८९",
  Arabic: "٠١٢٣٤٥٦٧٨٩",
  Kanji: "〇一二三四五六七八九"
}

function valid(name) {
  return SETS[name] !== undefined
}

function convert(text, name) {
  var set = SETS[name]
  if (!set || name === "Western") return String(text)
  var out = ""
  var s = String(text)
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i) - 48
    out += c >= 0 && c <= 9 ? set[c] : s[i]
  }
  return out
}

// How wide one digit is, in ems, for fitting text to a tile. The CJK digits are
// full-width; the others are close to a Latin digit in the UI font.
function width(name) {
  return name === "Kanji" ? 1.0 : 0.62
}
