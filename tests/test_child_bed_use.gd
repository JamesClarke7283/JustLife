extends SceneTree
## A child can really use their own bed: the person card sends them to it by its
## approach spot (not through the mattress), they walk there, lie on the mattress
## rather than in it, sleep, nap or relax; the starter homes put it where it can
## be reached; autonomy chooses it; the family starters can be started.
const DT: float = 1.0 / 30.0
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

func start(starter: String, profiles: Array = []) -> void:
	if is_instance_valid(app): app.queue_free(); await process_frame
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = profiles if not profiles.is_empty() else [{"name": "Parent Vale", "age_stage": "adult", "traits": []}, {"name": "Kit Vale", "age_stage": "child", "traits": []}]
	var list: Array = LifeProperties.starters_for(app.household_profiles)
	app.selected_lot = maxi(0, list.find(starter))
	app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		member.sim.minutes = 1260.0
		for need: String in LifeSim.NEED_NAMES: member.sim.needs[need] = 80.0
	app.household.minutes = 1260.0

func child_index() -> int:
	for index: int in range(app.household.members.size()):
		if str(app.household.members[index].sim.character.age_stage) == "child": return index
	return -1

func bed() -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.kind) == "child_bed": return item
	return {}

## The lowest and highest world y of the body's visible meshes.
func body_range(actor: LifeActor) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for node: Node in actor._model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var box: AABB = mesh.mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = mesh.global_transform * box.get_endpoint(corner)
			low = minf(low, point.y); high = maxf(high, point.y)
	return Vector2(low, high)

func run_until_active(limit: int = 3000) -> bool:
	app.household.set_speed(3)
	for frame: int in limit:
		app._process(DT)
		if frame % 4 == 0: await process_frame
		if str(app.sim.get_current_action().get("phase", "")) == "active":
			app.household.set_speed(0)
			return true
	app.household.set_speed(0)
	return false

func card_button(name: String) -> Button:
	return app.overlay.find_child(name, true, false)

func run() -> void:
	# ---- the person card, in a home that has a child bed
	await start("lumen")
	var kit: int = child_index()
	check(kit >= 0 and not bed().is_empty(), "Lumen has a child and a child's own bed")
	app.select_household_member(kit)
	await frames()
	app.sim.needs.energy = 15.0
	app.show_person()
	await frames()
	for name: String in ["ChildBed_sleep", "ChildBed_relax", "ChildBed_nap"]:
		check(card_button(name) != null and not card_button(name).disabled, "The card offers %s" % name)
	var aspiration: Label = null
	for node: Node in app.overlay.find_children("*", "Label", true, false):
		if str((node as Label).text).begins_with("Aspiration"): aspiration = node
	var overlaps: bool = false
	for name: String in ["ChildBed_sleep", "ChildBed_relax", "ChildBed_nap"]:
		if aspiration != null and card_button(name) != null and card_button(name).get_global_rect().intersects(aspiration.get_global_rect()): overlaps = true
	check(aspiration != null and not overlaps, "The bed buttons no longer sit on the aspiration line")
	card_button("ChildBed_sleep").pressed.emit()
	await frames()
	var queued: Dictionary = app.sim.get_current_action()
	check(str(queued.get("id", "")) == "sleep", "Go to Bed queues sleep")
	var spot: Vector3 = app.world.approach(bed())
	check(Vector3(queued.get("target_position", Vector3.INF)).distance_to(spot) < .05 and spot.distance_to(bed().node.position) > .5, "It walks to the bed's approach spot, not its middle")
	check(await run_until_active(), "The child gets to the bed and starts sleeping")
	check(str(app.player._activity_anchor.get("kind", "")) == "bed", "They are anchored to the bed")
	app.household.set_speed(1)
	for frame: int in 60: app._process(DT)
	app.household.set_speed(0)
	var mattress_top: float = bed().node.global_position.y + .52
	var range_y: Vector2 = body_range(app.player)
	check(range_y.x >= mattress_top - .03 and range_y.x <= mattress_top + .06, "They lie on the mattress, not in it (lowest %.3f vs top %.3f)" % [range_y.x, mattress_top])
	var feet: Vector3 = app.player.position
	check(app.world.sight_line_clear(spot, bed().node.global_position), "Nothing stands between the foot spot and the bed")
	var before_energy: float = float(app.sim.needs.energy)
	app.household.set_speed(8)
	var slept: bool = false
	for frame: int in 6000:
		app._process(DT)
		if app.sim.get_current_action().is_empty(): slept = true; break
	app.household.set_speed(0)
	check(slept and float(app.sim.needs.energy) > before_energy + 40.0, "The sleep completes and restores energy (%.0f -> %.0f)" % [before_energy, float(app.sim.needs.energy)])

	# ---- relax and nap from the card
	app.show_person(); await frames()
	card_button("ChildBed_relax").pressed.emit(); await frames()
	check(str(app.sim.get_current_action().get("id", "")) == "relax", "Relax queues")
	check(await run_until_active(), "The child gets to the bed to relax")
	check(str(app.player._activity_anchor.get("kind", "")) == "seat", "They sit on the foot of the bed to relax")
	app.sim.cancel_action(); await frames()
	app.sim.needs.energy = 30.0
	app.show_person(); await frames()
	card_button("ChildBed_nap").pressed.emit(); await frames()
	check(str(app.sim.get_current_action().get("id", "")) == "nap" and await run_until_active(), "Take a Nap queues and starts")
	app.sim.cancel_action(); await frames()

	# ---- clicking the bed itself works the same way
	app.sim.needs.energy = 15.0
	app.queue_interaction(bed(), "sleep")
	check(await run_until_active() and str(app.player._activity_anchor.get("kind", "")) == "bed", "Clicking the bed also sends them to sleep in it")
	app.sim.cancel_action(); await frames()

	# ---- autonomy at night, and a weekday nap, choose the child's own bed
	app.sim.autonomy = true
	app.sim.needs.energy = 12.0
	app.sim.minutes = 1290.0
	var night: Dictionary = app.sim._autonomy_need_choice("energy")
	check(not night.is_empty() and str(app._find_item(str(night.target_id)).get("kind", "")) == "child_bed", "A tired child chooses their own bed at night (%s)" % str(night.get("id", "")))
	app.sim.minutes = 700.0
	var day: Dictionary = app.sim._autonomy_need_choice("energy")
	check(not day.is_empty() and str(app._find_item(str(day.target_id)).get("kind", "")) == "child_bed", "A weekday nap is in their own bed, not the sofa (%s)" % str(day.get("id", "")))
	app.sim.autonomy = false

	# ---- an adult may not relax on it
	var adult: LifeSim = app.household.member_sim("player") if app.household.member_sim("player") != kit_sim() else app.household.members[0].sim
	var gate: Dictionary = adult.get_action_availability("relax", str(bed().id))
	check(not bool(gate.available), "An adult cannot relax on a child's bed (%s)" % str(gate.reason))

	# ---- every starter that has a child bed puts its foot spot on the bed's own side of the walls
	for starter: String in ["lumen", "haven"]:
		await start(starter)
		var home_bed: Dictionary = bed()
		check(not home_bed.is_empty(), "%s has a child's own bed" % starter)
		if home_bed.is_empty(): continue
		var stand: Vector3 = app.world.approach(home_bed)
		var edge: Vector3 = home_bed.node.global_position
		check(stand.is_finite() and app.world.sight_line_clear(stand, edge), "%s: the approach is on the bed's side of the walls" % starter)
		check(not app.world.path_to(Vector3(0, .16, 6.5), stand).is_empty(), "%s: the approach can be walked to from the garden" % starter)
		var panels_blocked: bool = false
		for panel: Rect2 in app.world.item_panels(home_bed):
			if app.world.construction.rect_blocked(panel, app.world.item_level(home_bed), 0.0): panels_blocked = true
		check(not panels_blocked, "%s: the bed stands clear of the walls" % starter)
		# A child's own pieces, and the bath and toilet beside them, stand on nothing else.
		var crowded: Array[String] = []
		for piece: Dictionary in app.world.items:
			if str(piece.kind) not in ["child_bed", "child_desk", "child_chair", "toy_chest", "dollhouse", "bathtub", "toilet"]: continue
			for other: Dictionary in app.world.items:
				if other == piece or LifeCatalog.passable(str(other.kind)): continue
				for panel_a: Rect2 in app.world.item_panels(piece):
					for panel_b: Rect2 in app.world.item_panels(other):
						if panel_a.intersects(panel_b) and not crowded.has("%s/%s" % [piece.kind, other.kind]) and not crowded.has("%s/%s" % [other.kind, piece.kind]): crowded.append("%s/%s" % [piece.kind, other.kind])
		check(crowded.is_empty(), "%s: the child's pieces overlap nothing (%s)" % [starter, str(crowded)])
		# The first structural edit (pressing Upper in Build) makes the home canonical, and every
		# piece the starter placed is then checked against the walls: nothing may stop a save.
		var migrated: Dictionary = LifeBuildingState.migrate(app.world.construction.snapshot())
		app.world.construction.restore(migrated.state)
		var verdict: String = app.world.validate_home_layout(app.world.serialize_items())
		check(bool(migrated.ok) and verdict.is_empty(), "%s: the furnishings still validate once the home is built on (%s)" % [starter, verdict])
		check(app.save_game("starter_%s" % starter, "Starter"), "%s: the game saves once the home is built on" % starter)

	# ---- Haven can be started from the picker
	await start("haven")
	check(LifeProperties.active(app.properties) == "haven" or str(app.properties.get("active", "")) == "haven", "Choosing Haven starts Haven")

	# ---- a home with no child bed says why, and queues nothing
	await start("willow")
	kit = child_index()
	app.select_household_member(kit)
	await frames()
	app.show_person(); await frames()
	check(card_button("ChildBed_sleep") != null and card_button("ChildBed_sleep").disabled, "Without a child bed the card's buttons are greyed")
	check("child's own bed" in str(card_button("ChildBed_sleep").tooltip_text), "They say a child's own bed is needed (%s)" % card_button("ChildBed_sleep").tooltip_text)
	check(app.sim.get_current_action().is_empty(), "Nothing was queued")

	print("CHILD_BED_USE ", checks, " checks, ", failures.size(), " failures")
	for message: String in failures: print("  ", message)
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func kit_sim() -> LifeSim:
	return app.household.members[child_index()].sim
