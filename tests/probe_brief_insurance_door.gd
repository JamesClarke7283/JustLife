extends SceneTree
## Focused check for burglar cover at ℒ600, Baby & Child Insurance at ℒ500, and
## a doorway through a shared wall after buying an adjacent plot.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/probe_brief_insurance_door.gd

const Land = preload("res://scripts/land.gd")
const Properties = preload("res://scripts/properties.gd")

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.household_profiles = [
		{"name": "Avery Stone", "age_stage": "young_adult", "traits": [], "hair": 0, "gender": "female"},
		{"name": "River Stone", "age_stage": "young_adult", "traits": [], "hair": 0, "gender": "male"}]
	app.creator_family_links = []
	app.start_household(); await frames(10)
	app.household.set_speed(0)
	app.household.set_funds(50000)

	# ------------------------------------------------------------- INS-01
	check(int(LifeSim.INSURANCE_POLICIES.home.premium) == 600,
		"Burglar / home cover is priced at ℒ600.")
	check(app.household.insurance().is_empty(), "Fresh household starts uninsured.")
	var before: int = app.household.funds
	var bought: Dictionary = app.buy_home_insurance("home")
	check(bool(bought.ok), "Buying home insurance succeeds (%s)." % str(bought.get("error", "")))
	check(app.household.funds == before - 600,
		"Buying charges exactly ℒ600 (ℒ%d -> ℒ%d)." % [before, app.household.funds])
	check(str(app.household.insurance().get("id", "")) == "home",
		"The policy is set on the household (%s)." % str(app.household.insurance()))
	var house_id: String = Properties.active(app.properties)
	check(str(Properties.policy(app.properties, house_id).get("id", "")) == "home",
		"The house record carries the same policy.")

	# ------------------------------------------------------------- INS-02
	check(int(LifeSim.INSURANCE_POLICIES.baby.premium) == 500,
		"Baby & Child Insurance is priced at ℒ500.")
	before = app.household.funds
	var baby: Dictionary = app.buy_home_insurance("baby")
	check(bool(baby.ok), "Buying Baby & Child Insurance succeeds (%s)." % str(baby.get("error", "")))
	check(app.household.funds == before - 500,
		"Baby cover charges ℒ500 (ℒ%d -> ℒ%d)." % [before, app.household.funds])
	check(str(Properties.house(app.properties, house_id).get("baby_policy", "")) == "baby",
		"The house keeps Baby & Child cover beside burglar cover.")
	check(str(app.household.insurance().get("id", "")) == "home",
		"Burglar cover stays in force after adding baby cover.")

	# ------------------------------------------------------------- BLD-01
	app.set_build_mode(true); await frames(4)
	app.household.set_funds(200000); app.sim.funds = 200000
	var land_buy: Dictionary = app.build_transactions.buy_land("west")
	check(bool(land_buy.ok), "Buying the west plot succeeds (%s)." % str(land_buy.get("error", "")))
	await frames(8)
	var tx = app.build_transactions
	# Room on the purchased strip, sharing the old west edge of the starter floor
	# (x = -6) so the doorway is an interior cut across that shared boundary.
	var room: Dictionary = tx.prepare({"op": "structure", "tool": "room", "level": 0,
		"ax": -18.0, "az": -4.0, "bx": -6.0, "bz": 4.0})
	check(bool(room.ok), "A room on the bought plot builds (%s)." % str(room.get("error", "")))
	if bool(room.ok):
		check(bool(tx.commit(room).ok), "The annex room commits.")
	var shared: Dictionary = {}
	var wall_xs: Array[String] = []
	for wall: Dictionary in app.world.construction.building_state.get("walls", []):
		wall_xs.append("id=%s x=%.3f z=%.3f w=%.3f d=%.3f" % [str(wall.id), float(wall.x), float(wall.z), float(wall.w), float(wall.d)])
		# Vertical wall on the annex's east edge (the shared boundary with the starter home).
		if absf(float(wall.x) + 6.0) < 0.2 and float(wall.d) > 1.5 and float(wall.w) < 0.5:
			shared = wall
	check(not shared.is_empty(), "The shared boundary wall exists near x=-6 (%s)." % str(wall_xs))
	if not shared.is_empty():
		var door: Dictionary = tx.prepare({"op": "structure", "tool": "door", "level": 0,
			"id": str(shared.id), "center": 0.0})
		check(bool(door.ok), "A doorway through the shared boundary is allowed (%s)." % str(door.get("error", "")))
		if bool(door.ok):
			check(bool(tx.commit(door).ok) and int(door.cost) == 90,
				"The shared-boundary doorway commits for ℒ90.")

	# --------------------------------------------------------------- pets
	var dog: Dictionary = {
		"id": "pet_probe", "name": "Scout", "species": "dog", "sex": "male",
		"coat_color": "89563a", "mark_color": "ead6b8", "gradient": 0.2,
		"coat_length": "short", "marking": "none", "care": LifePetCare.fresh(),
	}
	app.household.pets = {"version": 1, "next_serial": 2, "pets": [dog]}
	var offered: Array = app.household.pet_actions("pet_probe", app.household.selected_id())
	var labels: PackedStringArray = PackedStringArray()
	for entry: Dictionary in offered:
		labels.append(str(entry.get("label", "")))
	check(labels.has("Feed Dog") and labels.has("Play with Dog") and labels.has("Play Tricks") and labels.has("Take for a Walk"),
		"Dog interactions offer Feed/Play/Tricks/Walk (%s)." % str(labels))

	print("BRIEF_PROBE ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(2)
	quit(0 if failures.is_empty() else 1)
