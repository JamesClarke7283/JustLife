extends SceneTree
## The prison package: being caught really takes a Lifelet to Blackmoor, their
## family can travel there to visit them, and the sentence ends on the household's
## own clock.
##
## Every assertion drives the real household clock, the real prison venue and the
## real save, and reads what a player would see: where the Lifelet is, what the
## visit did, and whether they came home.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_prison.gd

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


func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	app.household_profiles[0]["age_stage"] = "adult"
	await frames(2)
	app.add_creator_member()
	app.household_profiles[1]["age_stage"] = "adult"
	app.household_profiles[1]["name"] = "Robin Vale"
	await frames(4)
	app.start_household()
	await frames(16)
	app.household.set_speed(0)

	var sim: LifeSim = app.sim
	check(not sim.is_imprisoned() and not sim.is_at_prison(), "A new Lifelet is neither serving nor inside.")

	# ------------------------------------------------------------ being caught
	var funds_before: int = sim.funds
	var sentence: Dictionary = sim.serve_sentence(500, 4)
	check(bool(sentence.ok), "A sentence can be served.")
	check(sim.is_imprisoned(), "The Lifelet is now serving a sentence.")
	check(sim.is_at_prison(), "A caught Lifelet is really taken to the prison, not left at home.")
	check(sim.is_away(), "Being inside is a real absence from the household's lot.")
	check(str(sim.away_state.get("activity", "")) == "prison", "The absence is the prison's own (%s)." % str(sim.away_state.get("activity", "")))
	check(int(sim.criminal_record.prison_until_day) == sim.day + 4, "The sentence has a real release day.")
	check(sim.funds == funds_before - 500, "The fine was really paid from the purse.")
	check(int(sim.criminal_record.caught_count) == 1, "The arrest is recorded.")
	# The HUD says where they are.
	check(app._away_status(sim.get_away_state()).contains("Inside"), "The HUD says the Lifelet is inside (%s)." % app._away_status(sim.get_away_state()))

	# A Lifelet inside cannot work or study.
	check(not sim.career_entry_error("waiter").is_empty(), "A Lifelet inside cannot take a job.")
	check(str(sim.career_entry_error("waiter")).contains("sentence"), "The refusal explains the sentence (%s)." % sim.career_entry_error("waiter"))
	# Being caught again while inside is impossible.
	check(not bool(sim.criminal_day_check().get("ok", true)), "A Lifelet already inside is not caught again.")

	# Nobody can visit who has family inside yet — only this household's own
	# family member is there, so the visit works.
	app.current_venue = "prison"
	app.show_venue_services("prison")
	await frames(4)
	check(app.overlay_open, "The prison's visiting desk opens.")
	check(app.overlay.find_child("Service_visit_family", true, false) != null, "The desk offers a family visit.")
	check(app.overlay.find_child("Service_release_day", true, false) != null, "The desk offers meeting them at the gate.")
	app.close_overlay()
	await frames(2)

	# The visit itself: a housemate's social need is met and the prisoner notices.
	var visitor: LifeSim = app.household.member_sim(str(app.household.members[1].id))
	# The visit is taken by whoever the player is controlling, so the controlled
	# Lifelet is the one whose social need it meets.
	app.select_household_member(1)
	await frames(3)
	app.sim.needs.social = 20.0
	var social_before: float = float(app.sim.needs.social)
	app._visit_incarcerated_family("prison", "visit_family")
	await frames(2)
	check(float(app.sim.needs.social) > social_before, "A family visit really meets the visitor's social need (%.0f -> %.0f)." % [social_before, float(app.sim.needs.social)])
	var visited: bool = false
	for memory: Dictionary in sim.memories:
		if str(memory.get("label", "")) == "A family visit": visited = true
	check(visited, "The family member inside remembers the visit.")
	check(sim.moodlets.any(func(m: Dictionary) -> bool: return str(m.get("label", "")) == "A visit from family"),
		"A visit leaves the family member inside feeling better.")

	# ---------------------------------------------- the sentence really ends
	var release_day: int = int(sim.criminal_record.prison_until_day)
	for i: int in 20000:
		if not sim.is_at_prison(): break
		app.household.set_speed(1)
		app.household.tick(4.0)
	check(sim.day >= release_day, "The household clock really reached the release day (day %d)." % sim.day)
	check(not sim.is_at_prison(), "The Lifelet was released from the prison.")
	check(not sim.is_away(), "A released Lifelet is home again rather than still absent.")
	app.household.set_speed(0)
	# The record of the arrest survives, as a criminal record should.
	check(int(sim.criminal_record.caught_count) == 1, "The record of the arrest is kept after release.")
	check(app._away_status(sim.get_away_state()).is_empty() or not app._away_status(sim.get_away_state()).contains("Inside"),
		"A released Lifelet is no longer shown as inside.")

	# ------------------------------------------------- being caught while away
	# A Lifelet already away when caught serves their sentence from home, because
	# one body cannot hold two absences.
	var away_sim: LifeSim = app.sim
	away_sim.away_state = {"version": 1, "activity": "career", "phase": "away", "departure_day": away_sim.day, "departure_minutes": 600.0, "return_day": away_sim.day, "return_minutes": 1020.0}
	var from_home: Dictionary = away_sim.serve_sentence(100, 3)
	check(bool(from_home.ok) and not bool(from_home.get("at_prison", true)),
		"A Lifelet caught while already away serves from home rather than holding two absences.")
	check(away_sim.is_imprisoned(), "They are still serving their sentence.")
	check(str(away_sim.away_state.get("activity", "")) == "career", "Their original absence is left intact.")
	away_sim.criminal_record["prison_until_day"] = away_sim.day - 1
	away_sim.criminal_record["serving_at_home"] = false
	away_sim.away_state = {}

	# ------------------------------------------------------------- saving
	# A saved sentence is validated, and a released Lifelet is simply at home.
	check(LifeCareers.criminal_error(sim.criminal_record).is_empty(), "A served sentence is a valid record.")
	check(not LifeCareers.criminal_error({"version": 1, "serving_at_home": "yes"}).is_empty(), "An invalid sentence location is refused.")

	print("PRISON_RESULT ", JSON.stringify({"checks": checks, "failures": failures,
		"caught": int(sim.criminal_record.caught_count)}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
