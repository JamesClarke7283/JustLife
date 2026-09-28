extends "res://tests/test_school_day.gd"

func run() -> void:
	for stage: String in ["child", "teen", "adult", "elder"]:
		for initial: float in [35.0, 80.0, 100.0]:
			var school: bool = stage in ["child", "teen"]
			var person: LifeSim = setup(stage, 480.0 if school else 540.0)
			person.needs.energy = initial
			person.autonomy = false
			person.queue_action("school_day" if school else "career_day", "lot_exit")
			person.begin_current_action()
			advance(person, 123.0)
			var restored: LifeSim = setup(stage)
			check(restored.restore_state(snapshot(person)).ok, "Midday energy reserve survives a saved day.")
			advance(person, (420.0 if school else 480.0) - 123.0)
			advance(restored, (420.0 if school else 480.0) - 123.0)
			check(person.away_state.completed and person.needs.energy >= 80.0, "%s completes the day with >=80 energy from %.0f." % [stage, initial])
			check(is_equal_approx(person.needs.energy, restored.needs.energy), "Resumed day has the same remaining energy.")
			advance(person, 45.0)
			check(person.needs.energy >= 80.0, "The return journey preserves evening energy.")
			person.complete_away_return()
			advance(person, 10.0)
			check(person.needs.energy < 80.0, "Normal energy decay resumes at home.")
	var night: LifeSim = setup("adult", 1020.0, 5)
	night.autonomy = false
	night.choose_career("police"); night.choose_police_shift("night")
	night.needs.energy = 50.0
	night.queue_action("career_day", "lot_exit"); night.begin_current_action()
	advance(night, 960.0)
	check(night.away_state.completed and night.needs.energy >= 80.0, "Overnight police duty also leaves >=80 energy.")
	for node: Node in owned: node.free()
	print("DAY_ENERGY_RESERVE %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
