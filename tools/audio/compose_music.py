#!/usr/bin/env python3
"""Composes the menu theme, the depot radio and the in-game phrase (tareas de Nacho N-403, N-911).

    python3 tools/audio/compose_music.py            # writes the three .ogg files
    pip install numpy soundfile                     # the only dependencies

Everything is synthesized here, note by note, from fixed seeds: no samples, no
third-party music, no AI generator -- the tracks are ours (see
do-not-drop/assets/audio/music/LICENCIA.md). Rerunning gives the same files.

The menu and the radio loop seamlessly: they're rendered for a whole number of bars and
every note's tail that rings past the end is folded back onto the start, so
the seam sounds like any other beat.

  mus_menu_loop.ogg          main menu. 112 BPM, C major, I-V-vi-IV then
                             IV-I-V-V; plucked keys, bouncy bass, whistled lead.
  mus_depot_radio_loop.ogg   the radio on the depot's break area (depot.gd).
                             88 BPM swing, F major ii-V-I-vi; played through a
                             small speaker (band-limited) with a bed of crackle.
  mus_ingame_loop.ogg        the road music of every run (ingame_music.gd). NOT a
                             loop: one calm phrase of ~32 s that the game fades in
                             and out and repeats after a long silence. 80 BPM, G
                             major, 10 bars; plucked arpeggios with a soft echo,
                             a light bass, a road-shaker tick and a sparse whistle.
                             Same instruments as the menu, a different, slower song.
"""
import json
import os
import threading

import numpy as np
import soundfile as sf

RATE = 32000
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "do-not-drop", "assets", "audio", "music")


def midi_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


class Track:
    def __init__(self, bpm, bars, swing=0.0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.swing = swing
        self.length = int(round(bars * 4 * self.beat * RATE))
        # Room for tails; folded back in finish().
        self.buffer = np.zeros(self.length + RATE * 4)

    def at(self, beat):
        """Sample index of a beat (quarter notes from the start), with swing on off-eighths."""
        whole = int(beat * 2)
        if self.swing and whole % 2 == 1 and abs(beat * 2 - whole) < 1e-6:
            beat += self.swing * 0.5
        return int(round(beat * self.beat * RATE))

    def add(self, start_beat, samples):
        i = self.at(start_beat)
        self.buffer[i:i + len(samples)] += samples

    def finish_once(self, tail_seconds=2.5, fade_seconds=0.8):
        """For a track that is NOT a loop: keeps the tails ringing past the last
        bar and ends on a short fade, so it stops without a click."""
        n = self.length + int(tail_seconds * RATE)
        out = self.buffer[:n].copy()
        fade = int(fade_seconds * RATE)
        out[-fade:] *= 0.5 * (1.0 + np.cos(np.linspace(0.0, np.pi, fade)))
        return out

    def finish(self):
        loop = self.buffer[:self.length].copy()
        tail = self.buffer[self.length:]
        loop[:len(tail)] += tail[:len(loop)]
        return loop


def env(n, attack=0.005, decay=0.3, sustain=0.0, release=0.05, hold=None):
    t = np.arange(n) / RATE
    hold = hold if hold is not None else n / RATE
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    d = sustain + (1.0 - sustain) * np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-4))
    r = np.clip(1.0 - (t - hold) / max(release, 1e-4), 0.0, 1.0)
    return a * d * r


def pluck(freq, seconds, bright=0.5):
    n = int((seconds + 0.6) * RATE)
    t = np.arange(n) / RATE
    wave = np.sin(2 * np.pi * freq * t) + bright * 0.5 * np.sin(4 * np.pi * freq * t) + bright * 0.2 * np.sin(6 * np.pi * freq * t)
    return wave * env(n, 0.004, 0.35, 0.15, 0.25, seconds)


def bass(freq, seconds):
    n = int((seconds + 0.2) * RATE)
    t = np.arange(n) / RATE
    wave = np.sin(2 * np.pi * freq * t) * 0.8 + np.sin(4 * np.pi * freq * t) * 0.25 + np.sign(np.sin(2 * np.pi * freq * t)) * 0.08
    return wave * env(n, 0.006, 0.25, 0.55, 0.08, seconds)


def whistle(freq, seconds, vibrato=5.5):
    n = int((seconds + 0.15) * RATE)
    t = np.arange(n) / RATE
    wobble = 1.0 + 0.006 * np.sin(2 * np.pi * vibrato * t) * np.clip(t / 0.15, 0, 1)
    phase = 2 * np.pi * np.cumsum(freq * wobble) / RATE
    wave = np.sin(phase) + 0.12 * np.sin(2 * phase) + 0.03 * np.random.default_rng(int(freq)).standard_normal(n)
    return wave * env(n, 0.03, 0.4, 0.7, 0.1, seconds)


def kick():
    n = int(0.3 * RATE)
    t = np.arange(n) / RATE
    freq = 45 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t * 11)


def noise_hit(seconds, decay, seed, colour=0.5):
    n = int(seconds * RATE)
    white = np.random.default_rng(seed).standard_normal(n)
    # One-pole high-pass-ish: brighter for hats, fuller for snares.
    shaped = white - colour * np.concatenate(([0.0], white[:-1]))
    return shaped * np.exp(-np.arange(n) / RATE * decay)


def chord_tones(root, quality):
    shapes = {"maj": [0, 4, 7], "min": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11]}
    return [root + i for i in shapes[quality]]


def one_pole_lowpass(signal, cutoff):
    alpha = 1.0 - np.exp(-2 * np.pi * cutoff / RATE)
    out = np.empty_like(signal)
    acc = 0.0
    for i, x in enumerate(signal):
        acc += alpha * (x - acc)
        out[i] = acc
    return out


def normalise(signal, peak=0.85):
    return signal * (peak / max(np.max(np.abs(signal)), 1e-6))


def normalise_rms(signal, rms_db, peak_db=-1.2):
    """Scales to an RMS level; if that would pass peak_db, the peaks are rounded
    off with a soft knee instead of clipping (the RMS is then re-matched)."""
    ceiling = 10.0 ** (peak_db / 20.0)
    target = 10.0 ** (rms_db / 20.0)
    out = signal * (target / np.sqrt(np.mean(signal ** 2)))
    for _ in range(8):
        if np.max(np.abs(out)) <= ceiling:
            break
        out = ceiling * np.tanh(out / ceiling)
        out *= target / np.sqrt(np.mean(out ** 2))
    return out


def menu_theme():
    track = Track(bpm=112, bars=16)
    rng = np.random.default_rng(403)
    # C G Am F / C G Am F / F C G G / F C G G
    progression = [(60, "maj"), (55, "maj"), (57, "min"), (53, "maj")] * 2 + [(53, "maj"), (60, "maj"), (55, "maj"), (55, "maj")] * 2
    scale = [0, 2, 4, 5, 7, 9, 11]
    melody_seed = []
    for bar, (root, quality) in enumerate(progression):
        start = bar * 4
        tones = chord_tones(root, quality)
        # Keys: a bright offbeat pluck, the chord an octave up.
        for step in [0.5, 1.5, 2.5, 3.5]:
            for tone in tones:
                track.add(start + step, pluck(midi_hz(tone + 12), track.beat * 0.45, 0.6) * 0.07)
        # Bass: root, fifth, octave bounce.
        for step, interval in [(0, 0), (1.5, 7), (2, 12), (3, 7)]:
            track.add(start + step, bass(midi_hz(root - 24 + interval), track.beat * 0.45) * 0.22)
        # Drums: four on the floor, snare on 2 and 4, hats on the eighths.
        for step in range(4):
            track.add(start + step, kick() * 0.32)
            track.add(start + step + 0.5, noise_hit(0.05, 90, bar * 8 + step, 0.9) * 0.05)
        for step in [1, 3]:
            track.add(start + step, noise_hit(0.18, 22, bar * 4 + step, 0.3) * 0.12)
        # Lead: a whistled line on chord tones, answered in the second half.
        if bar % 8 < 4:
            phrase = []
            for step in [0, 1, 1.5, 2.5, 3]:
                tone = tones[rng.integers(0, len(tones))] + 12
                phrase.append((step, tone))
            melody_seed.append(phrase)
        else:
            phrase = [(s, t + (scale[rng.integers(0, 3)] if s > 2 else 0)) for s, t in melody_seed[bar % 4]]
        for i, (step, tone) in enumerate(phrase):
            length = (phrase[i + 1][0] - step) if i + 1 < len(phrase) else 4 - step
            track.add(start + step, whistle(midi_hz(tone), track.beat * length * 0.9) * 0.11)
    return normalise(track.finish(), 0.8)


def echo(signal, delay_seconds, feedback, taps):
    """A soft repeat of the keys, to give them some air (no reverb needed)."""
    out = signal.copy()
    step = int(delay_seconds * RATE)
    for k in range(1, taps + 1):
        out[k * step:] += signal[:len(signal) - k * step] * feedback ** k
    return out


def ingame_phrase():
    """Road music, calm and a bit playful: G major, 80 BPM, 10 bars (30 s)
    and 2.5 s of ring-out. G Em Cmaj7 D / G Em Cmaj7 D / Cmaj7 G. The first two
    bars are the keys alone, then the bass joins, then the whistle sings a
    little four-note motif that answers itself and settles on the tonic."""
    keys = Track(bpm=80, bars=10)
    rest = Track(bpm=80, bars=10)
    # (bass note, quality, chord root in the keys' register)
    progression = [(43, "maj"), (40, "min"), (36, "maj7"), (38, "maj")] * 2 + [(36, "maj7"), (43, "maj")]
    # Whistle: (bar, beat, midi note, beats). Bars 0-1 rest; bar 4 is a breath.
    melody = [
        (2, 0, 74, 1.5), (2, 1.5, 76, 0.5), (2, 2, 79, 2),
        (3, 0, 78, 1.5), (3, 1.5, 76, 0.5), (3, 2, 74, 2),
        (4, 0.5, 71, 1), (4, 1.5, 74, 0.5), (4, 2, 76, 1), (4, 3, 74, 1),
        (5, 0, 76, 1.5), (5, 1.5, 74, 0.5), (5, 2, 71, 2),
        (6, 1, 76, 1), (6, 2, 79, 1.5), (6, 3.5, 76, 0.5),
        (7, 0, 78, 1.5), (7, 1.5, 81, 0.5), (7, 2, 78, 1), (7, 3, 74, 1),
        (8, 0, 76, 2), (8, 2, 72, 2),
        (9, 0, 71, 1), (9, 1, 67, 3),
    ]
    for bar, (bass_note, quality) in enumerate(progression):
        start = bar * 4
        tones = chord_tones(bass_note + 24, quality)
        # Keys: a broken chord up and back down, eighth notes; the last bar rings.
        if bar < 9:
            order = [0, 1, 2, 1, 0, 1, 2, 1]
            for i, idx in enumerate(order):
                keys.add(start + i * 0.5, pluck(midi_hz(tones[idx]), keys.beat * 0.5, 0.5) * 0.085)
            # The playful bit: a high answer on the "and" of 4.
            keys.add(start + 3.5, pluck(midi_hz(tones[2] + 12), keys.beat * 0.5, 0.6) * 0.045)
        else:
            for tone in tones:
                keys.add(start, pluck(midi_hz(tone), keys.beat * 3.0, 0.4) * 0.07)
            keys.add(start, pluck(midi_hz(tones[0] + 12), keys.beat * 3.0, 0.4) * 0.05)
        if bar >= 1:
            # Bass: root, fifth, and a little octave skip before the next bar.
            for step, interval, gain in [(0, 0, 0.2), (2, 7, 0.14), (3.5, 12, 0.08)]:
                if bar == 9 and step > 0:
                    continue
                rest.add(start + step, bass(midi_hz(bass_note + interval), rest.beat * (3.5 if bar == 9 else 0.8)) * gain)
        if bar < 9:
            # A felt thump on 1 and 3, a shaker on the eighths: the road underneath.
            for step in [0, 2]:
                if bar >= 1:
                    rest.add(start + step, kick() * 0.1)
            for step in range(8):
                rest.add(start + step * 0.5, noise_hit(0.05, 90, 700 + bar * 8 + step, 0.9) * (0.022 if step % 2 else 0.014))
    for bar, beat, tone, length in melody:
        gain = 0.1 if bar < 9 else 0.09
        rest.add(bar * 4 + beat, whistle(midi_hz(tone), rest.beat * length * 0.92, vibrato=5.0) * gain)
    mix = echo(keys.finish_once(), keys.beat * 0.75, 0.38, 3) + rest.finish_once()
    return normalise_rms(mix, -15.84)


def radio_program():
    track = Track(bpm=88, bars=16, swing=0.22)
    rng = np.random.default_rng(1970)
    # Gm7 C7 Fmaj7 Dm7, twice; then Bbmaj7 C7 Am7 Dm7, Gm7 C7 Fmaj7 Fmaj7.
    progression = [(55, "m7"), (48, "7"), (53, "maj7"), (50, "m7")] * 2 + [(58, "maj7"), (48, "7"), (57, "m7"), (50, "m7"), (55, "m7"), (48, "7"), (53, "maj7"), (53, "maj7")]
    for bar, (root, quality) in enumerate(progression):
        start = bar * 4
        tones = chord_tones(root, quality)
        # Comping on 2 and the and-of-3, like an old electric piano.
        for step in [1, 2.5]:
            for tone in tones:
                track.add(start + step, pluck(midi_hz(tone + 12), track.beat * 0.8, 0.3) * 0.06)
        # Walking bass, one note a beat.
        walk = [tones[0] - 24, tones[1] - 24, tones[2] - 24, tones[0] - 24 + (1 if bar % 2 else -1)]
        for step, note in enumerate(walk):
            track.add(start + step, bass(midi_hz(note), track.beat * 0.8) * 0.26)
        # Brushes: swung hats, a soft rim on 2 and 4.
        for step in range(8):
            track.add(start + step * 0.5, noise_hit(0.07, 45, bar * 16 + step, 0.95) * (0.05 if step % 2 else 0.035))
        for step in [1, 3]:
            track.add(start + step, noise_hit(0.08, 40, bar * 4 + step, 0.1) * 0.07)
        # A lazy lead: a few long chord tones, a scale step to lean on.
        for step in ([0, 2] if bar % 2 == 0 else [0.5, 2.5, 3.5]):
            tone = tones[rng.integers(0, len(tones))] + 12 + (2 if rng.random() < 0.2 else 0)
            track.add(start + step, pluck(midi_hz(tone + 12), track.beat * 1.2, 0.8) * 0.1)
    music = track.finish()
    # A small speaker: no deep bass, no air. High-pass by subtracting a
    # low-passed copy, then low-pass the rest -- over two laps of the loop,
    # keeping the second, so the filters' memory at the seam is the loop's own.
    twice = np.concatenate((music, music))
    twice = twice - one_pole_lowpass(twice, 220.0)
    music = one_pole_lowpass(twice, 3200.0)[len(music):]
    # The crackle of an old radio, and the odd pop.
    crackle_rng = np.random.default_rng(88)
    crackle = crackle_rng.standard_normal(len(music)) * 0.012
    pops = (crackle_rng.random(len(music)) < 0.00015) * crackle_rng.uniform(-0.25, 0.25, len(music))
    return normalise(music + crackle + pops, 0.75)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    loudness = {}
    for name, build in [("mus_menu_loop.ogg", menu_theme), ("mus_depot_radio_loop.ogg", radio_program), ("mus_ingame_loop.ogg", ingame_phrase)]:
        audio = build()
        path = os.path.join(OUT_DIR, name)
        sf.write(path, audio.astype(np.float32), RATE, format="OGG", subtype="VORBIS")
        print("%s: %.1f s, %d KB" % (os.path.normpath(path), len(audio) / RATE, os.path.getsize(path) // 1024))
    # What each file measures once decoded, for the mix (world_mix.gd,
    # test_world_audio_levels.gd): Godot can't hand a test the samples of an
    # .ogg, so the measure is written down here, next to the files.
    for name in sorted(os.listdir(OUT_DIR)):
        if name.endswith(".ogg"):
            data, _rate = sf.read(os.path.join(OUT_DIR, name))
            mono = data if data.ndim == 1 else data.mean(axis=1)
            loudness[name] = {"rms_dbfs": round(float(20 * np.log10(np.sqrt(np.mean(mono ** 2)))), 2),
                              "peak_dbfs": round(float(20 * np.log10(np.max(np.abs(mono)))), 2)}
    with open(os.path.join(OUT_DIR, "loudness.json"), "w", encoding="utf-8") as f:
        json.dump(loudness, f, indent=2, sort_keys=True)
        f.write("\n")
    print(loudness)


if __name__ == "__main__":
    # libvorbis recurses deep enough in sf.write to overflow the main thread's
    # 1 MB stack on Windows (exit 127, truncated .ogg): run on a roomier thread.
    threading.stack_size(64 * 1024 * 1024)
    worker = threading.Thread(target=main)
    worker.start()
    worker.join()
