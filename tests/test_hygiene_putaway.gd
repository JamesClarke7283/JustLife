extends SceneTree
## Hygiene, the toilet's own wash and the fridge's put-away, through public paths.
##
## No pointer or rendering proof: wash_hands/brush_teeth deltas, the queued
## follow-up after a finished toilet visit, and the return of a plated serving
## to its dish in the fridge are asserted from the real simulation and world.

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


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	app.selected_lot = 0
	app.start_household()
	await process_frame
	app.set_process(false)

	var sink: Dictionary = app.world.closest_item("sink", Vector3.ZERO)
	var toilet: Dictionary = app.world.closest_item("toilet", Vector3.ZERO)
	check(not sink.is_empty() and str(sink.kind) == "sink", "The starter home has a sink to wash at.")
	check(not toilet.is_empty() and str(toilet.kind) == "toilet", "The starter home has a toilet.")

	# Both sink actions are real hygiene gains, and brushing is the deeper one.
	var wash: Dictionary = app.sim.get_action_definition("wash_hands")
	var brush: Dictionary = app.sim.get_action_definition("brush_teeth")
	check(float(wash.changes.hygiene) > 0.0, "Washing hands improves hygiene.")
	check(float(brush.changes.hygiene) > 0.0, "Brushing teeth improves hygiene.")
	check(float(brush.changes.hygiene) > float(wash.changes.hygiene), "Brushing teeth is the deeper freshen-up.")
	var sink_ids: Array = app.sim.get_actions_for("sink", str(sink.id)).map(func(a: Dictionary) -> String: return str(a.id))
	check(sink_ids.has("wash_hands") and sink_ids.has("brush_teeth"), "The sink offers both wash_hands and brush_teeth.")

	# Finishing a toilet visit queues the wash itself, at a real sink.
	app.sim.needs.bladder = 20.0
	app.queue_interaction(toilet, "toilet")
	check(not app.sim.action_queue.is_empty(), "The toilet queues through the public instruction path.")
	var visit: Dictionary = app.sim.get_current_action()
	visit.phase = "active"
	visit.elapsed = float(visit.duration)
	app.sim._finish_front()
	var queued: Array = app.sim.action_queue.map(func(a: Dictionary) -> String: return str(a.id))
	check(queued.has("wash_hands"), "Washing hands follows the toilet without the player asking.")
	check(str(app.sim.action_queue[0].get("target_id", "")).begins_with("item_"), "The queued wash resolves to a real sink.")

	# A plated serving left out returns to its dish in the fridge.
	var food: LifeMeals = app.household.meals
	var now: float = app.meal_flow.now()
	var fridge: Dictionary = app.world.closest_item("fridge", Vector3.ZERO)
	var dining: Dictionary = app.world.closest_item("dining", Vector3.ZERO)
	var member: Dictionary = app.household.members[0]
	var batch: Dictionary = food.create_batch("garden_skillet", str(member.id), 2, app.current_venue, now)
	food.set_batch_location(str(batch.id), "surface", str(dining.id), dining.node.position, now)
	var plate: Dictionary = food.claim(str(batch.id), str(member.id), now)
	food.put_portion(str(plate.id), str(dining.id), "", dining.node.position, false)
	check(int(batch.remaining) == 3 and int(batch.served) == 1, "A serving taken from the dish reduces its remaining count.")
	var fridge_menu: Array = app.sim.get_actions_for("fridge", str(fridge.id))
	var put_away: Dictionary = {}
	for action: Dictionary in fridge_menu:
		if str(action.id) == "put_in_fridge":
			put_away = action
	check(not put_away.is_empty() and bool(put_away.available), "The fridge offers putting away food left out.")

	app.queue_interaction(fridge, "put_in_fridge")
	check(not app.sim.action_queue.is_empty(), "The put-away action queues.")
	app.household.set_speed(1)
	for frame: int in 3000:
		app._process(0.05)
		if str(batch.storage) == "fridge" or app.sim.action_queue.is_empty():
			break
	check(str(batch.storage) == "fridge" and str(batch.host) == str(fridge.id), "The dish ends up in the fridge.")
	check(int(batch.remaining) == 4 and int(batch.served) == 0, "The uneaten serving returns to its dish's remaining count.")
	check(food.portions.is_empty(), "The plated serving no longer exists separately.")

	app.queue_free()
	await process_frame
	print("HYGIENE_PUTAWAY %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
