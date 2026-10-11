#!/usr/bin/env python3
"""Mixes the plugin's sounds into a single PipeWire stream.

Starting a pw-cat for every sound looks harmless, but each one is a new PipeWire
stream that WirePlumber must evaluate, link and unlink. Measured at a fast pace
(about 7 merges a second) that was a quarter of a CPU core for WirePlumber alone,
and the churn also stalled the shell's own audio widgets. This keeps one stream
open and mixes in-process instead. The same stream, silent between sounds, is
what keeps the audio output awake while the game is open.

Usage: mixer.py SOUNDS_DIR

Commands on stdin, one per line:
  play NAME SPEED [GAIN]
                    start sounds/NAME.pcm; SPEED 1.0 is normal, 1.02 is about 34
                    cents sharper (and 2% shorter); GAIN 0.0 to 1.0 is optional
  volume V          0.0 to 1.0

It exits when stdin closes or on SIGTERM. Stdlib only.
"""
import array
import fcntl
import math
import operator
import os
import queue
import signal
import struct
import subprocess
import sys
import termios
import threading
import time

RATE = 24000                   # what the .pcm files are stored at
CHUNK = 240                    # samples per write: 10 ms
CHUNK_BYTES = CHUNK * 2
MAX_VOICES = 16
SILENCE = bytes(CHUNK_BYTES)


def load(directory):
    sounds = {}
    for entry in os.listdir(directory):
        if not entry.endswith(".pcm"):
            continue
        samples = array.array("h")
        with open(os.path.join(directory, entry), "rb") as f:
            samples.frombytes(f.read())
        if sys.byteorder == "big":
            samples.byteswap()
        sounds[entry[:-4]] = samples
    return sounds


def resample(src, speed):
    """Linear interpolation. Speed above 1 plays higher and shorter."""
    if abs(speed - 1.0) < 1e-4 or len(src) < 2:
        return src
    n = int((len(src) - 1) / speed)
    out = array.array("h", bytes(2 * n))
    last = len(src) - 1
    for i in range(n):
        p = i * speed
        j = int(p)
        if j >= last:
            break
        out[i] = int(src[j] + (src[j + 1] - src[j]) * (p - j))
    return out


def reader(sounds, commands):
    """Parse stdin on its own thread so resampling never delays the mixer's clock.

    A pitch variant is made the first time it is asked for and kept. Speeds are
    rounded to 10-cent steps, which nobody can hear and which keeps the number of
    variants small, so after a short while a play costs nothing to prepare."""
    variants = {}
    volume = 0.6
    for line in sys.stdin:
        parts = line.split()
        if not parts:
            continue
        try:
            if parts[0] == "play" and len(parts) >= 3 and parts[1] in sounds:
                speed = max(0.5, min(2.0, float(parts[2])))
                step = round(1200 * math.log2(speed) / 10)
                gain = round(max(0.0, min(1.0, float(parts[3]))) * 20) if len(parts) > 3 else 20
                key = (parts[1], step, gain)
                if key not in variants:
                    made = resample(sounds[parts[1]], 2 ** (step * 10 / 1200))
                    scale = volume * gain / 20
                    if abs(scale - 1) > 1e-3:
                        made = array.array("h", [int(x * scale) for x in made])
                    variants[key] = made
                commands.put(("play", variants[key]))
            elif parts[0] == "volume" and len(parts) >= 2:
                # Volume is baked into the cached variants, so the mixing loop never
                # has to scale; a change just drops the cache.
                volume = max(0.0, min(1.0, float(parts[1])))
                variants.clear()
        except ValueError:
            pass
    commands.put(("quit", None))


def backlog(fd):
    """Bytes written to the pipe that pw-cat has not read yet."""
    return struct.unpack("i", fcntl.ioctl(fd, termios.FIONREAD, b"\0\0\0\0"))[0]


def main():
    sounds = load(sys.argv[1])
    commands = queue.Queue()
    threading.Thread(target=reader, args=(sounds, commands), daemon=True).start()

    player = subprocess.Popen(
        ["pw-cat", "-p", "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16",
         "--latency", "30ms", "-P", '{ node.name = "2048-sound", media.name = "2048" }', "-"],
        stdin=subprocess.PIPE)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    out = player.stdin
    fd = out.fileno()

    voices = []          # [samples, position]
    try:
        while True:
            try:
                while True:
                    kind, value = commands.get_nowait()
                    if kind == "play":
                        voices.append([value, 0])
                        del voices[:-MAX_VOICES]
                    else:
                        return
            except queue.Empty:
                pass

            # Top the stream up only when it is running low. Writing on a fixed
            # clock instead would build a backlog while pw-cat starts, and that
            # backlog would then be added to every sound's latency for good.
            if backlog(fd) > CHUNK_BYTES:
                time.sleep(0.004)
                continue

            if not voices:
                out.write(SILENCE)
                out.flush()
                continue

            acc = [0] * CHUNK
            alive = []
            for voice in voices:
                samples, pos = voice
                piece = samples[pos:pos + CHUNK]
                if not piece:
                    continue
                if len(piece) < CHUNK:
                    piece.extend(array.array("h", bytes(2 * (CHUNK - len(piece)))))
                acc = list(map(operator.add, acc, piece))
                voice[1] = pos + CHUNK
                if voice[1] < len(samples):
                    alive.append(voice)
            voices = alive
            if max(acc) > 32767 or min(acc) < -32768:
                acc = [max(-32768, min(32767, x)) for x in acc]
            out.write(array.array("h", acc).tobytes())
            out.flush()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
    finally:
        try:
            player.kill()
        except OSError:
            pass


if __name__ == "__main__":
    main()
