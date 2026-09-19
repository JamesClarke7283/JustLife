extends SceneTree
## The education package: a Lifelet studies for a Bachelors, a Masters and a PHD
## at the university, a degree raises what the jobs that ask for one pay, and a
## PHD earns the title Dr.
##
## Every assertion drives the real university panel, the real degree award and
## the real workplace, and reads what a player would see: the qualification held,
## the pay that changed, and the name on the profile.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_education_degrees.gd

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


func _texts_contain(root: Node, needle: String) -> bool:
	for node: Node in root.find_children("*", "Label", true, false):
		if str((node as Label).text).contains(needle):
			return true
	return false


func _run() -> void:
	# ---------------------------------------------------------------- the ladder
	check(LifeCareers.DEGREES == ["none", "bachelors", "masters", "phd"], "The qualification ladder is Bachelors, Masters, PHD.")
	for degree: String in ["bachelors", "masters", "phd"]:
		var step: Dictionary = LifeCareers.degree_step(degree)
		check(not step.is_empty(), "The %s can be studied." % degree)
		check(int(step.fee) > 0 and int(step.days) > 0, "The %s really costs money and time." % degree)
		check(LifeCareers.honorific(degree).is_empty() == false, "The %s earns a name to be addressed by." % degree)
	# A higher degree needs the one below it.
	check(LifeCareers.degree_step("masters").needs == "bachelors", "A Masters needs a Bachelors first.")
	check(LifeCareers.degree_step("phd").needs == "masters", "A PHD needs a Masters first.")
	check(LifeCareers.degree_at_least("phd", "bachelors") and not LifeCareers.degree_at_least("bachelors", "phd"),
		"The qualification ladder really ranks.")
	# Only the final one is a doctor.
	check(LifeCareers.honorific("phd") == "Dr", "A PHD is addressed as Dr.")
	check(LifeCareers.honorific("bachelors") != "Dr" and LifeCareers.honorific("masters") != "Dr",
		"A Bachelors and a Masters are not doctors yet.")
	# A degree is worth more to a job that asks for one, and nothing to one that
	# does not.
	check(LifeCareers.needs_degree("doctor") and not LifeCareers.needs_degree("waiter"),
		"Only the jobs that ask for a degree treat one as worth paying more for.")
	check(LifeCareers.pay("doctor", 4, "none") < LifeCareers.pay("doctor", 4, "bachelors"), "A Bachelors raises a doctor's pay.")
	check(LifeCareers.pay("doctor", 4, "bachelors") < LifeCareers.pay("doctor", 4, "masters"), "A Masters raises it again.")
	check(LifeCareers.pay("doctor", 4, "phd") >= LifeCareers.pay("doctor", 4, "masters"), "A PHD is worth at least as much as a Masters.")
	# The degree premium tapers as the trade's own rate catches up, because the
	# brief fixes ℒ1,000 as the highest pay in the game: a PHD is better paid
	# every rung of the way up, and at the top the ladder's own rate is the cap.
	check(LifeCareers.pay("doctor", 1, "phd") > LifeCareers.pay("doctor", 1, "none"), "A PHD is paid more at the first rung.")
	check(LifeCareers.pay("doctor", 10, "phd") > LifeCareers.pay("doctor", 1, "phd"), "The ladder still rises with a degree in hand.")
	check(LifeCareers.pay("waiter", 4, "phd") == LifeCareers.pay("waiter", 4, "none"), "A PHD is worth nothing to waiting tables.")
	# The brief's own ceiling still holds with a PHD in hand.
	var best_with_phd: int = 0
	for job_id: String in LifeCareers.JOBS:
		if LifeCareers.is_criminal(job_id): continue
		best_with_phd = maxi(best_with_phd, LifeCareers.pay(job_id, LifeCareers.MAX_LEVEL, "phd"))
	check(best_with_phd <= 1000, "Even a PHD never pays past the brief's ℒ1000 ceiling (%d)." % best_with_phd)

	# ------------------------------------------------------------- the live game
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(8)
	app.set_sound(false)
	app.new_game()
	await frames(4)
	app.household_profiles[0]["age_stage"] = "adult"
	await frames(4)
	app.start_household()
	await frames(16)
	app.household.set_speed(0)

	check(app.sim._degree() == "none" and app.sim.honorific() != "Dr", "A new Lifelet holds no degree and is not a doctor.")
	# Enrolment is refused while a lower qualification is missing.
	check(not LifeCareers.degree_error("phd", "adult", "none", 1 << 30).is_empty(), "A PHD is refused without a Masters.")
	check(not LifeCareers.degree_error("masters", "adult", "none", 1 << 30).is_empty(), "A Masters is refused without a Bachelors.")
	check(LifeCareers.degree_error("bachelors", "adult", "none", 1 << 30).is_empty(), "A Bachelors is open to anybody with the fee.")

	# ------------------------------------------------ the university's own desk
	app.current_venue = "university"
	app.show_university_panel()
	await frames(4)
	check(app.overlay_open, "The university opens its own desk.")
	check(app.overlay.find_child("Degree_bachelors", true, false) != null, "The desk offers a Bachelors.")
	app.close_overlay()
	await frames(2)

	# Walk the whole ladder as a real Lifelet would, paying each fee.
	app.household.set_funds(200000)
	app.sim.funds = 200000
	for degree: String in ["bachelors", "masters", "phd"]:
		var step: Dictionary = LifeCareers.degree_step(degree)
		var funds_before: int = app.sim.funds
		app._take_degree(degree)
		await frames(3)
		check(app.sim._degree() == degree, "The Lifelet really holds a %s (%s)." % [degree, app.sim._degree()])
		check(app.sim.funds == funds_before - int(step.fee), "The %s cost exactly its fee (ℒ%d)." % [degree, int(step.fee)])
	app.close_overlay()
	await frames(2)
	check(app.sim.honorific() == "Dr", "A Lifelet with a PHD is addressed as Dr (%s)." % app.sim.honorific())

	# The title is really shown on the profile, not merely held.
	app.show_person()
	await frames(4)
	check(_texts_contain(app.overlay, "Dr"), "The profile shows the Dr title.")
	app.close_overlay()
	await frames(2)

	# ------------------------------------- a degree really changes the pay
	app.sim.skills.logic.level = 6
	app.sim.choose_career("doctor")
	await frames(3)
	check(str(app.sim.career.track) == "doctor", "A doctor's job can be taken with a PHD in hand.")
	var with_phd: int = app.sim.career_pay()
	# Drop the degree and the same job at the same rung pays less.
	app.sim.degree = "none"
	app.sim.career["salary"] = app.sim.career_pay()
	var without: int = app.sim.career_pay()
	check(without < with_phd, "The same job at the same rung pays less without the degree (ℒ%d -> ℒ%d)." % [with_phd, without])
	check(without == LifeCareers.base_pay("doctor", int(app.sim.career.get("level", 1))), "Without a degree the job pays its own ladder rate.")
	app.sim.degree = "phd"
	app.sim.career["salary"] = app.sim.career_pay()
	check(app.sim.career_pay() == with_phd, "Awarding the degree back restores the higher pay.")

	# ------------------------------------------------------------- saving
	check(app.save_game("degree_probe", "Degree probe"), "The household saves with a PHD.")
	var slot: Dictionary = LifeSaveLibrary.read_slot("degree_probe")
	var members: Array = (slot.get("data", {}) as Dictionary).get("members", [])
	var saved: Dictionary = (members[0] as Dictionary).get("state", {})
	check(str(saved.get("degree", "")) == "phd", "The qualification rides the save (%s)." % str(saved.get("degree", "")))
	var fresh: Object = load("res://scripts/life_sim.gd").new()
	root.add_child(fresh)
	fresh.new_household({"name": "Graduate", "age_stage": "adult", "traits": []})
	check(bool(fresh.restore_state(saved).ok), "A save with a PHD is valid.")
	check(fresh.honorific() == "Dr", "A loaded doctor is still a doctor.")
	var damaged: Dictionary = fresh.get_state()
	damaged.degree = "castle"
	check(not bool(fresh.restore_state(damaged).ok), "An unknown qualification is refused.")
	fresh.free()
	LifeSaveLibrary.delete_slot("degree_probe")

	print("EDUCATION_RESULT ", JSON.stringify({"checks": checks, "failures": failures,
		"degree": app.sim._degree(), "honorific": app.sim.honorific()}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
