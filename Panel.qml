import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Game.js" as Game
import "Stats.js" as Stats

// 2048 in a bar popup. The bar shows a "2" in a square icon; clicking it (or
// `omarchy-shell shell summon imranzero.2048`) opens the game under the icon.
// Rules live in Game.js, tile animation in Tile.qml/Board.qml; this file wires
// them to the bar, the keyboard, the settings and the saved state.
Panel {
  id: root
  moduleName: "imranzero.2048"
  ipcTarget: "imranzero.2048"
  // This file owns the IPC handler below, which adds game commands.
  manageIpc: false

  // ---- settings (this widget's entry in shell.json) -------------------------
  // The fallbacks passed to opt() below are the defaults.

  // Values just chosen in the settings page, shown at once while the shell
  // writes them to shell.json. Dropped as the saved values arrive.
  property var overrides: ({})

  function opt(name, fallback) {
    var pending = overrides[name]
    return pending !== undefined ? pending : setting(name, fallback)
  }

  // "Dropdown" under the bar icon, or "Window": a floating Hyprland window.
  readonly property string openAs: String(opt("openAs", "Dropdown")) === "Window" ? "Window" : "Dropdown"
  // Set by a right-click on the bar icon: open as a window this once, whatever
  // the setting says. Cleared when the panel closes.
  property bool windowOnce: false
  readonly property bool floating: windowOnce || openAs === "Window"

  readonly property int boardSize: Game.clampSize(opt("boardSize", 4))
  // The window scale, as a factor: 100% is 1.0.
  readonly property real uiScale: Math.max(0.6, Math.min(2.0, Number(opt("scale", 100)) / 100))
  readonly property string paletteMode: {
    var p = String(opt("palette", "Theme"))
    return p === "Classic" || p === "Mono" ? p : "Theme"
  }
  readonly property string animationSetting: {
    var a = String(opt("animationSpeed", "Normal"))
    return a === "Off" || a === "Fast" || a === "Slow" ? a : "Normal"
  }
  readonly property real animSpeed:
    animationSetting === "Off" ? 0 : animationSetting === "Fast" ? 0.6 : animationSetting === "Slow" ? 1.6 : 1.0
  readonly property bool soundOn: opt("sound", true) === true
  readonly property int soundVolume: Math.max(0, Math.min(100, Number(opt("soundVolume", 60))))

  // What the settings page shows.
  readonly property var settingValues: ({
    openAs: openAs,
    scale: Math.round(uiScale * 100),
    boardSize: boardSize,
    palette: paletteMode,
    animationSpeed: animationSetting,
    sound: soundOn,
    soundVolume: soundVolume
  })

  // Save one setting through the shell, the same path `omarchy bar set` uses.
  function setSetting(key, value) {
    var next = Object.assign({}, overrides)
    next[key] = value
    overrides = next
    // Let the change be heard: the bindings above have already caught up.
    if (key === "soundVolume" || (key === "sound" && value === true))
      sound.merge(64)
    Util.execArgv(["omarchy", "bar", "set", moduleName, key, JSON.stringify(value), "--json"])
    overrideExpiry.restart()
  }

  onSettingsChanged: {
    var keys = Object.keys(overrides)
    if (keys.length === 0) return
    var remaining = {}
    for (var i = 0; i < keys.length; i++)
      if (setting(keys[i], undefined) !== overrides[keys[i]]) remaining[keys[i]] = overrides[keys[i]]
    overrides = remaining
  }

  // If a save never lands (the command failed), show what is really stored.
  Timer {
    id: overrideExpiry
    interval: 5000
    onTriggered: root.overrides = ({})
  }

  function px(n) { return Math.round(Style.space(n) * uiScale) }
  function fpx(n) { return Math.max(8, Math.round(n * uiScale)) }

  // ---- state ----------------------------------------------------------------

  // Game.js state. Mutated in place, so score/best are mirrored for bindings.
  property var game: null
  property int score: 0
  property int best: 0
  property bool canUndo: false
  // Which page covers the board: "", "stats" or "settings".
  property string page: ""
  readonly property bool statsOpen: page === "stats"
  readonly property bool settingsOpen: page === "settings"

  function togglePage(name) {
    if (name === "stats") hintStats.press()
    page = page === name ? "" : name
  }
  property bool loaded: false

  // Saved data, by board size. Rewritten whole on every save.
  property var bests: ({})
  property var savedGames: ({})
  property var stats: Stats.empty()

  // Serialized states from before each move, newest last. Not saved to disk.
  property var history: []
  readonly property int historyLimit: 50

  readonly property string statePath:
    Quickshell.env("HOME") + "/.local/state/omarchy/imranzero-2048.json"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- game flow ------------------------------------------------------------

  function updateEnd() {
    if (!game) { board.endState = ""; return }
    var state = game.over ? "over" : (Game.isTerminated(game) ? "won" : "")
    // The overlay's numbers are only worth setting while it is up.
    if (state !== "") {
      board.endScore = game.score
      board.endMoves = game.moves
      board.endTile = Game.maxTile(game)
      board.endBest = game.score > 0 && game.score >= best
    }
    board.endState = state
  }

  function setHistory(list) {
    history = list
    canUndo = list.length > 0
  }

  function bumpStats() {
    // A fresh object, so bindings that read it notice the change.
    stats = Stats.clean(stats)
  }

  property bool bestBeaten: false
  // Scoring moves in a row; a move that scores nothing, or a new game or undo, resets it.
  property int combo: 0
  property real lastBlockedMs: 0

  function startGame() {
    bestBeaten = false
    combo = 0
    game = Game.newGame(boardSize)
    score = 0
    setHistory([])
    board.rebuild(Game.tiles(game), "spawn")
    updateEnd()
  }

  function newGame() {
    hintNew.press()
    startGame()
    save()
  }

  function keepGoing() {
    if (!game) return
    Game.keepPlaying(game)
    updateEnd()
    save()
  }

  // dir: 0 up, 1 right, 2 down, 3 left
  function doMove(dir) {
    if (!game || page !== "") return
    hintMove.press()
    var before = Game.serialize(game)
    var res = Game.move(game, dir)
    if (!res.moved) {
      if (!Game.isTerminated(game)) {
        board.bumpToward(dir)
        var now = Date.now()
        if (now - lastBlockedMs > 150) sound.play("merge0", -500, 0.5)
        lastBlockedMs = now
      }
      return
    }

    var list = history.slice()
    list.push(before)
    if (list.length > historyLimit) list.shift()
    setHistory(list)

    board.applyMove(res)
    score = game.score
    if (score > best) {
      // Beating a standing best is worth a moment, once per game. The first game
      // on a board size has no best to beat.
      if (!bestBeaten && best > 0) {
        bestBeaten = true
        scorePill.celebrate()
        sound.play("merge7", 0)
      }
      best = score
    }
    Stats.recordMove(stats, game, res)
    bumpStats()
    if (res.scoreDelta > 0) scorePill.flash(res.scoreDelta)
    // A streak of scoring moves earns a badge from the third on, and a quiet note.
    combo = res.scoreDelta > 0 ? combo + 1 : 0
    updateEnd()
    playFor(res)
    if (combo >= 3 && !res.won && !res.over) {
      board.showCombo(combo)
      sound.streak(combo)
    }
    save()
  }

  function undo() {
    if (!game || page !== "" || history.length === 0) return
    hintUndo.press()
    var list = history.slice()
    var previous = Game.fromSaved(list.pop())
    if (!previous) return
    Stats.recordUndo(stats, game, previous)
    bumpStats()
    game = previous
    score = game.score
    combo = 0
    setHistory(list)
    board.rebuild(Game.tiles(game), "restore")
    updateEnd()
    save()
  }

  function playFor(res) {
    if (res.won) { sound.play("win"); return }
    if (res.over) { sound.play("over"); return }
    var top = 0
    for (var i = 0; i < res.merges.length; i++) top = Math.max(top, res.merges[i].value)
    if (top > 0) sound.merge(top)
  }

  // ---- persistence ----------------------------------------------------------

  function save() {
    if (!game) return
    var key = String(game.size)
    var nextBests = Object.assign({}, bests)
    nextBests[key] = best
    bests = nextBests
    var nextGames = Object.assign({}, savedGames)
    // Same rule as the original: a finished game is not resumed.
    if (game.over) delete nextGames[key]
    else nextGames[key] = Game.serialize(game)
    savedGames = nextGames
    // Writing the file is deferred until play pauses (and at least every 15 s).
    // Each write to the state directory made something else in the shell do a
    // burst of work: measured while playing fast, one write every 300 ms took
    // the CPU from about 7 W to about 29 W, and no writes kept it at 7 W.
    dirty = true
    idleTimer.restart()
    if (!waitTimer.running) waitTimer.start()
  }

  // True while savedGames is newer than the file.
  property bool dirty: false

  function writeState() {
    idleTimer.stop()
    waitTimer.stop()
    dirty = false
    stateFile.setText(JSON.stringify({ version: 2, bests: bests, games: savedGames, stats: stats }) + "\n")
  }

  Timer {
    id: idleTimer
    interval: 2000
    onTriggered: root.writeState()
  }

  Timer {
    id: waitTimer
    interval: 15000
    onTriggered: root.writeState()
  }

  Component.onDestruction: if (dirty) root.writeState()

  function sameAsSaved() {
    if (!game || game.size !== boardSize) return false
    var saved = savedGames[String(boardSize)]
    if (game.over) return !saved
    return !!saved && JSON.stringify(Game.serialize(game)) === JSON.stringify(saved)
  }

  // Show the saved game for the current board size, or start one.
  function loadSize() {
    var key = String(boardSize)
    best = Math.max(0, Number(bests[key]) || 0)
    var saved = savedGames[key] ? Game.fromSaved(savedGames[key]) : null
    bestBeaten = false
    combo = 0
    if (saved && saved.size === boardSize) {
      game = saved
      score = game.score
      setHistory([])
      board.rebuild(Game.tiles(game))
      updateEnd()
    } else {
      startGame()
    }
    if (score > best) best = score
  }

  function restore(raw) {
    var data = null
    try { data = JSON.parse(raw) } catch (e) { data = null }
    var nextBests = {}
    var nextGames = {}
    if (data && data.version === 2) {
      if (data.bests && typeof data.bests === "object") nextBests = data.bests
      if (data.games && typeof data.games === "object") nextGames = data.games
    } else if (data && data.version === 1) {
      // Single 4x4 game from the first release.
      if (isFinite(data.best)) nextBests["4"] = Math.max(0, Math.floor(data.best))
      if (data.game) nextGames["4"] = data.game
    }
    bests = nextBests
    savedGames = nextGames
    stats = Stats.clean(data ? data.stats : null)

    // Re-reading on open must not throw away a game in progress or its undo
    // history; only another instance having moved since justifies a reload.
    if (loaded && sameAsSaved()) {
      best = Math.max(best, Number(bests[String(boardSize)]) || 0)
      return
    }
    loaded = true
    loadSize()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.restore(text())
    onLoadFailed: root.restore("")
  }

  // The bar has one instance of this widget per monitor, each with its own
  // in-memory game. Re-reading on open keeps them in step.
  // The dropdown's content settles in: a short slide down and scale up, on top of the
  // panel's own fade. Window mode has no bar to come from, so it skips this.
  property real enterT: 1

  NumberAnimation {
    id: enterAnim
    target: root
    property: "enterT"
    from: 0
    to: 1
    duration: Style.duration(Math.round(130 * root.animSpeed))
    easing.type: Easing.OutCubic
  }

  onOpenedChanged: {
    if (opened && !floating && animSpeed > 0) enterAnim.restart()
    if (opened) {
      // The file is older than this instance's game while a write is pending.
      if (!dirty) stateFile.reload()
      if (floating) prepareWindow()
    } else {
      page = ""
      ruleReady = false
      windowOnce = false
    }
  }

  // Switched modes while the game is showing.
  onFloatingChanged: if (opened && floating) prepareWindow()

  onBoardSizeChanged: if (loaded) loadSize()

  // omarchy-shell imranzero.2048 <open|close|toggle|move <up|right|down|left>|undo|newGame|stats>
  ShellIpc {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function move(direction: string): void {
      var dir = ({ up: 0, right: 1, down: 2, left: 3 })[direction]
      if (dir !== undefined) root.doMove(dir)
    }
    function undo(): void { root.undo() }
    function newGame(): void { root.newGame() }
    function stats(): void { root.togglePage("stats") }
    function settings(): void { root.togglePage("settings") }
  }

  ThemePalette { id: themePalette }

  Sound {
    id: sound
    enabled: root.soundOn
    volume: root.soundVolume
    active: root.opened
  }

  // ---- bar icon -------------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // A "2" in a square, from the Nerd Font; the bar colors it like its other icons.
    text: String.fromCodePoint(0xF03A7)
    // A little larger than the bar's default icon size, which makes this glyph look small.
    fontSize: Style.bar.iconFont + 3
    active: root.opened
    tooltipText: root.opened ? "" : "2048  \u00b7  right-click for a window"
    onPressed: function(b) {
      if (root.opened) { root.close(); return }
      // Decide the mode before opening, so the right surface is the one shown.
      root.windowOnce = b === Qt.RightButton
      root.open()
    }
  }

  // ---- popup and window -----------------------------------------------------

  // The widest part of the UI. Sets the width of both the dropdown and the window.
  readonly property real contentW: Math.max(board.side, settingsView.implicitWidth, hints.implicitWidth,
    leftRow.implicitWidth + scorePill.implicitWidth + px(12))

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && !root.floating
    padding: root.floatPad
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.contentW + panel.verticalContentInset)
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    // The game UI (keyCatcher, below) is parented here in dropdown mode.
    Item {
      id: dropHolder
      anchors.fill: parent
    }

  }

  // ---- window mode ----------------------------------------------------------

  // The one outer margin: from the edge of the popup or window to the board, the
  // header and the footer alike, on all four sides.
  readonly property int floatPad: Style.space(16)
  // Set once Hyprland has been asked to float the window, so it never shows up
  // tiled for a moment first.
  property bool ruleReady: false

  // A Hyprland window rule for our window, made at runtime so the user's
  // hyprland.lua stays untouched. Run on every open: a config reload drops
  // runtime rules. The previous handle is disabled first so rules do not pile up.
  readonly property string floatRuleLua:
    'local old = rawget(_G, "omarchy_2048_rule"); ' +
    'if old then pcall(function() old:set_enabled(false) end) end; ' +
    'rawset(_G, "omarchy_2048_rule", hl.window_rule({ name = "omarchy-2048-float", ' +
    'match = { class = "org.quickshell", title = "^2048$" }, float = true, center = true }))'

  function prepareWindow() {
    ruleReady = false
    floatRuleProc.running = false
    floatRuleProc.running = true
    floatRuleFallback.restart()
  }

  Process {
    id: floatRuleProc
    command: ["hyprctl", "eval", root.floatRuleLua]
    onExited: { floatRuleFallback.stop(); root.ruleReady = true }
  }

  // Not running Hyprland (or hyprctl is missing): show the window anyway.
  Timer {
    id: floatRuleFallback
    interval: 600
    onTriggered: root.ruleReady = true
  }

  FloatingWindow {
    visible: root.opened && root.floating && root.ruleReady
    title: "2048"
    color: Commons.Color.popups.background
    implicitWidth: Math.round(root.contentW + root.floatPad * 2)
    implicitHeight: Math.round(column.implicitHeight + root.floatPad * 2)
    // Exactly as big as the content, in both directions. A minimum alone would
    // let the window grow for a page and never shrink back.
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      // Closed from outside (the window manager): follow it.
      else if (root.opened && root.floating) root.close()
    }

    // The game UI (keyCatcher, below) is parented here in window mode.
    Item {
      id: floatHolder
      anchors.fill: parent
      anchors.margins: root.floatPad
    }
  }

  // ---- the game UI, shown in whichever of the two holds it -------------------

  PanelKeyCatcher {
    id: keyCatcher
    parent: root.floating ? floatHolder : dropHolder
    anchors.fill: parent

    onMoveRequested: function(dx, dy) {
      if (dy < 0) root.doMove(0)
      else if (dx > 0) root.doMove(1)
      else if (dy > 0) root.doMove(2)
      else root.doMove(3)
    }
    onActivateRequested: {
      if (root.page !== "") root.page = ""
      else board.activatePrimary()
    }
    onCloseRequested: {
      if (root.page !== "") root.page = ""
      else root.close()
    }
    onTabRequested: function(direction) { if (!root.floating) root.switchPanel(direction) }
    onTextKey: function(t, modifiers) {
      if (t === "q") root.close()
      else if (t === "r") root.newGame()
      else if (t === "u" || t === "z" || t === "\b") root.undo()
      else if (t === "t") root.togglePage("stats")
      else if (t === "o" || t === ",") root.togglePage("settings")
      else if (t === "w") root.doMove(0)
      else if (t === "d") root.doMove(1)
      else if (t === "s") root.doMove(2)
      else if (t === "a") root.doMove(3)
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: root.px(8)
      transformOrigin: Item.Top
      scale: 0.96 + 0.04 * root.enterT
      transform: Translate { y: -root.px(10) * (1 - root.enterT) }

      // One compact header row. On the left, the title and the actions as
      // borderless icon buttons; on the right, the scores in a single capsule.
      Item {
        // The same width as the board, so the title lines up with its left edge and
        // the score card with its right edge.
        width: Math.max(board.width, leftRow.implicitWidth + scorePill.implicitWidth + root.px(12))
        x: Math.round((parent.width - width) / 2)
        height: Math.max(leftRow.implicitHeight, scorePill.implicitHeight)

        Row {
          id: leftRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.px(10)

          // The title, outlined in the accent color.
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: titleText.implicitWidth + root.px(16)
            height: titleText.implicitHeight + root.px(4)
            radius: Style.cornerRadius
            color: "transparent"
            border.width: Math.max(2, root.px(2))
            border.color: Commons.Color.accent

            Text {
              id: titleText
              anchors.centerIn: parent
              text: "2048"
              color: Commons.Color.accent
              font.family: Style.font.family
              font.bold: true
              font.pixelSize: root.fpx(Style.font.heading + Style.space(4))
            }
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.px(2)

            HeaderButton {
              glyph: 0xF054C
              uiScale: root.uiScale
              tooltipText: "Undo (u)"
              enabled: root.canUndo && root.page === ""
              opacity: enabled ? 1 : 0.4
              onClicked: root.undo()
            }

            HeaderButton {
              glyph: 0xF0450
              uiScale: root.uiScale
              tooltipText: "New game (r)"
              onClicked: root.newGame()
            }

            HeaderButton {
              glyph: 0xF0493
              uiScale: root.uiScale
              tooltipText: "Settings (o)"
              active: root.settingsOpen
              onClicked: root.togglePage("settings")
            }
          }
        }

        ScorePill {
          id: scorePill
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          score: root.score
          best: root.best
          uiScale: root.uiScale
          speed: root.animSpeed
          active: root.statsOpen
          tooltipText: "Stats (t)"
          onClicked: root.togglePage("stats")
        }
      }

      // Board, with the stats or settings page laid over it. The slot takes
      // the page's height while one is open and eases between sizes, so the
      // popup grows and shrinks smoothly.
      Item {
        width: parent.width
        height: root.settingsOpen ? Math.max(board.height, settingsView.implicitHeight)
          : root.statsOpen ? Math.max(board.height, statsView.implicitHeight)
          : board.height

        // Eased in the dropdown. In a window it snaps: animating would resize
        // the window every frame.
        Behavior on height {
          enabled: !root.floating
          NumberAnimation { duration: Style.duration(Math.round(160 * root.animSpeed)); easing.type: Easing.OutCubic }
        }

        Board {
          id: board
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          size: root.boardSize
          uiScale: root.uiScale
          speed: root.animSpeed
          paletteMode: root.paletteMode
          palette: themePalette
          onSwiped: function(dir) { root.doMove(dir) }
          onNewGameRequested: root.newGame()
          onKeepGoingRequested: root.keepGoing()
        }

        StatsView {
          id: statsView
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: board.width
          height: parent.height
          shown: root.statsOpen
          stats: root.stats
          best: root.best
          bests: root.bests
          size: root.boardSize
          uiScale: root.uiScale
          onCloseRequested: root.page = ""
          onResetRequested: {
            root.stats = Stats.empty()
            root.save()
          }
        }

        SettingsView {
          id: settingsView
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: parent.width
          height: parent.height
          shown: root.settingsOpen
          values: root.settingValues
          uiScale: root.uiScale
          onChanged: function(key, value) { root.setSetting(key, value) }
          onCloseRequested: root.page = ""
        }
      }

      // Key hints, as key caps.
      Item {
        width: parent.width
        height: hints.implicitHeight

        Row {
          id: hints
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: root.px(8)

          KeyHint { id: hintMove; key: "\u2191\u2193\u2190\u2192"; label: "move"; uiScale: root.uiScale; speed: root.animSpeed }
          KeyHint { id: hintUndo; key: "U"; label: "undo"; uiScale: root.uiScale; speed: root.animSpeed }
          KeyHint { id: hintNew; key: "R"; label: "new"; uiScale: root.uiScale; speed: root.animSpeed }
          KeyHint { id: hintStats; key: "T"; label: "stats"; uiScale: root.uiScale; speed: root.animSpeed }
        }
      }
    }
  }
}
