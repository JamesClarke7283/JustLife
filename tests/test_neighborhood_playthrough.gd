extends "res://tests/test_playthrough.gd"
## Independent rendered eight-Lifelet, neighborhood, story and away-save flow.
## Inherits the isolation guard and real-frame/UI/mouse helpers, never game tick.

const TEST_NAMES: Array[String] = ["Ari Atlas", "Bea Brook", "Cy Cedar", "Dee Dawn", "Eli Ember", "Fay Fern", "Gio Grove", "Hal Harbor"]
const PLACE_NAMES: Dictionary = {"home":"Your home", "park":"Juniper Gardens", "library":"The Reading Room", "studio":"Common Ground Studio"}
var expected_home: Array = []
var expected_finish: String = ""
var story_chosen: Dictionary = {}

func _run() -> void:
	screenshot_dir = "res://art/neighborhood_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.set_sound(false)
	app.household.notice.connect(func(message: String) -> void: notices.append(message))
	app.household.member_action_finished.connect(func(member_id: String, action: Dictionary) -> void:
		completed.append(str(action.id))
		member_completed.append(member_id + ":" + str(action.id)))
	if resume_only:
		await _resume_away()
	else:
		await _enter_new_game()
		await _create_eight()
		await _speed_feedback()
		await _build_flow()
		expected_home = app.world.serialize_items().duplicate(true)
		expected_finish = app.floor_color
		await _cap("03_remodeled_home")
		await _neighborhood_flow()
		await _daily_story()
		await _save_away()
	_write_report()
	app.queue_free()
	await frames(3)
	print("NEIGHBORHOOD_RESULT assertions=%d failures=%d resume=%s" % [assertions, failures.size(), str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _cap(label_text: String, focus: bool = false) -> void:
	await screenshot(label_text, focus)
	evidence[-1]["venue"] = app.current_venue
	evidence[-1]["household_count"] = app.household.members.size()

func _create_eight() -> void:
	for i: int in range(8):
		if i > 0:await press("+ Add Lifelet")
		var edit: LineEdit = app.find_children("*", "LineEdit", true, false)[0]
		edit.text = TEST_NAMES[i]
		edit.text_changed.emit(edit.text)
		await press("Look")
		await press("Female" if i % 2 == 0 else "Male")
		await press(["Crop", "Bob", "Curls"][i % 3])
		await press("Wardrobe")
		if is_instance_valid(button_matching("Casual")):
			await press(["Casual", "Jacket", "Cardigan"][i % 3])
		await press(["Coastal", "Earthy", "Sage"][i % 3])
	check(app.household_profiles.size() == 8, "Creator holds eight individually named Lifelets.")
	var add_button: Button
	for node: Node in app.find_children("*", "Button", true, false):
		if node.text == "+ Add Lifelet":add_button = node
	check(is_instance_valid(add_button) and add_button.disabled, "Creator disables adding a ninth Lifelet.")
	_check_chips("creator")
	await _cap("01_eight_lifelet_creator")
	await press_member(TEST_NAMES[0])
	await press("Find my home", true)
	await press("Willow Cottage")
	await press("Start living", true)
	app.household.set_speed(0)
	for member: Dictionary in app.household.members:member.sim.autonomy = false
	var lane_neighbors:int=0
	for actor_id: String in app.world.actors:
		var household_member:bool=false
		for member: Dictionary in app.household.members:household_member = household_member or str(member.id) == actor_id
		if not household_member:lane_neighbors+=1
	check(app.household.members.size() == 8 and lane_neighbors==4, "Eight playable Lifelets enter the home with the four lane neighbors outside.")
	_check_chips("live")
	for i: int in range(8):
		await press_member(TEST_NAMES[i])
		check(app.sim.character.name == TEST_NAMES[i], "Household chip selects " + TEST_NAMES[i])
	await press_member(TEST_NAMES[0])
	await _cap("02_eight_lifelet_home")
	await _measure_frames()

func _check_chips(label_text: String) -> void:
	var rectangles: Array[Rect2] = []
	for person: String in TEST_NAMES:
		var found: Button
		for node: Node in app.find_children("*", "Button", true, false):
			if node.is_visible_in_tree() and str(node.tooltip_text).begins_with(person):found = node
		check(is_instance_valid(found), label_text + ": accessible identity chip for " + person)
		if is_instance_valid(found):rectangles.append(found.get_global_rect())
	var fits: bool = true
	var separates: bool = true
	for i: int in range(rectangles.size()):
		fits = fits and Rect2(0, 0, 1440, 900).encloses(rectangles[i])
		for j: int in range(i + 1, rectangles.size()):
			separates = separates and not rectangles[i].intersects(rectangles[j])
	check(fits and separates and rectangles.size() == 8, label_text + ": all eight chips fit without overlapping.")

func _measure_frames() -> void:
	await frames(20)
	var milliseconds: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	for i: int in range(60):
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		milliseconds.append(float(now - previous) / 1000.0)
		previous = now
	milliseconds.sort()
	var total: float = 0
	for value: float in milliseconds:total += value
	evidence[-1]["warm_idle_frame_pacing"] = {"frames":60, "mean_ms":total / 60.0, "p95_ms":milliseconds[56], "note":"Single eight-Lifelet idle view on current machine; not a device compatibility benchmark."}

func _speed_feedback() -> void:
	var labels: Array[String] = ["Ⅱ", "▶", "▶▶", "▶▶▶"]
	var values: Array[int] = [0, 1, 3, 8]
	for i: int in range(4):
		await press(labels[i])
		check(app.household.speed == values[i] and app.sim.speed == values[i], "HUD speed applies household-wide: " + str(values[i]))
		var selected: Button = button_matching(labels[i])
		var selected_style: StyleBox = selected.get_theme_stylebox("normal")
		var distinguished: bool = selected.toggle_mode and selected.button_pressed
		if selected_style is StyleBoxFlat:
			for j: int in range(4):
				if j == i:continue
				var other: StyleBox = button_matching(labels[j]).get_theme_stylebox("normal")
				if other is StyleBoxFlat and selected_style.bg_color != other.bg_color:distinguished = true
		check(distinguished, "Current speed has a persistent visible selected state: " + labels[i])
		# Preserve the selected running speed in these HUD-specific captures.
		await screenshot("02_speed_%d" % values[i], false, false)
	await press("Ⅱ")

func _travel(place: String) -> void:
	var funds_before: int = app.sim.funds
	var time_before: float = float(app.sim.day) * 1440.0 + app.sim.minutes
	var needs_before: Dictionary = app.sim.needs.duplicate(true)
	await press("Explore")
	check(app.overlay_pauses_sim and app.sim.speed == 0, "Neighborhood map pauses the household.")
	await press(str(PLACE_NAMES[place]))
	await _cap("map_" + place)
	await press("Travel here", true)
	# The shared car trip is an actual boarding walk, drive and arrival since
	# the travel-cinematic release, so the venue swap lands seconds later.
	var wait_started:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-wait_started<90000 and not (app.current_venue == place and app.mode == "live"):
		await frames(30)
	var entered: bool = app.current_venue == place and app.mode == "live"
	if entered:check(true, "Travel enters the selected destination: " + place)
	check(absf(float(app.sim.day) * 1440 + app.sim.minutes - time_before - 15.0) < 0.01, "Travel advances exactly fifteen game minutes.")
	check(app.sim.funds == funds_before, "Town travel has no unlisted money charge.")
	check(float(app.sim.needs.hunger) < float(needs_before.hunger), "Travel applies normal need decay.")
	var arrived: bool = app.household.members.size() == 8
	for member: Dictionary in app.household.members:arrived = arrived and app.world.actors.has(str(member.id))
	check(arrived, "All eight Lifelets arrive at " + place)
	var clear: bool = true
	for member: Dictionary in app.household.members:clear = clear and member.sim.action_queue.is_empty()
	check(clear and app.sim.speed == 0, "Travel clears old activities and preserves prior pause.")
	if place != "home":
		var expected_prefix: bool = true
		for item: Dictionary in app.world.items:expected_prefix = expected_prefix and str(item.id).begins_with(place + "_")
		check(expected_prefix, "Destination has its own stable furnishing identities.")
	await _cap("venue_" + place)

func _neighborhood_flow() -> void:
	# Pending orders are explicitly cleared by the travel flow shown in the map.
	await queue_via_menu("bed", "sleep")
	await _travel("park")
	await queue_via_menu("bench", "relax")
	app.household.set_speed(8)
	if await wait_until(func() -> bool: return active_is("relax", 0.45), "walk to the park bench and relax"):
		await _cap("04_park_bench", true)
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "finish park bench activity")
	app.household.set_speed(0)
	check(completed.has("relax"), "Park furniture supports a completed routed activity.")
	await _travel("library")
	await press("Build & buy")
	check(app.mode == "live" and app.current_venue == "library", "Public venue prevents editing the town as a private house.")
	await queue_via_menu("bookshelf", "read")
	app.household.set_speed(8)
	if await wait_until(func() -> bool: return active_is("read", 0.45), "route to library bookshelf and read"):
		await _cap("05_library_reading", true)
	await wait_until(func() -> bool: return app.sim.action_queue.is_empty(), "finish library reading")
	app.household.set_speed(0)
	check(float(app.sim.skills.logic.xp) > 0 or int(app.sim.skills.logic.level) > 1, "Library reading produces persistent Logic progress.")
	await _travel("studio")
	await press_member(TEST_NAMES[7])
	check(app.household.selected_index == 7, "Last household member becomes the away-save subject.")
	await press("Explore")
	root.size = Vector2i(1120, 700)
	await frames(6)
	await _cap("06_small_window_map")
	root.size = Vector2i(1440, 900)
	await frames(6)
	await press("Back to life")

func _daily_story() -> void:
	await press("Stories", true)
	await _cap("07_stories_before_daily_event")
	await press("Back to life")
	app.household.set_speed(8)
	# The evening story beat starts mid-morning after the venue circuit, so a
	# full day at very-fast speed needs up to ~three real minutes to cross
	# midnight; give the wait that whole budget.
	await wait_until(func() -> bool: return app.sim.day >= 2, "real simulation reaches the first daily story", 200)
	app.household.set_speed(0)
	var events: Array = app.sim.get_story_events()
	var event: Dictionary = {}
	for candidate: Dictionary in events:
		if candidate.id == "story_day_2":event = candidate
	check(not event.is_empty(), "First daily event appears on Day 2.")
	if event.is_empty():return
	await queue_via_menu("easel", "paint")
	var before_queue: Array = app.sim.action_queue.duplicate(true)
	var before_funds: int = app.sim.funds
	var before_needs: Dictionary = app.sim.needs.duplicate(true)
	var before_xp: float = float(app.sim.skills.cooking.xp)
	var before_friendship: float = float(app.sim.relationships.maya.friendship)
	var before_time: float = app.sim.minutes
	await press("Stories", true)
	await _cap("08_daily_story_choices")
	await press("Bring a homemade dish")
	check(app.sim.funds == before_funds - 24 and app.household.funds == app.sim.funds, "Story choice charges the displayed ℒ24 from the shared wallet.")
	check(absf(float(app.sim.needs.hunger) - minf(100, float(before_needs.hunger) + 12)) < 0.001 and absf(float(app.sim.needs.social) - minf(100, float(before_needs.social) + 24)) < 0.001, "Story choice applies its stated hunger/social changes.")
	check(absf(float(app.sim.skills.cooking.xp) - before_xp - 20) < 0.001 and absf(float(app.sim.relationships.maya.friendship) - before_friendship - 14) < 0.001, "Story choice grants displayed skill XP and friendship.")
	check(app.sim.minutes == before_time and equivalent(app.sim.action_queue, before_queue), "Story decision preserves time and queued player activity.")
	var remains: bool = false
	for candidate: Dictionary in app.sim.get_story_events():remains = remains or candidate.id == "story_day_2"
	check(not remains and app.sim.story_history[0].choice_id == "bring_dish", "Chosen daily event is consumed once and recorded in history.")
	story_chosen = app.sim.story_history[0].duplicate(true)
	await _cap("09_story_recorded")
	await press("Back to life")

func _save_away() -> void:
	var funds_before: int = app.sim.funds
	app.household.set_speed(8)
	if not await wait_until(func() -> bool: return active_is("paint", 0.15), "route to studio easel and begin paid painting", 40):return
	app.household.set_speed(0)
	check(app.sim.funds == funds_before - 20, "Studio painting charges its ℒ20 material cost on arrival.")
	await queue_via_menu("bookshelf", "read")
	await _cap("10_studio_painting_before_away_save", true)
	var expected: Dictionary = {"state":app.sim.get_state(), "player":vec(app.player.position), "world":app.world.serialize_items(), "lot":app.selected_lot, "floor":app.floor_color, "venue":app.current_venue, "home":expected_home, "finish":expected_finish, "story":story_chosen, "selected_index":app.household.selected_index, "members":[]}
	for member: Dictionary in app.household.members:
		expected.members.append({"id":member.id, "state":member.sim.get_state(), "position":vec(app.world.actors[member.id].position)})
	await _public_save("Juniper eight — studio chapter")
	var file := FileAccess.open("user://neighborhood_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected));file.close()
	await _cap("11_saved_away")

func _resume_away() -> void:
	check(FileAccess.file_exists("user://neighborhood_expected.json"), "Away checkpoint exists from prior process.")
	if not FileAccess.file_exists("user://neighborhood_expected.json"):return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://neighborhood_expected.json"))
	await _public_load()
	await _compare_saved(expected, "away fresh-process")
	check(app.current_venue == "studio" and app.world.house.name == "Community_studio", "Fresh process resumes in the actual saved public studio.")
	check(equivalent(app.home_layout, expected.home) and app.floor_color == expected.finish, "Away save retains the private home remodel and finish.")
	check(not app.sim.story_history.is_empty() and equivalent(app.sim.story_history[0], expected.story), "Chosen daily story and effects history survive restart.")
	var remains: bool = false
	for event: Dictionary in app.sim.get_story_events():remains = remains or event.id == "story_day_2"
	check(not remains, "Restart does not offer a consumed story for duplicate rewards.")
	await _cap("12_resumed_in_studio")
	var funds_before: int = app.sim.funds
	app.household.set_speed(8)
	await wait_until(func() -> bool: return active_is("paint", float(expected.state.action_queue[0].progress) + 0.02), "resume paid painting in studio")
	check(app.sim.funds == funds_before, "Away restart does not charge painting materials twice.")
	await _cap("13_resumed_studio_painting", true)
	app.household.set_speed(0)
	await _travel("home")
	check(equivalent(app.world.serialize_items(), expected.home), "Return home restores every furnishing and drawn wall/floor.")
	check(app.floor_color == expected.finish, "Return home restores selected floor finish.")
	_check_chips("returned home")
	await _cap("14_returned_remodeled_home")
	await press("Stories", true)
	await _cap("15_story_history_at_home")
	await press("Back to life")
