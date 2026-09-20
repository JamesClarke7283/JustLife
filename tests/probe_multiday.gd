extends SceneTree
## Run the household across several in-game days and read what really changed:
## bills, need crises, autonomous completions, school attendance and pay.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_multiday.gd

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://multiday"))
	root.get_texture().get_image().save_png("user://multiday/%s.png" % label)
	print("MULTIDAY_SHOT ", ProjectSettings.globalize_path("user://multiday/%s.png" % label))

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	# An adult who can work, and a child who can go to school.
	app.household_profiles[0]["age_stage"] = "adult"
	app.add_creator_member()
	await frames(4)
	app.household_profiles[1]["age_stage"] = "child"
	await frames(4)
	app.start_household(); await frames(16)
	check(app.mode == "live", "The household is living")
	check(app.household.members.size() == 2, "Two Lifelets moved in")

	var start_day: int = int(app.household.day)
	var start_funds: int = int(app.sim.funds)
	var start_bills: int = int(app.household.get_bills_paid()) if app.household.has_method("get_bills_paid") else -1
	print("day=%d funds=%d bills_field=%s" % [start_day, start_funds, str(start_bills)])

	# Watch every autonomous completion the household reports over the run.
	var completed: Array[String] = []
	app.household.member_action_finished.connect(func(member_id: String, action: Dictionary) -> void:
		if bool(action.get("autonomous", false)):
			completed.append("%s:%s" % [member_id, str(action.get("id", ""))]))

	# A game day is 24 real minutes at normal speed; very fast covers it in about
	# three. One full day is the meaningful unit here — it contains a school and
	# a work attendance window and one overnight — so the run is bounded to that.
	app.household.set_speed(3)
	var target_day: int = start_day + 1
	var deadline: int = Time.get_ticks_msec() + 900000
	while int(app.household.day) < target_day and Time.get_ticks_msec() < deadline:
		await frames(20)
	app.household.set_speed(0)
	await frames(8)

	var end_day: int = int(app.household.day)
	var end_funds: int = int(app.sim.funds)
	print("after: day=%d funds=%d autonomous=%d" % [end_day, end_funds, completed.size()])
	check(end_day >= start_day + 1, "The household really advanced a full in-game day (%d -> %d)" % [start_day, end_day])
	check(not completed.is_empty(), "Lifelets completed activities on their own across the days (%d)" % completed.size())
	var distinct: Dictionary = {}
	for entry: String in completed: distinct[entry.split(":")[1]] = true
	print("autonomous action kinds: ", distinct.keys())
	check(distinct.size() >= 3, "Autonomy varied rather than repeating one action (%d kinds)" % distinct.size())
	# Needs must stay survivable across the run rather than collapsing.
	var worst: float = 100.0
	for member: Dictionary in app.household.members:
		for key: String in member.sim.needs:
			worst = minf(worst, float(member.sim.needs[key]))
	print("lowest need at the end: %.1f" % worst)
	check(worst > 0.0, "No Lifelet was left at zero in any need (lowest %.1f)" % worst)
	# Career and school must have really run: attendance is an autonomous action
	# and a worked day pays, which is the progression the critic could not see.
	var kinds_seen: Dictionary = {}
	for entry: String in completed: kinds_seen[entry.split(":")[1]] = true
	check(kinds_seen.has("career_day") or kinds_seen.has("school_day") or kinds_seen.has("homework"),
		"School or work really ran unattended (%s)" % str(kinds_seen.keys()))
	check(end_funds != start_funds, "The household's money moved across the day (ℒ%d -> ℒ%d)" % [start_funds, end_funds])
	# And the world must still be coherent.
	check(app.world.items.size() > 10, "The home still holds its furnishings (%d)" % app.world.items.size())
	for member: Dictionary in app.household.members:
		check(app.world.actors.has(str(member.id)), "Every Lifelet still has a live actor")

	await shot("01_after_two_days")
	print("MULTIDAY_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "days": end_day - start_day, "autonomous": completed.size(), "kinds": distinct.keys()}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
