extends RefCounted
class_name CelebrationAudio
## The sounds of a celebration, made from arithmetic so the game needs no sound
## files for them: a brass fanfare with a drum roll, the birthday tune on a
## music box, and a looping party groove. Every stream is mono 16-bit at 22,050 Hz
## and built once, then kept.
##
## The tune is the public-domain 1893 melody ("Good Morning to All"). It is only
## notes: no words are stored or sung anywhere in the game.
##
## Building a stream costs a fraction of a second, so `warm` makes them on a
## worker thread while the game starts, and a caller that asks first just builds
## the one it needs. `build_all` builds everything on the calling thread for
## tests.

const RATE: int = 22050
const KEYS: Array[String] = ["fanfare", "birthday_tune", "party_loop"]
const FANFARE_SECONDS: float = 2.8
## Sixteen beats at 120 beats a minute, so the loop is exactly eight seconds long.
const LOOP_BEATS: int = 16
const LOOP_BPM: float = 120.0
const TUNE_BPM: float = 100.0
## A music-box chord comes before the melody.
const TUNE_INTRO: float = 1.0
## How long every music-box note keeps ringing after it is struck.
const TUNE_RING: float = 1.2
## The tune as [MIDI note, beats]. Three beats to a bar, with a one-beat pickup
## at the start of each of the four lines.
const TUNE_NOTES: Array = [
	[62, 0.75], [62, 0.25], [64, 1.0], [62, 1.0], [67, 1.0], [66, 2.0],
	[62, 0.75], [62, 0.25], [64, 1.0], [62, 1.0], [69, 1.0], [67, 2.0],
	[62, 0.75], [62, 0.25], [74, 1.0], [71, 1.0], [67, 1.0], [66, 1.0], [64, 2.0],
	[72, 0.75], [72, 0.25], [71, 1.0], [67, 1.0], [69, 1.0], [67, 2.0],
]
## The chord under the tune as [beat it is struck on, chord]: G, D and C.
const TUNE_CHORDS: Array = [
	[1.0, "G"], [4.0, "D"], [7.0, "D"], [10.0, "G"], [13.0, "G"],
	[16.0, "D"], [17.0, "C"], [19.0, "C"], [20.0, "G"], [23.0, "G"],
]
## Each chord as MIDI notes: the first, an octave lower, is the bass; the rest ring as a box.
const CHORD_NOTES: Dictionary = {"G": [55, 59, 62, 67], "D": [50, 57, 62, 66], "C": [48, 55, 60, 64]}
## One cycle of a tone is kept as a table this long, and read instead of calling sin.
const TABLE: int = 4096

static var _cache: Dictionary = {}
static var _lock: Mutex = Mutex.new()
static var _warming: bool = false
static var _sine: PackedFloat32Array = PackedFloat32Array()
static var _brass: PackedFloat32Array = PackedFloat32Array()


## About 2.8 seconds: a rising drum roll, four brass stabs climbing a C chord,
## then the whole chord held with a cymbal crash and a party horn. Peaks at 0.9.
static func fanfare() -> AudioStreamWAV: return _stream_for("fanfare")

## The birthday melody on a music box over soft chords, about seventeen seconds.
static func birthday_tune() -> AudioStreamWAV: return _stream_for("birthday_tune")

## Eight seconds of kick, claps, hats, a bass line and chord stabs that repeats
## without a seam.
static func party_loop() -> AudioStreamWAV: return _stream_for("party_loop")

## True once the stream for `key` has been built.
static func is_built(key: String) -> bool:
	_lock.lock()
	var found: bool = _cache.has(key)
	_lock.unlock()
	return found

## Build the named streams on a worker thread so the first celebration does not
## stall a frame. Asking for one that is not ready yet still works: it is built
## on the spot.
static func warm(keys: Array = ["fanfare"]) -> void:
	var wanted: Array = keys.filter(func(key: Variant) -> bool: return str(key) in KEYS and not is_built(str(key)))
	if wanted.is_empty() or _warming: return
	_warming = true
	WorkerThreadPool.add_task(Callable(CelebrationAudio, "_warm_job").bind(wanted), false, "celebration audio")

## Build every stream here and now (tests, and anything that must not wait).
static func build_all() -> void:
	for key: String in KEYS: _stream_for(key)

## Forget the built streams, so a test can time a cold build.
static func reset_cache() -> void:
	_lock.lock()
	_cache.clear()
	_lock.unlock()

## How long the birthday tune plays, melody and last ring included.
static func tune_seconds() -> float:
	var beats: float = 0.0
	for note: Array in TUNE_NOTES: beats += float(note[1])
	return TUNE_INTRO + beats * 60.0 / TUNE_BPM + TUNE_RING

## The seconds from the start of the tune at which each melody note is struck.
static func tune_note_times() -> Array[float]:
	var times: Array[float] = []
	var beat: float = 0.0
	for note: Array in TUNE_NOTES:
		times.append(TUNE_INTRO + beat * 60.0 / TUNE_BPM)
		beat += float(note[1])
	return times


static func _warm_job(keys: Array) -> void:
	for key: Variant in keys: _stream_for(str(key))
	_warming = false

static func _stream_for(key: String) -> AudioStreamWAV:
	_lock.lock()
	var hit: Variant = _cache.get(key)
	_lock.unlock()
	if hit != null: return hit
	var stream: AudioStreamWAV
	match key:
		"fanfare": stream = _build_fanfare()
		"birthday_tune": stream = _build_tune()
		_: stream = _build_loop()
	_lock.lock()
	if not _cache.has(key): _cache[key] = stream
	var kept: AudioStreamWAV = _cache[key]
	_lock.unlock()
	return kept


# ---- the three sounds ----

static func _build_fanfare() -> AudioStreamWAV:
	_make_tables()
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(int(RATE * FANFARE_SECONDS))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1893
	# A drum roll that gets louder over the first 0.6 seconds.
	for hit: int in 15:
		_mix(buffer, _noise_wave(rng, 0.07, 40.0, false), int(float(hit) * 0.04 * float(RATE)), 0.14 + 0.32 * float(hit) / 14.0, false)
	# Four brass stabs climb C, E, G, C.
	var stab_notes: Array[float] = [261.63, 329.63, 392.0, 523.25]
	for index: int in stab_notes.size():
		_mix(buffer, _brass_wave(stab_notes[index], 0.55, 3.2, 0.0), int((0.6 + 0.15 * float(index)) * float(RATE)), 0.17, false)
	# The whole C chord is held, with a little wobble in the pitch.
	for note: float in [130.81, 261.63, 329.63, 392.0, 523.25, 659.25]:
		_mix(buffer, _brass_wave(note, 1.55, 0.9, 0.006), int(1.2 * float(RATE)), 0.095, false)
	# A cymbal crash and a party horn sliding up.
	_mix(buffer, _noise_wave(rng, 1.2, 3.4, true), int(1.2 * float(RATE)), 0.30, false)
	_mix(buffer, _sweep_wave(0.5, 600.0, 900.0), int(1.25 * float(RATE)), 0.10, false)
	# The fanfare is pressed hard against its peak so it sounds big, not just tall.
	return _finish(buffer, 0.9, false, 2.5)

static func _build_tune() -> AudioStreamWAV:
	_make_tables()
	var beat_seconds: float = 60.0 / TUNE_BPM
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(int(RATE * tune_seconds()))
	var boxes: Dictionary = {}
	# A music-box chord as the lead-in, rolled upwards.
	for index: int in 4:
		_mix(buffer, _cached_box(boxes, float(CHORD_NOTES.G[index]) + 12.0, TUNE_RING), int(0.1 * float(index) * float(RATE)), 0.16, false)
	# Soft chords under the tune, struck on the beat and left to ring. Each chord is
	# one wave, rolled upwards, with its bass underneath.
	var chords: Dictionary = {}
	for name: String in CHORD_NOTES:
		var notes: Array = CHORD_NOTES[name]
		var chord: PackedFloat32Array = PackedFloat32Array()
		chord.resize(int((TUNE_RING + 0.15) * float(RATE)))
		for index: int in range(1, notes.size()):
			_mix(chord, _cached_box(boxes, float(notes[index]), TUNE_RING), int(0.05 * float(index) * float(RATE)), 0.075, false)
		_mix(chord, _brass_wave(_hz(float(notes[0]) - 12.0), 0.9, 2.4, 0.0), 0, 0.055, false)
		chords[name] = chord
	for entry: Array in TUNE_CHORDS:
		_mix(buffer, chords[str(entry[1])], int((TUNE_INTRO + float(entry[0]) * beat_seconds) * float(RATE)), 1.0, false)
	# The melody.
	var beat: float = 0.0
	for note: Array in TUNE_NOTES:
		_mix(buffer, _cached_box(boxes, float(note[0]), TUNE_RING), int((TUNE_INTRO + beat * beat_seconds) * float(RATE)), 0.30, false)
		beat += float(note[1])
	return _finish(buffer, 0.7, false)

static func _build_loop() -> AudioStreamWAV:
	_make_tables()
	var beat_seconds: float = 60.0 / LOOP_BPM
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(int(RATE * float(LOOP_BEATS) * beat_seconds))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 124
	var kick: PackedFloat32Array = _kick_wave()
	var clap: PackedFloat32Array = _clap_wave(rng)
	var hat: PackedFloat32Array = _noise_wave(rng, 0.045, 70.0, true)
	var boxes: Dictionary = {}
	# Four bars of C, A minor, F and G.
	var roots: Array[float] = [48.0, 45.0, 41.0, 43.0]
	var triads: Array = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]]
	var basses: Array = []
	var stabs: Array = []
	for bar: int in 4:
		basses.append(_brass_wave(_hz(roots[bar]), 0.2, 7.0, 0.0))
		var stab: PackedFloat32Array = PackedFloat32Array()
		stab.resize(int(0.2 * float(RATE)))
		for note: int in triads[bar]: _mix(stab, _brass_wave(_hz(float(note)), 0.2, 9.0, 0.0), 0, 0.075 / 0.24, false)
		stabs.append(stab)
	for beat: int in LOOP_BEATS:
		var at: int = int(float(beat) * beat_seconds * float(RATE))
		var half: int = at + int(beat_seconds * 0.5 * float(RATE))
		var bar: int = int(float(beat) * 0.25)
		_mix(buffer, kick, at, 0.6, true)
		if beat % 2 == 1: _mix(buffer, clap, at, 0.42, true)
		_mix(buffer, hat, half, 0.13, true)
		# The bass plays the off-beats, and a stab lands on the first beat and the
		# half-beat after the second.
		_mix(buffer, basses[bar], half, 0.24, true)
		if beat % 4 == 0: _mix(buffer, stabs[bar], at, 0.24, true)
		if beat % 4 == 2: _mix(buffer, stabs[bar], half, 0.24, true)
		# A little sparkle on the chord's notes, high up, on every half beat.
		var spark: Array = triads[bar]
		_mix(buffer, _cached_box(boxes, float(spark[beat % 3]) + 24.0, 0.6), at, 0.07, true)
		_mix(buffer, _cached_box(boxes, float(spark[(beat + 1) % 3]) + 24.0, 0.6), half, 0.05, true)
	return _finish(buffer, 0.8, true)


# ---- the small instruments, each returning one wave to be mixed in ----

static func _hz(midi: float) -> float: return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

## The two cycles every tone reads: a plain sine and a brass-like one (the first
## six harmonics at 1/n). Built once, on whichever thread asks first.
static func _make_tables() -> void:
	_lock.lock()
	if _sine.is_empty():
		var sine: PackedFloat32Array = PackedFloat32Array()
		var brass: PackedFloat32Array = PackedFloat32Array()
		sine.resize(TABLE)
		brass.resize(TABLE)
		for index: int in TABLE:
			var angle: float = TAU * float(index) / float(TABLE)
			sine[index] = sin(angle)
			var tone: float = 0.0
			for harmonic: int in range(1, 7): tone += sin(angle * float(harmonic)) / float(harmonic)
			brass[index] = tone * 0.55
		_brass = brass
		_sine = sine
	_lock.unlock()

## Add `wave` into `buffer` from sample `start`, scaled by `gain`. A looping
## buffer carries what runs past its end round to its beginning.
static func _mix(buffer: PackedFloat32Array, wave: PackedFloat32Array, start: int, gain: float, wrap: bool) -> void:
	var size: int = buffer.size()
	var count: int = wave.size()
	if not wrap:
		count = mini(count, size - start)
		for index: int in count: buffer[start + index] += wave[index] * gain
		return
	var at: int = start
	for index: int in count:
		if at >= size: at -= size
		buffer[at] += wave[index] * gain
		at += 1

## A brass-like note with a quick attack, a decay and a short release. `wobble`
## is how far the pitch swings as a fraction of the note (0.006 is about a tenth
## of a semitone), which gives a held chord a little life.
static func _brass_wave(hz: float, seconds: float, decay: float, wobble: float) -> PackedFloat32Array:
	var count: int = int(seconds * float(RATE))
	var wave: PackedFloat32Array = PackedFloat32Array()
	wave.resize(count)
	var step: float = hz / float(RATE)
	var fade: float = exp(-decay / float(RATE))
	var attack: int = int(0.025 * float(RATE))
	var release: int = int(0.12 * float(RATE))
	var swing: float = wobble * hz / (TAU * 5.5)
	var swing_step: float = 5.5 * float(TABLE) / float(RATE)
	var phase: float = 0.0
	var level: float = 1.0
	for index: int in count:
		var bend: float = swing * _sine[int(float(index) * swing_step) & (TABLE - 1)] if wobble > 0.0 else 0.0
		var envelope: float = level
		if index < attack: envelope *= float(index) / float(attack)
		if index > count - release: envelope *= float(count - index) / float(release)
		wave[index] = _brass[int((phase + bend) * float(TABLE)) & (TABLE - 1)] * envelope
		phase += step
		level *= fade
	return wave

## A music-box note: a bell-like set of partials that die away at different speeds.
static func _box_wave(midi: float, ring: float) -> PackedFloat32Array:
	var count: int = int(ring * float(RATE))
	var wave: PackedFloat32Array = PackedFloat32Array()
	wave.resize(count)
	var step: float = _hz(midi) / float(RATE)
	var low: float = exp(-3.2 / float(RATE))
	var middle: float = exp(-5.5 / float(RATE))
	var high: float = exp(-11.0 / float(RATE))
	var a: float = 1.0
	var b: float = 0.42
	var c: float = 0.16
	var attack: int = int(0.004 * float(RATE))
	var release: int = int(0.05 * float(RATE))
	var phase: float = 0.0
	for index: int in count:
		var position: int = int(phase * float(TABLE))
		var value: float = _sine[position & (TABLE - 1)] * a + _sine[(position * 2) & (TABLE - 1)] * b + _sine[int(phase * float(TABLE) * 5.4) & (TABLE - 1)] * c
		if index < attack: value *= float(index) / float(attack)
		if index > count - release: value *= float(count - index) / float(release)
		wave[index] = value
		phase += step
		a *= low
		b *= middle
		c *= high
	return wave

## The box note for a pitch, made once per tune and reused for every strike of it.
static func _cached_box(boxes: Dictionary, midi: float, ring: float) -> PackedFloat32Array:
	var key: String = "%d:%.2f" % [int(midi), ring]
	if not boxes.has(key): boxes[key] = _box_wave(midi, ring)
	return boxes[key]

## A burst of noise that dies away, optionally brightened by taking differences
## (cymbals, hats and claps).
static func _noise_wave(rng: RandomNumberGenerator, seconds: float, decay: float, bright: bool) -> PackedFloat32Array:
	var count: int = int(seconds * float(RATE))
	var wave: PackedFloat32Array = PackedFloat32Array()
	wave.resize(count)
	var fade: float = exp(-decay / float(RATE))
	var level: float = 1.0
	var last: float = 0.0
	for index: int in count:
		var sample: float = rng.randf_range(-1.0, 1.0)
		wave[index] = ((sample - last) * 0.5 if bright else sample) * level
		last = sample
		level *= fade
	return wave

## A party horn: a tone that slides up and swells.
static func _sweep_wave(seconds: float, from_hz: float, to_hz: float) -> PackedFloat32Array:
	var count: int = int(seconds * float(RATE))
	var wave: PackedFloat32Array = PackedFloat32Array()
	wave.resize(count)
	var phase: float = 0.0
	for index: int in count:
		var ratio: float = float(index) / float(count)
		phase += lerpf(from_hz, to_hz, ratio) / float(RATE)
		var position: int = int(phase * float(TABLE))
		var envelope: float = minf(ratio / 0.05, 1.0) * clampf((1.0 - ratio) / 0.25, 0.0, 1.0)
		wave[index] = (_sine[position & (TABLE - 1)] + 0.5 * _sine[(position * 2) & (TABLE - 1)] + 0.25 * _sine[(position * 3) & (TABLE - 1)]) * envelope * 0.6
	return wave

## A kick drum: a sine that falls from a thump to a low note.
static func _kick_wave() -> PackedFloat32Array:
	var count: int = int(0.28 * float(RATE))
	var wave: PackedFloat32Array = PackedFloat32Array()
	wave.resize(count)
	var phase: float = 0.0
	for index: int in count:
		var age: float = float(index) / float(RATE)
		phase += (46.0 + 110.0 * exp(-age * 32.0)) / float(RATE)
		wave[index] = _sine[int(phase * float(TABLE)) & (TABLE - 1)] * exp(-age * 15.0)
	return wave

## A hand clap: three quick bursts of noise.
static func _clap_wave(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var wave: PackedFloat32Array = PackedFloat32Array()
	wave.resize(int(0.12 * float(RATE)))
	for flam: int in 3: _mix(wave, _noise_wave(rng, 0.09, 38.0, true), int(0.011 * float(flam) * float(RATE)), 0.6 if flam < 2 else 1.0, false)
	return wave

## Scale to a peak, turn the floats into 16-bit samples and wrap them in a stream.
## A `drive` above zero rounds the loudest parts off first (a soft squash), which
## raises the average loudness without raising the peak.
static func _finish(buffer: PackedFloat32Array, peak: float, looped: bool, drive: float = 0.0) -> AudioStreamWAV:
	var loudest: float = 0.0
	for value: float in buffer: loudest = maxf(loudest, absf(value))
	var scale: float = peak / loudest * 32767.0 if loudest > 0.0 else 32767.0
	if drive > 0.0 and loudest > 0.0:
		var squash: float = drive / loudest
		scale = peak / tanh(drive) * 32767.0
		for index: int in buffer.size(): buffer[index] = tanh(buffer[index] * squash)
	var data: PackedByteArray = PackedByteArray()
	data.resize(buffer.size() * 2)
	for index: int in buffer.size(): data.encode_s16(index * 2, int(buffer[index] * scale))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buffer.size()
	return stream
