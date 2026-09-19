extends SceneTree
## The property package: a household can choose the house it starts in, own more
## than one, move between them mid-game, and insure each separately.
##
## Every assertion drives a public path — the real opening picker, the real
## property panel's own callbacks, the real world rebuild and a real save and
## load — and reads what the player would observe: which house is stood in, what
## was paid, and what cover is in force.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_properties.gd

const Properties = preload("res://scripts/properties.gd")
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


## How many real furniture records the live world holds.
func _furnishings() -> int:
	var total: int = 0
	for item: Dictionary in app.world.items:
		if not bool(item.get("derived", false)):
			total += 1
	return total


func _run() -> void:
	# ------------------------------------------------------------- the policy
	check(Properties.validate(Properties.fresh()).is_empty(), "A fresh property record is valid.")
	check(Properties.starters().size() == 3, "Three houses can be chosen at the start (%d)." % Properties.starters().size())
	check(Properties.type_info("juniper").beds == 4, "The largest house type really has four bedrooms.")
	check(not Properties.is_starter("juniper"), "A bought house is not a starter house.")
	check(Properties.price("juniper") > Properties.price("rowan") and Properties.price("rowan") > 0,
		"A larger house costs more than a smaller one.")
	for type_id: String in Properties.types():
		check(LifeCatalog.starter_layout(int(Properties.type_info(type_id).layout)).size() > 0,
			"The %s type has a real layout." % type_id)
	check(not Properties.validate({"version": 1, "houses": {"x": {"type": "castle"}}}).is_empty(),
		"An unknown kind of house is refused.")
	check(not Properties.validate({"version": 1, "active": "ghost", "houses": {}}).is_empty(),
		"A save living in a house it does not own is refused.")

	# --------------------------------------------------- the opening choice
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	app.household_profiles[0]["age_stage"] = "adult"
	await frames(4)
	# Choose the third starter house through the real picker, then start.
	app.selected_lot = 2
	app.show_lot_selection()
	await frames(4)
	app.start_household()
	await frames(16)
	app.household.set_speed(0)

	check(Properties.count(app.properties) == 1, "Starting grants exactly one home (%d)." % Properties.count(app.properties))
	check(Properties.active(app.properties) == "canvas", "The household starts in the house it chose (%s)." % Properties.active(app.properties))
	check(_furnishings() > 0, "The chosen house is really furnished (%d items)." % _furnishings())
	check(LifeBuildingState.lot() == Land.BASE, "A new home starts on the starting plot.")

	# --------------------------------------------------- buying a second home
	app.household.set_funds(500000)
	app.sim.funds = 500000
	var before_layout: int = _furnishings()
	var cost: int = Properties.move_cost(app.properties, "juniper")
	app._move_house("juniper")
	await frames(16)
	check(Properties.count(app.properties) == 2, "A second home can be bought (%d owned)." % Properties.count(app.properties))
	check(Properties.active(app.properties) == "juniper", "The household moved into the new home (%s)." % Properties.active(app.properties))
	check(app.household.funds == 500000 - cost, "The move cost exactly its quoted price (ℒ%d -> ℒ%d)." % [500000, app.household.funds])
	check(_furnishings() != before_layout, "The new house really has its own furnishings (%d vs %d)." % [_furnishings(), before_layout])
	check(_furnishings() > 40, "The largest house is substantially furnished (%d items)." % _furnishings())
	# The house left behind kept its own saved layout.
	var left: Dictionary = Properties.house(app.properties, "canvas")
	check(not (left.get("layout", []) as Array).is_empty(), "The house left behind kept its own furnishings.")

	# ------------------------------------------------ per-house insurance
	var juniper_id: String = Properties.active(app.properties)
	check(Properties.policy(app.properties, juniper_id).is_empty(), "A newly bought home starts uninsured.")
	app._buy_property_policy("premium")
	await frames(4)
	var held: Dictionary = Properties.policy(app.properties, juniper_id)
	check(held.get("id", "") == "premium", "The larger house can carry premium cover (%s)." % str(held.get("id", "")))
	check(app.sim.insurance_policy_id == "premium", "The cover in force on the sim is this house's own (%s)." % app.sim.insurance_policy_id)
	check(Properties.policy(app.properties, "canvas").is_empty(), "The other house is still uninsured (cover is per house).")
	# The premium policy really pays more than the loss.
	app.household.set_funds(4000)
	app.sim.funds = 4000
	var before_robbery: int = app.household.funds
	var robbed: Dictionary = app.household.robbery()
	check(bool(robbed.get("ok", false)), "An insured house can be robbed.")
	check(app.household.funds > before_robbery, "Premium cover pays back more than was taken (ℒ%d -> ℒ%d)." % [before_robbery, app.household.funds])

	# --------------------------------------------------------- moving back
	var back_cost: int = Properties.move_cost(app.properties, "canvas")
	app._move_house("canvas")
	await frames(16)
	check(Properties.active(app.properties) == "canvas", "The household can move back to its first home.")
	check(Properties.count(app.properties) == 2, "Moving back buys nothing and owns the same two homes.")
	check(Properties.policy(app.properties, "canvas").is_empty(), "Moving into an uninsured home leaves it uninsured.")
	check(app.sim.insurance_policy_id == "", "The uninsured home really carries no cover.")
	check(Properties.policy(app.properties, "juniper").get("id", "") == "premium", "The house moved out of keeps its own policy.")

	# ----------------------------------------------------- the public panel
	app.show_property_panel()
	await frames(4)
	check(app.overlay_open, "The property panel opens.")
	var rows: int = 0
	for type_id: String in Properties.types():
		if app.overlay.find_child("PropertyRow_" + type_id, true, false) != null:
			rows += 1
	check(rows == Properties.types().size(), "Every house type gets a row (%d of %d)." % [rows, Properties.types().size()])
	check(app.overlay.find_child("Property_canvas", true, false) != null, "The current home has its own row.")
	app.close_overlay()
	await frames(2)

	# ------------------------------------------------------------- saving
	check(app.save_game("properties_probe", "Properties probe"), "The household saves with its homes.")
	var slot: Dictionary = LifeSaveLibrary.read_slot("properties_probe")
	check(bool(slot.get("ok", false)), "The written slot reads back (%s)." % str(slot.get("error", "")))
	var members: Array = (slot.get("data", {}) as Dictionary).get("members", [])
	var saved_character: Dictionary = (members[0] as Dictionary).get("state", {}).get("character", {})
	var world_state: Dictionary = saved_character.get("world_state", {})
	check(not (world_state.get("properties", {}) as Dictionary).is_empty(), "The properties ride the saved world state.")
	var saved_props: Dictionary = world_state.get("properties", {})
	check(Properties.count(saved_props) == 2, "Both homes are recorded in the save (%d)." % Properties.count(saved_props))
	check(Properties.policy(saved_props, "juniper").get("id", "") == "premium", "The premium cover on the second home survives the save.")
	var fresh: Object = load("res://scripts/life_sim.gd").new()
	root.add_child(fresh)
	fresh.new_household({"name": "Owner", "age_stage": "adult", "traits": []})
	check(bool(fresh.restore_state((members[0] as Dictionary).get("state", {})).ok), "A save with two homes is valid.")
	check(Properties.count(fresh.character.get("world_state", {}).get("properties", {})) == 2, "The homes round-trip through a real save and load.")
	var damaged: Dictionary = fresh.get_state()
	damaged.character.world_state["properties"] = {"version": 1, "active": "nowhere", "houses": {}}
	check(not bool(fresh.restore_state(damaged).ok), "A save living in an unowned house is refused.")
	fresh.free()
	LifeSaveLibrary.delete_slot("properties_probe")

	print("PROPERTIES_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "owned": Properties.count(app.properties)}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
