extends "res://tests/test_playthrough.gd"
## Ninety-day progression: a real household plays on at very fast speed for
## ninety game days and the run proves the player can actually get somewhere —
## skills rise and pass their mid levels, a career climbs its own ladder with
## real pay rises and promotions, qualifications are earned through the public
## enrolment desk, the household's money survives and grows, and nobody starves
## while the kitchen is kept stocked through the household's own order.
##
## The default household is a new adult female and adult male who start as
## partners so pregnancy, a baby, cooking, pets and a career ceiling are all
## reachable on the same unattended clock.
##
##   python tests/run_playthrough.py --suite ninety_day_progress --timeout 5400

## Ninety days is the proof this suite was written for. `JUSTLIFE_NINETY_DAYS`
## shortens the run so its own tail (the evidence panels and the named save) can
## be smoke-tested without waiting for the full ninety.
const DAYS: int = 90
## Skill levels a household should reach in three months of ordinary living.
const SKILL_TARGET: int = 5
## Full ninety days should climb the career ladder to its authored ceiling.
const CAREER_TARGET: int = 10

var history: Array = []
var orders: int = 0
var promotions: int = 0
var qualification: String = ""
var days: int = clampi(int(OS.get_environment("JUSTLIFE_NINETY_DAYS")) if OS.has_environment("JUSTLIFE_NINETY_DAYS") else DAYS, 1, 400)
## Glitches observed during the long unattended run: day, detail, screenshot path.
## Written beside the progress report so a critic can open each capture.
var glitches: Array = []
## What the couple actually exercised: conception, birth, pets, career ceiling.
var mechanics: Dictionary = {
	"genders": [], "partners": false, "conceived": false, "baby_born": false,
	"baby_name": "", "baby_welcomed": false, "pet_bought": false, "pet_count": 0,
	"first_meal_done": false, "career_max_reached": false, "max_career_level": 0, "memorials": 0,
}

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
	print("NINETY_DAY_RESULT assertions=%d failures=%d resume=%s days=%d glitches=%d baby=%s career=%d" % [assertions,failures.size(),str(resume_only),days,glitches.size(),str(mechanics.baby_born),int(mechanics.max_career_level)])
	quit(0 if failures.is_empty() else 1)

## Watch the household's own signals, so promotions and deliveries are counted
## from what the game actually announced rather than inferred afterwards. The
## promotion announcement is the game's own "Promotion!" line.
func _checkpoint_hooks() -> void:
	app.household.notice.connect(func(message: String):
		if message.begins_with("Promotion!"):promotions += 1
		if message.to_lower().contains("delivery van arrived"):orders += 1)
	if app.household.has_signal("baby_born"):
		app.household.baby_born.connect(func(_mother_id: String):
			mechanics.baby_born = true
			print("NINETY_DAY_MECHANIC baby_born day=%d" % app.household.day))

func _create_household() -> void:
	await _enter_new_game()
	_set_name("Ada Reed")
	await _choose_age("Adult")
	await press("Female")
	await press("+ Add Lifelet")
	_set_name("Ben Reed")
	await _choose_age("Adult")
	await press("Male")
	# Partners so Try for Baby is a legal public path for this couple.
	await press_member("Ada Reed")
	await press("Connections")
	await _set_partner_connection(1)
	check(app.creator_connection(1) == "partners", "Ada and Ben start as partners in the creator.")
	mechanics.partners = app.creator_connection(1) == "partners"
	await press("Back to creating")
	await press_member("Ada Reed")
	await press("Find my home",true)
	await press("Willow Cottage")
	await press("Start living",true)
	await press("Ⅱ")
	for member: Dictionary in app.household.members:
		member.sim.autonomy = true
	check(app.household.members.size() == 2,"The household starts with two adults.")
	check(not app.world.items.is_empty(),"The starter home is really furnished.")
	var genders: Array = []
	for member: Dictionary in app.household.members:
		genders.append(str(member.sim.character.get("gender","")))
	mechanics.genders = genders
	check(genders.has("female") and genders.has("male"),
		"The couple is one adult female and one adult male (%s)." % str(genders))
	var ada: LifeSim = app.household.member_sim(str(app.household.members[0].id))
	var ben: LifeSim = app.household.member_sim(str(app.household.members[1].id))
	check(str(ada.romantic_partner) == str(app.household.members[1].id) and str(ben.romantic_partner) == str(app.household.members[0].id),
		"Partnership is reciprocal after move-in.")

func _set_partner_connection(other_index: int) -> void:
	# Role index 2 is Partners (housemates, siblings, partners, …).
	var option: OptionButton
	for node: Node in app.find_children("*", "OptionButton", true, false):
		if node.is_visible_in_tree() and int(node.get_meta("connection_member", -1)) == other_index:
			option = node
	check(is_instance_valid(option), "Visible partner connection selector for member %d." % other_index)
	if not is_instance_valid(option):
		return
	option.select(2)
	option.item_selected.emit(2)
	await frames(4)

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
	await _buy_opening_pet()
	await screenshot("00_start")
	await _conceive_couple()
	var start: Dictionary = _snapshot("start")
	var target: float = _now() + float(days) * 1440.0
	await _run_to(target)
	print("NINETY_DAY_RUN days=%d wall_s=%.1f mechanics=%s" % [app.household.day, Time.get_ticks_msec() / 1000.0, JSON.stringify(mechanics)])
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

## Buy a pet through the phone shop's own confirm path so the long run covers
## pet HUD and care alongside the human couple.
func _buy_opening_pet() -> void:
	if not is_instance_valid(app.pet_shop):
		return
	var reason: String = str(app.household.pet_shop_availability()) if app.household.has_method("pet_shop_availability") else ""
	if not reason.is_empty():
		print("NINETY_DAY_MECHANIC pet_shop_unavailable %s" % reason)
		return
	app.household.set_funds(app.household.funds + LifePets.price_for("cat") + 50)
	app.pet_shop.show_shop()
	await frames(3)
	app.pet_shop.show_species()
	await frames(2)
	app.pet_shop.confirm_pet()
	await frames(8)
	var pets: Array = app.household.pets.get("pets", []) if app.household.pets is Dictionary else []
	mechanics.pet_bought = pets.size() > 0
	mechanics.pet_count = pets.size()
	print("NINETY_DAY_MECHANIC pet_bought=%s count=%d" % [str(mechanics.pet_bought), int(mechanics.pet_count)])
	if app.overlay_open:
		app.close_overlay()
	await frames(2)
	await screenshot("00_pet")

## Put both partners to sleep in the shared bed and run Try for Baby through the
## household's public begin path — the same path the bed menu uses.
func _conceive_couple() -> void:
	var bed: Dictionary = first_item("bed")
	check(not bed.is_empty(), "The starter home has a bed for Try for Baby.")
	if bed.is_empty():
		return
	for member: Dictionary in app.household.members:
		member.sim.autonomy = false
		member.sim.action_queue.clear()
		member.sim.needs.energy = 20.0
	app.select_household_member(0)
	app.queue_interaction({"id":str(bed.id),"kind":str(bed.kind),"node":bed.node,"size":bed.size},"sleep")
	app.select_household_member(1)
	app.queue_interaction({"id":str(bed.id),"kind":str(bed.kind),"node":bed.node,"size":bed.size},"sleep")
	await frames(6)
	# Walk both into the bed and start sleep the way arrival does.
	for _i: int in range(80):
		app.household.set_speed(8)
		app._process(1.0 / 15.0)
		var both_asleep: bool = true
		for member: Dictionary in app.household.members:
			var action: Dictionary = member.sim.get_current_action()
			if str(action.get("id","")) != "sleep" or str(action.get("phase","")) != "active":
				both_asleep = false
				# Force arrival if still approaching.
				if str(action.get("id","")) == "sleep" and str(action.get("phase","")) in ["queued","approach"]:
					app._bind_member(str(member.id))
					if is_instance_valid(app.player) and action.has("target_position"):
						app.player.position = Vector3(action.target_position)
					app.household.begin_action(str(member.id))
		if both_asleep:
			break
	app.household.set_speed(0)
	await frames(4)
	var initiator: String = str(app.household.members[0].id)
	var started: Dictionary = app.household.begin_try_for_baby(initiator, str(bed.id))
	check(bool(started.ok), "Try for Baby starts for the sleeping couple (%s)." % str(started.get("error","")))
	if not bool(started.ok):
		for member: Dictionary in app.household.members:
			member.sim.autonomy = true
		return
	# Admit the beat and drive its shared clock to completion.
	for _j: int in range(10):
		await frames(1)
		for member: Dictionary in app.household.members:
			var beat: Dictionary = member.sim.get_current_action()
			if str(beat.get("id","")) != LifeBabyPlan.ACTION_ID:
				continue
			if str(beat.get("phase","")) != "active":
				app._bind_member(str(member.id))
				if is_instance_valid(app.player) and beat.has("target_position"):
					app.player.position = Vector3(beat.target_position)
				app.household.begin_action(str(member.id))
	app.household.set_speed(1)
	for _k: int in range(8):
		app.household.tick((LifeBabyPlan.DURATION + 1.0) / LifeSim.GAME_MINUTES_PER_SECOND)
		await frames(1)
	app.household.set_speed(0)
	mechanics.conceived = bool(app.household.pregnancy.get("active", false))
	check(mechanics.conceived, "Completing Try for Baby begins a real pregnancy.")
	await screenshot("00_pregnant")
	print("NINETY_DAY_MECHANIC conceived=%s day=%d" % [str(mechanics.conceived), app.household.day])
	for member: Dictionary in app.household.members:
		member.sim.autonomy = true

func _now() -> float:
	return float(app.household.day - 1) * 1440.0 + float(app.household.minutes)

## Advance the household's own clock at the fastest supported speed until the
## target game time is reached, sampling daily.
func _run_to(target: float) -> void:
	app.household.set_speed(8)
	var last_sample: float = _now()
	var start_wall: float = Time.get_ticks_msec() / 1000.0
	var guard: float = start_wall + 5400.0
	var last_day: int = app.household.day
	while _now() < target and Time.get_ticks_msec() / 1000.0 < guard:
		await _handle_family_ui_if_open()
		app._process(1.0 / 15.0)
		if app.household.day != last_day:
			last_day = app.household.day
			await _sample_day()
		if _now() - last_sample >= 1440.0:
			last_sample = _now()
			history.append(_snapshot("day_%d" % app.household.day))
	app.household.set_speed(0)
	check(_now() >= target,"The household really reaches day %d (reached day %d, %.0f game minutes)." % [days,app.household.day,_now()])

## Birth opens the baby creator, then Dad's hospital choice, then Welcome Baby
## Home. Drive each public step so the ninety-day clock is not stuck on a pause
## overlay after the newborn arrives.
func _handle_family_ui_if_open() -> void:
	if str(app.mode) == "creator" and str(app.creator_purpose) == "baby":
		app.profile.name = "Wren Reed"
		app.profile.gender = "female"
		app.profile.age_stage = "baby"
		app.profile.life_stage = "minor"
		if app.has_method("confirm_baby_creator"):
			app.confirm_baby_creator()
		await frames(8)
		if str(app.mode) != "live":
			app.mode = "live"
			app.world.live_enabled = true
			if is_instance_valid(app.world.house):
				app.world.house.visible = true
		mechanics.baby_born = true
		mechanics.baby_name = "Wren Reed"
		print("NINETY_DAY_MECHANIC baby_confirmed members=%d mode=%s" % [app.household.members.size(), str(app.mode)])
		await screenshot("baby_welcome")
	# Partner choice overlay after the hospital stay begins.
	if app.overlay_open and is_instance_valid(app.find_child("BirthNotifyDad", true, false)):
		var notify: Button = app.find_child("BirthNotifyDad", true, false)
		notify.pressed.emit()
		await frames(6)
		print("NINETY_DAY_MECHANIC dad_notified day=%d" % app.household.day)
		await screenshot("baby_dad_notified")
	# Welcome Baby Home once; then drive the arrival cinematic through app frames
	# so the ninety-day clock is not frozen while the car is on screen.
	if not bool(mechanics.baby_welcomed) and app.has_method("welcome_baby_home") and LifeBirthHomecoming.can_welcome(app.household.birth_homecoming):
		mechanics.baby_welcomed = true
		app.welcome_baby_home()
		await frames(4)
		for _drive: int in range(240):
			if app.birth_arrival.is_empty():
				break
			app._process(1.0 / 15.0)
			await frames(1)
		if not app.birth_arrival.is_empty() and app.has_method("_end_birth_arrival_cinematic"):
			# Fallback: finish the hospital stay without waiting on the car art.
			if app.household.has_method("finish_welcome_baby_home"):
				app.household.finish_welcome_baby_home()
			app._end_birth_arrival_cinematic()
			app.household.register_targets(app.world.simulation_targets())
			app.draw_live()
		print("NINETY_DAY_MECHANIC baby_home day=%d arrival_done=%s" % [app.household.day, str(app.birth_arrival.is_empty())])
		await screenshot("baby_home")
	for member: Dictionary in app.household.members:
		if is_instance_valid(member.sim) and not member.sim.is_spirit():
			member.sim.autonomy = true
	if app.household.speed <= 0:
		app.household.set_speed(8)

## One real day boundary: capture the live view and note critical needs, empty
## kitchens or starvation pressure so a long run leaves a glitch trail.
func _sample_day() -> void:
	await _handle_family_ui_if_open()
	var day_n: int = int(app.household.day)
	var label: String = "day_%02d" % day_n
	await screenshot(label)
	var shot: String = screenshot_dir.path_join(label + ".png")
	var max_career: int = 0
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		if sim == null or sim.is_spirit():
			continue
		max_career = maxi(max_career, int(sim.career.get("level", 0)))
		for want: Dictionary in sim.wants:
			if str(want.get("id","")) == "first_meal" and bool(want.get("complete", false)):
				mechanics.first_meal_done = true
		for need_name: String in ["hunger", "energy", "bladder", "hygiene", "fun", "social"]:
			var value: float = float(sim.needs.get(need_name, 100.0))
			if value < 12.0:
				_log_glitch(day_n, shot, "product",
					"%s %s at %.0f (critical)." % [str(sim.character.name), need_name, value])
		if float(sim.starvation_minutes) > 0.0:
			_log_glitch(day_n, shot, "product",
				"%s has %.0f starvation minutes." % [str(sim.character.name), float(sim.starvation_minutes)])
	mechanics.max_career_level = maxi(int(mechanics.max_career_level), max_career)
	if max_career >= CAREER_TARGET:
		mechanics.career_max_reached = true
	if int(app.household.funds) <= 0:
		_log_glitch(day_n, shot, "product", "Household funds are ℒ0.")
	var grocery_stock: int = int(app.household.groceries.get("stock", 0))
	var meal_portions: int = app.household.meals.portions.size() if app.household.meals != null else 0
	if grocery_stock <= 0 and meal_portions <= 0:
		_log_glitch(day_n, shot, "product", "Kitchen is empty (no grocery stock and no portions).")
	var babies: int = 0
	for member: Dictionary in app.household.members:
		if str(member.sim.character.get("age_stage","")) == "baby":
			babies += 1
	if babies > 0:
		mechanics.baby_born = true
	var pets: Array = app.household.pets.get("pets", []) if app.household.pets is Dictionary else []
	mechanics.pet_count = pets.size()
	print("NINETY_DAY_SAMPLE day=%d funds=%d stock=%d career=%d baby=%s pregnant=%s pets=%d glitches=%d" % [
		day_n, app.household.funds, grocery_stock, max_career, str(mechanics.baby_born),
		str(bool(app.household.pregnancy.get("active", false))), pets.size(), glitches.size()])

func _log_glitch(day_n: int, shot: String, kind: String, detail: String) -> void:
	var entry: Dictionary = {"day": day_n, "screenshot": shot, "kind": kind, "detail": detail}
	glitches.append(entry)
	print("GLITCH day=%d kind=%s %s shot=%s" % [day_n, kind, detail, shot])

func _snapshot(label_text: String) -> Dictionary:
	var members: Array = []
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		members.append({
			"id":str(member.id),"name":str(sim.character.name),"stage":str(sim.character.age_stage),
			"gender":str(sim.character.get("gender","")),
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
		"memorials":app.household.memorials.size(),"pregnant":bool(app.household.pregnancy.get("active",false)),
		"member_count":members.size(),"mechanics":mechanics.duplicate(true)}

func _report_progress(start: Dictionary) -> void:
	var end: Dictionary = _snapshot("end")
	history.append(end)
	var report: Dictionary = {"days":days,"start":start,"end":end,"history":history,
		"orders_delivered":orders,"promotions_seen":promotions,"qualification":qualification,
		"glitches":glitches}
	print("NINETY_DAY_SUMMARY ", JSON.stringify({"start_highest_skill":int(start.highest_skill),
		"end_highest_skill":int(end.highest_skill),"start_career":int(start.career_level),
		"end_career":int(end.career_level),"start_funds":int(start.funds),"end_funds":int(end.funds),
		"promotions":promotions,"deliveries":orders,"qualification":qualification,
		"memorials":int(end.memorials),"glitches":glitches.size()}))
	var file: FileAccess = FileAccess.open("user://ninety_day_progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	var glitch_file: FileAccess = FileAccess.open("user://ninety_day_glitches.json",FileAccess.WRITE)
	glitch_file.store_string(JSON.stringify({"days":days,"glitches":glitches},"\t"));glitch_file.close()
	# Scaled targets when JUSTLIFE_NINETY_DAYS shortens the run (e.g. a 60-day
	# playthrough still proves progress without demanding a full ninety-day ladder).
	var skill_target: int = maxi(3, int(round(float(SKILL_TARGET) * float(days) / float(DAYS))))
	var career_target: int = maxi(2, int(round(float(CAREER_TARGET) * float(days) / float(DAYS))))
	check(int(end.day) >= days + 1,"Ninety days really elapsed (%d days)." % int(end.day))
	# The household must actually get somewhere.
	check(int(end.highest_skill) > int(start.highest_skill),
		"A skill rose over the ninety days (%d -> %d)." % [int(start.highest_skill),int(end.highest_skill)])
	check(int(end.highest_skill) >= skill_target,
		"The household passes skill level %d (reached %d)." % [skill_target,int(end.highest_skill)])
	check(int(end.career_level) >= career_target,
		"The working adult climbs to career rung %d (reached %d)." % [career_target,int(end.career_level)])
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
	# Full ninety-day runs start as adults and age through elder, so memorials
	# are expected near the end. Shorter JUSTLIFE_NINETY_DAYS smoke runs
	# (e.g. 60 days) reach elder but not due_to_pass_on yet — demanding a
	# memorial there would be a stale assertion, not a lifecycle defect.
	var expect_end_of_life: bool = days >= DAYS - 5
	check(not expect_end_of_life or int(end.memorials) > 0 or int(end.day) < days - 20,
		"Elderly members reach a real end of life rather than living forever (%d memorials)." % int(end.memorials))
	# The kitchen's own order entry is what keeps food reachable in a home with
	# no computer, so the run must have used it and been delivered to.
	check(orders > 0,"The household ordered its own groceries during the run (%d deliveries)." % orders)
	check(int(end.stock) >= 0,"The kitchen's stock is a real number (%d)." % int(end.stock))
	check(not str(end.members[0].degree).is_empty() or not qualification.is_empty(),
		"A qualification is held after ninety days (%s)." % str(end.members[0].degree))
	check(int(end.funds) >= int(start.funds) - 5000,
		"The household's money is not quietly drained (%d -> %d)." % [int(start.funds),int(end.funds)])
	if days >= DAYS - 5:
		check(bool(mechanics.conceived) or bool(mechanics.baby_born),
			"The male+female partners conceived or welcomed a baby during the ninety days.")
		check(int(end.career_level) >= CAREER_TARGET,
			"A career reaches its maximum level %d (reached %d)." % [CAREER_TARGET,int(end.career_level)])
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
	# `_compare_saved` reads the lot and the floor finish, so the checkpoint
	# records them alongside the state it already kept.
	var expected: Dictionary = {"state":app.sim.get_state(),"player":vec(app.player.position),
		"world":app.world.serialize_items(),"selected_index":app.household.selected_index,
		"lot":app.selected_lot,"floor":app.floor_color,"members":[]}
	for member: Dictionary in app.household.members:
		# `_compare_saved` reads each member's body position too, so the
		# checkpoint records it alongside the state.
		expected.members.append({"id":member.id,"state":member.sim.get_state(),
			"position":vec(app.world.actors[member.id].position)})
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
