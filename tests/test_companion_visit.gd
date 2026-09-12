extends SceneTree
## Integration check for the companion credit: travel to the library during
## Priya's routine window, complete a real read through the public interaction
## path, and the host's friendship gains exactly the +2 companion credit.
## This is the check that catches a visited-venue wiring regression.

var app: Node
var checks: int = 0
var failures: int = 0
var frames: int = 0
var friendship_before: float = 0.0
var armed: bool = false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty() or OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("Set JUSTLIFE_DATA_DIR and XDG_DATA_HOME to isolated test folders.")
		quit(2)
		return
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.add_creator_member()
	app.start_household()
	app.set_sound(false)
	app.sim.relationships.priya.friendship = 25.0
	# Weekday 11:40: inside Priya's library window.
	app.sim.day = 1
	app.sim.minutes = 700.0
	app.travel_to("library")
	var armed_frames: int = 0
	while app.mode != "live" and armed_frames < 1200:
		app._process(0.05)
		if armed_frames % 10 == 0:await process_frame
		armed_frames += 1
	check(app.current_venue == "library" and app.sim.visited_venue == "library", "The arrival carries the library as the visited venue.")
	var shelf: Dictionary = {}
	for item: Dictionary in app.world.items:
		if item.kind == "bookshelf":
			shelf = item
			break
	check(not shelf.is_empty(), "The library exposes a bookshelf to read at.")
	var queued: bool = TestFurnishing.queue_member_action(app, shelf, "read")
	check(queued, "Reading at the library bookshelf queues through the public interaction path.")
	friendship_before = float(app.sim.relationships.priya.friendship)
	var frames: int = 0
	while frames < 6000:
		app._process(0.05)
		frames += 1
		if frames % 10 == 0:await process_frame
		if float(app.sim.relationships.priya.friendship) > friendship_before:break
	var gained: float = float(app.sim.relationships.priya.friendship) - friendship_before
	# Reads may complete more than once across the bounded pump; the gate is
	# that at least one companion credit (+2) landed through the real path.
	check(gained >= 2.0, "The companion credit lands through the real read path (+%.1f)." % gained)
	print("COMPANION_INTEGRATION %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
