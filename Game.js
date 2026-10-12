.pragma library

// Pure 2048 rules, ported from gabrielecirulli/2048 (game_manager.js, grid.js,
// tile.js). No QML dependencies, so it can be tested with plain node.
//
// Coordinates follow the original: cells[x][y], x is the column and y the row.
// Tiles carry stable ids so the view can animate a tile instead of redrawing it.
// Directions: 0 up, 1 right, 2 down, 3 left.
//
// Modes:
//   Classic    the original
//   Fibonacci  tiles are 1, 2, 3, 5, 8, ... and two neighbours in the sequence
//              merge (3 + 5 = 8; 1 + 1 = 2)
//   Evil       each new tile lands where it leaves the player's best next move worst
//   Daily      Classic from a seed made of the date and board size, so everyone
//              gets the same game that day

var VECTORS = [
  { x: 0, y: -1 },
  { x: 1, y: 0 },
  { x: 0, y: 1 },
  { x: -1, y: 0 }
]

var MODES = ["Classic", "Fibonacci", "Evil", "Daily"]

function cleanMode(mode) {
  return MODES.indexOf(mode) >= 0 ? mode : "Classic"
}

// Where a mode's game and best score are kept, by board size. Classic uses the
// bare size, as saves from before modes existed do.
function slotKey(mode, size) {
  return mode === "Classic" ? String(size) : mode.toLowerCase() + "-" + size
}

// 1, 2, 3, 5, 8, ... up past anything a board can hold.
var FIB = [1, 2]
while (FIB[FIB.length - 1] < 1e8) FIB.push(FIB[FIB.length - 1] + FIB[FIB.length - 2])

function emptyCells(size) {
  var cells = []
  for (var x = 0; x < size; x++) {
    var column = []
    for (var y = 0; y < size; y++) column.push(null)
    cells.push(column)
  }
  return cells
}

var MIN_SIZE = 3
var MAX_SIZE = 6

// The tile that wins the game. Smaller boards cannot reach 2048, bigger ones
// reach it too easily, so the target scales with the board.
function goalFor(size, mode) {
  // Random play wins 4181 on 5x5 and 6765 on 6x6, so those boards aim higher.
  if (mode === "Fibonacci") return { 3: 144, 4: 2584, 5: 10946, 6: 17711 }[size] || 2584
  return { 3: 256, 4: 2048, 5: 4096, 6: 8192 }[size] || 2048
}

// How far up the scale a tile is, for colours, effects and sound: 1 for the
// smallest tile, 11 for the goal on a 4x4 Classic board. Fibonacci's longer
// sequence is scaled to reach 11 at its goal too, so both look and sound alike.
function levelOf(value, mode, size) {
  if (mode === "Fibonacci") {
    var i = FIB.indexOf(value)
    var g = FIB.indexOf(goalFor(size, mode))
    return i < 0 ? 1 : 1 + Math.round(i * 10 / g)
  }
  return Math.max(1, Math.round(Math.log(value) / Math.LN2))
}

function canMerge(mode, a, b) {
  if (mode !== "Fibonacci") return a === b
  if (a === 1 && b === 1) return true
  var i = FIB.indexOf(a)
  var j = FIB.indexOf(b)
  return i >= 0 && j >= 0 && Math.abs(i - j) === 1
}

function validValue(mode, v) {
  if (mode === "Fibonacci") return FIB.indexOf(v) >= 0
  return v >= 2 && (v & (v - 1)) === 0
}

function clampSize(size) {
  var n = Math.round(Number(size))
  if (!isFinite(n)) return 4
  return Math.max(MIN_SIZE, Math.min(MAX_SIZE, n))
}

function newState(size, mode) {
  return {
    size: size,
    mode: mode,
    goal: goalFor(size, mode),
    cells: emptyCells(size),
    score: 0,
    moves: 0,
    over: false,
    won: false,
    keepPlaying: false,
    nextId: 1,
    // Daily only: the date it is for, and the seeded generator's state, saved
    // with the game so a resumed (or undone) game carries on the same way.
    day: "",
    rng: null
  }
}

// A number in [0, 1): from the game's own seeded generator (mulberry32) when it
// has one, so a Daily game is the same for everyone, otherwise Math.random.
function random(state) {
  if (typeof state.rng !== "number") return Math.random()
  var t = (state.rng + 0x6D2B79F5) | 0
  state.rng = t
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

// FNV-1a, for turning a date and size into a seed.
function hash(text) {
  var h = 0x811c9dc5
  for (var i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h | 0
}

// Largest tile currently on the board. Tiles only ever grow by merging, so
// this is also the largest tile of the whole game.
function maxTile(state) {
  var best = 0
  for (var x = 0; x < state.size; x++)
    for (var y = 0; y < state.size; y++) {
      var t = state.cells[x][y]
      if (t && t.value > best) best = t.value
    }
  return best
}

function makeTile(state, x, y, value) {
  return { id: state.nextId++, value: value, x: x, y: y, merged: false }
}

function availableCells(state) {
  var list = []
  for (var x = 0; x < state.size; x++)
    for (var y = 0; y < state.size; y++)
      if (!state.cells[x][y]) list.push({ x: x, y: y })
  return list
}

// The two values a new tile can have: the smaller 90% of the time.
function spawnValues(mode) {
  return mode === "Fibonacci" ? [1, 2] : [2, 4]
}

// ---- Evil ------------------------------------------------------------------
// The board as plain values, for trying moves without touching the game.

function valueGrid(state) {
  var g = []
  for (var x = 0; x < state.size; x++) {
    var column = []
    for (var y = 0; y < state.size; y++) column.push(state.cells[x][y] ? state.cells[x][y].value : 0)
    g.push(column)
  }
  return g
}

// Slides a value grid like move() does. Returns the new grid, or null if
// nothing moved.
function slideGrid(g, size, dir, mode) {
  var v = VECTORS[dir]
  var out = []
  var merged = []
  for (var x = 0; x < size; x++) { out.push(g[x].slice()); merged.push([]) }
  var moved = false
  for (var i = 0; i < size; i++) {
    for (var j = 0; j < size; j++) {
      var cx = v.x === 1 ? size - 1 - i : i
      var cy = v.y === 1 ? size - 1 - j : j
      var value = out[cx][cy]
      if (!value) continue
      var fx = cx, fy = cy
      var nx = cx + v.x, ny = cy + v.y
      while (nx >= 0 && nx < size && ny >= 0 && ny < size && !out[nx][ny]) {
        fx = nx; fy = ny
        nx += v.x; ny += v.y
      }
      var inside = nx >= 0 && nx < size && ny >= 0 && ny < size
      if (inside && !merged[nx][ny] && canMerge(mode, value, out[nx][ny])) {
        out[nx][ny] += value
        merged[nx][ny] = true
        out[cx][cy] = 0
        moved = true
      } else if (fx !== cx || fy !== cy) {
        out[fx][fy] = value
        out[cx][cy] = 0
        moved = true
      }
    }
  }
  return moved ? out : null
}

// How good a position is for the player: room to move, and pairs ready to merge.
function openness(g, size, mode) {
  var score = 0
  for (var x = 0; x < size; x++)
    for (var y = 0; y < size; y++) {
      if (!g[x][y]) { score += 1; continue }
      if (x + 1 < size && g[x + 1][y] && canMerge(mode, g[x][y], g[x + 1][y])) score += 0.5
      if (y + 1 < size && g[x][y + 1] && canMerge(mode, g[x][y], g[x][y + 1])) score += 0.5
    }
  return score
}

// The cell and value for a new tile that leaves the player's best reply worst.
function evilSpawn(state, free) {
  var size = state.size
  var g = valueGrid(state)
  var values = spawnValues(state.mode)
  var worst = Infinity
  var picks = []
  for (var i = 0; i < free.length; i++) {
    for (var k = 0; k < values.length; k++) {
      var c = free[i]
      g[c.x][c.y] = values[k]
      var best = -1
      for (var d = 0; d < 4; d++) {
        var after = slideGrid(g, size, d, state.mode)
        if (after) best = Math.max(best, openness(after, size, state.mode))
      }
      g[c.x][c.y] = 0
      if (best < worst) { worst = best; picks = [] }
      if (best === worst) picks.push({ x: c.x, y: c.y, value: values[k] })
    }
  }
  return picks[Math.floor(Math.random() * picks.length)]
}

// ----------------------------------------------------------------------------

// Drops a new tile on a free cell: random (90% the smaller value), or the
// cruellest one in Evil. Returns the new tile or null.
function addRandomTile(state, plain) {
  var free = availableCells(state)
  if (free.length === 0) return null
  var pick
  if (state.mode === "Evil" && !plain) {
    pick = evilSpawn(state, free)
  } else {
    var cell = free[Math.floor(random(state) * free.length)]
    var values = spawnValues(state.mode)
    pick = { x: cell.x, y: cell.y, value: random(state) < 0.9 ? values[0] : values[1] }
  }
  var tile = makeTile(state, pick.x, pick.y, pick.value)
  state.cells[pick.x][pick.y] = tile
  return tile
}

// `day` (YYYY-MM-DD) is needed for Daily, to seed it.
function newGame(size, mode, day) {
  mode = cleanMode(mode)
  var state = newState(clampSize(size || 4), mode)
  if (mode === "Daily") {
    state.day = String(day || "")
    state.rng = hash(state.day + ":" + state.size)
  }
  // The opening two are random even in Evil, so it is not lost from the start.
  addRandomTile(state, true)
  addRandomTile(state, true)
  return state
}

function isTerminated(state) {
  return state.over || (state.won && !state.keepPlaying)
}

function withinBounds(state, x, y) {
  return x >= 0 && x < state.size && y >= 0 && y < state.size
}

function tileMatchesAvailable(state) {
  for (var x = 0; x < state.size; x++) {
    for (var y = 0; y < state.size; y++) {
      var tile = state.cells[x][y]
      if (!tile) continue
      for (var d = 0; d < 4; d++) {
        var nx = x + VECTORS[d].x
        var ny = y + VECTORS[d].y
        if (!withinBounds(state, nx, ny)) continue
        var other = state.cells[nx][ny]
        if (other && canMerge(state.mode, other.value, tile.value)) return true
      }
    }
  }
  return false
}

function movesAvailable(state) {
  return availableCells(state).length > 0 || tileMatchesAvailable(state)
}

// Slides every tile as far as it goes, merging neighbours once per move.
// Mutates `state` and returns what the view needs to animate it:
//   moved       false when nothing changed (no spawn, no score)
//   scoreDelta  points gained by this move
//   moves       [{id, x, y}]  surviving tiles that slid to a new cell
//   merges      [{fromIds:[a, b], id, value, x, y, newMax}]  a and b slide into
//               (x, y) and die; a fresh tile `id` takes their place. newMax is
//               true when it is bigger than any tile so far this game.
//   spawned     {id, value, x, y} or null
//   won / over  true only on the move that triggered it
function move(state, dir) {
  var result = { moved: false, scoreDelta: 0, moves: [], merges: [], spawned: null, won: false, over: false }
  if (isTerminated(state)) return result

  var highest = maxTile(state)

  var vector = VECTORS[dir]
  var xs = []
  var ys = []
  for (var i = 0; i < state.size; i++) { xs.push(i); ys.push(i) }
  if (vector.x === 1) xs.reverse()
  if (vector.y === 1) ys.reverse()

  for (var cx = 0; cx < state.size; cx++)
    for (var cy = 0; cy < state.size; cy++)
      if (state.cells[cx][cy]) state.cells[cx][cy].merged = false

  for (var xi = 0; xi < xs.length; xi++) {
    for (var yi = 0; yi < ys.length; yi++) {
      var x = xs[xi]
      var y = ys[yi]
      var tile = state.cells[x][y]
      if (!tile) continue

      // Walk toward the wall until something blocks the way.
      var fx = x, fy = y
      var nx = x + vector.x, ny = y + vector.y
      while (withinBounds(state, nx, ny) && !state.cells[nx][ny]) {
        fx = nx; fy = ny
        nx += vector.x; ny += vector.y
      }
      var next = withinBounds(state, nx, ny) ? state.cells[nx][ny] : null

      if (next && !next.merged && canMerge(state.mode, next.value, tile.value)) {
        var merged = makeTile(state, nx, ny, tile.value + next.value)
        merged.merged = true
        state.cells[x][y] = null
        state.cells[nx][ny] = merged
        state.score += merged.value
        result.scoreDelta += merged.value
        var isNewMax = merged.value > highest
        if (isNewMax) highest = merged.value
        result.merges.push({ fromIds: [tile.id, next.id], id: merged.id, value: merged.value, x: nx, y: ny, newMax: isNewMax })
        result.moved = true
        if (merged.value === state.goal && !state.won) { state.won = true; result.won = true }
      } else if (fx !== x || fy !== y) {
        state.cells[x][y] = null
        state.cells[fx][fy] = tile
        tile.x = fx
        tile.y = fy
        result.moves.push({ id: tile.id, x: fx, y: fy })
        result.moved = true
      }
    }
  }

  if (result.moved) {
    state.moves++
    var spawned = addRandomTile(state)
    if (spawned) result.spawned = { id: spawned.id, value: spawned.value, x: spawned.x, y: spawned.y }
    if (!movesAvailable(state)) { state.over = true; result.over = true }
  }
  return result
}

function keepPlaying(state) {
  state.keepPlaying = true
}

// Flat tile list for building the view from scratch.
function tiles(state) {
  var list = []
  for (var x = 0; x < state.size; x++)
    for (var y = 0; y < state.size; y++) {
      var t = state.cells[x][y]
      if (t) list.push({ id: t.id, value: t.value, x: t.x, y: t.y })
    }
  return list
}

function serialize(state) {
  var list = []
  for (var x = 0; x < state.size; x++)
    for (var y = 0; y < state.size; y++) {
      var t = state.cells[x][y]
      if (t) list.push({ x: t.x, y: t.y, value: t.value })
    }
  var out = { size: state.size, mode: state.mode, tiles: list, score: state.score, moves: state.moves,
    over: state.over, won: state.won, keepPlaying: state.keepPlaying }
  if (state.mode === "Daily") { out.day = state.day; out.rng = state.rng }
  return out
}

// Rebuilds a state from serialize() output. Returns null if the data is bad,
// so a corrupt state file just starts a fresh game. Saves from before modes
// existed have no mode and are Classic.
function fromSaved(saved) {
  if (!saved || typeof saved !== "object") return null
  var size = saved.size
  if (size !== clampSize(size) || !Array.isArray(saved.tiles)) return null
  var mode = saved.mode === undefined ? "Classic" : saved.mode
  if (MODES.indexOf(mode) < 0) return null
  var state = newState(size, mode)
  for (var i = 0; i < saved.tiles.length; i++) {
    var t = saved.tiles[i]
    if (!t || !Number.isInteger(t.x) || !Number.isInteger(t.y) || !isFinite(t.value)) return null
    if (t.x < 0 || t.x >= size || t.y < 0 || t.y >= size) return null
    if (!validValue(mode, t.value)) return null
    if (state.cells[t.x][t.y]) return null
    state.cells[t.x][t.y] = makeTile(state, t.x, t.y, t.value)
  }
  state.score = Math.max(0, Number(saved.score) || 0)
  state.moves = Math.max(0, Math.floor(Number(saved.moves) || 0))
  state.over = saved.over === true
  state.won = saved.won === true
  state.keepPlaying = saved.keepPlaying === true
  if (mode === "Daily") {
    if (typeof saved.day !== "string" || !Number.isInteger(saved.rng)) return null
    state.day = saved.day
    state.rng = saved.rng
  }
  if (availableCells(state).length === size * size) return null
  return state
}
