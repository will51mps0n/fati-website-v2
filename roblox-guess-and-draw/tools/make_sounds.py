"""Synthesizes the game's cartoony sound effects into assets/sounds/*.ogg.
Needs numpy and ffmpeg. Run from anywhere:

    python3 tools/make_sounds.py
"""

import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "sounds"


def times(duration: float) -> np.ndarray:
    return np.arange(int(SR * duration)) / SR


def place(track: np.ndarray, sound: np.ndarray, start: float) -> None:
    i = int(start * SR)
    end = min(len(track), i + len(sound))
    track[i:end] += sound[: end - i]


def attack(t: np.ndarray, seconds: float) -> np.ndarray:
    return np.clip(t / seconds, 0, 1)


def tone(freq, t, harmonics=((1, 1.0),), vibrato=0.0, vibrato_rate=5.5, brightness=None):
    """Sum of harmonics; `freq` may vibrate; `brightness(t)` (0..1) fades in upper harmonics."""
    f = freq * (1 + vibrato * np.sin(2 * np.pi * vibrato_rate * t))
    phase = 2 * np.pi * np.cumsum(f) / SR
    out = np.zeros_like(t)
    for n, amp in harmonics:
        weight = amp if brightness is None else amp * brightness ** (n - 1)
        out += weight * np.sin(n * phase)
    return out


def saw(count):
    return [(n, 1 / n) for n in range(1, count + 1)]


def square(count):
    return [(n, 1 / n) for n in range(1, count + 1, 2)]


def click() -> np.ndarray:
    t = times(0.09)
    freq = 900 * np.exp(-t * 18) + 350
    body = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 45)
    snap = np.random.default_rng(1).uniform(-1, 1, len(t)) * np.exp(-t * 900) * 0.3
    return body + snap


def tick() -> np.ndarray:
    t = times(0.07)
    wood = (np.sin(2 * np.pi * 1900 * t) + 0.5 * np.sin(2 * np.pi * 2950 * t)) * np.exp(-t * 85)
    knock = np.random.default_rng(2).uniform(-1, 1, len(t)) * np.exp(-t * 1200) * 0.4
    return wood * attack(t, 0.001) + knock


def bell(freq, duration, decay):
    t = times(duration)
    partials = [(1, 1.0), (2, 0.35), (3, 0.12)]
    return tone(freq, t, partials) * np.exp(-t * decay) * attack(t, 0.003)


def correct() -> np.ndarray:
    track = np.zeros(int(SR * 0.75))
    place(track, bell(1046.5, 0.5, 9) * 0.8, 0.0)  # C6
    place(track, bell(1568.0, 0.65, 5), 0.09)  # G6
    return track


def your_turn() -> np.ndarray:
    track = np.zeros(int(SR * 0.8))
    notes = [523.25, 659.25, 783.99, 1046.5]  # C5 E5 G5 C6
    tri = [(1, 1), (3, -1 / 9), (5, 1 / 25), (7, -1 / 49)]
    for i, freq in enumerate(notes):
        last = i == len(notes) - 1
        length = 0.55 if last else 0.2
        t = times(length)
        note = tone(freq, t, tri, vibrato=0.006 if last else 0) * np.exp(-t * (4 if last else 14))
        place(track, note * attack(t, 0.004), i * 0.07)
    return track


def time_up() -> np.ndarray:
    """A sad trombone: wah, wah, wah, waaah."""
    notes = [(392.0, 0.0, 0.32), (369.99, 0.36, 0.32), (349.23, 0.72, 0.32), (329.63, 1.08, 0.9)]
    track = np.zeros(int(SR * 2.05))
    for i, (freq, start, length) in enumerate(notes):
        t = times(length)
        last = i == len(notes) - 1
        # Each note opens up then closes, like a plunger mute.
        brightness = 0.25 + 0.55 * np.sin(np.pi * np.clip(t / length, 0, 1)) ** 0.6
        note = tone(freq, t, saw(10), vibrato=0.012 if last else 0, vibrato_rate=5, brightness=brightness)
        fade = np.clip((length - t) / 0.08, 0, 1)
        place(track, note * attack(t, 0.02) * fade, start)
    return track


def victory() -> np.ndarray:
    """Ta-da-da-DAAA fanfare ending on a C major chord."""
    lead = [(392.0, 0.0, 0.13), (523.25, 0.13, 0.13), (659.25, 0.26, 0.13), (783.99, 0.39, 0.2),
            (659.25, 0.62, 0.13), (783.99, 0.76, 1.1)]
    track = np.zeros(int(SR * 2.0))
    for i, (freq, start, length) in enumerate(lead):
        t = times(length)
        last = i == len(lead) - 1
        note = tone(freq, t, square(9), vibrato=0.01 if last else 0, vibrato_rate=6,
                    brightness=0.55 + 0.25 * np.exp(-t * 4))
        fade = np.clip((length - t) / 0.12, 0, 1)
        place(track, note * attack(t, 0.01) * fade * (1.0 if last else 0.85), start)
    for freq in (261.63, 329.63, 392.0):  # chord under the last note
        t = times(1.1)
        chord = tone(freq, t, saw(6), brightness=np.full_like(t, 0.5)) * np.clip((1.1 - t) / 0.3, 0, 1)
        place(track, chord * attack(t, 0.05) * 0.3, 0.76)
    return track


SOUNDS = {
    "click": click,
    "tick": tick,
    "correct": correct,
    "your-turn": your_turn,
    "time-up": time_up,
    "victory": victory,
}


def save(name: str, samples: np.ndarray) -> None:
    samples = samples / np.max(np.abs(samples)) * 0.89
    tail = min(len(samples), int(SR * 0.01))
    samples[-tail:] *= np.linspace(1, 0, tail)
    pcm = (samples * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / f"{name}.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(SR)
            wav.writeframes(pcm.tobytes())
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "6",
             str(OUT / f"{name}.ogg")],
            check=True,
        )
    print(f"{name}.ogg  {len(samples) / SR:.2f}s")


if __name__ == "__main__":
    for sound_name, make in SOUNDS.items():
        save(sound_name, make())
