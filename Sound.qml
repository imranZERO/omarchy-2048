import QtQuick
import Quickshell.Io

// Plays the generated effects in sounds/. Does nothing unless `enabled`, so the
// widget stays silent by default.
//
// Every sound goes to one long-lived mixer process (mixer.py), which keeps a
// single PipeWire stream open and mixes into it. Starting a pw-cat per sound was
// the original design, and it made WirePlumber spend about a quarter of a CPU core
// at a fast pace, because each one is a new stream to set up and tear down.
//
// The same open stream is what keeps the output awake. Outputs sleep when idle and
// wake slowly (a USB DAC can take a few hundred milliseconds), which clips or
// swallows the first sound, so the mixer runs while the game is on screen and for
// a while after the last sound.
QtObject {
  id: root

  property bool enabled: false
  // 0..100
  property int volume: 60
  // True while the game is on screen.
  property bool active: false

  readonly property string dir: decodeURIComponent(Qt.resolvedUrl("sounds/").toString().replace("file://", ""))
  readonly property string script: decodeURIComponent(Qt.resolvedUrl("mixer.py").toString().replace("file://", ""))

  // The mixer outlives the popup a little, so a move made over IPC right after
  // closing it still lands on a warm output.
  property bool lingering: false
  readonly property bool keepAwake: enabled && (active || lingering)

  onActiveChanged: if (!active) hold()

  function hold() {
    lingering = true
    lingerTimer.restart()
  }

  property Timer lingerTimer: Timer {
    interval: 20000
    onTriggered: root.lingering = false
  }

  // Commands asked for before the mixer was up, sent once it starts.
  property var pending: []

  function send(line) {
    if (mixer.running) mixer.write(line + "\n")
    else if (pending.length < 16) pending.push(line)
  }

  function level() { return Math.max(0, Math.min(100, volume)) / 100 }

  onVolumeChanged: if (mixer.running) mixer.write("volume " + level() + "\n")

  property Process mixer: Process {
    command: ["python3", root.script, root.dir]
    stdinEnabled: true
    running: root.keepAwake

    onStarted: {
      write("volume " + root.level() + "\n")
      for (var i = 0; i < root.pending.length; i++) write(root.pending[i] + "\n")
      root.pending = []
    }
  }

  // Largest pitch shift either way, in cents (100 cents is a semitone).
  readonly property real wobbleCents: 40
  property real lastCents: 0

  // `cents` shifts the pitch (and, a little, the length) of this one play;
  // `gain` (0 to 1, default 1) makes it quieter.
  function play(name, cents, gain) {
    if (!enabled || volume <= 0) return
    hold()
    send("play " + name + " " + Math.pow(2, (cents || 0) / 1200) + " " + (gain === undefined ? 1 : gain))
  }

  // A random shift, always at least 15 cents from the last one, so two merges
  // in a row are audibly different.
  function nextCents() {
    var c
    do { c = (Math.random() * 2 - 1) * wobbleCents } while (Math.abs(c - lastCents) < 15)
    lastCents = c
    return c
  }

  // A hot streak: a quiet high note just after the move's own sound, climbing
  // with the streak (3 in a row is the first of three notes, then it tops out).
  property int streakNote: 5

  property Timer streakTimer: Timer {
    interval: 90
    onTriggered: root.play("merge" + root.streakNote, 0, 0.4)
  }

  function streak(count) {
    if (!enabled || volume <= 0) return
    streakNote = Math.min(7, count + 2)
    streakTimer.restart()
  }

  // Bigger tiles ring higher: 4 is the lowest note, 512 and up the highest.
  function merge(value) {
    var level = Math.round(Math.log(value) / Math.LN2)
    play("merge" + Math.max(0, Math.min(7, level - 2)), nextCents())
  }
}
