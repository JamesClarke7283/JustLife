extends SceneTree
## The progression package: the criminal and technical career tracks with their
## entry gate, home insurance against the nightly burglar, and the book/computer
## skill ceiling.
##
## Every assertion drives a public path — the ordinary action queue, the
## household's own save/restore, the real phone panel — and reads what the player
## would actually observe, never that a function merely exists.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_progression.gd

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


func frames(n: int = 1) -> void:
	for i: int in n:
		await process_frame


## A standalone adult with a real exit, no autonomy and full needs: the smallest
## thing that can actually work a paid shift through the ordinary queue.
func worker(stage: String = "young_adult") -> LifeSim:
	var sim: LifeSim = LifeSim.new()
	root.add_child(sim)
	sim.new_household({"name": "Probe Worker", "age_stage": stage, "traits": []})
	sim.autonomy = false
	sim.household_bills_enabled = false
	sim.wants.clear()
	sim.day = 1
	sim.career.schedule = LifeCareerSchedule.fresh(1)
	sim.minutes = 540.0
	sim.register_targets([{"id": "lot_exit", "kind": "lot_exit", "position": Vector3(0, .16, 8.5)}])
	for need: String in LifeSim.NEED_NAMES:
		sim.needs[need] = 100.0
	return sim


## Advance the simulation in whole game minutes, exactly as the world does.
func advance(sim: LifeSim, amount: float) -> void:
	while amount > .000001:
		var step: float = minf(60.0, amount)
		sim.tick(step / LifeSim.GAME_MINUTES_PER_SECOND)
		amount -= step


func _run() -> void:
	# Each section is awaited in turn: the phone-driven insurance checks suspend
	# on real frames, and an un-awaited coroutine would be dropped at quit.
	await _career_tracks()
	await _criminal_shift()
	await _technical_entry()
	_legacy_progression()
	await _insurance_and_robbery()
	await _books_and_computer()

	print("PROGRESSION %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## The original suite's standalone-simulation coverage, preserved verbatim: mood
## and memory persistence, career switching and promotion, wellness pay, and a
## snapshot that survives a real round trip. It belongs here rather than in a
## second progression file, so there is still one progression gate.
func _legacy_progression() -> void:
	var sim: LifeSim = LifeSim.new()
	root.add_child(sim)
	sim.autonomy = false
	for key: String in sim.needs:
		sim.needs[key] = 90
	sim.add_moodlet("A new canvas", "Inspired", "Something creative.", 20, 3)
	check(sim.get_mood().label == "Inspired", "An activity can leave a persistent emotion.")
	sim.set_speed(0)
	sim.tick(10)
	check(int(sim.moodlets[0].remaining) == 20, "Pause preserves emotion duration.")
	sim.set_speed(1)
	sim.tick(24.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	check(sim.moodlets.is_empty(), "Timed emotions expire with the simulation clock.")
	check(sim.choose_career("fitness"), "A Lifelet can choose a wellness career.")
	check(str(sim.career.title) == "Gym assistant" and int(sim.career.salary) == LifeCareers.base_pay("fitness", 1), "The wellness track has actual titles and pay.")
	check(str(sim.promotion_requirement().skill) == "fitness", "The wellness track promotes on the Fitness skill.")
	sim.skills.fitness.level = 2
	sim.career.performance = 100
	sim._check_promotion()
	# The kitchen asks for Cooking 2, so the door stays shut until it is earned.
	check(sim.career_entry_error("chef").contains("Cooking"), "The kitchen states the skill it wants.")
	sim.skills.cooking.level = 2
	check(sim.choose_career("chef"), "A Lifelet can choose a culinary career.")
	check(str(sim.career.title) == "Kitchen assistant" and int(sim.career.salary) == LifeCareers.base_pay("chef", 1), "Career changes have actual titles and pay.")
	sim.career.performance = 100
	sim._check_promotion()
	check(str(sim.career.title) == "Prep cook" and int(sim.career.salary) == LifeCareers.base_pay("chef", 2), "Promotions follow the selected career.")
	check(sim.memories.size() == 4, "Career milestones become personal memories.")
	sim.queue_action("job", "desk")
	check(not sim.choose_career("technology"), "Queued shifts cannot be switched to a different career pay scale.")
	sim.cancel_action()
	# The office asks for Logic 3 before it will take anybody on.
	check(not sim.career_entry_error("technology").is_empty(), "The office states the skill it wants.")
	sim.skills.logic.level = 3
	check(sim.choose_career("technology") and str(sim.career.title) == "Support specialist", "Changing careers after cancel works.")
	sim.add_moodlet("Stress", "Tense", "A hard day.", 100, 4)
	sim.needs.hunger = 5
	check(sim.get_mood().label == "Hungry", "Critical needs still take precedence over moodlets.")
	var state: Dictionary = sim.get_state()
	var copy: LifeSim = LifeSim.new()
	root.add_child(copy)
	check(bool(copy.restore_state(state).ok), "A progression snapshot is valid.")
	check(copy.moodlets.size() == sim.moodlets.size() and copy.memories.size() == sim.memories.size(), "Emotions and memories persist.")
	var damaged: Dictionary = state.duplicate(true)
	damaged.moodlets[0].remaining = "bad"
	check(not bool(copy.restore_state(damaged).ok), "Malformed timed emotions are rejected.")
	sim.free()
	copy.free()


# ---------------------------------------------------------------- careers

func _career_tracks() -> void:
	check(LifeCareers.has("criminal"), "The job list offers a Criminal track.")
	var criminal: Dictionary = LifeCareers.job("criminal")
	check(str(criminal.label) == "Criminal", "The criminal track is labelled Criminal.")
	check(LifeCareers.base_pay("criminal", 1) == 1000, "The criminal track pays ℒ1000 a day.")
	check(LifeCareers.is_criminal("criminal") and not LifeCareers.is_criminal("waiter"), "Only the criminal track carries the risk.")
	check(int(criminal.get("entry", {}).get("cost", 0)) == 0, "The criminal track charges no entry fee.")
	check(int(criminal.get("entry", {}).get("level", 0)) == 0, "The criminal track demands no skill level.")
	check(LifeCareers.unskilled().size() >= 1, "There is always a way into work for a Lifelet with no skills.")

	check(LifeCareers.has("technical"), "The job list offers a Technical track.")
	var technical: Dictionary = LifeCareers.job("technical")
	check(int(technical.get("entry", {}).get("cost", 0)) == 900, "The technical track costs ℒ900 to enter.")
	check(str(technical.get("entry", {}).get("skill", "")) == "logic" and int(technical.get("entry", {}).get("level", 0)) == 8,
		"The technical track requires Logic level 8 to enter.")
	check(LifeCareers.base_pay("technical", LifeCareers.MAX_LEVEL) > 0, "The technical track pays a real salary once joined.")
	check(str(LifeCareers.title_at("technical", 4)) == "Software engineer",
		"Software engineer is a rung of the technical ladder, not a separate job.")
	check(str(LifeCareers.title_at("technical", LifeCareers.MAX_LEVEL)) == "CEO of a technology company",
		"The top of the technical ladder is the head of a technology company.")

	# The brief's own numbers: twenty jobs, and 6% falling to 1.5% detection.
	check(LifeCareers.JOBS.size() >= 20, "At least twenty lines of work are offered (%d)." % LifeCareers.JOBS.size())
	check(is_equal_approx(LifeCareers.detection_chance("criminal", 1), 0.06),
		"A first-day criminal is caught 6%% of the time (%.3f)." % LifeCareers.detection_chance("criminal", 1))
	check(is_equal_approx(LifeCareers.detection_chance("criminal", LifeCareers.MAX_LEVEL), 0.015),
		"A practised criminal is caught 1.5%% of the time (%.3f)." % LifeCareers.detection_chance("criminal", LifeCareers.MAX_LEVEL))
	var practised: float = LifeCareers.detection_chance("criminal", LifeCareers.MAX_LEVEL)
	var raw: float = LifeCareers.detection_chance("criminal", 1)
	for level: int in range(2, LifeCareers.MAX_LEVEL):
		var chance: float = LifeCareers.detection_chance("criminal", level)
		check(chance < raw and chance > practised, "Rank %d is safer than the rank below and riskier than the top." % level)
	# The best honest ladder and the criminal one are the brief's twin ceilings.
	var best_honest: int = 0
	for job_id: String in LifeCareers.JOBS:
		if LifeCareers.is_criminal(job_id): continue
		best_honest = maxi(best_honest, LifeCareers.base_pay(job_id, LifeCareers.MAX_LEVEL))
	check(best_honest == 1000, "The best-paid honest job tops out at the brief's ℒ1000 a day (%d)." % best_honest)
	for job_id: String in LifeCareers.JOBS:
		check(LifeCareers.titles(job_id).size() == LifeCareers.MAX_LEVEL,
			"%s has a title for each of its ten levels (%d)." % [job_id, LifeCareers.titles(job_id).size()])
		var top: int = LifeCareers.base_pay(job_id, LifeCareers.MAX_LEVEL)
		check(top <= 1000, "%s never pays past the ℒ1000 ceiling (ℒ%d)." % [job_id, top])


## A criminal shift pays its promised ℒ1000 through the ordinary queue, and the
## door is open to anyone — no skill, no fee.
func _criminal_shift() -> void:
	var sim: LifeSim = worker()
	sim.funds = 2500
	check(sim.career_entry_error("criminal").is_empty(), "A fresh Lifelet may enter the criminal track with no skill and no fee.")
	check(sim.choose_career("criminal") and str(sim.career.track) == "criminal", "The criminal track can actually be chosen.")
	check(int(sim.career.salary) == 1000 and str(sim.career.title) == "Lookout", "Joining the criminal track sets its first rank and pay.")
	# The criminal pays no degree premium, whatever the Lifelet holds.
	sim.award_degree("phd")
	check(sim.career_pay() == 1000, "A degree is worth nothing to the criminal track (ℒ%d)." % sim.career_pay())
	# Work one honest shift through the real departure mechanics.
	check(sim.queue_action("career_day", "lot_exit", Vector3(0, .16, 8.5)), "A weekday shift queues against the neighborhood exit.")
	sim.begin_current_action()
	check(sim.is_away() and str(sim.away_state.activity) == "career", "Reaching the exit starts a real work absence.")
	check(sim.away_state.career_track == "criminal" and int(sim.away_state.salary) == 1000, "The absence carries the criminal track and its ℒ1000 salary.")
	var before: int = sim.funds
	advance(sim, 480.0)
	check(sim.funds - before == 1000, "A worked criminal shift credits exactly ℒ1000 (was %d, now %d)." % [before, sim.funds])
	check(int(sim.career.worked_day) == 1 and str(sim.away_state.phase) == "returning", "The shift is paid once and marks the day complete.")
	check(int(sim.skills.charisma.xp) > 0.0 or int(sim.skills.charisma.level) > 1, "Criminal work grows the track's own Charisma skill.")
	sim.free()

	# The same ℒ1000 reaches the shared household purse, not just one Lifelet.
	var home: LifeHousehold = LifeHousehold.new()
	root.add_child(home)
	home.new_household([{"name": "Rook Vance", "age_stage": "young_adult", "traits": []}])
	var member: LifeSim = home.member_sim("player")
	member.autonomy = false
	member.wants.clear()
	member.household_bills_enabled = false
	member.day = 1
	member.minutes = 540.0
	member.career.schedule = LifeCareerSchedule.fresh(1)
	member.register_targets([{"id": "lot_exit", "kind": "lot_exit", "position": Vector3(0, .16, 8.5)}])
	for need: String in LifeSim.NEED_NAMES:
		member.needs[need] = 100.0
	member.choose_career("criminal")
	member.queue_action("career_day", "lot_exit", Vector3(0, .16, 8.5))
	member.begin_current_action()
	var purse: int = home.funds
	while member.is_away() or member.funds == purse:
		home.tick(1.0)
		if member.funds != purse:
			break
	check(home.funds - purse == 1000, "The criminal shift's ℒ1000 lands on the shared household funds (ℒ%d -> ℒ%d)." % [purse, home.funds])
	home.queue_free()


## The technical trade is refused with a reason below Logic 8 and accepted at 8,
## and the ℒ900 course fee is really taken.
func _technical_entry() -> void:
	var sim: LifeSim = worker()
	sim.funds = 2500
	# The trade wants a degree as well as the skill, so the qualification is in
	# hand here and the skill gate is what this section is about.
	sim.degree = "bachelors"
	sim.skills.logic.level = 7
	var low: String = sim.career_entry_error("technical")
	check(not low.is_empty() and low.contains("8") and low.to_lower().contains("logic"),
		"Technical is refused below Logic 8 with a reason naming the level (%s)." % low)
	check(not sim.choose_career("technical") and str(sim.career.track) != "technical", "The refusal really blocks joining.")
	sim.skills.logic.level = 8
	check(sim.career_entry_error("technical").is_empty(), "Technical is available at Logic 8.")
	var fee_before: int = sim.funds
	check(sim.choose_career("technical") and str(sim.career.track) == "technical", "Technical can be joined at Logic 8.")
	check(fee_before - sim.funds == 900, "Joining technical pays the ℒ900 course fee (ℒ%d -> ℒ%d)." % [fee_before, sim.funds])
	# A purse that cannot cover the fee is refused before anything is charged.
	var broke: LifeSim = worker()
	broke.degree = "bachelors"
	broke.skills.logic.level = 8
	broke.funds = 100
	var short_reason: String = broke.career_entry_error("technical")
	check(not short_reason.is_empty() and not broke.choose_career("technical"), "An unaffordable course fee is refused.")
	check(broke.funds == 100, "A refused fee leaves the purse untouched.")
	sim.free()
	broke.free()


# -------------------------------------------------------- robber and cover

func _insurance_and_robbery() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(2)
	app.selected_lot = 0
	app.start_household()
	await frames(1)
	app.set_process(false)
	var home: LifeHousehold = app.household
	var sim: LifeSim = app.sim
	home.set_funds(4000)

	# Buying the policy charges its premium once and the phone reports it.
	check(home.insurance().is_empty(), "A fresh household is uninsured.")
	var bought: Dictionary = home.buy_insurance()
	check(bool(bought.ok), "Home insurance can be bought from the household.")
	check(home.funds == 4000 - int(LifeSim.INSURANCE_POLICIES.home.premium), "The premium is charged exactly once (ℒ%d)." % home.funds)
	var policy: Dictionary = home.insurance()
	check(policy.get("id", "") == "home" and int(policy.premium) == int(LifeSim.INSURANCE_POLICIES.home.premium),
		"The household reports its policy and price.")
	# Buying twice is refused, with a reason, and costs nothing more.
	var funds_before: int = home.funds
	var repeat: Dictionary = home.buy_insurance()
	check(not bool(repeat.ok) and not str(repeat.get("error", "")).is_empty(), "A second policy is refused with a reason.")
	check(home.funds == funds_before, "A refused repeat purchase takes no money.")

	# A robbery takes a real sum; insured, the same loss is paid straight back.
	var insured_before: int = home.funds
	var insured_robbery: Dictionary = home.robbery()
	check(int(insured_robbery.get("stolen", 0)) == LifeSim.ROBBERY_LOSS, "A robbery takes the advertised ℒ%d." % LifeSim.ROBBERY_LOSS)
	check(int(insured_robbery.get("reimbursed", 0)) == LifeSim.ROBBERY_LOSS, "Insurance reimburses the whole loss.")
	check(home.funds == insured_before, "An insured break-in leaves the purse exactly as it was.")

	# Uninsured, the loss is real.
	check(bool(home.cancel_insurance().ok) and home.insurance().is_empty(), "The policy can be cancelled.")
	var exposed_before: int = home.funds
	var bare_robbery: Dictionary = home.robbery()
	check(int(bare_robbery.get("reimbursed", 0)) == 0, "Without cover nothing is paid back.")
	check(home.funds == exposed_before - LifeSim.ROBBERY_LOSS,
		"An uninsured break-in really takes ℒ%d (ℒ%d -> ℒ%d)." % [LifeSim.ROBBERY_LOSS, exposed_before, home.funds])

	# The nightly event fires on its own period from the household's clock, so a
	# player who never calls robbery() is still robbed. Day 3 is a robbery night.
	# The owner (the bill ledger's owner) is the one member who rolls it.
	home.set_funds(4000)
	var owner: LifeSim = home.bill_owner()
	check(owner != null and owner.household_bills_enabled, "The household's first member owns the nightly roll.")
	owner.insurance_policy_id = ""
	owner.autonomy = false
	owner.wants.clear()
	for member: Dictionary in home.members:
		member.sim.insurance_policy_id = ""
		member.sim.autonomy = false
		member.sim.wants.clear()
		for need: String in LifeSim.NEED_NAMES:
			member.sim.needs[need] = 100.0
	home.day = 2
	home.minutes = 1439.0
	var night_before: int = home.funds
	home.tick(3.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	check(home.day == LifeSim.ROBBERY_PERIOD_DAYS, "The household's own clock reached the robbery night (day %d)." % home.day)
	check(home.funds == night_before - LifeSim.ROBBERY_LOSS,
		"A scheduled night really robs the household without anyone asking (ℒ%d -> ℒ%d)." % [night_before, home.funds])
	# A non-scheduled night leaves the purse alone.
	home.day = LifeSim.ROBBERY_PERIOD_DAYS + 1
	home.minutes = 1439.0
	var quiet_before: int = home.funds
	home.tick(3.0 / LifeSim.GAME_MINUTES_PER_SECOND)
	check(home.funds == quiet_before, "A night off the robbery schedule takes nothing.")

	# The policy survives a real save and a fresh household restore.
	home.set_funds(4000)
	home.buy_insurance("home")
	check(app.save_game("Progress Insure Round Trip"), "The insured household saves through the public path.")
	await frames(1)
	var slot: String = app.active_save_id
	home.cancel_insurance()
	check(home.insurance().is_empty(), "Cover is gone before the load.")
	app.load_game(slot)
	await frames(1)
	var restored: Dictionary = app.household.insurance()
	check(restored.get("id", "") == "home", "A fresh load restores the home insurance policy.")

	# A corrupt policy is refused before it can mint free reimbursements.
	var state: Dictionary = app.sim.get_state()
	state["insurance_policy_id"] = "diamond_crust"
	var receiver: LifeSim = LifeSim.new()
	root.add_child(receiver)
	check(not bool(receiver.restore_state(state).ok), "An unknown saved policy is refused.")
	receiver.free()

	# A capped loss can never push the purse negative.
	var poor: LifeSim = LifeSim.new()
	root.add_child(poor)
	poor.new_household({"name": "Pauper", "age_stage": "young_adult", "traits": []})
	poor.funds = 100
	var capped: Dictionary = poor.robbery()
	check(int(capped.get("stolen", 0)) == 100 and poor.funds == 0, "A robbery cannot take more than the purse holds.")
	poor.free()

	# The phone offers the purchase on its own row and opens the cover panel.
	# Start uninsured so the panel is the buying one, not the cancel one.
	app.household.cancel_insurance()
	app.adoption_flow.show_phone()
	await frames(1)
	var row: Button = app.overlay.get_node_or_null("PhoneInsurance") as Button
	check(row != null, "The phone carries a Home insurance row.")
	var back_row: Button = app.overlay.get_node_or_null("PhoneBack") as Button
	if row != null and back_row != null:
		# The whole point of re-spacing: every row, Back included, stays inside the
		# white card (top 143, height 616) rather than spilling off its bottom.
		var lowest: float = maxf(row.position.y + row.size.y, back_row.position.y + back_row.size.y)
		check(lowest <= 143.0 + 616.0, "Every phone row fits inside the panel (lowest edge %.0f of 759)." % lowest)
		check(back_row.position.y + back_row.size.y <= 143.0 + 616.0, "`Back to life` stays on the panel.")
	if row != null:
		row.pressed.emit()
		await frames(1)
		var buy: Button = app.overlay.get_node_or_null("PhoneBuyInsurance") as Button
		check(buy != null, "The insurance panel offers the purchase.")
		if buy != null:
			var phone_before: int = app.household.funds
			buy.pressed.emit()
			await frames(1)
			check(not app.household.insurance().is_empty(), "The phone purchase really insures the home.")
			check(app.household.funds == phone_before - int(LifeSim.INSURANCE_POLICIES.home.premium), "The phone purchase charges the premium once.")
	app.close_overlay()
	app.queue_free()
	await frames(1)


# ---------------------------------------------------------- books and computer

func _books_and_computer() -> void:
	# Every skill the simulation knows has a book, at a sane price and XP.
	for skill: String in LifeSim.SKILL_NAMES:
		check(LifeHouseholdFlow.BOOK_SKILLS.has(skill), "The shelf sells a %s book." % skill)
		if LifeHouseholdFlow.BOOK_SKILLS.has(skill):
			var book: Dictionary = LifeHouseholdFlow.BOOK_SKILLS[skill]
			check(not str(book.get("label", "")).is_empty() and int(book.get("price", 0)) > 0 and float(book.get("xp", 0.0)) > 0.0,
				"The %s book has a real label, price and teaching XP." % skill)

	var app2: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app2)
	await frames(2)
	app2.selected_lot = 0
	app2.start_household()
	await frames(1)
	app2.set_process(false)
	var flow: LifeHouseholdFlow = app2.household_flow
	var sim: LifeSim = app2.sim
	var shelf: Dictionary = app2.world.closest_item("bookshelf", Vector3.ZERO)
	check(not shelf.is_empty(), "The starter home has a bookshelf for the book checks.")

	# A book teaches its subject through the ordinary queue, bound at purchase.
	check(bool(flow.buy_book(str(shelf.id), "logic").ok), "A Logic book can be bought for the shelf.")
	sim.skills.logic.level = 1
	sim.skills.logic.xp = 0.0
	check(sim.queue_action("study_book", str(shelf.id)), "Studying the shelf queues through the public path.")
	var session: Dictionary = sim.get_current_action()
	check(str(session.get("book_skill", "")) == "logic" and float(session.get("xp", 0.0)) > 0.0,
		"The queued session is bound to the book's own subject and XP.")
	sim.begin_current_action()
	advance(sim, 60.0)
	check(int(sim.skills.logic.level) > 1, "A studied book really raises the subject's level.")

	# The shelf refuses past level 9: the tenth level belongs to the computer.
	sim.skills.logic.level = 9
	sim.skills.logic.xp = 0.0
	var reason: String = flow.action_availability(sim, "study_book", str(shelf.id))
	check(not reason.is_empty() and reason.contains("10"), "Studying at level 9 is refused with a reason naming level 10 (%s)." % reason)
	var queued: Array = sim.action_queue.duplicate(true)
	check(not sim.queue_action("study_book", str(shelf.id)), "The refused book session does not queue.")
	check(sim.action_queue == queued, "A refused book session leaves the queue unchanged.")

	# A book cannot carry a skill to 10 even with a banked surplus of XP.
	sim.skills.logic.level = 8
	sim.skills.logic.xp = 10000.0
	flow.study_definition(sim.get_action_definition("study_book"), "logic")
	sim._apply_continuous_effects({"id": "study_book", "skill": "logic", "xp": 10000.0, "book_skill": "logic", "changes": {}, "duration": 60.0}, 1.0)
	check(int(sim.skills.logic.level) == LifeHouseholdFlow.BOOK_MAX_LEVEL,
		"A book stops the subject at level %d (got %d)." % [LifeHouseholdFlow.BOOK_MAX_LEVEL, int(sim.skills.logic.level)])

	# The computer is the way to level 10, and refuses exactly there. A single
	# session is 70 XP, so the check starts one session shy of the 450 needed.
	sim.skills.logic.level = LifeHouseholdFlow.BOOK_MAX_LEVEL
	sim.skills.logic.xp = 449.0
	sim.register_targets([{"id": "pc", "kind": "computer", "position": Vector3(2, .16, 2)}])
	var menu: Array = sim.get_actions_for("computer", "pc")
	var mastery: Dictionary = {}
	for entry: Dictionary in menu:
		if str(entry.id) == "computer_logic":
			mastery = entry
	check(not mastery.is_empty(), "The computer offers a Logic mastery action.")
	check(bool(mastery.get("available", false)), "Logic mastery is available at level %d." % LifeHouseholdFlow.BOOK_MAX_LEVEL)
	check(sim.queue_action("computer_logic", "pc"), "The computer mastery action queues.")
	sim.begin_current_action()
	advance(sim, 120.0)
	check(int(sim.skills.logic.level) == 10, "The computer carries Logic to exactly level 10 (got %d)." % int(sim.skills.logic.level))
	# Refused once mastered, with a reason.
	var done: String = ""
	for entry: Dictionary in sim.get_actions_for("computer", "pc"):
		if str(entry.id) == "computer_logic":
			done = str(entry.unavailable_reason)
	check(not done.is_empty() and done.contains("10"), "A mastered subject is refused on the computer with a reason (%s)." % done)
	check(not sim.queue_action("computer_logic", "pc"), "A mastered subject cannot be studied again.")
	check(int(sim.skills.logic.level) == 10, "A refused mastery session never pushes a skill past level 10.")

	app2.queue_free()
	await frames(1)
