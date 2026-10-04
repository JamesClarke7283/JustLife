extends SceneTree
## The music of a party. The party loop is heard from a stereo's speaker when the home has
## one (a 3D player that fades with distance) and flat when it has not; either way it is the
## same loop under the same rules: it outranks the theme and not the birthday tune, the
## theme is turned down by volume and never paused, the Sound and Music switches silence it,
## and a paused household holds it where it is. The party's own controller turns it on when
## the first guest is inside, off when the host switches it off or the party ends.
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
	for step: int in int(seconds / DT): app.party_music.tick(DT)

## A 3D player begins playing on the next physics frame, so a pause only lands on it after a few frames.
func settle() -> void:
	await frames(3)
	app.party_music.tick(DT)

func stereo_item() -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == "stereo": return item
	return {}

## A party record that is on, with one guest who has come, for the controller to read.
func party_record(phase: String, music: bool) -> Dictionary:
	var record: Dictionary = LifePartyPlan.build(1, app.household.selected_id(), "", float(app.household.day - 1) * 1440.0 + app.household.minutes, 3, music, [{"id": "maya", "potluck": false}])
	record.phase = phase
	return record

func run() -> void:
	await boot()
	var party: LifePartyMusic = app.party_music
	var theme: AudioStreamPlayer = app.music_player
	var flow: LifePartyFlow = app.party_flow
	# ---- the speaker
	check(is_instance_valid(party.stereo_player) and party.stereo_player is AudioStreamPlayer3D and party.stereo_player.name == "PartyMusic" and party.stereo_player.get_parent() == party, "The party music node owns a 3D speaker named PartyMusic")
	check(is_equal_approx(party.stereo_player.unit_size, 12.0) and not party.loop_at.is_finite(), "It fades over a dozen meters, and starts with nowhere to be")
	var spot: Vector3 = Vector3(2.0, 1.0, -3.0)
	party.set_party_loop(true, spot)
	await settle()
	check(party.wants_loop and party.loop_at.is_equal_approx(spot) and party.stereo_player.global_position.is_equal_approx(spot), "Given a stereo's place, the loop is asked for there")
	check(party.stereo_player.playing and not party.stereo_player.stream_paused and not party.loop_player.playing, "The speaker plays, and the flat player does not")
	check(party.current_voice() == "party" and party.stereo_player.stream == CelebrationAudio.party_loop(), "The voice heard is the party loop")
	tick_for(1.0)
	check(is_equal_approx(theme.volume_db, LifePartyMusic.DUCK_DB) and theme.playing and not theme.stream_paused, "The theme is turned down by volume, and not paused")
	# the switches
	app.set_music(false)
	await settle()
	check(party.current_voice() == "theme" and party.stereo_player.stream_paused, "With Music off the speaker is silent")
	app.set_music(true)
	await settle()
	check(party.current_voice() == "party" and not party.stereo_player.stream_paused, "...and back with Music")
	app.set_sound(false)
	await settle()
	check(party.current_voice() == "theme" and party.stereo_player.stream_paused, "With Sound off the speaker is silent")
	tick_for(1.0)
	check(is_equal_approx(theme.volume_db, -8.0) or theme.volume_db > LifePartyMusic.DUCK_DB, "...and the theme is let back up (%.1f dB)" % theme.volume_db)
	app.set_sound(true)
	await settle()
	tick_for(1.0)
	check(party.current_voice() == "party" and is_equal_approx(theme.volume_db, LifePartyMusic.DUCK_DB), "...and turned down again with it")
	# a pause
	await create_timer(.4).timeout
	party.tick(DT)
	var at: float = party.stereo_player.get_playback_position()
	app.household.set_speed(0)
	await settle()
	var held: float = party.stereo_player.get_playback_position()
	await create_timer(.3).timeout
	check(party.stereo_player.stream_paused and absf(party.stereo_player.get_playback_position() - held) < .05 and not theme.stream_paused, "A paused household holds the speaker where it is (%.2f then %.2f)" % [held, party.stereo_player.get_playback_position()])
	check(at > .2, "...it had been playing in real time (%.2f)" % at)
	app.household.set_speed(1)
	await settle()
	check(not party.stereo_player.stream_paused and party.stereo_player.playing, "...and it carries on after the pause")
	# Build mode and the main menu stop the game without touching the household's speed.
	for held_mode: String in ["build", "menu"]:
		app.mode = held_mode
		await settle()
		check(party.stereo_player.stream_paused, "The speaker holds while the game is in %s mode" % held_mode)
	app.mode = "live"
	await settle()
	check(not party.stereo_player.stream_paused and party.stereo_player.playing, "...and carries on back in Live mode")
	# the birthday tune outranks it
	party.play_birthday_tune()
	await settle()
	check(party.current_voice() == "birthday" and party.stereo_player.stream_paused and not party.tune_player.stream_paused, "The birthday tune outranks the speaker")
	party.stop_birthday_tune()
	await settle()
	check(party.current_voice() == "party" and not party.stereo_player.stream_paused, "...and the speaker is heard again when the song ends")
	# hand over to the flat player and back
	party.set_party_loop(true)
	await settle()
	check(party.loop_player.playing and not party.loop_player.stream_paused and not party.stereo_player.playing and not party.loop_at.is_finite(), "Without a stereo the loop plays flat, and the speaker stops")
	party.set_party_loop(true, spot)
	await settle()
	check(party.stereo_player.playing and not party.stereo_player.stream_paused and not party.loop_player.playing, "With a stereo again it is handed back to the speaker")
	party.set_party_loop(true, spot + Vector3(1, 0, 0))
	await settle()
	check(party.stereo_player.global_position.is_equal_approx(spot + Vector3(1, 0, 0)) and party.stereo_player.playing, "A stereo that is moved takes the speaker with it, without restarting")
	party.stop_all()
	check(not party.wants_loop and not party.stereo_player.playing and not party.loop_player.playing and not party.loop_at.is_finite() and is_equal_approx(theme.volume_db, -8.0), "stop_all ends the speaker as well and puts the theme straight back")
	# a new load ends it
	party.set_party_loop(true, spot)
	app.load_epoch += 1
	tick_for(.1)
	check(not party.wants_loop and not party.stereo_player.playing, "A new load ends the speaker's music")

	# ---- the party controller turns it on and off
	check(flow.active() == false and not app.party_on(), "No party is on to begin with")
	app.household.party = party_record("inviting", true)
	app.household.party_serial = 1
	flow.present_music()
	check(not party.wants_loop, "While the party is only inviting, there is no music yet")
	app.household.party.phase = "active"
	flow.present_music()
	await settle()
	check(party.wants_loop and not party.loop_at.is_finite() and party.loop_player.playing, "A home with no stereo has the party loop played flat")
	check(not flow._stereo.is_finite(), "...because the controller found no stereo")
	# a stereo appears
	var placed: bool = false
	for place: Vector2 in [Vector2(-1.2, 1.0), Vector2(-.6, 1.6), Vector2(.4, 2.2), Vector2(-1.4, -.4), Vector2(1.0, -1.0)]:
		if app.world.can_place("stereo", Vector3(place.x, .16, place.y), 0.0):
			app.world.add_item({"id": "party_stereo", "kind": "stereo", "x": place.x, "z": place.y, "rotation": 0.0})
			placed = true
			break
	check(placed and not stereo_item().is_empty(), "A stereo is set up")
	flow._stereo_clock = 0.0
	flow.present_music()
	await settle()
	var speaker: Vector3 = (stereo_item().node as Node3D).global_position
	check(party.wants_loop and party.loop_at.is_finite() and party.loop_at.distance_to(speaker + Vector3(0, 1.0, 0)) < .05, "With a stereo in the house the loop comes from it, a meter up")
	check(party.stereo_player.playing and not party.loop_player.playing, "The speaker is the one playing")
	flow.set_music(false)
	await settle()
	check(not bool(app.household.party.music) and not party.wants_loop and not party.stereo_player.playing, "The host's Music button silences it")
	flow.set_music(true)
	await settle()
	check(bool(app.household.party.music) and party.wants_loop and party.stereo_player.playing, "...and brings it back")
	app.household.party.phase = "ending"
	flow.present_music()
	check(not party.wants_loop, "The music ends with the party's last stretch")
	# a party with nobody left ends and takes its music with it
	app.household.party.phase = "active"
	app.household.party.guests[0].status = "inside"
	app.household.party.guests[0].came = true
	flow.present_music()
	check(party.wants_loop, "The music is on once more")
	app.mode = "live"
	flow.tick(DT)
	flow._clock = 0.0
	flow.tick(DT)
	check(not flow.active() and not party.wants_loop and not party.stereo_player.playing and not party.loop_player.playing, "When the last guest has gone the party ends and the music stops")
	check(is_equal_approx(theme.volume_db, -8.0) or theme.volume_db > LifePartyMusic.DUCK_DB, "The theme is on its way back up")
	print("PARTY MUSIC TESTS: %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await frames(2)
	quit(1 if not failures.is_empty() else 0)
