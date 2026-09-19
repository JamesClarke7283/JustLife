extends SceneTree
## The business package: a Lifelet who has earned a lot and reached a high rung
## of their trade can buy a business and hire people to work there.
##
## Every assertion drives the real career panel's own business screen, the real
## household purchase and the real household clock, and reads what a player would
## see: what was paid, who was hired, and what the business took today.
##
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_business.gd

const LifeBusiness = preload("res://scripts/business.gd")

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
	# ---------------------------------------------------------------- policy
	check(LifeBusiness.MIN_LEVEL == 9, "Running a business needs level 9, as the brief asks.")
	check(LifeBusiness.START_COST == 100000 and LifeBusiness.UPGRADE_COST == 200000,
		"The brief's two price points are the ones the table uses.")
	check(LifeBusiness.ids().size() >= 6, "Several kinds of business are offered (%d)." % LifeBusiness.ids().size())
	check(LifeBusiness.validate_owned(null).is_empty() and LifeBusiness.validate_owned({}).is_empty(),
		"Owning nothing is a valid holding.")
	var ids: Array[String] = LifeBusiness.ids()
	for business_id: String in ids:
		var info: Dictionary = LifeBusiness.info(business_id)
		check(LifeSim.SKILL_NAMES.has(str(info.skill)), "The %s needs a real skill (%s)." % [business_id, str(info.skill)])
		check(int(info.cost) >= LifeBusiness.START_COST, "The %s costs at least the entry price." % business_id)
		# The bar the player is refused against is never below the brief's level
		# 9, even when a table row was authored lower; the stated requirement
		# must name that same bar, so the reading and the enforcing agree.
		var bar: int = maxi(LifeBusiness.MIN_LEVEL, int(info.level))
		check(LifeBusiness.requirement_text(business_id).contains("level %d" % bar),
			"The %s states its enforced bar, level %d (%s)." % [business_id, bar, LifeBusiness.requirement_text(business_id)])
		var below: String = LifeBusiness.purchase_error(business_id, "adult", {str(info.skill): {"level": bar - 1}}, 1000000)
		check(below.contains("level %d" % bar), "A Lifelet one level short of the %s is refused against level %d (%s)." % [business_id, bar, below])
		check(not LifeBusiness.requirement_text(business_id).is_empty(), "The %s states its requirement." % business_id)
		var affordable: String = LifeBusiness.purchase_error(business_id, "adult", {str(info.skill): {"level": 10}}, 1000000)
		check(affordable.is_empty(), "A skilled, funded Lifelet may buy the %s (%s)." % [business_id, affordable])
	# A Lifelet below the rung is refused with the numbers named.
	var low_skill: String = LifeBusiness.purchase_error(ids[0], "adult", {str(LifeBusiness.info(ids[0]).skill): {"level": 4}}, 1000000)
	check(not low_skill.is_empty() and low_skill.contains("4"), "A low skill is refused and names the actual level (%s)." % low_skill)
	# A business the purse cannot reach is refused with the shortfall.
	var broke: String = LifeBusiness.purchase_error(ids[0], "adult", {str(LifeBusiness.info(ids[0]).skill): {"level": 10}}, 100)
	check(not broke.is_empty() and broke.to_lower().contains("needs"), "An unaffordable business is refused with its shortfall (%s)." % broke)
	# A minor cannot run one.
	check(not LifeBusiness.purchase_error(ids[0], "child", {str(LifeBusiness.info(ids[0]).skill): {"level": 10}}, 1000000).is_empty(),
		"A child cannot run a business.")
	check(not LifeBusiness.validate_owned({"version": 1, "id": "ghost"}).is_empty(), "An unknown business in a save is refused.")
	check(not LifeBusiness.validate_owned({"version": 1, "id": ids[0], "staff": ["a", "a"]}).is_empty(),
		"The same employee twice in a save is refused.")
	# A full staff makes the business pay more.
	var unstaffed: int = LifeBusiness.daily_income({"id": ids[0], "staff": []})
	var staffed: int = LifeBusiness.daily_income({"id": ids[0], "staff": ["A", "B"]})
	check(staffed > unstaffed, "More employees means the business takes more (%d -> %d)." % [unstaffed, staffed])

	# ------------------------------------------------------------- the live game
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

	check(app.household.business.is_empty(), "A new household runs no business.")
	app.household.set_funds(1000)
	app.sim.funds = 1000
	# A poor, unskilled household is refused.
	var poor: Dictionary = app.household.buy_business(ids[0], str(app.household.members[0].id))
	check(not bool(poor.ok) and not str(poor.get("error", "")).is_empty(), "A household with no skill and no money is refused.")

	# Give the Lifelet the trade at its top rung, and the money.
	var chosen: String = ids[0]
	var needed_skill: String = str(LifeBusiness.info(chosen).skill)
	var needed_level: int = maxi(LifeBusiness.MIN_LEVEL, int(LifeBusiness.info(chosen).level))
	app.sim.skills[needed_skill].level = needed_level
	app.household.set_funds(LifeBusiness.START_COST + 50000)
	app.sim.funds = app.household.funds

	# ------------------------------------------------------- the real panel
	app.show_business_panel()
	await frames(4)
	check(app.overlay_open, "The business panel opens.")
	var rows: int = 0
	for business_id: String in ids:
		if app.overlay.find_child("BusinessRow_" + business_id, true, false) != null: rows += 1
	check(rows == ids.size(), "Every business gets a row (%d of %d)." % [rows, ids.size()])
	var buy: Button = app.overlay.find_child("Business_" + chosen, true, false)
	check(buy != null and not buy.disabled, "A skilled, funded Lifelet can buy the one they qualify for.")
	app.close_overlay()
	await frames(2)

	# --------------------------------------------------------- the purchase
	var funds_before: int = app.household.funds
	var bought: Dictionary = app.household.buy_business(chosen, str(app.household.members[0].id))
	check(bool(bought.ok), "The business can really be bought (%s)." % str(bought.get("error", "")))
	check(int(bought.cost) == LifeBusiness.START_COST, "It costs its stated price (ℒ%d)." % LifeBusiness.START_COST)
	check(app.household.funds == funds_before - LifeBusiness.START_COST, "The purse pays exactly once.")
	check(str(app.household.business.id) == chosen, "The household now runs it.")
	# A second business is refused rather than silently replacing the first.
	var second: Dictionary = app.household.buy_business(ids[1], str(app.household.members[0].id))
	check(not bool(second.ok) and str(app.household.business.id) == chosen, "A second business is refused without replacing the first.")

	# ----------------------------------------------------------- hiring
	var employee_id: String = str(app.household.members[1].id)
	var income_before: int = app.household.business_income()
	var hire: Dictionary = app.household.hire_employee(employee_id)
	check(bool(hire.ok), "A housemate can be hired (%s)." % str(hire.get("error", "")))
	check(int(hire.cost) == LifeBusiness.hire_cost(chosen), "The hire fee is the table's own (ℒ%d)." % int(hire.cost))
	check(app.household.business_income() > income_before, "Hiring really raises what the business takes (%d -> %d)." % [income_before, app.household.business_income()])
	var roster: Array = app.household.business.get("staff", [])
	check(roster.has(str(app.household.members[1].sim.character.name)), "The employee is really on the roster.")
	# The same person cannot be hired twice.
	var again: Dictionary = app.household.hire_employee(employee_id)
	check(not bool(again.ok), "The same Lifelet cannot be hired twice.")

	# ------------------------------------------------- the day's takings
	var purse_before: int = app.household.funds
	var expected: int = app.household.business_income()
	for i: int in 200:
		app.household.set_speed(1)
		app.household.tick(1.0)
		if app.household.funds != purse_before:
			break
	check(app.household.funds == purse_before + expected,
		"The business really took its daily income (ℒ%d -> ℒ%d, expected ℒ%d)." % [purse_before, app.household.funds, expected])
	check(int(app.household.business.earned) == expected, "The earnings total records what it took.")

	# ------------------------------------------------------------- saving
	check(app.save_game("business_probe", "Business probe"), "The household saves with its business.")
	var slot: Dictionary = LifeSaveLibrary.read_slot("business_probe")
	check(bool(slot.get("ok", false)), "The written slot reads back (%s)." % str(slot.get("error", "")))
	var saved: Dictionary = (slot.get("data", {}) as Dictionary).get("business", {})
	check(str(saved.get("id", "")) == chosen, "The business rides the save.")
	check((saved.get("staff", []) as Array).size() == 1, "The employee rides the save.")
	var damaged: Dictionary = app.household.get_state()
	damaged.business = {"version": 1, "id": "ghost"}
	var fresh: LifeHousehold = LifeHousehold.new()
	check(not bool(fresh.restore_state(damaged).ok), "A save naming an unknown business is refused.")
	fresh.free()
	LifeSaveLibrary.delete_slot("business_probe")

	print("BUSINESS_RESULT ", JSON.stringify({"checks": checks, "failures": failures,
		"income": app.household.business_income()}))
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
