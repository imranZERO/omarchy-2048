.pragma library

// Lifetime numbers shown on the stats page. Pure functions over a plain object
// so they can be tested with node and saved as JSON.
//
//   games     games started (a game counts from its first move)
//   wins      games that reached the goal tile
//   moves     moves made
//   bestTile  largest tile ever built

function empty() {
  return { games: 0, wins: 0, moves: 0, bestTile: 0 }
}

function clean(raw) {
  var s = empty()
  if (!raw || typeof raw !== "object") return s
  var keys = Object.keys(s)
  for (var i = 0; i < keys.length; i++) {
    var n = Math.floor(Number(raw[keys[i]]))
    if (isFinite(n) && n > 0) s[keys[i]] = n
  }
  return s
}

// Call after a successful Game.move(). `game` is the state after the move.
function recordMove(stats, game, res) {
  stats.moves++
  if (game.moves === 1) stats.games++
  if (res.won) stats.wins++
  for (var i = 0; i < res.merges.length; i++)
    if (res.merges[i].value > stats.bestTile) stats.bestTile = res.merges[i].value
}

// Call when an undo steps from `before` back to `after` (both Game states).
// The best tile is left alone: it records what was built, not what survived.
function recordUndo(stats, before, after) {
  if (stats.moves > 0) stats.moves--
  if (before.moves === 1 && after.moves === 0 && stats.games > 0) stats.games--
  if (before.won && !after.won && stats.wins > 0) stats.wins--
}

function winRate(stats) {
  return stats.games > 0 ? Math.round(100 * stats.wins / stats.games) : 0
}

function averageMoves(stats) {
  return stats.games > 0 ? Math.round(stats.moves / stats.games) : 0
}
