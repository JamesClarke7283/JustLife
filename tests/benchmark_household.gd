extends SceneTree
## Run only in an isolated project without editor/MCP autoloads.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var home: LifeHousehold = LifeHousehold.new()
	root.add_child(home)
	home.new_household([
		{"age_stage":"elder"}, {"age_stage":"adult"}, {"age_stage":"adult"},
		{"age_stage":"teen"}, {"age_stage":"child"}, {"age_stage":"young_adult"},
		{"age_stage":"elder"}, {"age_stage":"child"}])
	var result: Dictionary = home.configure_family([
		{"a":"player", "b":"housemate_1", "role":"parent"},
		{"a":"player", "b":"housemate_2", "role":"parent"},
		{"a":"housemate_1", "b":"housemate_3", "role":"parent"},
		{"a":"housemate_2", "b":"housemate_4", "role":"parent"},
		{"a":"housemate_5", "b":"housemate_3", "role":"parent"},
		{"a":"housemate_1", "b":"housemate_7", "role":"parent"}])
	if not result.ok:
		push_error(str(result))
		quit(1)
		return
	for member: Dictionary in home.members:
		member.sim.autonomy = false
	for index: int in range(50):
		home._sync_social_context()
	for measurement: String in ["sync", "tick_paused", "tick_live"]:
		var times: Array = []
		home.set_speed(0 if measurement == "tick_paused" else 1)
		for repetition: int in range(3):
			var started: int = Time.get_ticks_usec()
			for index: int in range(1000):
				if measurement == "sync":
					home._sync_social_context()
				else:
					home.tick(1.0 / 60.0)
			times.append(float(Time.get_ticks_usec() - started) / 1000.0)
		print(measurement, " mean microseconds per call (3x1000):", times)
	home.queue_free()
	await process_frame
	quit()
