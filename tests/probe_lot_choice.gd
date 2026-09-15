extends SceneTree
## Prove the three-lot housing choice is playable: each lot really builds its
## own home, and the furnishing sets differ.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_lot_choice.gd

const LifeCatalog = preload("res://scripts/catalog.gd")
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://lot_choice"))
	root.get_texture().get_image().save_png("user://lot_choice/%s.png" % label)
	print("LOT_SHOT ", ProjectSettings.globalize_path("user://lot_choice/%s.png" % label))

func kind_counts() -> Dictionary:
	var counts: Dictionary = {}
	for item: Dictionary in app.world.items:
		counts[str(item.get("kind", ""))] = int(counts.get(str(item.get("kind", "")), 0)) + 1
	return counts

func kind_multiset() -> Array:
	var kinds: Array = []
	for item: Dictionary in app.world.items: kinds.append(str(item.get("kind", "")))
	kinds.sort()
	return kinds

## Move into a chosen lot through the real creator flow and report what was built.
func live_in(lot: int) -> Dictionary:
	app._begin_new_game()
	await frames(6)
	app.selected_lot = lot
	app.show_lot_selection()
	await frames(6)
	app.start_household()
	await frames(16)
	app.household.set_speed(0)
	await frames(4)
	return {
		"mode": app.mode,
		"items": app.world.items.size(),
		"funds": int(app.sim.funds),
		"kinds": kind_counts(),
		"multiset": kind_multiset(),
	}

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)

	var results: Array[Dictionary] = []
	var names: Array[String] = ["Willow Cottage", "Sage House", "A Fresh Canvas"]
	for lot: int in range(3):
		var result: Dictionary = await live_in(lot)
		check(result.mode == "live", "%s really moved the household in (mode %s)" % [names[lot], str(result.mode)])
		check(int(result.items) > 0, "%s built a furnished home (%d items)" % [names[lot], int(result.items)])
		check(app.current_venue == "home", "%s is the household's home" % names[lot])
		# Every placed kind must be a real catalogue item.
		for kind: String in result.kinds:
			check(LifeCatalog.ITEMS.has(kind), "%s placed a real catalogue item (%s)" % [names[lot], kind])
		await shot("lot%d_%s" % [lot, names[lot].to_lower().replace(" ", "_")])
		results.append(result)

	# The three starter layouts must not be the same house three times.
	var summary: Array[String] = []
	for i: int in range(3):
		summary.append("%s: %d items, §%d" % [names[i], int(results[i].items), int(results[i].funds)])
	print("lots -> " + "; ".join(summary))
	for i: int in range(3):
		for j: int in range(i + 1, 3):
			var same: bool = results[i].items == results[j].items
			var identical: bool = str(results[i].multiset) == str(results[j].multiset)
			check(not identical, "%s and %s are really different homes" % [names[i], names[j]])
	var distinct: Dictionary = {}
	for result: Dictionary in results: distinct[str(result.multiset)] = true
	check(distinct.size() == 3, "All three starter layouts are distinct (%d of 3)" % distinct.size())
	# A Fresh Canvas advertises more funds, so the budget choice must be real.
	check(int(results[2].funds) > int(results[0].funds), "The third lot really starts with more funds (§%d vs §%d)" % [int(results[2].funds), int(results[0].funds)])
	# And it must really be less furnished, as its description promises.
	check(int(results[2].items) < int(results[0].items), "A Fresh Canvas is really sparer than Willow Cottage (%d vs %d items)" % [int(results[2].items), int(results[0].items)])

	print("LOT_CHOICE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
