extends SceneTree
## Prove Build & buy really trades: a valid placement is accepted and debits the
## household, an invalid one is refused with a visible reason and costs nothing,
## and undo reverses a purchase.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_build_trade.gd

const LifeCatalog = preload("res://scripts/catalog.gd")
const Building = preload("res://scripts/building_state.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://build_trade"))
	root.get_texture().get_image().save_png("user://build_trade/%s.png" % label)
	print("BUILD_TRADE_SHOT ", ProjectSettings.globalize_path("user://build_trade/%s.png" % label))

func notice_text() -> String:
	if is_instance_valid(app.notice_label): return str(app.notice_label.text)
	return ""

## Scan the lot for a spot the game itself accepts, rather than guessing.
func first_valid_spot(kind: String) -> Vector3:
	for xi in range(-40, 41):
		for zi in range(-40, 41):
			var at := Vector3(float(xi) * 0.25, Building.GROUND_Y, float(zi) * 0.25)
			if app.world.can_place(kind, at, 0.0): return at
	return Vector3(NAN, 0, 0)

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(14)
	app.household.set_speed(0)
	app.set_build_mode(true)
	await frames(4)
	check(app.mode == "build", "Build & buy is open")

	var funds_before: int = int(app.sim.funds)
	var items_before: int = app.world.items.size()
	var price: int = int(LifeCatalog.ITEMS["chair"].price)

	# --- A valid placement is accepted and debits the household ---------------
	var spot: Vector3 = first_valid_spot("chair")
	check(spot.is_finite(), "The lot offers a spot the game accepts for a chair")
	if spot.is_finite():
		app.begin_purchase("chair")
		await frames(3)
		app.on_placement("chair", spot, 0.0)
		await frames(6)
		check(app.world.items.size() == items_before + 1, "The chair was really placed (%d -> %d)" % [items_before, app.world.items.size()])
		var funds_after: int = int(app.sim.funds)
		check(funds_after == funds_before - price, "The purchase debited exactly its price (§%d -> §%d, price §%d)" % [funds_before, funds_after, price])
		check(int(app.household.funds) == funds_after, "The household's own ledger agrees with the HUD (§%d)" % int(app.household.funds))
		check(notice_text().contains("added to your home"), "The player is told what happened: \"%s\"" % notice_text())
		await shot("01_valid_placement")

		# --- Undo reverses it ---------------------------------------------------
		var placed: int = app.world.items.size()
		var funds_before_undo: int = int(app.sim.funds)
		app.undo_build()
		await frames(6)
		check(app.world.items.size() == placed - 1, "Undo removed the furnishing (%d -> %d)" % [placed, app.world.items.size()])
		check(int(app.sim.funds) == funds_before_undo + price, "Undo refunded the price (§%d -> §%d)" % [funds_before_undo, int(app.sim.funds)])

	# --- An invalid placement is refused and costs nothing --------------------
	var blocked_funds: int = int(app.sim.funds)
	var blocked_items: int = app.world.items.size()
	app.begin_purchase("chair")
	await frames(3)
	# A point far outside any floor is refused by the game's own validity check.
	var outside := Vector3(40.0, Building.GROUND_Y, 40.0)
	check(not app.world.can_place("chair", outside, 0.0), "A point off the lot is not a legal placement")
	app.on_placement("chair", outside, 0.0)
	await frames(6)
	check(app.world.items.size() == blocked_items, "The refused placement added nothing (%d)" % app.world.items.size())
	check(int(app.sim.funds) == blocked_funds, "The refused placement charged nothing (§%d)" % int(app.sim.funds))
	check(not notice_text().is_empty(), "The refusal explains itself: \"%s\"" % notice_text())
	await shot("02_refused_placement")
	app.cancel_placement()

	# --- The catalogue price is really enforced ------------------------------
	app.household.set_funds(10)
	await frames(3)
	var poor_items: int = app.world.items.size()
	app.begin_purchase("bed")
	await frames(2)
	var poor_spot: Vector3 = first_valid_spot("bed")
	if poor_spot.is_finite():
		app.on_placement("bed", poor_spot, 0.0)
		await frames(6)
		check(app.world.items.size() == poor_items, "A furnishing the household cannot afford is refused")
		check(int(app.sim.funds) == 10, "A refused purchase leaves funds untouched (§%d)" % int(app.sim.funds))
		check(notice_text().contains("You need"), "The shortfall is explained: \"%s\"" % notice_text())
	app.cancel_placement()

	print("BUILD_TRADE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
