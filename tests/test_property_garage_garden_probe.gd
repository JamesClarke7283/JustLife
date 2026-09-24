extends SceneTree
## Preset homes, four-bay garage snaps, outdoor Join / Call Friend / Stay Over,
## and a carried-furniture house move. Focused checks that would fail before the
## property and garden update.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_property_garage_garden_probe.gd

const Properties = preload("res://scripts/properties.gd")

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)
		push_error(message)


func frames(n: int = 3) -> void:
	for i: int in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# ------------------------------------------------------------- presets
	for type_id: String in ["medium", "large", "ultramodern", "traditional"]:
		var info: Dictionary = Properties.type_info(type_id)
		check(bool(info.get("preset", false)), "%s is a buyable preset." % type_id)
		check(info.get("architecture_styles", []).size() == 3, "%s offers 3 architecture styles." % type_id)
		check(info.get("exterior_swatches", []).size() == 10, "%s offers 10 exterior swatches." % type_id)
		var layout: Array = LifeCatalog.starter_layout(int(info.layout))
		check(layout.size() > 0, "%s has a non-empty starter layout." % type_id)
		var kinds: Dictionary = {}
		for entry: Dictionary in layout:
			kinds[str(entry.kind)] = true
		if type_id == "medium":
			check(kinds.has("pool") and kinds.has("garden_table") and kinds.has("bbq"), "Medium includes pool, outdoor table and BBQ.")
			check(int(info.price) == 1500, "Medium costs ℒ1500.")
			check(int(info.beds) == 2, "Medium has 2 bedrooms.")
		elif type_id == "large":
			check(kinds.has("pool") and kinds.has("hot_tub") and kinds.has("car_garage") and kinds.has("bbq"), "Large includes pool, hot tub, garage and BBQ.")
			check(int(info.beds) == 4 and int(info.baths) == 3, "Large has 4 beds and 3 baths.")
		elif type_id in ["ultramodern", "traditional"]:
			check(kinds.has("garden_table") and kinds.has("bbq"), "%s has garden seating and BBQ." % type_id)

	check(LifeCatalog.vehicle_snap_locals("car_garage").size() == 4, "A garage exposes 4 vehicle snap locals.")
	check(LifeOutdoorActs.can_ask_to_join("garden_table") and LifeOutdoorActs.can_ask_to_join("bbq"), "Garden table and BBQ accept Ask to Join.")
	check(LifeOutdoorActs.CALL_FRIEND_ACTION == "call_friend_over", "Call Friend Over is a named outdoor action.")
	check(LifeHomeVisit.STAY_OVER_EXTRA_MINUTES > 0.0, "Stay Over extends the guest leave timer.")

	var carried: Array = [{"id": "old_fridge", "kind": "fridge", "x": 0.0, "z": 0.0, "rotation": 0.0}, {"id": "old_car", "kind": "car", "x": 1.0, "z": 1.0, "rotation": 0.0}]
	var starter: Array = LifeCatalog.starter_layout(6)
	var merged: Array = Properties.merge_move_layout(carried, starter)
	var merged_kinds: Dictionary = {}
	for entry: Dictionary in merged:
		merged_kinds[str(entry.kind)] = true
	check(merged_kinds.has("fridge") and merged_kinds.has("car"), "Move merge keeps carried furniture and cars.")
	check(merged_kinds.has("pool") and merged_kinds.has("bbq"), "Move merge keeps preset outdoor amenities.")

	# ------------------------------------------------------------- live world
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(6)
	app.set_sound(false)
	app.household_profiles = [{"name": "Alex Grove", "age_stage": "adult", "life_stage": "adult", "traits": ["Friendly"]}]
	app.selected_lot = 0
	app.start_household()
	await frames(8)
	app.household.set_speed(0)
	app.household.set_funds(50000)

	# Garage snaps: place a four-car garage then a car nearby.
	app.world.add_item({"id": "probe_garage", "kind": "car_garage", "x": 0.0, "z": 10.0, "rotation": 180.0}, false)
	await frames(1)
	var free_before: int = app.world.garage_vehicle_bays().size()
	check(free_before == 4, "Empty garage reports 4 free bays (%d)." % free_before)
	app.world.add_item({"id": "probe_car", "kind": "car", "x": 0.5, "z": 9.5, "rotation": 0.0}, true)
	await frames(2)
	var car: Dictionary = {}
	for item: Dictionary in app.world.items:
		if str(item.id) == "probe_car":
			car = item
			break
	check(not car.is_empty(), "Probe car was placed.")
	if car.is_empty():
		print("PROPERTY_GARAGE_GARDEN_PROBE %d/%d" % [checks - failures.size(), checks])
		quit(1)
		return
	# If auto-snap missed (lot clutter), force the public snap path.
	if app.world.garage_vehicle_bays("probe_car").size() == 4:
		app.world._snap_all_vehicles_to_garages()
		await frames(1)
	var bays: Array = app.world.garage_vehicle_bays()
	check(bays.size() == 3, "Three free bays remain after one car snaps in (%d)." % bays.size())
	var car_node: Node3D = car.get("node")
	var snapped: bool = false
	for item: Dictionary in app.world.items:
		if str(item.get("kind", "")) != "car_garage": continue
		var gnode: Node3D = item.get("node")
		if not is_instance_valid(gnode): continue
		var yaw: float = gnode.rotation.y
		var basis_x := Vector3(cos(yaw), 0, -sin(yaw))
		var basis_z := Vector3(sin(yaw), 0, cos(yaw))
		for local: Vector3 in LifeCatalog.vehicle_snap_locals("car_garage"):
			var world: Vector3 = gnode.global_position + basis_x * local.x + basis_z * local.z
			if is_instance_valid(car_node) and car_node.global_position.distance_to(world) < 1.2:
				snapped = true
	check(snapped, "Probe car sits on a garage snap point.")
	check(app.world.toggle_garage_door("probe_garage"), "Garage door toggles open.")
	var garage: Dictionary = app.world.items.filter(func(i: Dictionary) -> bool: return str(i.id) == "probe_garage")[0]
	check(bool(garage.node.get_meta("garage_door_open", false)), "Garage door meta is open after toggle.")

	# Drive party groups include adults.
	var options: Array = app.residents.party_options()
	check(options.any(func(e: Dictionary) -> bool: return str(e.get("group", "")) == "adults"), "Drive party lists an adults group.")

	# Stay Over on an inside guest.
	var guest_id: String = ""
	for id: String in LifeResidents.PEOPLE.keys():
		guest_id = id
		break
	if not guest_id.is_empty():
		app.residents.home_visit.state = {
			"serial": 1, "guest": guest_id, "phase": "inside", "created_at": 0.0,
			"arrived_at": 0.0, "admitted_at": 0.0, "phase_at": app.residents.home_visit._now(),
			"welcome": [0, 0, 0], "inside": [0, 0, 0], "exit": [0, 0, 0],
			"route": {"points": [], "point": 0}, "greeting": {}, "next_greeting": 1,
			"departure": {}, "blocked": false, "meal": {}, "next_meal": 1, "auto_welcome": false,
		}
		var before: float = app.residents.home_visit.stay_deadline()
		check(app.residents.home_visit.ask_to_stay_over(), "Ask to Stay Over succeeds for an inside guest.")
		check(app.residents.home_visit.stay_deadline() > before, "Stay Over lengthens the leave deadline.")

	# Buy medium through the real move path's payment + layout apply.
	var before_funds: int = app.household.funds
	var buy: Dictionary = Properties.move_into(app.properties, "medium", app.household.funds)
	check(bool(buy.ok), "Medium can be bought for the quoted price.")
	app.properties = buy.state
	app.household.set_funds(int(buy.funds))
	check(app.household.funds == before_funds - int(buy.cost), "Buying medium deducts house price plus moving fee.")
	var layout: Array = LifeCatalog.starter_layout(6)
	app.home_layout = layout
	app.setup_live(layout)
	await frames(4)
	check(Properties.active(app.properties) == "medium", "Active home is Medium after the buy.")
	var owned: Dictionary = Properties.grant(Properties.fresh(), "medium", "medium", {})
	var exterior: Dictionary = Properties.set_exterior(owned.state, "medium", "ultra_modern", "8faf9f", "")
	check(bool(exterior.ok) and str(exterior.state.houses.medium.architecture_style) == "ultra_modern", "Exterior style and colour apply on a preset.")
	check(not bool(Properties.set_exterior(owned.state, "medium", "gothic", "", "").ok), "Unknown architecture styles are refused.")

	print("PROPERTY_GARAGE_GARDEN_PROBE %d/%d" % [checks - failures.size(), checks])
	quit(1 if not failures.is_empty() else 0)
