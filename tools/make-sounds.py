#!/usr/bin/env python3
"""Generate the plugin's sound effects into ../sounds (stdlib only).

One profile: low, round and weighty. Each merge is a pitch-dropping "bloop"
over a thump, with a short bright tick on the attack, lightly saturated.

  merge0..merge7  one per tile size, climbing a pentatonic scale from C2
  win             rising arpeggio that rings out
  over            slow, heavy fall

Files are headerless 16-bit mono PCM at 24 kHz (*.pcm), about 26 KB per merge.
There is almost nothing above 12 kHz in these sounds, so half the sample rate
costs nothing audible. mixer.py mixes them into one PipeWire stream and shifts the
pitch a few percent per play, which is how repeated merges avoid sounding
identical without storing extra versions. To audition one:

  pw-cat -p --raw --rate 24000 --channels 1 --format s16 sounds/merge3.pcm

What keeps it even:
  * The lowest notes are mostly inaudible fundamental, so their harmonics are
    boosted, and nothing is generated below ~40 Hz (it only eats headroom).
  * Every file is matched to the same A-weighted loudness, so a small merge
    and a big one sound equally loud even though their pitches differ.

Tweak the constants and re-run: python3 tools/make-sounds.py
"""
import math
import os
import random
import struct

RATE = 48000  # PipeWire's default, so nothing gets resampled
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "sounds")

# Pentatonic run, one note per merge level (4, 8, 16 ... 512 and up).
SCALE = [1.0, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2.0, 9 / 4, 5 / 2]
ROOT = 65.41  # C2
NOTES = [ROOT * r for r in SCALE]

LENGTH = 0.55
# (frequency ratio, amplitude, decay seconds)
PARTIALS = [(1, 1.0, 0.22), (2, 0.85, 0.16), (3, 0.45, 0.10), (4, 0.22, 0.06)]
BLOOP = (0.45, 0.026)             # start this much sharper, settle in 26 ms
SUB = (0.5, 0.65, 0.24)           # octave below: ratio, amplitude, decay
THUMP = (95.0, 52.0, 0.95, 0.09)  # start Hz, end Hz, amplitude, decay
CLICK = 0.12                      # noise pop on the attack
TICK = (6, 0.10, 0.012)           # bright sine ping on the attack: ratio, amplitude, decay
DRIVE = 1.9                       # soft saturation
LOW_DRIVE = 1.0                   # extra saturation per octave below 165 Hz: more audible harmonics
LOW_BOOST = 0.9                   # extra harmonics per octave below 165 Hz
TARGET_PEAK = 0.95
HIGHPASS_HZ = 28.0                # nothing useful below this


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


def bounce(freq, weight):
    """One merge note. `weight` (0..1) makes bigger tiles hit harder."""
    n = int(RATE * LENGTH)
    out = []
    phases = [0.0] * len(PARTIALS)
    tick_phase = 0.0
    sub_phase = 0.0
    thump_phase = 0.0
    rng = random.Random(7)
    click_state = 0.0
    bloop_amt, bloop_tau = BLOOP
    sub_ratio, sub_amp, sub_tau = SUB
    th_f0, th_f1, th_amp, th_tau = THUMP
    tick_ratio, tick_amp, tick_tau = TICK
    # Low notes: the fundamental is barely audible, so lean on the harmonics.
    boost = 1.0 + LOW_BOOST * max(0.0, math.log2(165.0 / freq))
    # A sub an octave down is only worth having if it is audible.
    sub_freq = freq * sub_ratio
    sub_gain = clamp((sub_freq - 36.0) / 16.0, 0.0, 1.0)
    for i in range(n):
        t = i / RATE
        glide = 1.0 + bloop_amt * math.exp(-t / bloop_tau)
        s = 0.0
        for k, (ratio, amp, tau) in enumerate(PARTIALS):
            phases[k] += 2 * math.pi * freq * ratio * glide / RATE
            gain = amp * (boost if ratio > 1 else 1.0)
            s += gain * math.exp(-t / tau) * math.sin(phases[k])
        if sub_gain > 0:
            sub_phase += 2 * math.pi * sub_freq * glide / RATE
            s += sub_gain * sub_amp * math.exp(-t / sub_tau) * math.sin(sub_phase)
        th_f = th_f1 + (th_f0 - th_f1) * math.exp(-t / 0.02)
        thump_phase += 2 * math.pi * th_f / RATE
        s += th_amp * (0.6 + 0.6 * weight) * math.exp(-t / th_tau) * math.sin(thump_phase)
        # Short bright ping and a few ms of low-passed noise: the attack.
        tick_phase += 2 * math.pi * freq * tick_ratio * 2.0 / RATE
        s += tick_amp * (0.5 + weight) * math.exp(-t / tick_tau) * math.sin(tick_phase)
        click_state += 0.35 * (rng.uniform(-1, 1) - click_state)
        s += CLICK * math.exp(-t / 0.004) * click_state * 3
        s *= min(1.0, t / 0.0015)  # no hard start
        out.append(s)
    return out


def womp(length=0.8):
    """Game over: a heavy pitch fall."""
    n = int(RATE * length)
    out = []
    phase = phase2 = 0.0
    for i in range(n):
        t = i / RATE
        f = 55.0 + (210.0 - 55.0) * math.exp(-t / 0.22)
        phase += 2 * math.pi * f / RATE
        phase2 += 2 * math.pi * f * 2.01 / RATE
        env = math.exp(-t / 0.33)
        s = env * (math.sin(phase) + 0.55 * math.sin(phase2))
        s *= min(1.0, t / 0.002)
        out.append(s)
    return out


def mix(parts, total):
    out = [0.0] * int(RATE * total)
    for start, samples, gain in parts:
        offset = int(RATE * start)
        for i, v in enumerate(samples):
            if offset + i < len(out):
                out[offset + i] += v * gain
    return out


def highpass(samples, fc=HIGHPASS_HZ):
    a = 1.0 / (1.0 + 2 * math.pi * fc / RATE)
    out = []
    prev_x = prev_y = 0.0
    for x in samples:
        prev_y = a * (prev_y + x - prev_x)
        prev_x = x
        out.append(prev_y)
    return out


def finish(samples, drive=DRIVE):
    """Cut the infrasonic rumble, soft-saturate, fade the tail, peak-normalise."""
    samples = highpass(samples)
    raw_peak = max(1e-9, max(abs(v) for v in samples))
    sat = [math.tanh(drive * v / raw_peak) / math.tanh(drive) for v in samples]
    fade = int(RATE * 0.02)
    n = len(sat)
    for i in range(n - fade, n):
        sat[i] *= (n - i) / fade
    peak = max(1e-9, max(abs(v) for v in sat))
    return [v * TARGET_PEAK / peak for v in sat]


# ---- loudness ---------------------------------------------------------------

def _sections():
    """A-weighting as first-order sections (bilinear transform)."""
    k = 2.0 * RATE
    # The standard corner frequencies are in Hz; the filter wants rad/s.
    two_pi = 2.0 * math.pi
    poles_hp = [two_pi * f for f in (20.598997, 20.598997, 107.65265, 737.86223)]  # paired with the four zeros
    poles_lp = [two_pi * 12194.217] * 2
    sections = []
    for p in poles_hp:
        d = k + p
        sections.append(((k / d, -k / d), (p - k) / d))
    for p in poles_lp:
        d = k + p
        sections.append(((1 / d, 1 / d), (p - k) / d))
    return sections


def _run(samples, sections):
    for (b0, b1), a1 in sections:
        out = []
        px = py = 0.0
        for x in samples:
            py = b0 * x + b1 * px - a1 * py
            px = x
            out.append(py)
        samples = out
    return samples


_SECTIONS = _sections()


def _rms(x):
    return math.sqrt(sum(v * v for v in x) / len(x))


def _a_norm():
    tone = [math.sin(2 * math.pi * 1000 * i / RATE) for i in range(RATE)]
    return _rms(tone) / _rms(_run(tone, _SECTIONS)[RATE // 2:])


_A_NORM = _a_norm()


def loudness(samples):
    """A-weighted RMS: how loud it sounds, rather than how big the waveform is."""
    return _rms(_run(samples, _SECTIONS)) * _A_NORM


def halve_rate(samples, cutoff=10000.0, taps=63):
    """48 kHz to 24 kHz: a windowed-sinc low-pass, then every second sample."""
    mid = (taps - 1) // 2
    h = []
    for n in range(taps):
        x = n - mid
        sinc = 2 * cutoff / RATE if x == 0 else math.sin(2 * math.pi * cutoff / RATE * x) / (math.pi * x)
        h.append(sinc * (0.5 - 0.5 * math.cos(2 * math.pi * n / (taps - 1))))
    gain = sum(h)
    h = [v / gain for v in h]
    n = len(samples)
    out = []
    for i in range(0, n, 2):
        acc = 0.0
        for k in range(taps):
            j = i + k - mid
            if 0 <= j < n:
                acc += h[k] * samples[j]
        out.append(acc)
    return out


def write_pcm(path, samples):
    """Headerless signed 16-bit little-endian mono, at half of RATE (24 kHz)."""
    samples = halve_rate(samples)
    with open(path, "wb") as f:
        f.write(b"".join(struct.pack("<h", int(clamp(v, -1, 1) * 32767)) for v in samples))


def main():
    os.makedirs(OUT, exist_ok=True)
    # Earlier versions kept styles in subfolders, or WAV files.
    for entry in os.listdir(OUT):
        path = os.path.join(OUT, entry)
        if os.path.isdir(path):
            for f in os.listdir(path):
                os.remove(os.path.join(path, f))
            os.rmdir(path)
        elif entry.endswith((".wav", ".pcm")):
            os.remove(path)

    files = {}
    for i, f in enumerate(NOTES):
        drive = DRIVE + LOW_DRIVE * max(0.0, math.log2(165.0 / f))
        files["merge%d" % i] = finish(bounce(f, i / 7), drive)

    chord = [NOTES[0], NOTES[2], NOTES[3], NOTES[5]]  # root, third, fifth, octave
    arpeggio = [(0.085 * k, bounce(f, 0.5 + 0.5 * k / 3), 1.0) for k, f in enumerate(chord)]
    files["win"] = finish(mix(arpeggio, 0.085 * 3 + LENGTH))
    files["over"] = finish(womp())

    # Match everything to the quietest, so nothing needs more than full scale.
    target = min(loudness(v) for v in files.values())
    for name, samples in files.items():
        scale = target / loudness(samples)
        write_pcm(os.path.join(OUT, name + ".pcm"), [v * scale for v in samples])


if __name__ == "__main__":
    main()
