extends SceneTree
## Pool water is a solid footprint walkers path around; swim keeps a stroke;
## Ask to Join queues two Lifelets into parallel lanes.
const Variants = preload("res://scripts/catalog_variants.gd")
const DT: float = 1.0 / 30.0

var checks: int = 0
var failures: Array = []
var app: Node


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)


func frames(n: int = 2) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [
		{"name": "Tom Vale", "age_stage": "young_adult", "life_stage": "adult", "traits": ["Active"]},
		{"name": "Sam Vale", "age_stage": "young_adult", "life_stage": "adult", "traits": ["Friendly"]},
	]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	app.household.set_funds(20000)
	check(app.household.members.size() >= 2, "Household has company on the lot for Ask to Join")

	# Place a large pool so a wrong authored-only obstacle would leave a walkable
	# strip of water. Prefer garden spots that can_place accepts.
	var pool: Dictionary = {}
	for spot: Vector2 in [Vector2(-12, 4), Vector2(12, 4), Vector2(-12, -8), Vector2(12, -8), Vector2(-14, 0), Vector2(14, 0)]:
		var at := Vector3(spot.x, LifeBuildingState.level_y(0), spot.y)
		if app.world.can_place("pool", at, 0.0, "classic", "large"):
			app.world.add_item({"id": "probe_pool", "kind": "pool", "x": at.x, "z": at.z, "rotation": 0, "style": "classic", "size": "large", "color": "7fb8c6"})
			pool = app._find_item("probe_pool")
			break
	check(not pool.is_empty(), "A large pool places in the garden")
	if pool.is_empty():
		_finish(); return
	app.household.register_targets(app.world.simulation_targets())

	var authored: Vector2 = LifeCatalog.ITEMS.pool.size
	var panels: Array[Rect2] = app.world.item_panels(pool)
	check(panels.size() == 1, "Pool contributes one solid water band")
	if not panels.is_empty():
		check(panels[0].size.x > authored.x * 1.8, "Large pool solid width matches its size (%.2f vs authored %.2f)" % [panels[0].size.x, authored.x])
		check(panels[0].size.y > authored.y * 1.8, "Large pool solid depth matches its size (%.2f vs authored %.2f)" % [panels[0].size.y, authored.y])

	# Walk around the water, not across the basin centre.
	var water: Rect2 = panels[0]
	var centre := Vector3(water.get_center().x, .16, water.get_center().y)
	check(not app.world.lot_navigation.point_clear(0, centre), "The basin centre is solid to walkers")
	# Stand clearly west and east of the full basin, then snap each to the nearest
	# clear cell so the chord between them still crosses the water.
	var west: Vector3 = app.world.nearest_clear_point(Vector3(water.position.x - 2.0, .16, water.get_center().y), 0)
	var east: Vector3 = app.world.nearest_clear_point(Vector3(water.end.x + 2.0, .16, water.get_center().y), 0)
	check(west.is_finite() and east.is_finite(), "Clear standing spots exist on both sides of the pool")
	check(west.x < water.position.x and east.x > water.end.x, "Standing spots stay on opposite sides of the basin")
	var path: PackedVector3Array = app.world.path_to(west, east)
	check(not path.is_empty(), "A walker finds a route past the pool")
	var travel: float = 0.0
	for i: int in range(1, path.size()):
		travel += path[i - 1].distance_to(path[i])
	# Going around a large pool must travel farther than the straight chord
	# through the water (about the basin width plus approach).
	check(travel > water.size.x + water.size.y * 0.5, "The route detours around the water (%.1f m for a %.1f×%.1f basin)" % [travel, water.size.x, water.size.y])
	var deep: Rect2 = Rect2(water.get_center() - water.size * 0.25, water.size * 0.5)
	var through_middle: bool = false
	for point: Vector3 in path:
		if deep.has_point(Vector2(point.x, point.z)):
			through_middle = true
			break
	check(not through_middle, "No path waypoint sits in the middle of the basin")

	# Front-crawl stroke still turns the arms over the water.
	var person: LifeActor = app.world.actors.get(app.household.selected_id())
	var anchor: Dictionary = app.world.activity_anchor(pool, LifeOutdoorActs.ACTION_ID, {"swim_lane": 0})
	check(str(anchor.get("kind", "")) == "swim", "Swim anchor is a stroke lap")
	var arms: Array[Quaternion] = []
	for i: int in 120:
		person.set_activity_anchor(anchor.position, anchor.yaw, anchor.kind, LifeOutdoorActs.ACTION_ID, anchor)
		person.animate(DT, 1.0, false, LifeOutdoorActs.ACTION_ID)
		if i % 12 == 0:
			arms.append((person._joints["Arm_R"] as Node3D).quaternion)
	var spread: float = 0.0
	for q: Quaternion in arms:
		spread = maxf(spread, q.angle_to(arms[0]))
	check(spread > 1.0, "The arms turn over in a stroke (%.2f rad)" % spread)
	person.clear_activity_anchor()

	# Parallel lanes for company.
	var lane0: Dictionary = app.world.outdoor_water_anchor(pool, {"swim_lane": 0})
	var lane1: Dictionary = app.world.outdoor_water_anchor(pool, {"swim_lane": 1})
	check(Vector3(lane0.swim_from).distance_to(lane1.swim_from) > 0.3, "Joiners take parallel swim lanes")

	# Ask to Join queues both Lifelets with swim_lane tags.
	var lead: String = app.household.selected_id()
	var partner_id: String = ""
	for member: Dictionary in app.household.members:
		if str(member.id) != lead:
			partner_id = str(member.id)
			break
	var partners: Array = app.household.outdoor_join_partners(str(pool.id), lead)
	check(partners.size() >= 1, "Ask to Join lists household company")
	var available: bool = false
	for partner: Dictionary in partners:
		if str(partner.id) == partner_id and bool(partner.available):
			available = true
	check(available, "The other Lifelet on the lot can join")
	var result: Dictionary = app.household.queue_outdoor_join(str(pool.id), [lead, partner_id], app.world.approach(pool))
	check(bool(result.ok), "Ask to Join queues both Lifelets (%s)" % str(result.get("error", "")))
	if bool(result.ok):
		var lead_sim: LifeSim = app.household.member_sim(lead)
		var partner_sim: LifeSim = app.household.member_sim(partner_id)
		check(not lead_sim.action_queue.is_empty() and int(lead_sim.action_queue[0].get("swim_lane", -1)) == 0, "Lead takes lane 0")
		check(not partner_sim.action_queue.is_empty() and int(partner_sim.action_queue[0].get("swim_lane", -1)) == 1, "Partner takes lane 1")

	# Hot tub also offers Ask to Join.
	var tub: Dictionary = {}
	for spot: Vector2 in [Vector2(-9, 7), Vector2(9, 7), Vector2(-15, 6), Vector2(15, 6)]:
		var at := Vector3(spot.x, LifeBuildingState.level_y(0), spot.y)
		if app.world.can_place("hot_tub", at, 0.0):
			app.world.add_item({"id": "probe_tub", "kind": "hot_tub", "x": at.x, "z": at.z, "rotation": 0, "style": "round"})
			tub = app._find_item("probe_tub")
			break
	check(not tub.is_empty() and LifeOutdoorActs.can_ask_to_join("hot_tub"), "Hot tub is Ask-to-Join capable")

	_finish()


func _finish() -> void:
	var out := FileAccess.open("res://evidence/pool_join_probe.txt", FileAccess.WRITE)
	if out:
		out.store_string("checks=%d failures=%d\n" % [checks, failures.size()])
		for line: String in failures:
			out.store_string("FAIL: %s\n" % line)
		out.close()
	print("POOL_JOIN_PROBE assertions=%d failures=%d" % [checks, failures.size()])
	for line: String in failures:
		print("FAIL: ", line)
	if is_instance_valid(app):
		app.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
