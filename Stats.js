.pragma library

// Lifetime numbers shown on the stats page. Pure functions over a plain object
// so they can be tested with node and saved as JSON.
//
//   games     games started (a game counts from its first move)
//   wins      games that reached the goal tile
//   moves     moves made
//   bestTile  largest tile ever built
//   sizes     the same four numbers per mode and board size, keyed as saved games
//             are: "3" to "6" for Classic, "fibonacci-4", "evil-5", "daily-6" and
//             so on for the others. Counted from when each was added, so they
//             start at zero for older saves.
//
// The totals count every mode, except that a Fibonacci tile never sets the
// overall best tile: 2584 there is not comparable with a 2048 elsewhere.

var FIELDS = ["games", "wins", "moves", "bestTile"]

function counts() {
  return { games: 0, wins: 0, moves: 0, bestTile: 0 }
}

function empty() {
  var s = counts()
  s.sizes = {}
  return s
}

function cleanCounts(raw) {
  var c = counts()
  if (!raw || typeof raw !== "object") return c
  for (var i = 0; i < FIELDS.length; i++) {
    var n = Math.floor(Number(raw[FIELDS[i]]))
    if (isFinite(n) && n > 0) c[FIELDS[i]] = n
  }
  return c
}

var KEY = /^(?:(?:fibonacci|evil|daily)-)?[3-6]$/

function clean(raw) {
  var s = cleanCounts(raw)
  s.sizes = {}
  if (raw && raw.sizes && typeof raw.sizes === "object") {
    var keys = Object.keys(raw.sizes)
    for (var i = 0; i < keys.length; i++)
      if (KEY.test(keys[i])) s.sizes[keys[i]] = cleanCounts(raw.sizes[keys[i]])
  }
  return s
}

// The numbers for one mode and board size (a Game.slotKey), all zero when none
// were recorded.
function forSlot(stats, key) {
  return (stats.sizes && stats.sizes[key]) || counts()
}

function bucket(stats, key) {
  if (!stats.sizes) stats.sizes = {}
  if (!stats.sizes[key]) stats.sizes[key] = counts()
  return stats.sizes[key]
}

// Call after a successful Game.move(). `game` is the state after the move, and
// `key` its Game.slotKey.
function recordMove(stats, game, res, key) {
  var targets = [stats, bucket(stats, key)]
  for (var t = 0; t < targets.length; t++) {
    var c = targets[t]
    c.moves++
    if (game.moves === 1) c.games++
    if (res.won) c.wins++
    if (c === stats && game.mode === "Fibonacci") continue
    for (var i = 0; i < res.merges.length; i++)
      if (res.merges[i].value > c.bestTile) c.bestTile = res.merges[i].value
  }
}

// Call when an undo steps from `before` back to `after` (both Game states).
// The best tile is left alone: it records what was built, not what survived.
function recordUndo(stats, before, after, key) {
  var targets = [stats, bucket(stats, key)]
  for (var t = 0; t < targets.length; t++) {
    var c = targets[t]
    if (c.moves > 0) c.moves--
    if (before.moves === 1 && after.moves === 0 && c.games > 0) c.games--
    if (before.won && !after.won && c.wins > 0) c.wins--
  }
}

function winRate(stats) {
  return stats.games > 0 ? Math.round(100 * stats.wins / stats.games) : 0
}

function averageMoves(stats) {
  return stats.games > 0 ? Math.round(stats.moves / stats.games) : 0
}
