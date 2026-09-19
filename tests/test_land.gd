extends SceneTree
## The land package: buying neighbouring plots really grows the household's lot,
## and the growth is what the ground, the navigation graph and the build rules
## all see.
##
## Every assertion drives a public path — the real Build transaction, the real
## world rebuild, the real save and a fresh load — and reads what the player
## would actually observe: the lot the world bounds against, the walkable cells
## the graph holds, and where a furnishing may stand.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_land.gd

const Land = preload("res://scripts/land.gd")

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


func frames(n: int = 3) -> void:
	for i: int in n:
		await process_frame


## How many walkable ground cells the live navigation graph holds.
func _walkable_cells() -> int:
	var total: int = 0
	var region: Rect2i = app.world.navigation.region
	for x: int in range(region.position.x, region.end.x):
		for z: int in range(region.position.y, region.end.y):
			if not app.world.navigation.is_point_solid(Vector2i(x, z)):
				total += 1
	return total


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	app.household_profiles[0]["age_stage"] = "adult"
	await frames(4)
	app.start_household()
	await frames(16)
	app.household.set_speed(0)

	# ---------------------------------------------------------------- the policy
	check(Land.validate(Land.fresh()).is_empty(), "A fresh land record is valid.")
	check(Land.plots(Land.fresh()) == 0 and Land.rect(Land.fresh()) == Land.BASE,
		"A fresh household owns exactly the starting plot.")
	check(not Land.validate({"version": 1, "west": -1}).is_empty(), "A negative plot count is refused.")
	check(not Land.validate({"version": 9, "west": 0}).is_empty(), "An unknown land version is refused.")
	check(Land.validate({"version": 1, "west": 3, "east": 2, "north": 1}).is_empty(), "Real plot counts are valid.")
	check(not Land.validate({"west": 3}).is_empty(), "A land record without a version is refused.")
	# The price rises with each plot on the same side.
	check(Land.price({"west": 0}, "west") < Land.price({"west": 1}, "west"),
		"Land gets dearer the further out it is.")
	check(Land.price(Land.fresh(), "south") == 0 and not Land.purchase_error(Land.fresh(), "south", 1 << 30).is_empty(),
		"The street frontage is not for sale.")

	# -------------------------------------------------------- the real purchase
	app.set_build_mode(true)
	await frames(4)
	var start_lot: Rect2 = LifeBuildingState.lot()
	var start_cells: int = _walkable_cells()
	app.household.set_funds(100000)
	app.sim.funds = 100000
	var price: int = Land.price(LifeBuildingState.land, "west")

	var bought: Dictionary = app.build_transactions.buy_land("west")
	check(bool(bought.ok), "A neighbouring plot on a side can really be bought (%s)." % str(bought.get("error", "")))
	check(int(bought.get("cost", 0)) == price, "The plot costs the price the policy quoted (ℒ%d)." % price)
	check(app.household.funds == 100000 - price, "The purse pays exactly once (ℒ%d -> ℒ%d)." % [100000, app.household.funds])
	var grown: Rect2 = LifeBuildingState.lot()
	check(grown.size.x > start_lot.size.x and is_equal_approx(grown.position.x, start_lot.position.x - Land.PLOT_WIDTH),
		"The lot really grew westward by one plot (%.1f -> %.1f wide)." % [start_lot.size.x, grown.size.x])
	check(is_equal_approx(grown.position.y, start_lot.position.y) and is_equal_approx(grown.end.y, start_lot.end.y),
		"The lot does not grow toward the street.")
	check(_walkable_cells() > start_cells, "The bought plot is really walkable (%d -> %d cells)." % [start_cells, _walkable_cells()])
	var region: Rect2i = app.world.navigation.region
	check(region.position.x * .25 <= grown.position.x and region.end.x * .25 >= grown.end.x,
		"The navigation region covers the new ground (%s vs %s)." % [str(region), str(grown)])

	# The ground and its boundaries move with the lot.
	var hedge_found: bool = false
	for node: Node in app.world.ground_node.get_children():
		if node is MeshInstance3D and (node as MeshInstance3D).position.z < grown.position.y + 1.5 and (node as MeshInstance3D).position.z > grown.position.y:
			hedge_found = true
	check(hedge_found, "The back hedge is drawn on the lot's new edge.")

	# A furnishing may now stand on ground that was outside the old lot.
	var old_outside := Vector3(grown.position.x + 1.0, .16, -2.0)
	check(old_outside.x < start_lot.position.x, "The chosen spot really was outside the starting lot.")
	check(app.world.can_place("kennel", old_outside, 0.0), "A kennel now fits on the bought plot.")
	check(not app.world.can_place("kennel", Vector3(grown.position.x - 2.0, .16, -2.0), 0.0),
		"A kennel is still refused beyond the new boundary.")

	# ------------------------------------------------------- indefinite growth
	var funds_before: int = app.household.funds
	for i: int in 5:
		var more: Dictionary = app.build_transactions.buy_land("east")
		check(bool(more.ok), "Plot %d on the east side can be bought (%s)." % [i + 2, str(more.get("error", ""))])
	var wide: Rect2 = LifeBuildingState.lot()
	check(Land.plots(LifeBuildingState.land) == 6, "Six plots are owned in total (%d)." % Land.plots(LifeBuildingState.land))
	check(wide.size.x > grown.size.x + 4 * Land.PLOT_WIDTH - .01, "The lot keeps growing with every plot (%.1f m wide)." % wide.size.x)
	check(app.household.funds < funds_before, "Every plot was paid for.")
	# The north side deepens the garden without touching the frontage.
	var north: Dictionary = app.build_transactions.buy_land("north")
	check(bool(north.ok) and is_equal_approx(LifeBuildingState.lot().end.y, Land.BASE.end.y),
		"The northern plot deepens the garden and leaves the street where it is.")
	check(is_equal_approx(LifeBuildingState.lot().position.y, Land.BASE.position.y - Land.PLOT_DEPTH),
		"The northern plot really moved the back edge.")

	# A purchase the purse cannot afford is refused with a reason and changes
	# nothing at all.
	var small: int = LifeBuildingState.lot().size.x
	app.household.set_funds(10)
	app.sim.funds = 10
	var refused: Dictionary = app.build_transactions.buy_land("west")
	check(not bool(refused.ok) and not str(refused.get("error", "")).is_empty(), "An unaffordable plot is refused with a reason.")
	check(is_equal_approx(LifeBuildingState.lot().size.x, small), "A refused purchase changes no land.")
	check(app.household.funds == 10, "A refused purchase takes no money.")

	# ------------------------------------------------------------------- saving
	# The land rides the real save, and a fresh load restores the lot it was
	# saved on.
	check(app.world.serialize_items().size() > 0, "The home still serializes with its larger lot.")
	app.home_layout = app.world.serialize_items()
	var saved_ok: bool = app.save_game("land_probe", "Land probe")
	check(saved_ok, "The household really saves with its larger lot.")
	var sim: Object = app.sim
	var slot: Dictionary = LifeSaveLibrary.read_slot("land_probe")
	check(bool(slot.get("ok", false)), "The written slot reads back (%s)." % str(slot.get("error", "")))
	var saved_household: Dictionary = slot.get("data", {})
	var saved_members: Array = saved_household.get("members", [])
	check(not saved_members.is_empty(), "The saved household has its members.")
	var saved_character: Dictionary = (saved_members[0] as Dictionary).get("state", {}).get("character", {})
	var world_state: Dictionary = saved_character.get("world_state", {})
	check(world_state.get("land", {}) is Dictionary and not (world_state.get("land", {}) as Dictionary).is_empty(),
		"The household's land rides the saved world state (%s)." % str(world_state.get("land", {})))
	var saved_land: Dictionary = (world_state.get("land", {}) as Dictionary).duplicate(true)
	check(Land.plots(saved_land) == 7, "The saved land records every bought plot (%d)." % Land.plots(saved_land))

	# A fresh household loading that state gets the same lot back.
	var fresh: Object = load("res://scripts/life_sim.gd").new()
	root.add_child(fresh)
	fresh.new_household({"name": "Land Owner", "age_stage": "adult", "traits": []})
	var restored: Dictionary = fresh.restore_state((saved_members[0] as Dictionary).get("state", {}))
	check(bool(restored.ok), "A save with bought land is valid (%s)." % str(restored.get("error", "")))
	var saved_again: Dictionary = fresh.character.get("world_state", {}).get("land", {})
	check(Land.plots(saved_again) == Land.plots(saved_land), "The land round-trips through a real save and load.")
	# A corrupt land record is refused rather than trusted.
	var damaged: Dictionary = fresh.get_state()
	damaged.character.world_state["land"] = {"version": 1, "west": -4}
	check(not bool(fresh.restore_state(damaged).ok), "A corrupt land record is refused.")
	fresh.free()
	LifeSaveLibrary.delete_slot("land_probe")

	print("LAND_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "lot": str(LifeBuildingState.lot()), "plots": Land.plots(LifeBuildingState.land)}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
