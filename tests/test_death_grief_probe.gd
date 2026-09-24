extends SceneTree
## Death dialog, Extend cancel, OK remove, and grief moodlet duration.
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
		{"name": "Tom Vale", "age_stage": "adult", "life_stage": "adult", "traits": ["Active"]},
		{"name": "Liz Vale", "age_stage": "elder", "life_stage": "adult", "traits": ["Creative"]},
	]
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(1)
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		member.sim.set_speed(1)

	var liz: LifeSim = app.household.member_sim("housemate_1")
	check(liz != null, "Liz exists")
	# Force a pending farewell without auto-killing through the tick.
	liz.needs.hunger = 0.0
	liz.starvation_minutes = 9999.0
	liz.pending_passing_cause = ""
	liz.tick(0.2)
	check(liz.pending_passing_cause == "hunger", "Starvation raises a pending passing (%s)" % liz.pending_passing_cause)
	check(not liz.is_spirit(), "Pending farewell has not killed Liz yet")
	await frames(4)
	check(app.overlay_open, "Death dialog overlay is open")
	app.close_overlay()

	# Extend cancels death and can change age.
	check(liz.cancel_pending_passing("adult"), "Extend / Change Age cancels the pending farewell")
	check(liz.pending_passing_cause.is_empty() and not liz.is_spirit(), "Liz is living after Extend")
	check(str(liz.character.age_stage) == "adult", "Age slider applied adult stage")
	check(float(liz.needs.hunger) >= 50.0, "Extend restores hunger so she is not immediately due again")

	# OK path: confirm once, memorial and mourning, no double-kill.
	liz.needs.hunger = 0.0
	liz.starvation_minutes = 9999.0
	liz.pending_passing_cause = "hunger"
	var before_memorials: int = app.household.memorials.size()
	check(liz.pass_on("hunger"), "OK confirms a single pass_on")
	await frames(3)
	check(liz.is_spirit(), "Liz is a spirit after OK")
	check(app.household.memorials.size() == before_memorials + 1, "Memorial recorded once")
	check(not liz.pass_on("hunger"), "Second pass_on is refused (no double-kill)")

	var tom: LifeSim = app.household.member_sim("player")
	var grief: Dictionary = {}
	for mood: Dictionary in tom.moodlets:
		if str(mood.label) == "In mourning":
			grief = mood; break
	check(not grief.is_empty(), "Tom receives an In mourning moodlet")
	if not grief.is_empty():
		var days: float = float(grief.remaining) / 1440.0
		check(days >= 2.9 and days <= 5.1, "Grief lasts 3–5 in-game days (got %.2f)" % days)

	print("DEATH_GRIEF_PROBE %d/%d" % [checks - failures.size(), checks])
	for failure: String in failures:
		print("FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
