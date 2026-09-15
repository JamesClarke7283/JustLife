extends SceneTree
## Prove the neighbourhood is playable, not menu text: travel to a public venue
## really rebuilds the world, and a resident's own home really has its own
## furniture and its own rooms.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_venue_travel.gd

const Building = preload("res://scripts/building_state.gd")
const Neighborhood = preload("res://scripts/neighborhood.gd")
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://venue_travel"))
	root.get_texture().get_image().save_png("user://venue_travel/%s.png" % label)
	print("VENUE_SHOT ", ProjectSettings.globalize_path("user://venue_travel/%s.png" % label))

## Advance the trip the way the game's own frame loop does, until it settles.
func finish_trip() -> bool:
	for frame: int in 4000:
		if app.mode != "travel": return true
		app._process(0.05)
		if frame % 10 == 0: await process_frame
	return app.mode != "travel"

func kind_counts() -> Dictionary:
	var counts: Dictionary = {}
	for item: Dictionary in app.world.items:
		var kind: String = str(item.get("kind", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(14)
	app.household.set_speed(0)
	check(app.current_venue == "home", "The household starts at home")
	var home_counts: Dictionary = kind_counts()
	var home_items: int = app.world.items.size()
	check(home_items > 10, "The starter home is really furnished (%d items)" % home_items)

	# --- Travel to a public venue --------------------------------------------
	app.show_neighborhood("library")
	await frames(4)
	check(app.overlay_open, "Explore opens a venue chooser")
	app.travel_to("library")
	await frames(4)
	check(app.mode == "travel", "Choosing Travel really begins a journey")
	var settled: bool = await finish_trip()
	check(settled, "The journey finishes")
	await frames(8)
	check(app.current_venue == "library", "The household arrived at The Reading Room (at %s)" % app.current_venue)
	check(app.mode == "live", "Arriving returns to Live mode")
	var venue_counts: Dictionary = kind_counts()
	print("home kinds=%s" % str(home_counts))
	print("library kinds=%s" % str(venue_counts))
	check(not venue_counts.is_empty(), "The venue is furnished with its own items (%d)" % app.world.items.size())
	check(venue_counts != home_counts, "The venue's furniture differs from the home's")
	check(app.world.items.size() != home_items or venue_counts != home_counts, "The world really rebuilt for the venue")
	var member_count: int = 0
	for member: Dictionary in app.household.members:
		if app.world.actors.has(str(member.id)): member_count += 1
	check(member_count == app.household.members.size(), "Every household member arrived (%d/%d)" % [member_count, app.household.members.size()])
	await shot("01_library_venue")

	# --- Return home, then visit a resident's own house ----------------------
	app.travel_to("home")
	await frames(4)
	await finish_trip()
	await frames(8)
	check(app.current_venue == "home", "The household returned home")
	check(app.world.items.size() == home_items, "The home's own furniture was restored (%d vs %d)" % [app.world.items.size(), home_items])

	# A resident's home needs friendship to visit, so grant it through the
	# simulation's own relationship record, as building a friendship would.
	var resident: String = "maya"
	for id: String in app.sim.relationships:
		if id == resident:
			app.sim.relationships[id]["friendship"] = 40
	check(app.residents.can_visit(resident), "Maya's home is visitable at 40 friendship")
	app.travel_to("maya_home")
	await frames(4)
	await finish_trip()
	await frames(8)
	check(app.current_venue == "maya_home", "The household arrived at Maya's cottage (at %s)" % app.current_venue)
	var maya_counts: Dictionary = kind_counts()
	print("maya kinds=%s" % str(maya_counts))
	check(not maya_counts.is_empty(), "Maya's home has its own furniture (%d items)" % app.world.items.size())
	check(maya_counts != home_counts and maya_counts != venue_counts, "Maya's home differs from both the starter house and the library")
	await shot("02_maya_home")

	print("VENUE_TRAVEL_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
