extends SceneTree
## Gathering round the cake: when a birthday comes round on its own (a child
## turning into a teenager is the headline), the family gathers round a cake, sings
## to the music-box tune, the birthday person blows out the candles and a real cake
## is set out to share. The paid birthday at the fridge stays a solo celebration.
## Covers the waiting rules (the clock of the day, away at school, homework, busy
## people), cancelling, a save in the middle of the song, and saves that lie.
const DT: float = .1
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

## A fresh game. `profiles` are the household. The default is the first Monday at
## 16:40, after the school run, so nobody has school or work to leave for. (Only the
## clock of the day is moved, never the day, so a save of it stays believable.)
func boot(profiles: Array, starter: String = "willow", day: int = 1, minutes: float = 1000.0) -> void:
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(true)
	app.household_profiles = profiles
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find(starter))
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_speed(0)
	set_clock(day, minutes)
	for member: Dictionary in app.household.members:
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 85.0
		member.sim.autonomy = true

func set_clock(day: int, minutes: float) -> void:
	app.household.day = day
	app.household.minutes = minutes
	for member: Dictionary in app.household.members:
		member.sim.day = day
		member.sim.minutes = minutes

func trio() -> Array:
	return [{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Ben Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]

func member(first: String) -> LifeSim:
	for entry: Dictionary in app.household.members:
		if str(entry.sim.character.name).begins_with(first): return entry.sim
	return null

func member_id(first: String) -> String:
	for entry: Dictionary in app.household.members:
		if str(entry.sim.character.name).begins_with(first): return str(entry.id)
	return ""

func body(first: String) -> LifeActor: return app.world.actors.get(member_id(first))

func item_of(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind: return item
	return {}

## Run frames until `done` says so (or the limit runs out). Real frames now and
## then let deferred calls happen.
func run_until(done: Callable, limit: int = 8000) -> bool:
	for index: int in limit:
		app._process(DT)
		if index % 25 == 0: await process_frame
		if done.call(): return true
	return false

func kit_session() -> Dictionary: return app.household.birthday_session_for(member_id("Kit"))

## Game minutes into the gathering, on the birthday person's own clock.
func elapsed_of(session: Dictionary) -> float:
	if session.is_empty(): return -1.0
	return float(app.household.member_sim(str(session.celebrant_id)).get_current_action().get("elapsed", 0.0))

func flames_lit(cake: Node) -> int:
	var lit: int = 0
	for flame: Node in cake.find_children("Flame_*", "Node3D", true, false):
		if (flame as Node3D).visible: lit += 1
	return lit

## Whether every ornament the table came with (its bowl of fruit) is hidden.
func fruit_hidden(table: Dictionary) -> bool:
	var seen: int = 0
	for prop: Dictionary in app.world._surface_props(table):
		for node: Node3D in prop.nodes:
			seen += 1
			if node.visible: return false
	return seen > 0

## A Lifelet who is free for the ritual, with some of it changed.
func facts(changes: Dictionary) -> Dictionary:
	return {"living": true, "home": true, "front_id": "", "until_duty": INF}.merged(changes, true)

func moodlet_labels(sim: LifeSim) -> Array:
	return sim.moodlets.map(func(entry: Dictionary) -> String: return str(entry.label))

func run() -> void:
	# ---- the rules on their own
	check(LifeBirthdayRitual.phase_at(0.0) == "sing" and LifeBirthdayRitual.phase_at(16.9) == "sing" and LifeBirthdayRitual.phase_at(17.0) == "hush" and LifeBirthdayRitual.phase_at(18.5) == "blow" and LifeBirthdayRitual.phase_at(19.5) == "cheer", "The ritual runs sing, hush, blow and cheer")
	check(is_equal_approx(LifeBirthdayRitual.SING_END, 17.0) and absf(CelebrationAudio.tune_seconds() - LifeBirthdayRitual.SING_END) < 1.0, "The sung part is as long as the music-box tune (%.1f seconds)" % CelebrationAudio.tune_seconds())
	check(LifeBirthdayRitual.window_open(420.0) and LifeBirthdayRitual.window_open(1290.0) and not LifeBirthdayRitual.window_open(419.0) and not LifeBirthdayRitual.window_open(1291.0), "Gatherings are held between 07:00 and 21:30")
	check(LifeBirthdayRitual.eligible(facts({})), "A Lifelet at home with nothing on is free")
	check(not LifeBirthdayRitual.eligible(facts({"home": false})) and not LifeBirthdayRitual.eligible(facts({"front_id": "sleep"})) and not LifeBirthdayRitual.eligible(facts({"front_id": "nap"})) and not LifeBirthdayRitual.eligible(facts({"in_session": true})) and not LifeBirthdayRitual.eligible(facts({"front_id": "school_day"})) and not LifeBirthdayRitual.eligible(facts({"front_id": "career_day"})), "Away, asleep, napping, already gathered or heading for school or work: not free")
	check(not LifeBirthdayRitual.eligible(facts({"until_duty": 45.0}))and LifeBirthdayRitual.eligible(facts({"until_duty": 46.0})), "Not free with a duty within forty-five minutes")
	check(LifeBirthdayRitual.eligible(facts({"front_id": "homework", "front_active": false, "front_by_player": true, "until_duty": INF})) and LifeBirthdayRitual.eligible(facts({"front_id": "homework", "front_active": true, "front_by_player": false})), "A birthday does not wait for homework")
	check(not LifeBirthdayRitual.eligible(facts({"front_id": "cook", "front_active": true, "front_by_player": true})), "...but a player's activity that has begun is left alone")
	check(not LifeBirthdayRitual.eligible(facts({"baby": true})), "A baby is too small to sing")
	check(LifeBirthdayRitual.moodlet("celebrant", 2).label == "Best birthday ever" and LifeBirthdayRitual.moodlet("celebrant", 1).label == "Make a wish" and LifeBirthdayRitual.moodlet("singer", 3).label == "Birthday wishes", "The moods: best birthday ever from two singers, a wish from fewer, birthday wishes for a singer")
	var half: Vector2 = LifeMeals.SURFACE_HALF_SIZE.dining
	var slots: Array[Vector3] = LifeBirthdayRitual.ring_slots(half)
	var nearest_pair: float = INF
	for first_index: int in slots.size():
		for second_index: int in range(first_index + 1, slots.size()): nearest_pair = minf(nearest_pair, slots[first_index].distance_to(slots[second_index]))
	check(slots.size() == 12 and nearest_pair > LifeBirthdayRitual.MIN_SPACING and slots[0].z > half.y and is_zero_approx(slots[0].x), "Twelve places round a table, the first in front on a long side, none closer than %.2f m (%.2f)" % [LifeBirthdayRitual.MIN_SPACING, nearest_pair])
	check(LifeBirthdayRitual.held_offsets(4).size() == 4 and LifeBirthdayRitual.held_offsets(0).is_empty(), "A ring round a held cake")
	check(LifeBirthdayRitual.group_error(["a", "b"], ["a", "b"]).is_empty() and not LifeBirthdayRitual.group_error(["a", "a"], ["a"]).is_empty() and not LifeBirthdayRitual.group_error(["z"], ["a"]).is_empty() and not LifeBirthdayRitual.group_error([], ["a"]).is_empty(), "A group needs real, different members")
	# The poses, on one body at a time
	for stage: String in ["child", "teen", "adult"]:
		var pose_actor: LifeActor = preload("res://scripts/actor.gd").new()
		root.add_child(pose_actor)
		pose_actor.configure({"name": "Pose QA", "age_stage": stage, "low_detail": true})
		pose_actor.voice_enabled = false
		pose_actor.celebration_presentation = {"role": "celebrant", "ritual_phase": "sing", "elapsed": 3.0, "held_cake": false, "cake_point": Vector3.ZERO}
		for index: int in 90: pose_actor.animate(1.0 / 60.0, 1, false, "blow_candles")
		check(not pose_actor._birthday_cake.visible and pose_actor._joints.Head.rotation.x < .15, "%s: the birthday person waits upright for the song, with no cake in their hands (pitch %.2f)" % [stage, pose_actor._joints.Head.rotation.x])
		pose_actor.celebration_presentation.elapsed = 18.8
		for index: int in 90: pose_actor.animate(1.0 / 60.0, 1, false, "blow_candles")
		check(pose_actor._joints.Head.rotation.x > .15, "%s: they lean in to blow as the flames go out (pitch %.2f)" % [stage, pose_actor._joints.Head.rotation.x])
		pose_actor.celebration_presentation.elapsed = 22.0
		for index: int in 90: pose_actor.animate(1.0 / 60.0, 1, false, "blow_candles")
		check(pose_actor._joints.Head.rotation.x < .1, "%s: and straighten up to clap (pitch %.2f)" % [stage, pose_actor._joints.Head.rotation.x])
		var frozen: Transform3D = pose_actor._joints.Head.transform
		pose_actor.animate(.6, 0, true, "")
		check(pose_actor._joints.Head.transform.is_equal_approx(frozen), "%s: a pause freezes the pose" % stage)
		pose_actor.celebration_presentation = {"role": "celebrant", "ritual_phase": "sing", "elapsed": 3.0, "held_cake": true, "cake_point": Vector3.ZERO}
		for index: int in 90: pose_actor.animate(1.0 / 60.0, 1, false, "blow_candles")
		var lit: int = pose_actor._cake_flames.filter(func(flame: Node3D) -> bool: return flame.visible).size()
		check(pose_actor._birthday_cake.visible and lit == 3, "%s: a held cake is in their hands with three candles lit (%d)" % [stage, lit])
		pose_actor.celebration_presentation.elapsed = 19.0
		for index: int in 90: pose_actor.animate(1.0 / 60.0, 1, false, "blow_candles")
		lit = pose_actor._cake_flames.filter(func(flame: Node3D) -> bool: return flame.visible).size()
		check(pose_actor._birthday_cake.visible and lit == 0, "%s: the candles are out and the cake is still held" % stage)
		pose_actor.celebration_presentation.elapsed = 22.0
		for index: int in 90: pose_actor.animate(1.0 / 60.0, 1, false, "blow_candles")
		check(not pose_actor._birthday_cake.visible, "%s: the cake is put away for the cheer" % stage)
		var singer_actor: LifeActor = preload("res://scripts/actor.gd").new()
		root.add_child(singer_actor)
		singer_actor.configure({"name": "Singer QA", "age_stage": stage, "low_detail": true})
		singer_actor.voice_enabled = false
		singer_actor.celebration_presentation = {"role": "singer", "ritual_phase": "sing", "elapsed": 3.0, "held_cake": true, "cake_point": Vector3.ZERO}
		var sway: Array[float] = []
		for index: int in 240:
			singer_actor.animate(1.0 / 60.0, 1, false, "sing_birthday")
			if index % 20 == 0: sway.append(singer_actor._joints.Head.rotation.y)
		check(not singer_actor._birthday_cake.visible and sway.max() - sway.min() > .001, "%s: a singer carries no cake and moves with the tune" % stage)
		pose_actor.queue_free()
		singer_actor.queue_free()
	# The record of owed birthdays, checked on its own
	var save: Dictionary = {"day": 5, "members": [{"id": "player", "state": {"character": {"age_stage": "teen", "life_status": "living"}}}, {"id": "housemate_1", "state": {"character": {"age_stage": "adult", "life_status": "living"}}}]}
	var owed_entry: Dictionary = {"serial": 1, "member_id": "player", "from": "child", "to": "teen", "day": 4, "minutes": 600.0, "party_serial": 0}
	var record: Dictionary = {"version": 1, "next_serial": 2, "pending": [owed_entry]}
	check(LifeBirthdayRitual.validate(null, save).is_empty() and LifeBirthdayRitual.validate(LifeBirthdayRitual.fresh(), save).is_empty() and LifeBirthdayRitual.validate(record, save).is_empty(), "A missing, a fresh and a sound record are all accepted")
	check(LifeBirthdayRitual.validate({"version": 1, "next_serial": 2, "pending": [owed_entry.merged({"hold_until": 7000.0, "party_serial": 3}, true)]}, save).is_empty(), "A pause and a party number are allowed")
	var lies: Array = [
		["a record that is not one", "cake"],
		["an unknown version", record.merged({"version": 2}, true)],
		["a counter that is not a number", record.merged({"next_serial": "two"}, true)],
		["nine owed at once", record.merged({"pending": range(9).map(func(index: int) -> Dictionary: return owed_entry.merged({"serial": 1, "member_id": "m%d" % index}, true))}, true)],
		["an entry that is not a record", record.merged({"pending": ["cake"]}, true)],
		["a Lifelet nobody knows", record.merged({"pending": [owed_entry.merged({"member_id": "nobody"}, true)]}, true)],
		["the same Lifelet twice", record.merged({"next_serial": 3, "pending": [owed_entry, owed_entry.merged({"serial": 2}, true)]}, true)],
		["a stage that is skipped", record.merged({"pending": [owed_entry.merged({"to": "adult"}, true)]}, true)],
		["a stage the Lifelet has left", record.merged({"pending": [owed_entry.merged({"from": "teen", "to": "young_adult"}, true)]}, true)],
		["a number past the counter", record.merged({"pending": [owed_entry.merged({"serial": 2}, true)]}, true)],
		["a number of zero", record.merged({"pending": [owed_entry.merged({"serial": 0}, true)]}, true)],
		["a day too long ago", record.merged({"pending": [owed_entry.merged({"day": 2}, true)]}, true)],
		["a day in the future", record.merged({"pending": [owed_entry.merged({"day": 6}, true)]}, true)],
		["a time past midnight", record.merged({"pending": [owed_entry.merged({"minutes": 2000.0}, true)]}, true)],
		["a negative party number", record.merged({"pending": [owed_entry.merged({"party_serial": -1}, true)]}, true)],
		["a pause of no sense", record.merged({"pending": [owed_entry.merged({"hold_until": -5.0}, true)]}, true)]]
	for lie: Array in lies: check(not LifeBirthdayRitual.validate(lie[1], save).is_empty(), "A record with %s is refused" % lie[0])
	var passed: Dictionary = save.duplicate(true)
	passed.members[0].state.character.life_status = "passed"
	check(not LifeBirthdayRitual.validate(record, passed).is_empty(), "A birthday owed to someone who has passed on is refused")

	var only: String = OS.get_environment("RITUAL_ONLY")
	if only == "pure":
		print("TEEN BIRTHDAY RITUAL TESTS (rules only): %d checks, %d failures" % [checks, failures.size()])
		for message: String in failures: print("  FAILED: ", message)
		quit(1 if not failures.is_empty() else 0)
		return

	# ---- a child's birthday on a Monday afternoon, in the Willow home
	await boot(trio())
	var kit: LifeSim = member("Kit")
	var ada: LifeSim = member("Ada")
	var ben: LifeSim = member("Ben")
	var kit_id: String = member_id("Kit")
	var table: Dictionary = item_of("dining")
	var sofa: Dictionary = item_of("sofa")
	check(not table.is_empty() and not sofa.is_empty() and app.world.item_cloth(table).is_empty(), "The home has a dining table (bare) and a sofa")
	app.household.set_speed(3)
	# The real clock: a child's twenty days run out.
	kit.lifecycle.progress = 1.0 - .2 / (20.0 * 1440.0)
	check(app.household.pending_birthdays().is_empty() and app.household.birthday_session_for(kit_id).is_empty(), "Nothing is owed before the birthday")
	app._process(DT)
	app.household.set_speed(0)
	await frames(2)
	var owed: Array = app.household.pending_birthdays()
	check(str(kit.character.age_stage) == "teen" and owed.size() == 1 and str(owed[0].member_id) == kit_id and owed[0].from == "child" and owed[0].to == "teen" and owed[0].serial == 1 and owed[0].party_serial == 0, "The automatic birthday makes Kit a teenager and a cake is owed (%s)" % str(owed))
	check(app.household.celebrations.next_serial == 2, "The next owed birthday would be number two")
	# Ben has a plan of his own, lined up a moment before.
	check(ben.queue_action("relax", str(sofa.id), app.world.approach(sofa)), "Ben has queued a rest on the sofa")
	check(ben.action_queue[0].id == "relax" and str(ben.action_queue[0].phase) == "approach", "...and is walking to it")
	check(not app.birthday_flow.try_start(), "With the clock stopped nothing starts")
	app.household.set_speed(3)
	check(app.birthday_flow.try_start(), "With the clock running the family gathers")
	var session: Dictionary = kit_session()
	check(not session.is_empty() and session.kind == "birthday" and session.members[0] == kit_id and session.members.size() == 3 and str(session.celebrant_id) == kit_id and str(session.phase) == "assembling", "A birthday gathering with Kit first and both others (%s)" % str(session.get("members", [])))
	check(str(session.table_id) == str(table.id) and not bool(session.held), "...round the dining table")
	var spots: Array[Vector3] = []
	var near_table: bool = true
	var far_apart: bool = true
	for id: Variant in session.members:
		var spot: Vector3 = Vector3(session.positions[str(id)][0], session.positions[str(id)][1], session.positions[str(id)][2])
		for other: Vector3 in spots:
			if other.distance_to(spot) < .55: far_apart = false
		spots.append(spot)
		if Vector2(spot.x - table.node.global_position.x, spot.z - table.node.global_position.z).length() > 2.2: near_table = false
	check(near_table and far_apart, "Everyone's spot is within 2.2 m of the table and at least 55 cm from the next")
	check(kit.action_queue[0].id == "blow_candles" and kit.action_queue[0].cooperation_primary == true and kit.action_queue[0].cooperation_role == "celebrant" and str(kit.action_queue[0].target_id) == str(table.id), "Kit's own action is to blow out the candles, and owns the clock")
	check(ada.action_queue[0].id == "sing_birthday" and ben.action_queue[0].id == "sing_birthday" and ada.action_queue[0].cooperation_primary == false, "The others sing")
	check(ben.action_queue.size() == 2 and ben.action_queue[1].id == "relax" and str(ben.action_queue[1].phase) == "queued", "Ben's own plan waits behind the song")
	check(app.birthday_flow.notices.size() == 1 and app.birthday_flow.notices[0].contains("Everyone gathers round the cake for Kit!"), "The player is told (%s)" % str(app.birthday_flow.notices))
	check(not app.birthday_flow.try_start(), "A second gathering does not start for the same birthday")
	check(str(app.household.cooperation_state(str(session.id)).get("id", "")) == str(session.id), "The household knows the session")
	var friend_before: float = float(ada.relationships[kit_id].friendship)
	var friend_back_before: float = float(kit.relationships[member_id("Ada")].friendship)

	var arrived: bool = await run_until(func() -> bool: return str(kit_session().get("phase", "")) == "active")
	check(arrived, "Everyone reaches their place and the song can begin")
	app._process(DT)
	check(app.household.speed == 1 and app.birthday_flow.notices.any(func(line: String) -> bool: return line.contains("Slowing down")), "The game drops to Normal speed for the song")
	var cake: Node3D = app.birthday_flow.props.get(str(session.id))
	check(is_instance_valid(cake) and cake.get_parent() == table.node and flames_lit(cake) == 3, "A cake with three lit candles stands on the table")
	check(is_instance_valid(cake) and cake.scale.x > 1.4 and absf(cake.position.y - float(LifeMeals.SURFACE_HEIGHTS.dining)) < .02, "...on the table top, larger than the hand-held one")
	check(fruit_hidden(table), "The table's own bowl of fruit makes way for the cake")
	check(app.party_music.wants_tune and app.party_music.tune_player.playing and not app.party_music.tune_player.stream_paused, "The birthday tune is playing")
	check(app.party_music.current_voice() == "birthday" and app.music_player.volume_db <= app.party_music.theme_db, "...and the theme is turned down for it, not stopped")
	check(app.sim.speed == 1, "The selected Lifelet's clock agrees")
	await run_until(func() -> bool: return elapsed_of(kit_session()) >= 2.0)
	var heard: String = ""
	for first: String in ["Ada", "Ben"]:
		var said: Dictionary = body(first).speech_presentation()
		if not said.is_empty(): heard += str(said.text)
	check(heard.contains("♪"), "Singers have music notes in their speech bubbles (%s)" % heard)
	check(body("Kit").celebration_presentation.get("role") == "celebrant" and body("Ada").celebration_presentation.get("role") == "singer" and body("Ada").celebration_presentation.get("ritual_phase") == "sing", "Each person's body knows their part")
	# Pausing holds the song and the tune where they are.
	app.household.set_speed(0)
	# One frame lets the pause reach the player; the mixer keeps running in real time
	# until it does, so measuring before it can read a stale position on a busy machine.
	app._process(DT)
	var held_at: float = elapsed_of(kit_session())
	var tune_at: float = app.party_music.tune_position()
	for index: int in 20: app._process(DT)
	check(is_equal_approx(elapsed_of(kit_session()), held_at) and app.party_music.tune_player.stream_paused and absf(app.party_music.tune_position() - tune_at) < .05, "Pausing holds the song and the tune where they are")
	app.household.set_speed(1)
	await run_until(func() -> bool: return elapsed_of(kit_session()) >= held_at + 1.0, 400)
	check(elapsed_of(kit_session()) >= held_at + 1.0 and not app.party_music.tune_player.stream_paused, "...and they carry on together afterwards")
	var sung: bool = await run_until(func() -> bool: return elapsed_of(kit_session()) >= 18.7)
	check(sung and flames_lit(cake) == 0, "The candles go out at the end of the hush")
	check(body("Kit")._joints.Head.rotation.x > .15, "The birthday person leans in and blows (head pitch %.2f)" % body("Kit")._joints.Head.rotation.x)
	var kit_wish: Dictionary = body("Kit").speech_presentation()
	check(not kit_wish.is_empty(), "They say something as the candles go out")
	await run_until(func() -> bool: return elapsed_of(kit_session()) >= 20.0)
	var cheer_heard: String = ""
	for first: String in ["Ada", "Ben"]:
		var said: Dictionary = body(first).speech_presentation()
		if not said.is_empty(): cheer_heard += str(said.text) + "|"
	check(cheer_heard.contains("Hooray") or cheer_heard.contains("Happy birthday, Kit") or cheer_heard.contains("wish") or cheer_heard.contains("Yay"), "Everyone cheers (%s)" % cheer_heard)
	check(not cheer_heard.contains("to you"), "No song lyrics are ever shown")
	var finished: bool = await run_until(func() -> bool: return kit_session().is_empty())
	await frames(2)
	check(finished, "The gathering ends after the cheer")
	check(moodlet_labels(kit).has("Best birthday ever") and moodlet_labels(ada).has("Birthday wishes") and moodlet_labels(ben).has("Birthday wishes"), "Kit has the best birthday ever and the singers have their wishes")
	check(float(ada.relationships[kit_id].friendship) == minf(100.0, friend_before + 4.0) and float(kit.relationships[member_id("Ada")].friendship) == minf(100.0, friend_back_before + 4.0), "Friendship grows by four both ways")
	check(kit.memories[0].label == "Blew out the candles" and str(kit.memories[0].detail).contains("2 people"), "Kit remembers it (%s)" % str(kit.memories[0]))
	check(app.household.pending_birthdays().is_empty(), "The birthday is no longer owed")
	var cakes: Array = app.household.meals.batches.filter(func(batch: Dictionary) -> bool: return str(batch.recipe) == "layer_cake")
	check(cakes.size() == 1 and cakes[0].initial == 8 and str(cakes[0].storage) == "surface" and str(cakes[0].host) == str(table.id) and str(cakes[0].chef) == kit_id, "A layer cake with eight servings is set out on the table for sharing (%s)" % str(cakes))
	app._process(DT)
	check(not is_instance_valid(app.birthday_flow.props.get(str(session.id))) and not app.party_music.wants_tune, "The candle cake and the tune are gone")
	check(body("Kit").celebration_presentation.is_empty() and body("Ada").celebration_presentation.is_empty(), "Nobody keeps a birthday pose")
	check(ben.action_queue.size() > 0 and ben.action_queue[0].id == "relax" and not bool(ben.action_queue[0].autonomous), "Ben's own plan is back at the front")
	check(app.household.cooperations.is_empty(), "No session is left over")
	check(app.household.speed == 3 and app.sim.speed == 3, "The speed the player had chosen is back after the song (%d)" % app.household.speed)

	if only.is_empty() or only == "owed": await scenario_who_is_owed()
	if only.is_empty() or only == "waiting": await scenario_waiting()
	if only.is_empty() or only == "busy": await scenario_busy_and_obstructed()
	if only.is_empty() or only == "cancelling": await scenario_cancelling()
	if only.is_empty() or only == "held": await scenario_held_cake()
	if only.is_empty() or only == "save": await scenario_save_and_load()
	if only.is_empty() or only == "lying": await scenario_lying_saves()

	print("TEEN BIRTHDAY RITUAL TESTS: %d checks, %d failures" % [checks, failures.size()])
	for message: String in failures: print("  FAILED: ", message)
	quit(1 if not failures.is_empty() else 0)


## The paid birthday at the fridge owes nothing; every automatic birthday owes a cake.
func scenario_who_is_owed() -> void:
	await boot(trio())
	app.household.set_speed(3)
	var kit: LifeSim = member("Kit")
	check(kit.celebrate_birthday(false, "cake") and kit.last_birthday_source == "cake", "Kit has the paid birthday at the fridge")
	check(app.household.pending_birthdays().is_empty() and not app.birthday_flow.try_start() and app.household.cooperations.is_empty(), "The paid birthday owes no cake and starts no gathering")
	check(not app.household.get_state().has("celebrations"), "...and the save has no record of one")
	var ada: LifeSim = member("Ada")
	check(ada.celebrate_birthday(false), "Ada's birthday comes round on its own")
	var owed: Array = app.household.pending_birthdays()
	check(owed.size() == 1 and owed[0].from == "adult" and owed[0].to == "elder", "An adult turning elder is owed a cake too (%s)" % str(owed))
	check(app.household.get_state().has("celebrations") and app.household.get_state().celebrations.pending.size() == 1, "A birthday that is owed is saved")
	check(app.birthday_flow.try_start(), "...and the family gathers for them")
	var session: Dictionary = app.household.birthday_session_for(member_id("Ada"))
	check(not session.is_empty() and session.members[0] == member_id("Ada") and session.members.size() == 3, "Everyone comes, Kit as well")
	check(member("Ben").celebrate_birthday(false) and app.household.pending_birthdays().size() == 2 and app.household.pending_birthdays()[1].serial == 2, "A second birthday is owed in turn")
	check(not app.birthday_flow.try_start(), "...but it waits: everyone is already at the first cake")
	# An owed birthday does not outlast the days: three midnights later it is dropped.
	app.household.cooperations.clear()
	for member_entry: Dictionary in app.household.members: member_entry.sim.action_queue.clear()
	app.household.set_speed(8)
	for night: int in 3:
		check(app.household.pending_birthdays().size() == 2, "Still owed before midnight %d" % (night + 1))
		set_clock(app.household.day, 1439.5)
		app._process(DT)
	check(app.household.day == 4 and app.household.pending_birthdays().is_empty(), "Birthdays owed for more than two days are dropped (day %d)" % app.household.day)

## The waiting rules: the clock of the day, a pupil away at school, a duty about to
## be due, and homework (which never makes a birthday wait).
func scenario_waiting() -> void:
	await boot(trio(), "willow", 1, 120.0)
	app.household.set_speed(3)
	var ada_id: String = member_id("Ada")
	member("Ada").celebrate_birthday(false)
	check(not app.household.birthday_entry(ada_id).is_empty() and not bool(app.household.birthday_plan(ada_id).ok) and not app.birthday_flow.try_start(), "A birthday at two in the morning waits")
	set_clock(1, 425.0)
	check(app.birthday_flow.try_start() and not app.household.birthday_session_for(ada_id).is_empty(), "...until seven")
	check(app.household.birthday_session_for(ada_id).members == [ada_id, member_id("Ben")], "...when a pupil with the bus coming stays out of it")
	# Leaving for work comes first, even for a gathering already under way.
	set_clock(1, float(member("Ada")._career_pattern().open) + 1.0)
	app.household.tick(.0)
	check(app.household.birthday_session_for(ada_id).is_empty() and not app.household.birthday_entry(ada_id).is_empty(), "A gathering still going when work is due is called off, and the cake stays owed")
	var kit: LifeSim = member("Kit")
	var kit_id: String = member_id("Kit")

	# a school morning: the bus is about to come
	await boot(trio(), "willow", 1, 420.0)
	app.household.set_speed(3)
	kit = member("Kit")
	kit_id = member_id("Kit")
	check(kit.minutes_until_departure() == 30.0, "At seven on a school day a pupil has thirty minutes (%.0f)" % kit.minutes_until_departure())
	kit.celebrate_birthday(false)
	var plan: Dictionary = app.household.birthday_plan(kit_id)
	check(not bool(plan.ok) and str(plan.error).contains("leave soon") and not app.birthday_flow.try_start(), "...so the birthday waits (%s)" % str(plan.get("error", "")))
	set_clock(1, 800.0)
	check(app.birthday_flow.try_start(), "After the school morning it goes ahead")

	# a school evening with homework still to do
	await boot(trio(), "willow", 1, 1050.0)
	app.household.set_speed(3)
	kit = member("Kit")
	kit_id = member_id("Kit")
	check(kit._autonomy_duty_id() == "homework","Kit has homework due this evening (%s)" % kit._autonomy_duty_id())
	check(kit.celebrate_birthday(false), "Kit's birthday comes round while the homework is due")
	check(bool(app.household.birthday_plan(kit_id).ok), "Homework due does not hold the birthday back (%s)" % str(app.household.birthday_plan(kit_id).get("error", "")))
	check(app.birthday_flow.try_start() and not kit_session().is_empty(), "The family gathers round the cake before the homework")
	check(member("Ada").action_queue[0].id == "sing_birthday" and kit.action_queue[0].id == "blow_candles", "...with the song at the front of everyone's queue")

	# a pupil at school is sent home by the birthday and gathers once back
	await boot(trio(), "willow", 1, 480.0)
	kit = member("Kit")
	kit_id = member_id("Kit")
	app.household.set_speed(8)
	var gone: bool = await run_until(func() -> bool: return kit.is_away(), 3000)
	check(gone, "Kit goes off to school")
	kit.celebrate_birthday(false)
	check(kit.is_away() and str(kit.away_state.get("phase", "")) == "returning", "The birthday sends the pupil home early")
	check(not bool(app.household.birthday_plan(kit_id).ok) and str(app.household.birthday_plan(kit_id).error).contains("away") and not app.birthday_flow.try_start(), "The cake waits for them to be home")
	var home: bool = await run_until(func() -> bool: return not kit.is_away(), 6000)
	check(home, "Kit walks home")
	var gathered: bool = await run_until(func() -> bool: return not kit_session().is_empty(), 4000)
	check(gathered, "The family gathers once Kit is home (it is %s)" % LifeCalendar.clock_text(app.household.minutes))

## Busy people are skipped with a notice, babies are not asked, and a spot that gets
## blocked drops its person.
func scenario_busy_and_obstructed() -> void:
	var profiles: Array = trio()
	profiles.append({"name": "Bea Vale", "age_stage": "baby", "traits": []})
	await boot(profiles)
	app.household.set_speed(3)
	var kit: LifeSim = member("Kit")
	var ada: LifeSim = member("Ada")
	var ben: LifeSim = member("Ben")
	var sofa: Dictionary = item_of("sofa")
	check(ben.queue_action("relax", str(sofa.id), app.world.approach(sofa)), "Ben has a rest under way")
	ben.action_queue[0].phase = "active"
	kit.celebrate_birthday(false)
	check(app.birthday_flow.try_start(), "The gathering starts without him")
	var session: Dictionary = kit_session()
	check(session.members == [member_id("Kit"), member_id("Ada")], "Only Kit and Ada gather: Ben is busy and Bea is a baby (%s)" % str(session.get("members", [])))
	var said: String = app.birthday_flow.notices[app.birthday_flow.notices.size() - 1]
	check(said.contains("Ben is busy and will miss the song.") and not said.contains("Bea"), "Ben is told he will miss the song (%s)" % said)
	check(ben.action_queue[0].id == "relax" and str(ben.action_queue[0].phase) == "active" and ben.action_queue.size() == 1, "Ben's own activity carries on untouched")
	# Something is put down on Ada's spot: just Ada steps out.
	var ada_spot: Vector3 = Vector3(session.positions[member_id("Ada")][0], session.positions[member_id("Ada")][1], session.positions[member_id("Ada")][2])
	app.world.add_item({"id": "spot_block_ada", "kind": "plant", "x": ada_spot.x, "z": ada_spot.z, "rotation": 0}, false)
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	session = kit_session()
	check(not session.is_empty() and session.members == [member_id("Kit")] and ada.action_queue.is_empty(), "A blocked spot sends that singer away and leaves the gathering")
	var kit_spot: Vector3 = Vector3(session.positions[member_id("Kit")][0], session.positions[member_id("Kit")][1], session.positions[member_id("Kit")][2])
	app.world.add_item({"id": "spot_block_kit", "kind": "plant", "x": kit_spot.x, "z": kit_spot.z, "rotation": 0}, false)
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	check(kit_session().is_empty() and kit.action_queue.is_empty() and not app.household.birthday_entry(member_id("Kit")).is_empty(), "A blocked spot for the birthday person calls the gathering off, and the cake stays owed")

## One singer steps out, the birthday person calls it off, a new day ends it.
func scenario_cancelling() -> void:
	await boot(trio())
	app.household.set_speed(3)
	var kit: LifeSim = member("Kit")
	var ada: LifeSim = member("Ada")
	var ben: LifeSim = member("Ben")
	var kit_id: String = member_id("Kit")
	kit.celebrate_birthday(false)
	check(app.birthday_flow.try_start(), "The family gathers")
	ada.cancel_action()
	var session: Dictionary = kit_session()
	check(not session.is_empty() and session.members == [kit_id, member_id("Ben")] and ada.action_queue.is_empty(), "A singer who steps out leaves the song to the others")
	await run_until(func() -> bool: return str(kit_session().get("phase", "")) == "active")
	check(str(kit_session().phase) == "active", "The rest still sing")
	kit.cancel_action()
	check(kit_session().is_empty() and ben.action_queue.is_empty() and kit.action_queue.is_empty(), "The birthday person calling it off ends it for everyone")
	var entry: Dictionary = app.household.birthday_entry(kit_id)
	check(not entry.is_empty() and entry.has("hold_until"), "The cake stays owed, with a pause before the next try")
	app._process(DT)
	check(not app.party_music.wants_tune and app.birthday_flow.props.is_empty() and body("Kit").celebration_presentation.is_empty(), "The tune and the cake go with it")
	check(not fruit_hidden(item_of("dining")) and app.household.speed == 3, "The table's fruit comes back, and so does the speed")
	check(not app.birthday_flow.try_start(), "It is not started again straight away")
	set_clock(app.household.day, app.household.minutes + 100.0)
	check(app.birthday_flow.try_start(), "...but is, a while later")
	# A new day ends a gathering that is still going.
	set_clock(app.household.day + 1, 600.0)
	app.household.tick(.0)
	check(kit_session().is_empty() and not app.household.birthday_entry(kit_id).is_empty(), "A new day ends a gathering; the birthday is still owed")

## With no table to put it on, the cake is held in two hands.
func scenario_held_cake() -> void:
	await boot(trio())
	app.household.set_speed(3)
	for item: Dictionary in app.world.items.duplicate():
		if str(item.kind) in ["dining", "counter", "corner_counter", "coffee_table", "table"]: app.world.remove_item(str(item.id))
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	var kit: LifeSim = member("Kit")
	var kit_id: String = member_id("Kit")
	kit.celebrate_birthday(false)
	check(app.birthday_flow.try_start(), "The family gathers with no table at all")
	var session: Dictionary = kit_session()
	check(bool(session.held) and str(session.table_id).is_empty() and session.members.size() == 3, "The cake is held in two hands, and both others come")
	check(str(kit.action_queue[0].target_id).is_empty() and kit.action_queue[0].target_kind == "birthday_cake" and kit.action_queue[0].cooperation_primary == true, "Kit's action names the cake, not a table")
	var near_kit: bool = true
	var kit_at: Vector3 = Vector3(session.positions[kit_id][0], session.positions[kit_id][1], session.positions[kit_id][2])
	for id: Variant in session.members:
		var spot: Vector3 = Vector3(session.positions[str(id)][0], session.positions[str(id)][1], session.positions[str(id)][2])
		if str(id) != kit_id and (spot.distance_to(kit_at) > 2.0 or spot.distance_to(kit_at) < .55): near_kit = false
	check(near_kit, "The others ring Kit within two metres")
	var arrived: bool = await run_until(func() -> bool: return str(kit_session().get("phase", "")) == "active")
	app._process(DT)
	check(arrived and app.birthday_flow.props.is_empty(), "They gather, and there is no cake on any table")
	var held: LifeActor = body("Kit")
	var lit: int = held._cake_flames.filter(func(flame: Node3D) -> bool: return flame.visible).size()
	check(held._birthday_cake.visible and lit == 3, "Kit holds the cake with its three candles lit (%d lit)" % lit)
	check(not body("Ada")._birthday_cake.visible, "Nobody else holds one")
	await run_until(func() -> bool: return elapsed_of(kit_session()) >= 18.8)
	lit = held._cake_flames.filter(func(flame: Node3D) -> bool: return flame.visible).size()
	check(lit == 0 and held._joints.Head.rotation.x > .15, "The candles are blown out (%d lit)" % lit)
	await run_until(func() -> bool: return elapsed_of(kit_session()) >= 21.0)
	check(not held._birthday_cake.visible, "The cake is put away for the cheering")
	var finished: bool = await run_until(func() -> bool: return kit_session().is_empty())
	var cakes: Array = app.household.meals.batches.filter(func(batch: Dictionary) -> bool: return str(batch.recipe) == "layer_cake")
	check(finished and cakes.size() == 1 and cakes[0].initial == 8 and str(cakes[0].storage) == "fridge", "With nowhere to set it out the cake goes in the fridge (%s)" % str(cakes))

## A save made in the middle of the song loads and the song carries on.
func scenario_save_and_load() -> void:
	await boot(trio())
	app.household.set_speed(3)
	var kit_id: String = member_id("Kit")
	member("Kit").celebrate_birthday(false)
	check(app.birthday_flow.try_start(), "The family gathers")
	await run_until(func() -> bool: return elapsed_of(kit_session()) >= 8.0)
	app.household.set_speed(0)
	var saved_at: float = elapsed_of(kit_session())
	check(saved_at >= 8.0 and str(kit_session().phase) == "active", "The song is eight minutes in (%.1f)" % saved_at)
	check(app.save_game("ritual_save", "Ritual"), "The game saves in the middle of the song")
	app.queue_free()
	await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(true)
	app.load_game("ritual_save")
	await frames(6)
	app.set_process(false)
	app.household.set_speed(0)
	app._process(DT)
	app._process(DT)
	var session: Dictionary = kit_session()
	check(not session.is_empty() and session.members.size() == 3 and session.members[0] == kit_id and absf(elapsed_of(session) - saved_at) < .01, "A fresh game loads the gathering at the same moment (%.2f)" % elapsed_of(session))
	check(not app.household.birthday_entry(kit_id).is_empty(), "...and the birthday is still owed")
	var cake: Node3D = app.birthday_flow.props.get(str(session.id))
	check(is_instance_valid(cake) and flames_lit(cake) == 3, "The cake is back on the table with its three candles lit")
	check(app.party_music.wants_tune and app.party_music.tune_player.stream_paused, "The tune is ready and held while the game is paused")
	check(absf(app.party_music.tune_position() - saved_at) < 2.0, "...at the place it had reached (%.1f of %.1f)" % [app.party_music.tune_position(), saved_at])
	check(body("Kit").celebration_presentation.get("role") == "celebrant" and absf(float(body("Kit").celebration_presentation.get("elapsed", -1.0)) - saved_at) < .01, "Everyone is posed for that moment")
	app.household.set_speed(1)
	var finished: bool = await run_until(func() -> bool: return kit_session().is_empty())
	check(finished and moodlet_labels(member("Kit")).has("Best birthday ever"), "Unpaused, the family finishes the song and Kit has the best birthday ever")
	check(app.household.meals.batches.any(func(batch: Dictionary) -> bool: return str(batch.recipe) == "layer_cake" and batch.initial == 8), "...and the cake is set out")

## A save that lies about the gathering or the owed birthdays is refused.
func scenario_lying_saves() -> void:
	await boot(trio())
	check(not app.household.get_state().has("celebrations"), "A household with nothing owed saves no birthday record")
	var plain: Dictionary = saved_state()
	check(bool(restore_result(plain).ok), "...and a save with no birthday record loads, as old saves do (%s)" % str(restore_result(plain).get("error", "")))
	app.household.set_speed(3)
	var kit_id: String = member_id("Kit")
	var ada_id: String = member_id("Ada")
	member("Kit").celebrate_birthday(false)
	check(app.birthday_flow.try_start(), "The family gathers")
	await run_until(func() -> bool: return elapsed_of(kit_session()) >= 3.0)
	app.household.set_speed(0)
	var clean: Dictionary = saved_state()
	var untouched: Dictionary = restore_result(clean)
	check(bool(untouched.ok), "A save in the middle of the song loads (%s)" % str(untouched.get("error", "")))
	var data: Dictionary = saved_state()
	data.cooperations[0].positions[ada_id] = data.cooperations[0].positions[kit_id]
	var result: Dictionary = restore_result(data)
	check(not bool(result.ok) and str(result.error).contains("stacks"), "Two people on one spot are refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.cooperations[0].id = "homework_9"
	for entry: Dictionary in data.members:
		if entry.state.action_queue.size() > 0 and entry.state.action_queue[0].has("cooperation_id"): entry.state.action_queue[0].cooperation_id = "homework_9"
	result = restore_result(data)
	check(not bool(result.ok) and str(result.error).contains("birthday"), "A gathering with the wrong kind of token is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	for entry: Dictionary in data.members:
		if entry.id == ada_id: entry.state.action_queue[0].id = "blow_candles"
	result = restore_result(data)
	check(not bool(result.ok) and str(result.error).contains("birthday"), "A singer carrying the birthday person's action is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	for entry: Dictionary in data.members: entry.state.action_queue[0].elapsed = 30.0
	result = restore_result(data)
	check(not bool(result.ok), "A song that has run past its end is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.cooperations[0].held = true
	result = restore_result(data)
	check(not bool(result.ok) and str(result.error).contains("table"), "A held cake that stands on a table is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.celebrations.pending = []
	result = restore_result(data)
	check(not bool(result.ok) and str(result.error).contains("not waiting"), "A gathering for a birthday that is not owed is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.celebrations.pending[0].to = "adult"
	result = restore_result(data)
	check(not bool(result.ok) and str(result.error).contains("skips"), "An owed birthday that skips a stage is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.celebrations.pending[0].day = int(data.day) + 5
	result = restore_result(data)
	check(not bool(result.ok) and str(result.error).contains("out-of-date"), "An owed birthday from the future is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.celebrations.pending.append(data.celebrations.pending[0].duplicate(true))
	result = restore_result(data)
	check(not bool(result.ok), "The same birthday owed twice is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.celebrations.pending[0].member_id = "nobody"
	result = restore_result(data)
	check(not bool(result.ok), "A birthday for nobody is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.celebrations.pending[0].serial = int(data.celebrations.next_serial) + 3
	result = restore_result(data)
	check(not bool(result.ok), "A birthday numbered past the counter is refused (%s)" % str(result.get("error", "")))
	data = saved_state()
	data.celebrations = "lots of cake"
	result = restore_result(data)
	check(not bool(result.ok), "A birthday record that is not a record is refused")

## The household's state as a save file would hold it.
func saved_state() -> Dictionary:
	return JSON.parse_string(JSON.stringify(app.household.json_safe(app.household.get_state())))

## What a fresh household makes of a saved state.
func restore_result(data: Dictionary) -> Dictionary:
	var fresh_household: LifeHousehold = LifeHousehold.new()
	root.add_child(fresh_household)
	var result: Dictionary = fresh_household.restore_state(data.duplicate(true))
	fresh_household.queue_free()
	return result
