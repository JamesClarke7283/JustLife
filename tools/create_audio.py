"""Synthesize JustLife's original wordless Lifelet voices and quiet ambience.

Python standard library only. No recordings, franchise sounds, text-to-speech,
language model, or external soundfont is used. Run from any working directory:
    python3 tools/create_audio.py
"""

from __future__ import annotations

import json
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
RATE = 24000
TAU = math.tau
# Vocal tract resonances, in Hz. Numbers describe timbre, not spoken language.
VOWELS = [(710, 1180, 2640), (510, 1790, 2520), (310, 2260, 2940),
          (530, 900, 2480), (350, 1040, 2310), (570, 1480, 2710)]


def smooth(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def resonator(source: list[float], frequency: float, bandwidth: float) -> list[float]:
    radius = math.exp(-math.pi * bandwidth / RATE)
    a = 2.0 * radius * math.cos(TAU * frequency / RATE)
    b = -radius * radius
    gain = 1.0 - radius
    previous = older = 0.0
    result = []
    for sample in source:
        current = gain * sample + a * previous + b * older
        result.append(current)
        older, previous = previous, current
    return result


def lowpass(source: list[float], cutoff: float) -> list[float]:
    alpha = 1.0 - math.exp(-TAU * cutoff / RATE)
    current = 0.0
    result = []
    for sample in source:
        current += alpha * (sample - current)
        result.append(current)
    return result


def syllable(duration: float, pitch: float, bend: float, vowel: tuple[int, int, int],
             rng: random.Random, softness: float) -> list[float]:
    count = int(duration * RATE)
    phase = rng.random()
    source: list[float] = []
    previous_flow = 0.0
    pitch_jitter = 0.0
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]
    breath = lowpass(noise, 3400)
    for index in range(count):
        t = index / RATE
        progress = index / max(1, count - 1)
        pitch_jitter = pitch_jitter * 0.997 + rng.uniform(-1, 1) * 0.003
        frequency = pitch * (1.0 + bend * (progress - 0.5)
                             + 0.013 * math.sin(TAU * 5.1 * t)
                             + pitch_jitter * 0.12)
        phase = (phase + frequency / RATE) % 1.0
        # A smooth, asymmetrical glottal pulse with a brief breathy closure.
        if phase < 0.45:
            flow = 0.5 - 0.5 * math.cos(math.pi * phase / 0.45)
        elif phase < 0.68:
            flow = math.cos(math.pi * (phase - 0.45) / 0.46)
        else:
            flow = 0.0
        derivative = (flow - previous_flow) * RATE / max(100.0, frequency)
        previous_flow = flow
        source.append(derivative + breath[index] * (0.08 + softness * 0.09))
    # Parallel broad resonances provide warm vowels without metallic ringing.
    layers = [resonator(source, formant, width)
              for formant, width in zip(vowel, (125, 175, 240))]
    consonant = resonator(noise, rng.choice((780, 1250, 1850)), 650)
    result: list[float] = []
    nasal = rng.choice((False, False, True))
    for index in range(count):
        t = index / RATE
        progress = index / max(1, count - 1)
        attack = smooth(t / 0.035)
        release = smooth((duration - t) / 0.060)
        vowel_envelope = attack * release * (0.86 + 0.14 * math.sin(math.pi * progress))
        # Slight vowel-to-vowel color motion gives each utterance a natural arc.
        color_shift = smooth((progress - 0.56) / 0.30)
        voice = (layers[0][index] * (0.84 - 0.10 * color_shift)
                 + layers[1][index] * (0.40 + 0.13 * color_shift)
                 + layers[2][index] * 0.16)
        if nasal:
            voice *= 0.75 + 0.25 * smooth(t / 0.055)
        consonant_envelope = math.exp(-((t - 0.025) / 0.020) ** 2)
        airy_tail = smooth((progress - 0.7) / 0.3) * release
        result.append(voice * vowel_envelope
                      + consonant[index] * consonant_envelope * 0.09
                      + breath[index] * airy_tail * 0.006)
    return lowpass(result, 4300)


def phrase(seed: int, count: int, pitch: float, duration_range: tuple[float, float],
           rising: float, softness: float) -> list[float]:
    rng = random.Random(seed)
    result = [0.0] * int(0.07 * RATE)
    vowel_indices = rng.sample(range(len(VOWELS)), min(count, len(VOWELS)))
    for index in range(count):
        duration = rng.uniform(*duration_range)
        vowel = VOWELS[vowel_indices[index % len(vowel_indices)]]
        melodic_arc = math.sin((index + 0.4) / max(1, count) * math.pi)
        frequency = pitch * (0.92 + melodic_arc * 0.15 + rng.uniform(-0.06, 0.06))
        bend = rising if index == count - 1 else rng.uniform(-0.15, 0.17)
        voice = syllable(duration, frequency, bend, vowel, rng, softness)
        level = rng.uniform(0.73, 0.98)
        result.extend(value * level for value in voice)
        result.extend([0.0] * int(rng.uniform(0.026, 0.085) * RATE))
    result.extend([0.0] * int(0.12 * RATE))
    # Very short, quiet early reflections soften a completely dry synthetic voice.
    dry = result[:]
    for delay, gain in ((0.021, 0.085), (0.039, 0.04)):
        offset = int(delay * RATE)
        for index in range(offset, len(result)):
            result[index] += dry[index - offset] * gain
    return result


def click() -> list[float]:
    rng = random.Random(221)
    result = []
    for index in range(int(0.11 * RATE)):
        t = index / RATE
        attack = smooth(t / 0.003)
        body = math.sin(TAU * 530 * t) * math.exp(-t * 82)
        soft_transient = rng.uniform(-1, 1) * math.exp(-t * 190) * 0.26
        result.append((body + soft_transient) * attack)
    return lowpass(result, 2900)


def chime() -> list[float]:
    """A soft three-note rising chime: the news that a baby is on the way.

    Original synthesis like the rest of the set. A gentle bell arpeggio with a
    warm fundamental, a fifth and an octave, each note decaying naturally.
    """
    duration = 1.9
    count = int(duration * RATE)
    result = [0.0] * count
    # Rising major triad, then a held octave: C5, E5, G5, C6.
    for offset, frequency, gain in ((0.00, 523.25, 0.62),
                                    (0.34, 659.25, 0.58),
                                    (0.68, 783.99, 0.54),
                                    (1.02, 1046.50, 0.50)):
        start = int(offset * RATE)
        for index in range(start, count):
            t = (index - start) / RATE
            envelope = smooth(t / 0.012) * math.exp(-t * 2.6)
            # A bell-like partial above the fundamental gives it a soft sparkle.
            voice = (math.sin(TAU * frequency * t) * 0.82
                     + math.sin(TAU * frequency * 2.01 * t) * 0.14
                     + math.sin(TAU * frequency * 3.97 * t) * 0.05)
            result[index] += voice * envelope * gain
    return lowpass(result, 5200)


def ambience() -> list[float]:
    rng = random.Random(719)
    duration = 18.0
    count = int(duration * RATE)
    noise = [rng.uniform(-1.0, 1.0) for _ in range(count)]
    air = lowpass(lowpass(noise, 420), 420)
    result = [sample * (0.24 + 0.035 * math.sin(TAU * index / count))
              for index, sample in enumerate(air)]
    # A few original distant bird-like whistles; quiet, soft, and irregular.
    for start in (2.1, 2.48, 7.9, 11.2, 11.54, 15.2):
        length = rng.uniform(0.13, 0.23)
        pitch = rng.uniform(1760, 2480)
        phase = rng.random()
        for index in range(int(length * RATE)):
            progress = index / (length * RATE)
            frequency = pitch * (1.0 + 0.14 * math.sin(math.pi * progress))
            phase += TAU * frequency / RATE
            envelope = math.sin(math.pi * progress) ** 2
            location = int(start * RATE) + index
            result[location] += math.sin(phase) * envelope * 0.065
    # Crossfade the noise seam; birds are intentionally away from the endpoints.
    seam = int(0.40 * RATE)
    for index in range(seam):
        progress = smooth(index / seam)
        blended = result[count - seam + index] * (1 - progress) + result[index] * progress
        result[index] = blended
        result[count - seam + index] = blended
    # Zero endpoints over a brief fade guarantee click-free loop boundaries.
    for index in range(int(0.025 * RATE)):
        fade = smooth(index / (0.025 * RATE))
        result[index] *= fade
        result[-1 - index] *= fade
    return result


def save(name: str, data: list[float], target_rms_db: float,
         peak_limit: float = 0.70) -> dict[str, float | str | int]:
    # Remove DC before normalizing, then constrain peak rather than hard-clipping.
    dc = sum(data) / max(1, len(data))
    data = [sample - dc for sample in data]
    rms = math.sqrt(sum(sample * sample for sample in data) / max(1, len(data)))
    peak = max(abs(sample) for sample in data)
    gain = min(10 ** (target_rms_db / 20) / max(1e-9, rms), peak_limit / max(1e-9, peak))
    pcm = [round(sample * gain * 32767) for sample in data]
    with wave.open(str(OUT / f"{name}.wav"), "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    measured_peak = max(abs(sample) for sample in pcm) / 32768
    measured_rms = math.sqrt(sum((sample / 32768) ** 2 for sample in pcm) / len(pcm))
    return {"file": f"{name}.wav", "seconds": round(len(pcm) / RATE, 3),
            "sample_rate": RATE, "channels": 1, "peak_dbfs": round(20 * math.log10(max(1e-9, measured_peak)), 2),
            "rms_dbfs": round(20 * math.log10(max(1e-9, measured_rms)), 2),
            "clipped_samples": sum(abs(sample) >= 32767 for sample in pcm)}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    clips = {
        "voice_greeting": phrase(37, 6, 163, (0.16, 0.25), 0.22, 0.4),
        "voice_happy": phrase(111, 7, 190, (0.13, 0.23), -0.08, 0.35),
        "voice_thoughtful": phrase(63, 5, 146, (0.21, 0.34), -0.18, 0.75),
        "voice_argument": phrase(87, 7, 169, (0.15, 0.24), -0.25, 0.20),
        "voice_reaction": phrase(215, 3, 181, (0.19, 0.29), 0.26, 0.55),
    }
    measurements = [save(name, data, -20.0) for name, data in clips.items()]
    measurements.append(save("soft_click", click(), -28.0, 0.30))
    measurements.append(save("chime_pregnancy", chime(), -20.0, 0.62))
    measurements.append(save("ambience_garden", ambience(), -38.0, 0.13))
    (OUT / "measurements.json").write_text(json.dumps(measurements, indent=2) + "\n")
    for item in measurements:
        print(f"{item['file']}: {item['seconds']}s; peak {item['peak_dbfs']} dBFS; "
              f"RMS {item['rms_dbfs']} dBFS; clipped={item['clipped_samples']}")


if __name__ == "__main__":
    main()
