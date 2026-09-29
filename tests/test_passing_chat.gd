extends SceneTree
## A Lifelet who can see the sidewalk may wave to, greet or chat with anybody
## walking past: an adult, a teen, a child, an elder, a dog on a lead or a dog
## trotting by. Through the real main scene: a click on the passer opens the menu,
## the Lifelet walks to a clear spot beside them, the passer stops and answers,
## Social and Fun rise with a familiar-face bonus and a cooldown, and the passer is
## released and walks on at their own pace however the moment ends.
## Headless, about two minutes (it loads the whole main scene).

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func step(count: int, delta: float = .05) -> void:
	for _i: int in range(count):
		app._process(delta)
		await process_frame

## Step until the condition holds or `limit` frames pass.
func until(condition: Callable, limit: int, delta: float = .05) -> bool:
	for _i: int in range(limit):
		if condition.call():
			return true
		app._process(delta)
		await process_frame
	return condition.call()

func passer(id: String) -> Dictionary:
	return app.street_life.find(id)

## Stand the passer on the sidewalk in front of the Lifelet, always on duty.
func place(id: String, x: float, dir: int = 1) -> void:
	var entry: Dictionary = passer(id)
	entry["hours"] = [[0.0, 24.0]]
	entry["active"] = true
	entry["x"] = x
	entry["dir"] = dir
	entry["lane"] = LifeStreetLife.lane_for(entry)
	entry["hold_left"] = 0.0
	entry["holder"] = ""
	if not str(entry.get("follows", "")).is_empty():
		return
	app.street_life._follow()

func park_others(keep: Array) -> void:
	for entry: Dictionary in app.street_life.passers:
		if str(entry.id) in keep:
			continue
		entry["active"] = false
		entry["hold_left"] = 0.0
		entry["hours"] = [[0.0, 0.0]]
		entry["x"] = LifeStreetLife.EAST
		entry["holder"] = ""

func refresh() -> void:
	app.residents.publish_targets(true)

func ready_for_moment() -> void:
	app.sim.last_passing_any = -1e18
	app.sim.passing_contacts.clear()
	app.sim.needs.social = 20.0
	app.sim.needs.fun = 40.0

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	app.set_process(false)
	app.set_sound(false)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
	app.household.minutes = 600.0
	for member: Dictionary in app.household.members:
		member.sim.minutes = 600.0
	var sim: LifeSim = app.sim
	var body: LifeActor = app.player

	# ------------------------------------------------------------ menus and clicks
	check(app.street_life.passers.size() >= 6, "The street has several passers (%d)." % app.street_life.passers.size())
	app.street_life.tick(.05, 1.0, 600.0)
	park_others(["street_adult", "street_walker_dog", "street_child_a", "street_teen", "street_pet", "street_elder", "street_child_b"])
	place("street_child_a", -1.0, 1)
	place("street_child_b", -6.0, -1)
	place("street_teen", 2.0, -1)
	place("street_adult", 5.0, 1)
	place("street_elder", -4.0, 1)
	place("street_pet", 8.0, -1)
	await step(2)
	# With the house between the Lifelet and the sidewalk the passers are out of
	# sight: the menu is there, disabled, with the reason.
	body.position = Vector3(0, .16, -9.5)
	refresh()
	var indoor_menu: Array = sim.get_actions_for("passer", "street_child_a")
	check(indoor_menu.size() == 3 and indoor_menu.all(func(a: Dictionary) -> bool: return not bool(a.available)), "With the house in the way a passer's three moments are offered but disabled.")
	check(str(indoor_menu[0].unavailable_reason).contains("Step outside"), "The disabled entries say to step outside (%s)." % str(indoor_menu[0].unavailable_reason))
	# On the lawn the passers can be hailed.
	body.position = Vector3(0, .16, 6.4)
	app.traversal.cancel(app.bound_member_id)
	refresh()
	await step(2)
	for kind_case: Array in [["street_child_a", 3, "child"], ["street_teen", 3, "teen"], ["street_adult", 4, "adult"], ["street_elder", 3, "elder"], ["street_pet", 2, "pet"]]:
		var menu: Array = sim.get_actions_for("passer", str(kind_case[0]))
		check(menu.size() == int(kind_case[1]) and menu.all(func(a: Dictionary) -> bool: return bool(a.available)), "A passing %s offers %d moments to a Lifelet outside (%s)." % [kind_case[2], kind_case[1], ", ".join(menu.map(func(a: Dictionary) -> String: return str(a.label)))])
	var adult_ids: Array = sim.get_actions_for("passer", "street_adult").map(func(a: Dictionary) -> String: return str(a.id))
	check(adult_ids.has("compliment_passer_dog") and not sim.get_actions_for("passer", "street_child_a").any(func(a: Dictionary) -> bool: return str(a.id) == "compliment_passer_dog"), "Only the neighbour walking a dog can be complimented on it.")
	var pet_ids: Array = sim.get_actions_for("passer", "street_pet").map(func(a: Dictionary) -> String: return str(a.id))
	check(pet_ids == ["greet_passing_pet", "pet_passing_pet"], "A dog is offered a hello and a pat.")
	var chat_labels: Dictionary = {}
	for id: String in ["street_child_a", "street_teen", "street_adult", "street_elder"]:
		for entry: Dictionary in sim.get_actions_for("passer", id):
			if str(entry.id) == "passing_chat":
				chat_labels[id] = str(entry.label)
	check(chat_labels.values().size() == 4 and chat_labels.values().duplicate().size() == 4 and chat_labels.street_child_a != chat_labels.street_elder, "Small talk reads differently for a child, a teen, an adult and an elder (%s)." % str(chat_labels.values()))

	# A real click on the passer's body reaches the menu.
	var clicked: Array = []
	app.world.object_clicked.connect(func(info: Dictionary, _screen: Vector2) -> void: clicked.append(info))
	var kid: Node3D = app.street_bodies.body_of("street_child_a")
	app.world.camera_target = kid.position
	app.world.update_camera()
	await physics_frame
	await physics_frame
	await process_frame
	var screen: Vector2 = app.world.camera.unproject_position(kid.position + Vector3(0, .6, 0))
	app.world.pick(screen)
	check(clicked.size() == 1 and str(clicked[0].get("id", "")) == "street_child_a" and str(clicked[0].get("kind", "")) == "passer", "A click on the passing child's body picks the passer (%s)." % str(clicked.map(func(i: Dictionary) -> String: return str(i.get("id", "")))))
	if not clicked.is_empty():
		app.on_object_clicked(clicked[0], screen)
		await process_frame
		var texts: Array = app.overlay.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
		check(texts.any(func(t: String) -> bool: return t.contains("Wave hello")) and texts.any(func(t: String) -> bool: return t.contains("Say hello")), "The passing child's card lists the moments (%s)." % str(texts))
		app.close_overlay()

	# ----------------------------------------------------------- a full moment
	for scenario: Array in [["street_child_a", "greet_passer", -1.0, 1], ["street_teen", "passing_chat", 2.0, -1], ["street_adult", "compliment_passer_dog", 5.0, 1], ["street_elder", "wave_to_passer", -4.0, 1]]:
		var id: String = str(scenario[0])
		var action_id: String = str(scenario[1])
		park_others([id, "street_walker_dog"] if id == "street_adult" else [id])
		place(id, float(scenario[2]), int(scenario[3]))
		body.position = Vector3(0, .16, 6.4)
		app.traversal.cancel(app.bound_member_id)
		ready_for_moment()
		refresh()
		await step(2)
		var before_social: float = float(sim.needs.social)
		var before_fun: float = float(sim.needs.fun)
		var item: Dictionary = app.world.pick_extras[id].duplicate()
		app.queue_interaction(item, action_id)
		await step(1)
		check(str(sim.get_current_action().get("id", "")) == action_id and sim.get_current_action().phase in ["approach", "active"], "%s queues %s." % [id, action_id])
		var at_click: Vector3 = app.street_life.position_of(passer(id))
		var held_fast: bool = await until(func() -> bool: return app.street_life.is_held(id), 40)
		check(held_fast, "%s stops for the Lifelet who is coming." % id)
		var still: bool = true
		var reached: bool = false
		for _i: int in range(900):
			app._process(.05)
			await process_frame
			var moved: float = app.street_life.position_of(passer(id)).distance_to(at_click)
			if moved > .001:
				still = false
			if sim.get_current_action().get("phase", "") == "active":
				reached = true
				break
		check(reached, "%s: the Lifelet walks up and the moment begins." % id)
		check(still, "%s stays exactly where they were stopped through the approach." % id)
		var distance: float = Vector2(body.position.x - at_click.x, body.position.z - at_click.z).length()
		check(distance >= .75 and distance <= 1.7, "%s: the Lifelet stands %.2f m from the passer, at conversation range." % [id, distance])
		check(body.position.z <= at_click.z + .05, "%s: the Lifelet stands on the house side of the sidewalk." % id)
		check(app.world.lot_navigation.point_clear(0, body.position), "%s: the Lifelet's spot is clear of solid obstacles." % id)
		# During the moment the passer faces the Lifelet.
		await step(20)
		var passer_body: Node3D = app.street_bodies.body_of(id)
		var facing: Vector3 = Vector3(sin(passer_body.rotation.y), 0, cos(passer_body.rotation.y))
		var toward: Vector3 = (body.position - passer_body.position)
		toward.y = 0.0
		check(facing.dot(toward.normalized()) > .9, "%s turns to face the Lifelet (dot %.2f)." % [id, facing.dot(toward.normalized())])
		check(app.street_life.is_held(id), "%s is still held during the moment." % id)
		var finished: bool = await until(func() -> bool: return sim.action_queue.is_empty(), 1500)
		check(finished, "%s: the moment completes." % id)
		check(float(sim.needs.social) > before_social + 3.0 and float(sim.needs.fun) > before_fun, "%s: Social %.1f -> %.1f and Fun %.1f -> %.1f rise." % [id, before_social, sim.needs.social, before_fun, sim.needs.fun])
		check(sim.passing_contacts.has(id) and int(sim.passing_contacts[id].count) == 1, "%s: the meeting is remembered." % id)
		await step(3)
		check(not app.street_life.is_held(id), "%s is released when the moment ends." % id)
		var after: Vector3 = app.street_life.position_of(passer(id))
		await step(40)
		var walked: float = app.street_life.position_of(passer(id)).distance_to(after)
		var expected: float = LifePedestrianPace.metres_per_second(str(passer(id).pace)) * 2.0
		check(absf(walked - expected) < expected * .25 + .05, "%s walks on at their natural pace (%.2f m in 2 s, expected %.2f)." % [id, walked, expected])
		# The cooldown stops the same moment being repeated at once.
		var again: Dictionary = sim.get_action_availability(action_id, id)
		check(not bool(again.available) and str(again.reason).length() > 0, "%s: repeating the %s at once is refused (%s)." % [id, action_id, str(again.reason)])

	# ------------------------------------------------------- familiar faces
	park_others(["street_child_b"])
	place("street_child_b", -2.0, 1)
	body.position = Vector3(0, .16, 6.4)
	app.traversal.cancel(app.bound_member_id)
	ready_for_moment()
	var gains: Array = []
	for attempt: int in range(3):
		sim.last_passing_any = -1e18
		if sim.passing_contacts.has("street_child_b"):
			sim.passing_contacts["street_child_b"]["at"] = -1e18
		sim.needs.social = 20.0
		refresh()
		await step(2)
		app.street_life.release("street_child_b")
		place("street_child_b", float(app.street_life.find("street_child_b").x), 1)
		app.queue_interaction(app.world.pick_extras["street_child_b"].duplicate(), "greet_passer")
		var done: bool = await until(func() -> bool: return sim.action_queue.is_empty() and float(sim.needs.social) > 20.0, 1500)
		gains.append(float(sim.needs.social) - 20.0)
		check(done, "Meeting %d with the same child completes." % (attempt + 1))
		await step(4)
	check(gains.size() == 3 and gains[1] > gains[0] and gains[2] > gains[1], "Each time the same face is met the moment is a little warmer (%s)." % str(gains))

	# ------------------------------------------------------------- a dog
	park_others(["street_pet"])
	place("street_pet", -1.0, 1)
	body.position = Vector3(0, .16, 6.4)
	app.traversal.cancel(app.bound_member_id)
	ready_for_moment()
	refresh()
	await step(2)
	var dog_before_fun: float = float(sim.needs.fun)
	app.queue_interaction(app.world.pick_extras["street_pet"].duplicate(), "pet_passing_pet")
	var dog_ok: bool = await until(func() -> bool: return sim.get_current_action().get("phase", "") == "active", 900)
	check(dog_ok, "The Lifelet walks up to the passing dog.")
	var dog: LifePetActor = app.street_bodies.body_of("street_pet") as LifePetActor
	var dog_distance: float = Vector2(body.position.x - dog.position.x, body.position.z - dog.position.z).length()
	check(dog_distance >= .45 and dog_distance <= 1.3, "The Lifelet stands %.2f m from the dog, close enough to pat it." % dog_distance)
	check(app.street_life.is_held("street_pet"), "The dog waits for the pat.")
	await step(45)
	check(dog.interaction == "pet_pet", "The dog sits up to be patted.")
	var palm: Vector3 = body.palm_world("R")
	check(palm.distance_to(dog.back_point()) < .35, "The Lifelet's hand reaches the dog's back (%.2f m away)." % palm.distance_to(dog.back_point()))
	var dog_done: bool = await until(func() -> bool: return sim.action_queue.is_empty(), 1500)
	check(dog_done and float(sim.needs.fun) > dog_before_fun + 5.0, "Patting the dog lifts Fun (%.1f -> %.1f)." % [dog_before_fun, sim.needs.fun])
	await step(3)
	check(not app.street_life.is_held("street_pet") and dog.interaction == "", "The dog is released and goes back to trotting.")

	# --------------------------------------------- cancel, despawn, save, autonomy
	# Cancelling on the way releases the passer at once.
	park_others(["street_teen"])
	place("street_teen", -3.0, 1)
	body.position = Vector3(6.0, .16, 6.4)
	app.traversal.cancel(app.bound_member_id)
	ready_for_moment()
	refresh()
	await step(2)
	app.queue_interaction(app.world.pick_extras["street_teen"].duplicate(), "greet_passer")
	await step(4)
	check(app.street_life.is_held("street_teen") and sim.get_current_action().phase == "approach", "The teen waits while the Lifelet crosses the lawn.")
	# A save taken now carries the queued moment, and the sim restores it.
	var saved: Dictionary = sim.get_state()
	var copy := LifeSim.new()
	var restored: Dictionary = copy.restore_state(JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(saved))))
	check(bool(restored.get("ok", false)) and copy.action_queue.size() == 1 and str(copy.action_queue[0].id) == "greet_passer" and str(copy.action_queue[0].target_id) == "street_teen", "The queued hello survives a JSON save and restore (%s)." % str(restored.get("error", "")))
	copy.free()
	app.cancel_current_action()
	await step(3)
	check(not app.street_life.is_held("street_teen"), "Cancelling releases the passer at once.")
	# The passer leaving the street cancels gracefully.
	ready_for_moment()
	place("street_teen", -3.0, 1)
	refresh()
	await step(2)
	app.queue_interaction(app.world.pick_extras["street_teen"].duplicate(), "greet_passer")
	await step(4)
	passer("street_teen")["active"] = false
	await step(6)
	check(sim.action_queue.is_empty() and not app.street_life.is_held("street_teen"), "A passer who leaves cancels the moment and frees the queue.")
	# The Lifelet walking indoors mid-approach also lets the passer go.
	place("street_teen", -3.0, 1)
	ready_for_moment()
	refresh()
	await step(2)
	app.queue_interaction(app.world.pick_extras["street_teen"].duplicate(), "greet_passer")
	await step(4)
	body.position = Vector3(0, .16, -9.5)
	app.traversal.cancel(app.bound_member_id)
	refresh()
	app._refresh_sim_targets(false)
	await step(6)
	check(sim.action_queue.is_empty() and not app.street_life.is_held("street_teen"), "A Lifelet who can no longer see the passer drops the moment and frees them.")

	# Autonomy: an idle Lifelet outside, low on company, sometimes starts one.
	park_others(["street_child_a"])
	place("street_child_a", -1.0, 1)
	body.position = Vector3(0, .16, 6.4)
	app.traversal.cancel(app.bound_member_id)
	ready_for_moment()
	sim.needs.social = 10.0
	refresh()
	await step(2)
	var chosen: Dictionary = {}
	for slot: int in range(12):
		sim.minutes = 600.0 + float(slot) * 21.0
		chosen = LifePassingPolicy.autonomy_choice(sim)
		if not chosen.is_empty():
			break
	check(not chosen.is_empty() and str(chosen.target_id) == "street_child_a" and str(chosen.id) == "wave_to_passer", "An idle Lifelet outside occasionally waves to a passing child first (%s)." % str(chosen))
	sim.minutes = 600.0
	sim.passing_contacts["street_child_a"] = {"at": 100.0, "count": 2}
	sim.last_passing_any = -1e18
	var later: Dictionary = {}
	for slot: int in range(12):
		sim.minutes = 640.0 + float(slot) * 21.0
		later = LifePassingPolicy.autonomy_choice(sim)
		if not later.is_empty():
			break
	check(not later.is_empty() and str(later.id) == "passing_chat", "A familiar face is worth stopping for a chat (%s)." % str(later))
	# Somebody who cannot see the sidewalk never starts one.
	body.position = Vector3(0, .16, -9.5)
	refresh()
	check(LifePassingPolicy.autonomy_choice(sim).is_empty(), "A Lifelet who cannot see the sidewalk starts nothing.")

	# A save taken on the way carries the moment, and the loaded game finishes it.
	park_others(["street_teen"])
	place("street_teen", -3.0, 1)
	body.position = Vector3(6.0, .16, 6.4)
	app.traversal.cancel(app.bound_member_id)
	ready_for_moment()
	refresh()
	await step(2)
	app.queue_interaction(app.world.pick_extras["street_teen"].duplicate(), "greet_passer")
	await step(8)
	check(sim.get_current_action().get("phase", "") == "approach" and app.street_life.is_held("street_teen"), "The Lifelet is on the way to the teen when the game is saved.")
	app.household.set_speed(0)
	check(app.save_game("", "Passing hello"), "The game saves mid-approach.")
	var slot: String = app.active_save_id
	app.load_game(slot)
	await process_frame
	await process_frame
	sim = app.sim
	body = app.player
	check(str(sim.get_current_action().get("id", "")) == "greet_passer" and str(sim.get_current_action().get("target_id", "")) == "street_teen", "The loaded game still has the queued hello (%s)." % str(sim.get_current_action().get("id", "")))
	app.household.set_speed(1)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
	park_others(["street_teen"])
	place("street_teen", -3.0, 1)
	var resumed: bool = await until(func() -> bool: return app.sim.action_queue.is_empty() and app.sim.passing_contacts.has("street_teen"), 2000)
	check(resumed, "The loaded game walks to the teen and completes the hello.")
	await step(4)
	check(not app.street_life.is_held("street_teen"), "The teen is released after the loaded hello.")
	sim = app.sim
	body = app.player

	# Autonomy end to end: an idle Lifelet on the lawn who is short of company
	# starts a wave on their own, and it runs like any other moment.
	for id: String in ["maya", "leo", "priya", "tom"]:
		app.world.set_actor_away(id, true, true)
		app.residents.locations[app.current_venue][id].phase = "home"
		app.residents.locations[app.current_venue][id].wait = 999999.0
	park_others(["street_child_a"])
	place("street_child_a", -2.0, 1)
	body.position = Vector3(0, .16, 6.4)
	app.traversal.cancel(app.bound_member_id)
	ready_for_moment()
	sim.autonomy = true
	sim.needs.social = 10.0
	for need: String in ["hunger", "energy", "hygiene", "bladder", "fun"]:
		sim.needs[need] = 90.0
	sim.action_queue.clear()
	app.household.set_speed(8)
	var started: bool = false
	for _i: int in range(4000):
		app._process(.05)
		await process_frame
		sim.needs.hunger = 90.0
		sim.needs.energy = 90.0
		sim.needs.hygiene = 90.0
		sim.needs.bladder = 90.0
		sim.needs.fun = 90.0
		var current: String = str(sim.get_current_action().get("id", ""))
		if current in LifePassingPolicy.ALL:
			started = true
			check(bool(sim.get_current_action().get("autonomous", false)), "The idle Lifelet started %s on their own." % current)
			break
		if not passer("street_child_a").active:
			place("street_child_a", -2.0, 1)
	check(started, "An idle Lifelet outside with low Social starts a passing moment by themselves.")
	sim.autonomy = false
	app.household.set_speed(1)
	sim.needs.social = 10.0
	var auto_done: bool = await until(func() -> bool: return sim.action_queue.is_empty(), 2500)
	await step(3)
	check(auto_done and not app.street_life.is_held("street_child_a"), "The autonomous moment completes and frees the passer (queue %s, held %s, phase %s, at %s, passer at %s)." % [str(sim.action_queue.map(func(a: Dictionary) -> String: return str(a.id))), str(app.street_life.is_held("street_child_a")), str(sim.get_current_action().get("phase", "")), str(body.position), str(app.street_life.position_of(passer("street_child_a")))])

	print("PASSING_CHAT %d checks, %d failures" % [checks, failures.size()])
	app.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
