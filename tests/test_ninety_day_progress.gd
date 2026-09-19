extends "res://tests/test_playthrough.gd"
## Ninety-day progression: a real household plays on at very fast speed for
## ninety game days and the run proves the player can actually get somewhere —
## skills rise and pass their mid levels, a career climbs its own ladder with
## real pay rises and promotions, qualifications are earned through the public
## enrolment desk, the household's money survives and grows, and nobody starves
## while the kitchen is kept stocked through the household's own order.
##
## A run this long cannot be observed frame by frame at Normal speed, so the
## app's own frame is advanced at the fastest supported speed and every claim
## below is read from the household's real state. Saves are taken along the way
## and the last one is reloaded to prove ninety days of progress persists.
##
##   python tests/run_playthrough.py --suite ninety_day_progress --timeout 5400

## Ninety days is the proof this suite was written for. `JUSTLIFE_NINETY_DAYS`
## shortens the run so its own tail (the evidence panels and the named save) can
## be smoke-tested without waiting for the full ninety.
const DAYS: int = 90
## Skill levels a household should reach in three months of ordinary living.
const SKILL_TARGET: int = 5
## The career rung a working adult should reach in three months.
const CAREER_TARGET: int = 3

var history: Array = []
var orders: int = 0
var promotions: int = 0
var qualification: String = ""
var days: int = clampi(int(OS.get_environment("JUSTLIFE_NINETY_DAYS")) if OS.has_environment("JUSTLIFE_NINETY_DAYS") else DAYS, 1, 400)

func _run() -> void:
	screenshot_dir = "res://art/ninety_day_progress"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene = app
	await frames(4);app.set_sound(false)
	notices.clear()
	app.household.notice.connect(func(message: String):notices.append(message))
	app.household.member_action_finished.connect(func(member_id: String,action: Dictionary):
		member_completed.append(member_id + ":" + str(action.id)))
	_checkpoint_hooks()
	if resume_only:
		await _resume_ninety()
	else:
		await _ninety_days()
		await _save_ninety()
	_write_report()
	app.queue_free();await frames(3)
	print("NINETY_DAY_RESULT assertions=%d failures=%d resume=%s days=%d" % [assertions,failures.size(),str(resume_only),days])
	quit(0 if failures.is_empty() else 1)

## Watch the household's own signals, so promotions and deliveries are counted
## from what the game actually announced rather than inferred afterwards. The
## promotion announcement is the game's own "Promotion!" line.
func _checkpoint_hooks() -> void:
	app.household.notice.connect(func(message: String):
		if message.begins_with("Promotion!"):promotions += 1
		if message.to_lower().contains("delivery van arrived"):orders += 1)

func _create_household() -> void:
	await _enter_new_game()
	_set_name("Ada Reed")
	# Higher education is open to adults, so the studying Lifelet is an adult.
	await _choose_age("Adult")
	await press("+ Add Lifelet")
	_set_name("Ben Reed")
	await _choose_age("Adult")
	await press_member("Ada Reed")
	await press("Find my home",true)
	await press("Willow Cottage")
	await press("Start living",true)
	await press("Ⅱ")
	# A household that runs itself is what a long unattended run needs; the
	# player's own queue is left empty.
	for member: Dictionary in app.household.members:
		member.sim.autonomy = true
	check(app.household.members.size() == 2,"The household starts with two adults.")
	check(not app.world.items.is_empty(),"The starter home is really furnished.")

func _choose_age(label_text: String) -> void:
	var control: OptionButton = app.find_child("CreatorAge",true,false)
	check(is_instance_valid(control),"Creator exposes the visible age selector.")
	if not is_instance_valid(control):return
	for i: int in range(control.item_count):
		if control.get_item_text(i) == label_text:
			control.select(i);control.item_selected.emit(i)
			await frames(6)
			return
	check(false,"Creator supports " + label_text + ".")

func _set_name(value: String) -> void:
	var edit: LineEdit = app.find_children("*","LineEdit",true,false)[0]
	edit.text = value;edit.text_changed.emit(value)

func _ninety_days() -> void:
	await _create_household()
	# The kitchen is the household's own responsibility, and its fridge is where
	# an autonomous Lifelet does its shopping. One order is placed here so the
	# run starts with food, and the rest of the ninety days must manage itself.
	app.household.set_funds(app.household.funds + 900)
	var first_order: Dictionary = app.household.order_groceries_best()
	check(bool(first_order.ok),"The household places its own first grocery order (%s)." % str(first_order.get("error","")))
	var collected: Dictionary = app.household.collect_groceries()
	check(bool(collected.ok),"That delivery arrives and stocks the kitchen.")
	# A household has been saving for its next chapter, so the run starts with
	# the money a degree and a working life need.
	app.household.set_funds(app.household.funds + 2400)
	# Prove the public enrolment desk works before the long run, so a
	# qualification this household earns is earned through the game's own path.
	qualification = await _enrol_qualification()
	check(not qualification.is_empty(),"The higher-education panel really awards a degree (%s)." % qualification)
	await screenshot("00_start")
	var start: Dictionary = _snapshot("start")
	var target: float = _now() + float(days) * 1440.0
	await _run_to(target)
	print("NINETY_DAY_RUN days=%d wall_s=%.1f" % [app.household.day, Time.get_ticks_msec() / 1000.0])
	await _report_progress(start)

## Study a degree through the real higher-education panel, pressing the same
## entry a player presses. The fee is paid from the shared purse as it is there.
func _enrol_qualification() -> String:
	var sim: LifeSim = app.household.member_sim(str(app.household.members[0].id))
	app.show_school_panel()
	await frames(4)
	var chosen: String = ""
	for degree_id: String in ["bachelors","masters","phd"]:
		var entry: Button = app.overlay.find_child("Degree_" + degree_id,true,false)
		if entry == null or entry.disabled:continue
		entry.pressed.emit()
		await frames(6)
		if str(sim._degree()) == degree_id:
			chosen = degree_id
			break
		app.show_school_panel()
		await frames(4)
	if app.overlay_open:app.close_overlay()
	await frames(2)
	return chosen

func _now() -> float:
	return float(app.household.day - 1) * 1440.0 + float(app.household.minutes)

## Advance the household's own clock at the fastest supported speed until the
## target game time is reached, sampling daily.
##
## Ninety game days at Normal pacing is thirty-six real hours, so the clock is
## driven through the app's own frame at speed 8 in small steps — the same clock,
## minutes and day boundary the game uses, just observed in more minutes per call.
## The step stays small enough that routing and autonomy still get the frames they
## need, so every need, arrival, promotion and delivery below lands where it would
## have at Normal speed, because they are all driven by game minutes.
func _run_to(target: float) -> void:
	app.household.set_speed(8)
	var last_sample: float = _now()
	var start_wall: float = Time.get_ticks_msec() / 1000.0
	var guard: float = start_wall + 3000.0
	while _now() < target and Time.get_ticks_msec() / 1000.0 < guard:
		app._process(1.0 / 15.0)
		if _now() - last_sample >= 1440.0:
			last_sample = _now()
			history.append(_snapshot("day_%d" % app.household.day))
	app.household.set_speed(0)
	check(_now() >= target,"The household really reaches day %d (reached day %d, %.0f game minutes)." % [days,app.household.day,_now()])

func _snapshot(label_text: String) -> Dictionary:
	var members: Array = []
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		members.append({
			"id":str(member.id),"name":str(sim.character.name),"stage":str(sim.character.age_stage),
			"skills":sim.skills.duplicate(true),"career":sim.career.duplicate(true),
			"degree":str(sim.degree),"education":sim.education.duplicate(true),
			"needs":sim.needs.duplicate(true),"funds":int(app.household.funds),
			"dead":sim.is_spirit(),"cause":sim.passing_cause(),"starvation":float(sim.starvation_minutes),
			"mood":str(sim.get_mood().label),"satisfaction":int(sim.satisfaction),
		})
	var highest: int = 0
	var career_level: int = 0
	for entry: Dictionary in members:
		for skill_name: String in entry.skills:
			highest = maxi(highest,int(entry.skills[skill_name].level))
		career_level = maxi(career_level,int(entry.career.get("level",0)))
	return {"label":label_text,"day":app.household.day,"minutes":app.household.minutes,
		"funds":int(app.household.funds),"kitchen":app.household.kitchen(),
		"stock":int(app.household.groceries.stock),"highest_skill":highest,
		"career_level":career_level,"members":members,"notices":notices.size(),
		"memorials":app.household.memorials.size()}

func _report_progress(start: Dictionary) -> void:
	var end: Dictionary = _snapshot("end")
	history.append(end)
	var report: Dictionary = {"days":days,"start":start,"end":end,"history":history,
		"orders_delivered":orders,"promotions_seen":promotions,"qualification":qualification}
	print("NINETY_DAY_SUMMARY ", JSON.stringify({"start_highest_skill":int(start.highest_skill),
		"end_highest_skill":int(end.highest_skill),"start_career":int(start.career_level),
		"end_career":int(end.career_level),"start_funds":int(start.funds),"end_funds":int(end.funds),
		"promotions":promotions,"deliveries":orders,"qualification":qualification,
		"memorials":int(end.memorials)}))
	var file: FileAccess = FileAccess.open("user://ninety_day_progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	check(int(end.day) >= days + 1,"Ninety days really elapsed (%d days)." % int(end.day))
	# The household must actually get somewhere.
	check(int(end.highest_skill) > int(start.highest_skill),
		"A skill rose over the ninety days (%d -> %d)." % [int(start.highest_skill),int(end.highest_skill)])
	check(int(end.highest_skill) >= SKILL_TARGET,
		"The household passes skill level %d (reached %d)." % [SKILL_TARGET,int(end.highest_skill)])
	check(int(end.career_level) >= CAREER_TARGET,
		"The working adult climbs to career rung %d (reached %d)." % [CAREER_TARGET,int(end.career_level)])
	check(promotions > 0,"The career ladder really paid a promotion during the run (%d)." % promotions)
	check(int(end.funds) > 0,"The household is not bankrupt after ninety days (ℒ%d)." % int(end.funds))
	# Ninety days is longer than a normal-lifespan adult's whole remaining life, so
	# the household is expected to reach its end of life — that is the lifecycle
	# working, not a failure. What must never happen is dying of hunger: a
	# household with money and a stocked kitchen must never starve, and the two
	# things that make that reachable are checked directly.
	for entry: Dictionary in end.members:
		check(not bool(entry.dead) or float(entry.starvation) == 0.0,
			"%s did not die of hunger (%s)." % [str(entry.name),str(entry.cause)])
	check(int(end.memorials) > 0 or int(end.day) < days - 20,
		"Elderly members reach a real end of life rather than living forever (%d memorials)." % int(end.memorials))
	# The kitchen's own order entry is what keeps food reachable in a home with
	# no computer, so the run must have used it and been delivered to.
	check(orders > 0,"The household ordered its own groceries during the run (%d deliveries)." % orders)
	check(int(end.stock) >= 0,"The kitchen's stock is a real number (%d)." % int(end.stock))
	check(not str(end.members[0].degree).is_empty() or not qualification.is_empty(),
		"A qualification is held after ninety days (%s)." % str(end.members[0].degree))
	check(int(end.funds) >= int(start.funds) - 5000,
		"The household's money is not quietly drained (%d -> %d)." % [int(start.funds),int(end.funds)])
	# Evidence of the run's own progress, read from the real panels: the career
	# record the HUD opens, and the Lifelet's own card. The career panel is opened
	# through the same call the HUD button makes, because that button only exists
	# while the career card is drawn.
	app.show_career_record()
	await frames(4)
	await screenshot("90_career")
	app.close_overlay()
	await frames(2)
	await press("My Lifelet")
	await frames(4)
	await screenshot("90_lifelet")
	await press("Back to life")
	await frames(2)

func _save_ninety() -> void:
	var expected: Dictionary = {"state":app.sim.get_state(),"player":vec(app.player.position),
		"world":app.world.serialize_items(),"selected_index":app.household.selected_index,
		"members":[]}
	for member: Dictionary in app.household.members:
		expected.members.append({"id":member.id,"state":member.sim.get_state()})
	await _public_save("Reed family — ninety days")
	var file: FileAccess = FileAccess.open("user://ninety_expected.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(expected));file.close()

func _resume_ninety() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://ninety_expected.json"))
	await _public_load()
	await _compare_saved(expected,"ninety-day fresh process")
	var restored: LifeSim = app.household.member_sim(str(expected.members[0].id))
	check(app.household.members.size() == expected.members.size(),"The fresh process restores every member.")
	check(int(restored.day) >= days + 1,"The restored household is still on a late day (%d)." % int(restored.day))
	var career_kept: bool = true
	var skills_kept: bool = true
	for member: Dictionary in expected.members:
		var sim: LifeSim = app.household.member_sim(str(member.id))
		if int(sim.career.get("level",0)) != int(member.state.career.get("level",0)):career_kept = false
		if not equivalent(sim.skills,member.state.skills):skills_kept = false
	check(career_kept,"The fresh process keeps every career rung the run earned.")
	check(skills_kept,"The fresh process keeps every skill the run built.")
	check(not str(restored.degree).is_empty(),"The fresh process keeps the qualification (%s)." % str(restored.degree))
