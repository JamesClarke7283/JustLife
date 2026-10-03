extends SceneTree
## What a Lifelet is offered at the pool and the hot tub, through the real click menu:
## a swim or a soak, or a place to watch the garden television from (a seat on the
## pool's coping, a relaxed place in the tub). Every age from a child up, elders
## included, may use the water; the television choices are listed even before a
## television stands in view, unavailable and saying what is missing.
##
##   JUSTLIFE_DATA_DIR=/tmp/x XDG_DATA_HOME=/tmp/y godot --headless --path . --audio-driver Dummy --script res://tests/test_water_choices.gd

const DT: float = 1.0 / 30.0
var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)


func frames(n: int = 3) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("This test needs an isolated JUSTLIFE_DATA_DIR.")
		quit(2)
		return
	_run.call_deferred()


func _boot(stages: Array) -> void:
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = []
	for index: int in stages.size():
		app.household_profiles.append({"name": "%s %d" % [str(stages[index]).capitalize(), index], "age_stage": stages[index], "traits": []})
	app.selected_lot = maxi(0, LifeProperties.starters_for(app.household_profiles).find("lumen"))
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_speed(0)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		for need: String in LifeSim.NEED_NAMES:
			member.sim.needs[need] = 80.0
		member.sim.minutes = 600.0
	app.household.minutes = 600.0
	app.world.add_item({"id": "wc_tub", "kind": "hot_tub", "x": -8.4, "z": -2.6, "rotation": 0.0})
	app.world.rebuild_navigation()
	app._refresh_sim_targets()


func _put_up_tv() -> void:
	app.world.add_item({"id": "wc_tv", "kind": "outdoor_tv", "x": -11.0, "z": -0.5, "rotation": 90.0})
	app.world.rebuild_navigation()
	app._refresh_sim_targets()


func _item(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == kind:
			return item
	return {}


## The buttons the click menu really shows for a furnishing, with whether each is on.
func _menu(item: Dictionary) -> Dictionary:
	app.close_overlay()
	app.show_interactions(item, Vector2(600, 400))
	await frames(2)
	var shown: Dictionary = {}
	for button: Node in app.overlay.find_children("*", "Button", true, false):
		var text: String = (button as Button).text
		if not text.is_empty():
			shown[text] = not (button as Button).disabled
	return shown


func _step(count: int) -> void:
	for i: int in count:
		app._process(DT)


func _until_active(sim: LifeSim, limit: int = 4000) -> bool:
	app.household.set_speed(3)
	for frame: int in limit:
		app._process(DT)
		if frame % 6 == 0:
			await process_frame
		var action: Dictionary = sim.get_current_action()
		if action.is_empty():
			return false
		if str(action.phase) == "active":
			return true
	return false


func _clear() -> void:
	for member: Dictionary in app.household.members:
		while not member.sim.action_queue.is_empty():
			member.sim.cancel_action()
	app.household.set_speed(0)
	_step(2)


func _run() -> void:
	await _boot(["adult", "adult", "elder"])
	var pool: Dictionary = _item("pool")
	var tub: Dictionary = _item("hot_tub")
	check(not pool.is_empty() and not tub.is_empty(), "The home has a pool and a hot tub to use")

	# ---- the menu, with no television in sight yet
	var pool_menu: Dictionary = await _menu(pool)
	check(pool_menu.get("Go for a swim", false), "The pool menu opens with a plain swim, not the generic garden label")
	check(pool_menu.has("Sit by the edge and watch the garden TV") and not pool_menu["Sit by the edge and watch the garden TV"], "The pool lists the edge seat, off until a garden TV is in view")
	var tub_menu: Dictionary = await _menu(tub)
	check(tub_menu.get("Soak in the hot tub", false), "The hot tub menu opens with a plain soak")
	check(tub_menu.has("Relax and watch the garden TV") and not tub_menu["Relax and watch the garden TV"], "The hot tub lists relaxing with the garden TV, off until one is in view")
	check(not pool_menu.has("Enjoy the garden") and not tub_menu.has("Enjoy the garden"), "Neither menu offers the generic Enjoy the garden")

	# ---- with a television in view, for an adult and for an elder
	_put_up_tv()
	pool = _item("pool")
	tub = _item("hot_tub")
	for index: int in [0, 2]:
		app.select_household_member(index)
		var stage: String = str(app.sim.character.age_stage)
		pool_menu = await _menu(pool)
		tub_menu = await _menu(tub)
		check(pool_menu.get("Go for a swim", false) and pool_menu.get("Sit by the edge and watch the garden TV", false), "A %s is offered both pool choices" % stage)
		check(tub_menu.get("Soak in the hot tub", false) and tub_menu.get("Relax and watch the garden TV", false), "A %s is offered both hot tub choices" % stage)
	app.close_overlay()

	# ---- an adult and an elder really get into the pool and the tub
	for index: int in [0, 2]:
		app.select_household_member(index)
		var sim: LifeSim = app.sim
		var stage: String = str(sim.character.age_stage)
		app.queue_interaction(pool, "enjoy_outdoors")
		check(await _until_active(sim) and str(app.player._activity_anchor.get("kind", "")) == "swim", "A %s walks to the pool and swims" % stage)
		_step(40)
		check(sim.wetness >= 1.0 and str(sim.character.outfit_category) == "swim", "A %s is in swimwear and soaked (%.2f, %s)" % [stage, sim.wetness, str(sim.character.outfit_category)])
		_clear()
		app.queue_interaction(tub, "enjoy_outdoors")
		check(await _until_active(sim) and str(app.player._activity_anchor.get("kind", "")) == "seat", "A %s walks to the hot tub and soaks" % stage)
		_clear()

	# ---- the tub's television choice keeps the soaker in the water, facing the screen
	app.select_household_member(0)
	for member: Dictionary in app.household.members:
		member.sim.wetness = 0.0
	app.queue_interaction(tub, LifeTVGroup.WATER_TV)
	var soaker: LifeSim = app.sim
	check(LifeTVGroup.owns(soaker.get_current_action()) and str(soaker.get_current_action().id) == "enjoy_outdoors", "Relaxing with the garden TV is a soak in the tub with the screen on")
	check(await _until_active(soaker), "The soaker reaches the tub")
	_step(60)
	var anchor: Dictionary = app.tv_group.anchor(soaker.get_current_action(), app.player)
	check(bool(anchor.get("tv_water", false)) and soaker.wetness > 0.0, "They sit in the water, wet, looking at the screen")
	_clear()

	# ---- sitting by the pool's edge, then a housemate joining from the menu
	for member: Dictionary in app.household.members:
		member.sim.wetness = 0.0
		member.sim.auto_swimwear = false
		LifeCharacterIdentity.apply_category(member.sim.character, "everyday")
	app.select_household_member(0)
	var viewer: LifeSim = app.sim
	var viewer_id: String = str(app.household.selected_id())
	app.queue_interaction(pool, LifeTVGroup.EDGE_TV)
	check(LifeTVGroup.edge(viewer.get_current_action()), "Choosing the edge seat queues a coping place")
	var seated: bool = false
	var companion: LifeSim = app.household.members[1].sim
	app.household.set_speed(3)
	for frame: int in 4000:
		app._process(DT)
		if frame % 6 == 0:
			await process_frame
		if str(viewer.get_current_action().get("phase", "")) == "active" and str(companion.get_current_action().get("phase", "")) == "active":
			seated = true
			break
	check(seated and LifeTVGroup.edge(companion.get_current_action()), "A free housemate is seated beside them on the coping")
	_step(40)
	check(viewer.wetness == 0.0 and str(viewer.character.outfit_category) != "swim", "The viewer stays dry and in their own clothes")

	app.select_household_member(2)
	var elder: LifeSim = app.sim
	var choices: Dictionary = await _menu(pool)
	var joins: Array = choices.keys().filter(func(text: String) -> bool: return text.begins_with("Join watching"))
	check(joins.size() == 1, "A third Lifelet is offered Join watching at the pool")
	app.queue_interaction(pool, "join_tv")
	check(LifeTVGroup.edge(elder.get_current_action()), "Joining seats the elder on the coping too")
	var lanes: Array = []
	for member: Dictionary in app.household.members:
		var held: Dictionary = member.sim.get_current_action()
		if LifeTVGroup.edge(held):
			lanes.append("%d:%d" % [int(held.edge_side), int(held.swim_lane)])
	var distinct: Dictionary = {}
	for lane: String in lanes:
		distinct[lane] = true
	check(lanes.size() == 3 and distinct.size() == 3, "Three viewers hold three separate coping places (%s)" % str(lanes))
	check(viewer_id == str(app.household.members[0].id), "The first viewer is still the Lifelet who chose it")
	_clear()

	# ---- the television still needs power
	app.select_household_member(0)
	app.sim.utilities_cut = true
	pool_menu = await _menu(pool)
	tub_menu = await _menu(tub)
	check(not pool_menu.get("Sit by the edge and watch the garden TV", true) and not tub_menu.get("Relax and watch the garden TV", true), "With the utilities cut neither television choice is on")
	app.queue_interaction(pool, LifeTVGroup.EDGE_TV)
	check(app.sim.get_current_action().is_empty(), "And clicking the edge seat anyway starts nothing")
	app.sim.utilities_cut = false
	app.close_overlay()

	# ---- joining goes to the viewer at this tub, not the first one at the same television
	app.world.add_item({"id": "wc_bench", "kind": "bench", "x": -11.5, "z": -2.4, "rotation": 90.0})
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	var bench_sim: LifeSim = app.household.members[0].sim
	var tub_sim: LifeSim = app.household.members[1].sim
	var joiner_sim: LifeSim = app.household.members[2].sim
	check(app.tv_group.request(bench_sim, "wc_tv", false) and str(app._find_item(str(bench_sim.get_current_action().target_id)).kind) == "bench", "One housemate watches the garden television from a bench")
	app.select_household_member(1)
	app.queue_interaction(tub, LifeTVGroup.WATER_TV)
	while not joiner_sim.action_queue.is_empty():
		joiner_sim.cancel_action()
	check(LifeTVGroup.owns(tub_sim.get_current_action()) and str(tub_sim.get_current_action().target_id) == str(tub.id), "Another watches the same television from the hot tub")
	app.select_household_member(2)
	var join_menu: Dictionary = await _menu(tub)
	check(join_menu.keys().any(func(text: String) -> bool: return text.begins_with("Join watching")), "The third Lifelet is offered Join watching at the tub")
	app.queue_interaction(tub, "join_tv")
	check(str(joiner_sim.get_current_action().get("target_id", "")) == str(tub.id), "Join watching at the tub seats them in the tub, not on the bench")
	_clear()
	app.close_overlay()

	# ---- the coping seat is on the rim and clear of the wall at every style, size and turn
	for style: String in ["classic", "roman", "lagoon"]:
		for size: String in ["small", "medium", "large"]:
			for turn: float in [0.0, 90.0, 180.0, 270.0]:
				var id: String = "wc_geo_%s_%s_%d" % [style, size, int(turn)]
				app.world.add_item({"id": id, "kind": "pool", "x": 30.0, "z": 30.0, "rotation": turn, "style": style, "size": size})
				var geo: Dictionary = app._find_item(id)
				var scale: float = LifeCatalogVariants.size_scale(size)
				var ok: bool = not geo.is_empty()
				var report: String = ""
				for side: int in 2:
					for lane: int in LifeOutdoorActs.MAX_JOIN:
						var seat: Dictionary = app.world.pool_edge_seat(geo, side, lane, Vector3(30, 0, 24), false)
						if seat.is_empty():
							ok = false
							continue
						var local: Vector3 = geo.node.to_local(seat.position)
						var forward: Vector3 = Vector3(sin(seat.yaw), 0, cos(seat.yaw))
						var knee: Vector3 = geo.node.to_local(seat.position + forward * .35)
						if absf(local.y - (.35 * scale + .07)) > .01:
							ok = false
							report += " height"
						if style != "lagoon":
							# Hips on the coping, knees no further out than the wall's inner face.
							if absf(local.z) < 1.5 * scale - .01 or absf(local.z) > 1.9 * scale:
								ok = false
								report += " hips"
							if absf(knee.z) > 1.35 * scale + .02:
								ok = false
								report += " knee"
				check(ok, "%s %s pool turned %d: every coping place is on the rim, level, with the knees over the water%s" % [style, size, int(turn), report])
				app.world.remove_item(id)

	print("WATER_CHOICES %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures:
		print("  FAILED: ", failure)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
