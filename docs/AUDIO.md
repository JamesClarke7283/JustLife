# JustLife audio

Lifelets express themselves with original wordless vocal babble. The clips contain no deliberate words and implement no language or translation system. No franchise audio, recordings, voice cloning, samples, external soundfonts, or third-party sound assets are used.

## Generated assets

Run `python3 tools/create_audio.py` to regenerate deterministic 24 kHz, mono, 16-bit PCM WAV files in `assets/audio/` using Python's standard library.

| File | Purpose | Length | Integrated RMS |
| --- | --- | --- | --- |
| voice_greeting.wav | Friendly greeting and introduction | 1.85 s | −20 dBFS |
| voice_happy.wav | Amused, warm or excited response | 1.88 s | −20 dBFS |
| voice_thoughtful.wav | Gentle, reflective conversation | 1.85 s | −20 dBFS |
| voice_argument.wav | More emphatic disagreement | 2.02 s | −20 dBFS |
| voice_reaction.wav | Brief expressive reaction | 1.09 s | −20 dBFS |
| soft_click.wav | Quiet interface feedback | 0.11 s | −28 dBFS |
| ambience_garden.wav | Very quiet air and distant bird-like calls | 18 s | −38 dBFS |

The synthesis uses a differentiated glottal pulse, broad vowel formant resonators, light aspiration and consonant noise, changing pitch contours, irregular pauses, vibrato and small early reflections. This is intentionally stylized chatter rather than recorded human speech. Peak normalization leaves headroom; no samples clip. Exact durations, peaks, RMS and clipped sample counts are recorded in `assets/audio/measurements.json`. Automated measurement is complete. An audio preview was requested through the tool, but this model session does not support listening to audio input; no subjective listening claim is made.

## Actor integration

`LifeActor` creates its own `AudioStreamPlayer3D` at mouth height. Active friendly, joke, deep_talk, flirt and argue interactions choose the appropriate category, with a real-time 4–8 second cooldown. Each Lifelet gets a stable pitch variation derived from their name plus small per-utterance variation. An optional numeric `voice_pitch` profile field (0.8–1.3) overrides the base voice pitch.

`actor.speech(text)` also queues a short reaction. Playback waits for the next `animate(delta, speed_factor, moving, action_id)` call so the current pause state is respected. A speed factor of zero immediately stops the current voice and suppresses new playback. Fast-forward does not multiply chatter frequency. Set `actor.voice_enabled = false` from the sound toggle to stop and disable voice playback immediately; re-enable with `true`.

Voices load the local WAV sources with `AudioStreamWAV.load_from_file`, so their playback does not depend on waiting for Godot's asset importer. `unit_size = 8`, `max_distance = 42` and `volume_db = -2` keep them soft at the household camera distance. There is no audio bus requirement.

## Interface and ambience integration

The main UI owns its non-positional click and ambience players. `soft_click.wav` is a one-shot `AudioStreamPlayer` sound. Load `ambience_garden.wav` as an `AudioStreamWAV`, set `loop_mode = AudioStreamWAV.LOOP_FORWARD`, `loop_begin = 0`, and `loop_end = int(stream.get_length() * stream.mix_rate)`, then assign it to an `AudioStreamPlayer` and play it. The generated loop has quiet crossfaded air with short click-free endpoints and distant calls away from the loop boundary. Start at 0 dB on the player: the file itself is already very quiet. Connect both players to the same sound toggle as Lifelet voices.

API reference fetched through Context7: [AudioStreamWAV](https://docs.godotengine.org/en/4.7/classes/class_audiostreamwav.html), [AudioStreamPlayer3D](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer3d.html).
