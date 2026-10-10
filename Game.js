.pragma library

// Pure 2048 rules, ported from gabrielecirulli/2048 (game_manager.js, grid.js,
// tile.js). No QML dependencies, so it can be tested with plain node.
//
// Coordinates follow the original: cells[x][y], x is the column and y the row.
// Tiles carry stable ids so the view can animate a tile instead of redrawing it.
// Directions: 0 up, 1 right, 2 down, 3 left.

var VECTORS = [
  { x: 0, y: -1 },
  { x: 1, y: 0 },
  { x: 0, y: 1 },
  { x: -1, y: 0 }
]

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
function goalFor(size) {
  return { 3: 256, 4: 2048, 5: 4096, 6: 8192 }[size] || 2048
}

function clampSize(size) {
  var n = Math.round(Number(size))
  if (!isFinite(n)) return 4
  return Math.max(MIN_SIZE, Math.min(MAX_SIZE, n))
}

function newState(size) {
  return {
    size: size,
    goal: goalFor(size),
    cells: emptyCells(size),
    score: 0,
    moves: 0,
    over: false,
    won: false,
    keepPlaying: false,
    nextId: 1
  }
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

// Drops a 2 (90%) or 4 (10%) on a random free cell. Returns the new tile or null.
function addRandomTile(state) {
  var free = availableCells(state)
  if (free.length === 0) return null
  var cell = free[Math.floor(Math.random() * free.length)]
  var tile = makeTile(state, cell.x, cell.y, Math.random() < 0.9 ? 2 : 4)
  state.cells[cell.x][cell.y] = tile
  return tile
}

function newGame(size) {
  var state = newState(clampSize(size || 4))
  addRandomTile(state)
  addRandomTile(state)
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
        if (other && other.value === tile.value) return true
      }
    }
  }
  return false
}

function movesAvailable(state) {
  return availableCells(state).length > 0 || tileMatchesAvailable(state)
}

// Slides every tile as far as it goes, merging equal neighbours once per move.
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

      if (next && next.value === tile.value && !next.merged) {
        var merged = makeTile(state, nx, ny, tile.value * 2)
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
  return { size: state.size, tiles: list, score: state.score, moves: state.moves, over: state.over, won: state.won, keepPlaying: state.keepPlaying }
}

// Rebuilds a state from serialize() output. Returns null if the data is bad,
// so a corrupt state file just starts a fresh game.
function fromSaved(saved) {
  if (!saved || typeof saved !== "object") return null
  var size = saved.size
  if (size !== clampSize(size) || !Array.isArray(saved.tiles)) return null
  var state = newState(size)
  for (var i = 0; i < saved.tiles.length; i++) {
    var t = saved.tiles[i]
    if (!t || !isFinite(t.x) || !isFinite(t.y) || !isFinite(t.value)) return null
    if (t.x < 0 || t.x >= size || t.y < 0 || t.y >= size) return null
    if (t.value < 2 || (t.value & (t.value - 1)) !== 0) return null
    if (state.cells[t.x][t.y]) return null
    state.cells[t.x][t.y] = makeTile(state, t.x, t.y, t.value)
  }
  state.score = Math.max(0, Number(saved.score) || 0)
  state.moves = Math.max(0, Math.floor(Number(saved.moves) || 0))
  state.over = saved.over === true
  state.won = saved.won === true
  state.keepPlaying = saved.keepPlaying === true
  if (availableCells(state).length === size * size) return null
  return state
}
