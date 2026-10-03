extends SceneTree
## The celebration sounds and the one object that plays them. The three streams
## are procedural (a fanfare, the 1893 birthday melody, an eight-second party
## loop); the party music owner turns the game's theme down while they play,
## never pauses it, follows the Sound and Music switches and holds still when the
## household is paused.
const DT: float = .05
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i: int in count: await process_frame

func sample(stream: AudioStreamWAV, index: int) -> float: return float(stream.data.decode_s16(index * 2)) / 32768.0

func peak_of(stream: AudioStreamWAV) -> float:
	var loudest: float = 0.0
	for index: int in stream.data.size() / 2: loudest = maxf(loudest, absf(sample(stream, index)))
	return loudest

func rms_of(stream: AudioStreamWAV) -> float:
	var total: float = 0.0
	var count: int = stream.data.size() / 2
	for index: int in count: total += sample(stream, index) * sample(stream, index)
	return sqrt(total / float(count))

## How much of one pitch is in a short stretch of the sound (a Goertzel filter).
func power_at(stream: AudioStreamWAV, start: int, length: int, hz: float) -> float:
	var sine: float = 0.0
	var cosine: float = 0.0
	for index: int in length:
		var window: float = 0.5 - 0.5 * cos(TAU * float(index) / float(length))
		var value: float = sample(stream, start + index) * window
		sine += value * sin(TAU * hz * float(index) / float(stream.mix_rate))
		cosine += value * cos(TAU * hz * float(index) / float(stream.mix_rate))
	return (sine * sine + cosine * cosine) / float(length)

func boot() -> void:
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(true)
	app.set_music(true)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}]
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_speed(1)

func tick_for(seconds: float) -> void:
	for step: int in int(seconds / DT):
		app.party_music.tick(DT)

func run() -> void:
	# ---- the three streams
	CelebrationAudio.reset_cache()
	var fanfare: AudioStreamWAV = CelebrationAudio.fanfare()
	check(fanfare.format == AudioStreamWAV.FORMAT_16_BITS and fanfare.mix_rate == 22050 and not fanfare.stereo, "The fanfare is mono 16-bit at 22,050 Hz")
	check(fanfare.get_length() >= 2.5 and fanfare.get_length() <= 3.2, "The fanfare lasts about 2.8 seconds (%.2f)" % fanfare.get_length())
	check(peak_of(fanfare) >= 0.85 and peak_of(fanfare) <= 0.95, "It peaks near 0.9 (%.3f)" % peak_of(fanfare))
	check(rms_of(fanfare) >= 0.15, "It is loud all through, not just at one peak (RMS %.3f)" % rms_of(fanfare))
	check(CelebrationAudio.fanfare() == fanfare and CelebrationAudio.is_built("fanfare"), "Built once and kept")
	var loop: AudioStreamWAV = CelebrationAudio.party_loop()
	check(is_equal_approx(loop.get_length(), 8.0) and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.loop_begin == 0 and loop.loop_end == 8 * 22050, "The party loop is eight seconds and loops forward over all of it")
	check(absf(sample(loop, 0) - sample(loop, loop.data.size() / 2 - 1)) < 0.12 and peak_of(loop) <= 0.85, "The loop's two ends meet without a jump (%.3f to %.3f)" % [sample(loop, loop.data.size() / 2 - 1), sample(loop, 0)])
	check(rms_of(loop) > 0.05, "The loop has a body of sound (RMS %.3f)" % rms_of(loop))
	var tune: AudioStreamWAV = CelebrationAudio.birthday_tune()
	check(is_equal_approx(tune.get_length(), CelebrationAudio.tune_seconds()) and tune.get_length() > 15.0 and tune.get_length() < 20.0 and tune.loop_mode == AudioStreamWAV.LOOP_DISABLED, "The birthday tune plays once for about seventeen seconds (%.1f)" % tune.get_length())

	# ---- the tune is the 1893 melody: 25 notes, each at its own pitch
	var melody: Array[int] = [62, 62, 64, 62, 67, 66, 62, 62, 64, 62, 69, 67, 62, 62, 74, 71, 67, 66, 64, 72, 72, 71, 67, 69, 67]
	var times: Array[float] = CelebrationAudio.tune_note_times()
	check(times.size() == melody.size(), "The tune has the melody's 25 notes (%d)" % times.size())
	var hertz: Dictionary = {}
	for midi: int in [62, 64, 66, 67, 69, 71, 72, 74]: hertz[midi] = 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
	var wrong: Array[String] = []
	for index: int in mini(times.size(), melody.size()):
		var start: int = int((times[index] + 0.02) * 22050.0)
		var best: int = -1
		var best_power: float = -1.0
		for midi: int in hertz:
			var power: float = power_at(tune, start, 3000, hertz[midi])
			if power > best_power:
				best_power = power
				best = midi
		if best != melody[index]: wrong.append("note %d wanted %d heard %d" % [index, melody[index], best])
	check(wrong.is_empty(), "Every note is struck at the right pitch (%s)" % ", ".join(wrong))
	check(times[0] > 0.9 and times[times.size() - 1] < tune.get_length() - 1.0, "The melody starts after the lead-in chord and ends with room to ring")

	# ---- a worker thread builds, and asking meanwhile still works
	CelebrationAudio.reset_cache()
	CelebrationAudio.warm(["fanfare", "party_loop"])
	var meanwhile: AudioStreamWAV = CelebrationAudio.fanfare()
	check(meanwhile != null and meanwhile.get_length() > 2.5, "Asking for a sound while it is being warmed builds it on the spot")
	var waited: float = 0.0
	while not CelebrationAudio.is_built("party_loop") and waited < 10.0:
		await process_frame
		waited += 0.05
	check(CelebrationAudio.is_built("party_loop") and CelebrationAudio.party_loop().get_length() == 8.0, "The warmed loop is ready and is the real one")
	check(CelebrationAudio.fanfare() == meanwhile, "...and the fanfare asked for meanwhile is the one that was kept")
	CelebrationAudio.build_all()
	check(CelebrationAudio.is_built("fanfare") and CelebrationAudio.is_built("birthday_tune") and CelebrationAudio.is_built("party_loop"), "build_all builds all three here and now")

	# ---- the party music owner
	await boot()
	var music: AudioStreamPlayer = app.music_player
	var party: LifePartyMusic = app.party_music
	check(is_instance_valid(party) and party.get_parent() == app and party.tune_player.name == "BirthdayTune" and party.loop_player.name == "PartyLoop", "The controller owns a party music node with a tune player and a loop player")
	check(music.playing and not music.stream_paused and is_equal_approx(music.volume_db, -8.0), "The theme is playing at its usual -8 dB")
	check(party.current_voice() == "theme", "With nothing on, the theme is what is heard")

	party.play_birthday_tune()
	check(party.current_voice() == "birthday" and party.tune_player.playing and not party.tune_player.stream_paused, "The birthday tune starts and takes first place")
	tick_for(1.0)
	check(is_equal_approx(music.volume_db, -24.0), "The theme is turned down to -24 dB by volume (%.1f)" % music.volume_db)
	check(music.playing and not music.stream_paused, "...and it is never paused or stopped")
	party.set_party_loop(true)
	tick_for(0.2)
	check(party.current_voice() == "birthday" and party.loop_player.stream_paused, "While the tune plays the party loop is held silent: the tune outranks it")
	check(is_equal_approx(party.tune_player.volume_db, -3.0) and is_equal_approx(party.loop_player.volume_db, -8.0), "The tune is the louder of the two")

	party.stop_birthday_tune()
	tick_for(0.2)
	check(party.current_voice() == "party" and not party.loop_player.stream_paused and party.loop_player.playing, "When the tune ends the party loop is heard")
	check(is_equal_approx(music.volume_db, -24.0) and not music.stream_paused, "The theme stays down for the party")

	# ---- holding still while the household is paused
	tick_for(0.5)
	var held_at: float = party.loop_player.get_playback_position()
	app.household.set_speed(0)
	tick_for(0.5)
	check(party.loop_player.stream_paused, "At speed 0 the party loop is paused where it is (paused %s, playing %s, at %.2f)" % [str(party.loop_player.stream_paused), str(party.loop_player.playing), party.loop_player.get_playback_position()])
	check(not music.stream_paused and is_equal_approx(music.volume_db, -24.0), "...while the theme is neither paused nor brought back up")
	var paused_at: float = party.loop_player.get_playback_position()
	await frames(5)
	check(absf(party.loop_player.get_playback_position() - paused_at) < 0.05, "It does not move while paused (%.2f then %.2f)" % [paused_at, party.loop_player.get_playback_position()])
	app.household.set_speed(1)
	tick_for(0.2)
	check(not party.loop_player.stream_paused, "It carries on when the household runs again (was at %.2f)" % held_at)

	# ---- the switches
	app.set_music(false)
	check(party.current_voice() == "theme" and party.loop_player.stream_paused, "With Music off the party loop is silent")
	party.play_birthday_tune()
	check(party.current_voice() == "birthday" and not party.tune_player.stream_paused, "...but the birthday tune follows Sound alone and still plays")
	app.set_sound(false)
	check(party.current_voice() == "theme" and party.tune_player.stream_paused and party.loop_player.stream_paused, "With Sound off nothing of the party is heard")
	tick_for(1.0)
	check(is_equal_approx(music.volume_db, -8.0), "...and the theme is back at its own level (%.1f)" % music.volume_db)
	app.set_sound(true)
	app.set_music(true)
	tick_for(1.0)
	check(party.current_voice() == "birthday" and is_equal_approx(music.volume_db, -24.0), "Turning both back on brings the party back and the theme down")

	# ---- ending it
	party.stop_all()
	check(not party.wants_tune and not party.wants_loop and not party.tune_player.playing and not party.loop_player.playing and is_equal_approx(music.volume_db, -8.0), "stop_all ends every sound and puts the theme straight back")
	check(not music.stream_paused, "The theme was never paused through all of that")
	party.play_birthday_tune()
	tick_for(1.0)
	party.stop_birthday_tune()
	tick_for(1.0)
	check(is_equal_approx(music.volume_db, -8.0) and party.current_voice() == "theme", "When the last sound ends the theme slides back up to -8 dB (%.1f)" % music.volume_db)

	# ---- a paused household holds the tune's place, and a save can read it
	party.stop_all()
	party.play_birthday_tune(5.0)
	await create_timer(0.6).timeout
	var running_at: float = party.tune_position()
	check(running_at >= 5.4 and running_at < 7.0, "The tune moves on in real time (%.2f)" % running_at)
	app.household.set_speed(0)
	tick_for(0.1)
	var stopped_at: float = party.tune_position()
	await create_timer(0.5).timeout
	check(party.tune_player.stream_paused and absf(party.tune_position() - stopped_at) < 0.05 and stopped_at >= 5.4, "Paused, the tune stays where it was and its place can still be read (%.2f then %.2f)" % [stopped_at, party.tune_position()])
	app.household.set_speed(1)
	tick_for(0.1)
	check(not party.tune_player.stream_paused, "It carries on when the household runs again")
	party.stop_all()

	# ---- a new game or a load ends it, but a tune asked for right after is kept
	party.set_party_loop(true)
	app.load_epoch += 1
	tick_for(0.1)
	check(not party.wants_loop and not party.loop_player.playing, "A new load ends the party music")
	app.load_epoch += 1
	party.play_birthday_tune(3.0)
	tick_for(0.1)
	check(party.wants_tune and party.tune_player.playing and party.tune_position() >= 2.9, "A tune started right after a load is kept, and can start part-way in (%.1f)" % party.tune_position())
	app.mode = "creator"
	tick_for(0.1)
	check(not party.wants_tune and not party.tune_player.playing, "Leaving for the main menu ends it")
	app.mode = "live"

	print("Celebration sound: %d checks, %d failures." % [checks, failures.size()])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
