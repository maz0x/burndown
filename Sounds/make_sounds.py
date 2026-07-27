#!/usr/bin/env python3
"""Generate Burndown's original alert sounds (no Apple audio, fully redistributable).

Six short mono 16-bit 44.1 kHz WAV chimes, each built from pure sine partials with
an exponential decay so they read as calm instrument hits, not beeps. Deterministic:
re-running produces byte-identical files. Output: Sounds/<Name>.wav
"""
import math, struct, wave, os

RATE = 44100

def render(partials, dur, glide=0.0, attack=0.004, gain=0.55):
    """partials: list of (freq, amp, decay_rate). glide shifts pitch multiplicatively over the tail."""
    n = int(RATE * dur)
    out = [0.0] * n
    for f, amp, dk in partials:
        phase = 0.0
        for i in range(n):
            t = i / RATE
            freq = f * ((1.0 + glide) ** (t / dur))
            phase += 2 * math.pi * freq / RATE
            env = (min(1.0, t / attack)) * math.exp(-dk * t)
            out[i] += amp * env * math.sin(phase)
    peak = max(1e-9, max(abs(v) for v in out))
    return [v / peak * gain for v in out]

def mix(*segments_with_offsets, dur):
    n = int(RATE * dur)
    out = [0.0] * n
    for seg, off in segments_with_offsets:
        o = int(RATE * off)
        for i, v in enumerate(seg):
            if o + i < n: out[o + i] += v
    peak = max(1e-9, max(abs(v) for v in out))
    if peak > 0.9:
        out = [v / peak * 0.9 for v in out]
    return out

def write(name, samples):
    path = os.path.join(os.path.dirname(__file__), name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in samples))
    print("wrote", path)

# Ember: warm low chime, a fifth above a mellow fundamental.
write("Ember", render([(392, 1.0, 5.5), (588, 0.45, 7.0), (784, 0.2, 9.0)], 0.85))
# Chime: bright bell with inharmonic sparkle.
write("Chime", render([(880, 1.0, 6.0), (1320, 0.5, 8.0), (2217, 0.22, 11.0)], 0.7))
# Drop: a soft falling third, like a water drop.
write("Drop", render([(740, 1.0, 7.0), (1110, 0.3, 9.0)], 0.6, glide=-0.35))
# Pulse: two quick gentle taps.
tap = render([(660, 1.0, 18.0), (990, 0.35, 22.0)], 0.16)
write("Pulse", mix((tap, 0.0), (tap, 0.19), dur=0.5))
# Bloom: a rising major arpeggio blended into one swell.
a = render([(523, 1.0, 6.0)], 0.55); b = render([(659, 0.8, 6.5)], 0.45); c = render([(784, 0.7, 7.0)], 0.4)
write("Bloom", mix((a, 0.0), (b, 0.09), (c, 0.18), dur=0.75))
# Knock: a low felt thump.
write("Knock", render([(180, 1.0, 16.0), (95, 0.7, 12.0), (360, 0.2, 25.0)], 0.4))
