extends SceneTree
## Every life-stage change is announced in the middle of the screen: a card that
## names the new stage, a loud fanfare and large streamers, and nothing blocks the
## game underneath. Celebrations wait their turn, wait for a menu to close, and
## never survive a load. The routing for the later milestones (retiring, driving,
## the pension) is checked here with synthetic milestones.
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

func boot(sound: bool) -> void:
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(sound)
	app.household_profiles = [
		{"name": "Ada Vale", "age_stage": "adult", "traits": []},
		{"name": "Kit Vale", "age_stage": "child", "traits": []},
		{"name": "Tess Vale", "age_stage": "teen", "traits": []},
		{"name": "Yan Vale", "age_stage": "young_adult", "traits": []},
		{"name": "Pip Vale", "age_stage": "child", "traits": []}]
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_speed(0)

func member(first_name: String) -> LifeSim:
	for entry: Dictionary in app.household.members:
		if str(entry.sim.character.name).begins_with(first_name): return entry.sim
	return null

func member_id(first_name: String) -> String:
	for entry: Dictionary in app.household.members:
		if str(entry.sim.character.name).begins_with(first_name): return str(entry.id)
	return ""

## The celebrations on the screen right now.
func celebrations() -> Array:
	return app.get_children().filter(func(node: Node) -> bool: return node is LifeMilestoneCelebration and not node.is_queued_for_deletion())

## Let the controller notice what is waiting, then return what is showing.
func show_now() -> Node:
	app._process(DT)
	await frames(2)
	var shown: Node = app.announcements.current if app.announcements.showing() else null
	if shown != null: shown.set_process(false)
	return shown

## Run the showing celebration out to its end, so the next can start.
func finish_current() -> void:
	var shown: Node = app.announcements.current
	if is_instance_valid(shown): shown.advance(shown.duration + 1.0)
	await frames(2)

func players_in(node: Node) -> Array: return node.find_children("*", "AudioStreamPlayer", true, false)

func run() -> void:
	await boot(true)
	check(is_instance_valid(app.announcements) and is_instance_valid(app.party_music), "The controller owns an announcement service and a party music owner")
	check(app.household.member_milestone.is_connected(app.announcements.milestone), "The household's milestone signal reaches the announcements")

	# ---- the old signals keep their shape
	var two_args: Array = []
	var three_args: Array = []
	var milestones: Array = []
	member("Kit").age_changed.connect(func(previous: String, current: String): two_args.append([previous, current]))
	app.household.member_age_changed.connect(func(id: String, previous: String, current: String): three_args.append([id, previous, current]))
	app.household.member_milestone.connect(func(id: String, kind: String, data: Dictionary): milestones.append([id, kind, data]))

	# ---- one birthday, in full
	var kit: LifeSim = member("Kit")
	check(kit.celebrate_birthday(false), "Kit's birthday happens")
	check(two_args == [["child", "teen"]] and three_args.size() == 1 and three_args[0] == [member_id("Kit"), "child", "teen"], "age_changed and member_age_changed keep their two and three arguments")
	check(milestones.size() == 1 and milestones[0][1] == "birthday" and milestones[0][2].current == "teen" and milestones[0][2].source == "auto" and milestones[0][0] == member_id("Kit"), "The household relays one birthday milestone naming the stages and where it came from")
	check(celebrations().is_empty(), "Nothing is on the screen until the controller's next frame")
	var banner: Node = await show_now()
	check(banner != null and banner.title == "Kit is now a teenager!", "The banner names the new stage: %s" % (str(banner.title) if banner != null else "no banner"))
	check(banner != null and banner.subtitle.contains("Happy birthday, Kit Vale"), "...and wishes the person a happy birthday in the smaller line")
	check(banner != null and banner.style == "grand" and banner.sound, "A birthday is the grand style with the fanfare on")
	var viewport: Vector2 = app.get_viewport().get_visible_rect().size
	var centre: Vector2 = banner.title_label.get_global_rect().get_center()
	check(absf(centre.x - viewport.x * .5) <= viewport.x * .05 and absf(centre.y - viewport.y * .5) <= viewport.y * .05, "The title sits within 5%% of the middle of the screen (%s in %s)" % [str(centre), str(viewport)])
	check(banner.title_label.get_theme_font_size("font_size") >= 48 and banner.title_label.text == banner.title, "The title is at least 48 px")
	check(is_instance_valid(banner.banner) and banner.banner.name == "MilestoneBanner" and banner.title_label.name == "MilestoneTitle" and banner.subtitle_label.name == "MilestoneSubtitle", "The card and its two lines have their names")
	check(banner.layer == 61, "The celebration is on its own layer above the interface")
	check(banner.pieces.size() >= 200, "At least 200 streamers and confetti pieces (%d)" % banner.pieces.size())
	var smallest: float = 1000.0
	for piece: Dictionary in banner.pieces: smallest = minf(smallest, minf(piece.node.size.x, piece.node.size.y))
	check(smallest >= 30.0, "Every piece is at least 30 px on its shortest side (%.0f)" % smallest)
	var solid: Array[String] = []
	for control: Node in banner.find_children("*", "Control", true, false):
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE: solid.append(str(control.name))
	check(solid.is_empty() and banner.canvas.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Nothing in the celebration takes the mouse (%s)" % ", ".join(solid))
	var players: Array = players_in(banner)
	check(players.size() == 1 and players[0].name == "MilestoneFanfare", "With sound on there is one fanfare player (%d)" % players.size())
	check(players.size() == 1 and players[0].stream.get_length() >= 2.5 and players[0].volume_db >= -1.0 and players[0].playing, "...at full volume and at least 2.5 seconds long")
	var moved_before: Vector2 = banner.pieces[0].node.position
	banner.advance(1.0)
	check(banner.pieces[0].node.position != moved_before and banner.banner.modulate.a > .99, "The streamers fly and the card is fully shown after a second")
	banner.advance(banner.duration - banner.elapsed - 0.1)
	check(is_instance_valid(banner) and not banner.is_queued_for_deletion() and banner.remaining() < 0.2, "It is still up just before seven seconds (%.2f left)" % banner.remaining())
	banner.advance(0.3)
	await frames(2)
	check(not is_instance_valid(banner), "It removes itself after seven seconds")
	check(celebrations().is_empty() and not app.announcements.showing(), "Nothing is left on the screen afterwards")

	# ---- every stage has its words, through the real birthday path
	var tess: LifeSim = member("Tess")
	var yan: LifeSim = member("Yan")
	var ada: LifeSim = member("Ada")
	milestones.clear()
	tess.celebrate_birthday(false)
	yan.celebrate_birthday(false)
	ada.celebrate_birthday(false)
	check(milestones.size() == 3, "Three birthdays in one moment make three milestones")
	var first: Node = await show_now()
	check(first != null and first.title == "Tess is now a young adult!", "First in line: %s" % (str(first.title) if first != null else "none"))
	check(celebrations().size() == 1 and app.announcements.queue.size() == 2, "Only one is on the screen while two wait (%d showing, %d waiting)" % [celebrations().size(), app.announcements.queue.size()])
	await finish_current()
	var second: Node = await show_now()
	check(second != null and second.title == "Yan is now an adult!", "Then the next one: %s" % (str(second.title) if second != null else "none"))
	await finish_current()
	var third: Node = await show_now()
	check(third != null and third.title == "Ada is now an elder!", "Then the last: %s" % (str(third.title) if third != null else "none"))
	await finish_current()
	check(await show_now() == null and celebrations().is_empty(), "And then the screen is clear")
	app.household.member_milestone.emit(member_id("Kit"), "birthday", {"current": "child"})
	var child_words: Node = await show_now()
	check(child_words != null and child_words.title == "Kit is now a child!", "A child's words: %s" % (str(child_words.title) if child_words != null else "none"))
	await finish_current()
	check(LifeLifecycle.milestone_text("Kit", "baby") == "Kit is now a baby!", "Every stage the game knows has its words")

	# ---- the paid birthday gets the same banner, and says where it came from
	milestones.clear()
	var tess_again: LifeSim = member("Tess")
	tess_again.celebrate_birthday(false, "cake")
	check(tess_again.last_birthday_source == "cake" and milestones.size() == 1 and milestones[0][2].source == "cake", "The paid birthday is announced as a cake birthday")
	var cake: Node = await show_now()
	check(cake != null and cake.title.begins_with("Tess is now an ") and cake.style == "grand", "...with the same grand banner (%s)" % (str(cake.title) if cake != null else "none"))
	await finish_current()

	# ---- the real clock: a child whose twenty normal days run out is announced as a teenager
	var pip: LifeSim = member("Pip")
	check(str(pip.character.age_stage) == "child" and LifeLifecycle.duration("child", str(pip.lifecycle.lifespan)) == 20.0, "A child's stage is twenty days long at the normal pace")
	milestones.clear()
	pip.lifecycle.progress = 1.0 - 10.0 / (20.0 * 1440.0)
	pip._advance_age(5.0)
	check(str(pip.character.age_stage) == "child" and milestones.is_empty() and celebrations().is_empty(), "Five minutes before the twentieth day ends nothing has happened")
	pip._advance_age(5.0)
	check(str(pip.character.age_stage) == "teen" and milestones.size() == 1 and milestones[0][2].source == "auto" and pip.last_birthday_source == "auto", "When the days run out the automatic birthday makes them a teenager")
	var natural: Node = await show_now()
	check(natural != null and natural.title == "Pip is now a teenager!" and natural.style == "grand" and players_in(natural).size() == 1, "...with the banner and the fanfare (%s)" % (str(natural.title) if natural != null else "none"))
	await finish_current()

	# ---- turning Sound off silences a fanfare that is still playing
	app.household.member_milestone.emit(member_id("Kit"), "birthday", {"current": "teen"})
	var loud: Node = await show_now()
	check(loud != null and players_in(loud).size() == 1 and players_in(loud)[0].playing, "A fanfare is playing")
	app.set_sound(false)
	check(loud != null and not players_in(loud)[0].playing and not players_in(loud)[0].stream_paused, "Muting stops it at once")
	await finish_current()
	app.set_sound(true)

	# ---- sound off: the same banner without the fanfare
	app.set_sound(false)
	app.household.member_milestone.emit(member_id("Kit"), "birthday", {"current": "teen"})
	var quiet: Node = await show_now()
	check(quiet != null and not quiet.sound and players_in(quiet).is_empty() and quiet.pieces.size() >= 200, "With sound off the banner and streamers show but no player is made")
	await finish_current()
	app.set_sound(true)

	# ---- a menu that pauses the game holds celebrations back
	app._begin_pause_overlay()
	app.household.member_milestone.emit(member_id("Kit"), "birthday", {"current": "teen"})
	check(await show_now() == null and app.announcements.queue.size() == 1, "A paused menu holds the celebration back")
	app.close_overlay()
	app.household.set_speed(0)
	var released: Node = await show_now()
	check(released != null and released.title == "Kit is now a teenager!", "It appears once the menu closes")
	await finish_current()

	# ---- the later milestones, by their routing
	var ada_id: String = member_id("Ada")
	app.household.member_milestone.emit(ada_id, "retired", {})
	var retired: Node = await show_now()
	check(retired != null and retired.title == "Ada Vale is now retired" and retired.style == "grand" and players_in(retired).size() == 1, "Retired: the grand banner, with the name and the fanfare (%s)" % (str(retired.title) if retired != null else "none"))
	await finish_current()
	app.household.member_milestone.emit(member_id("Kit"), "driving_licensed", {})
	var licensed: Node = await show_now()
	check(licensed != null and licensed.title == "Kit can now drive!" and licensed.style == "grand", "A licence: the grand banner (%s)" % (str(licensed.title) if licensed != null else "none"))
	await finish_current()
	app.household.member_milestone.emit(member_id("Kit"), "driving_introduced", {})
	var introduced: Node = await show_now()
	check(introduced != null and introduced.style == "card" and introduced.title == "Kit can learn to drive" and introduced.pieces.is_empty() and players_in(introduced).is_empty(), "Driving introduced: a quiet card with no streamers and no fanfare")
	await finish_current()
	app.household.member_milestone.emit(ada_id, "retirement_eligible", {})
	await frames(1)
	check(app.notice_text.contains("Ada") and app.notice_text.contains("retire") and celebrations().is_empty(), "Retirement eligibility is a corner notice, not a banner (%s)" % app.notice_text)
	app.household.member_milestone.emit(ada_id, "pension", {"amount": 1000})
	await frames(1)
	check(app.notice_text.contains("ℒ1,000") and celebrations().is_empty(), "A pension is a corner notice with the amount (%s)" % app.notice_text)
	app.household.member_milestone.emit(ada_id, "no_such_milestone", {})
	check(celebrations().is_empty() and app.announcements.queue.is_empty(), "An unknown milestone does nothing")

	# ---- letters
	app.household.post_box_provider = func() -> Array[String]: return ["post_box_1"]
	var before_letters: int = app.household.mail.letters.size()
	var kit_now: LifeSim = member("Kit")
	kit_now.celebrate_birthday(false)
	await show_now()
	await finish_current()
	var cards: Array = app.household.mail.letters.filter(func(letter: Dictionary) -> bool: return str(letter.title) == "Many happy returns")
	check(app.household.mail.letters.size() == before_letters + 1 and cards.size() == 1 and cards[0].subject == "Kit" and str(cards[0].body).contains("birthday card for Kit"), "A birthday posts the 'Many happy returns' card for the person (%d letters)" % app.household.mail.letters.size())
	app.household.day += 1
	app.household.post_birthday_letter("Kit")
	app.household.post_birthday_letter("Kit")
	app.household.day -= 1
	cards = app.household.mail.letters.filter(func(letter: Dictionary) -> bool: return str(letter.title) == "Many happy returns")
	check(cards.size() == 2, "A birthday on another day posts another card, and the same day posts only one (%d)" % cards.size())
	app.household.member_milestone.emit(ada_id, "retirement_eligible", {})
	var retire_cards: Array = app.household.mail.letters.filter(func(letter: Dictionary) -> bool: return str(letter.title) == "Time to put your feet up")
	app.household.member_milestone.emit(ada_id, "driving_introduced", {})
	await show_now()
	await finish_current()
	var drive_cards: Array = app.household.mail.letters.filter(func(letter: Dictionary) -> bool: return str(letter.title) == "Learning to drive")
	check(retire_cards.size() == 1 and drive_cards.size() == 1, "Retirement and driving each post their letter")

	# ---- a save being restored shows no old celebrations
	milestones.clear()
	app.household.restoring = true
	member("Tess")._emit_milestone("birthday", {"previous": "teen", "current": "young_adult", "source": "auto", "name": "Tess Vale", "day": 3})
	app.household.restoring = false
	check(milestones.is_empty(), "While a household is restoring, milestones are not relayed")

	# ---- a load throws away what is waiting and what is showing
	app.household.set_speed(0)
	check(app.save_game(), "The household saves (%s)" % app.notice_text)
	var slot: String = app.active_save_id
	member("Kit").celebrate_birthday(false)
	var live_banner: Node = await show_now()
	member("Tess").celebrate_birthday(false)
	app.household.member_milestone.emit(ada_id, "retired", {})
	check(live_banner != null and not app.announcements.queue.is_empty(), "A celebration is showing and others are waiting before the load")
	app.load_game(slot)
	await frames(4)
	app._process(DT)
	await frames(2)
	check(celebrations().is_empty() and app.announcements.queue.is_empty() and not app.announcements.showing(), "After a load nothing is showing and nothing is waiting")
	check(app.household.member_milestone.is_connected(app.announcements.milestone), "The loaded household is connected to the announcements")
	var after: LifeSim = member("Kit")
	after.celebrate_birthday(false)
	var later: Node = await show_now()
	check(later != null and later.title.begins_with("Kit is now "), "A birthday after the load is announced (%s)" % (str(later.title) if later != null else "none"))
	await finish_current()
	LifeSaveLibrary.delete_slot(slot)

	# ---- going back to the menu takes everything down
	app.household.member_milestone.emit(member_id("Ada"), "retired", {})
	app._process(DT)
	await frames(2)
	check(app.announcements.showing(), "A celebration is showing before leaving the game")
	app.mode = "creator"
	app._process(DT)
	await frames(2)
	check(celebrations().is_empty() and app.announcements.queue.is_empty(), "Leaving for the main menu takes the celebration down")

	print("Milestone announcement: %d checks, %d failures." % [checks, failures.size()])
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
