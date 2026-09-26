extends "res://tests/test_ninety_day_progress.gd"
## One hundred eighty days with one adult couple, two children, and the
## grandchildren those children can reach with another Lifelet.
##
##   python tests/run_playthrough.py --suite one_eighty_day_family --timeout 15000
##
## Pregnancy is 14 days. On a normal lifespan a baby reaches young adult
## (the first stage whose life_stage is adult, which Try for Baby requires)
## 63 days after birth: baby 28, child 14, teen 21. Two pregnancies cannot
## overlap, and a household that already has a baby cannot start another, so
## the second child waits until the first leaves the baby stage. Both births
## and a grandchild still fit inside 180 days. Lifespans are not shortened.

const CHILD_NAMES: Array[String] = ["Lina Reed", "Owen Reed", "Noa Reed", "Kit Reed"]
const RESIDENTS: Array[String] = ["maya", "leo", "priya", "tom"]

var founder_ids: Array[String] = []
var birth_names: Array[String] = []
var welcomed_ids: Array[String] = []
var courted: Dictionary = {}
var grandchild_blocker: String = ""
var tree_log: Array = []
var next_conception_day: int = 1


func _run() -> void:
	days = 180
	screenshot_dir = "res://art/one_eighty_day_family"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.set_sound(false)
	notices.clear()
	app.household.notice.connect(func(message: String): notices.append(message))
	app.household.member_action_finished.connect(func(member_id: String, action: Dictionary):
		member_completed.append(member_id + ":" + str(action.id)))
	_checkpoint_hooks()
	if resume_only:
		await _resume_family()
	elif OS.get_environment("JUSTLIFE_CONTINUE") == "1":
		await _continue_clock()
		await _save_family()
	else:
		await _ninety_days()
		await _save_family()
	_write_report()
	var reached: int = int(app.household.day)
	var kids: int = _children_of_founders()
	var grands: int = _grandchildren()
	print("FAMILY_RESULT assertions=%d failures=%d resume=%s days=%d kids=%d grandchildren=%d blocker=%s glitches=%d" % [
		assertions, failures.size(), str(resume_only), reached, kids, grands, grandchild_blocker, glitches.size()])
	app.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)


func _create_household() -> void:
	await super()
	founder_ids.clear()
	for member: Dictionary in app.household.members:
		founder_ids.append(str(member.id))
	mechanics["founder_ids"] = founder_ids.duplicate()


func _continue_clock() -> void:
	await _public_load()
	await frames(8)
	_checkpoint_hooks()
	founder_ids.clear()
	for member: Dictionary in app.household.members:
		var person_name: String = str(member.sim.character.name)
		if person_name in ["Ada Reed", "Ben Reed"]:
			founder_ids.append(str(member.id))
	if founder_ids.size() < 2:
		for member: Dictionary in app.household.members:
			if founder_ids.size() >= 2:
				break
			founder_ids.append(str(member.id))
	mechanics["founder_ids"] = founder_ids.duplicate()
	mechanics.partners = true
	mechanics.conceived = true
	mechanics.baby_born = true
	for member: Dictionary in app.household.members:
		if is_instance_valid(member.sim) and not member.sim.is_spirit():
			member.sim.autonomy = true
	print("FAMILY_CONTINUE day=%d members=%d children=%d" % [app.household.day, app.household.members.size(), _children_of_founders()])
	var start: Dictionary = _snapshot("continue")
	await _run_to(180.0 * 1440.0)
	await _report_progress(start)


func _run_to(target: float) -> void:
	app.household.set_speed(8)
	var last_sample: float = _now()
	var start_wall: float = Time.get_ticks_msec() / 1000.0
	# Ninety days budgets 5400s. This run is about a minute a day, so 180 days
	# needs the longer wall clock and still leaves time for the birth UI.
	# A minute of game time needs a real fraction of a frame. Stepping a whole
	# minute let a queued chat outrun meals, and the earlier 5-hour guard stopped
	# the household on day 137. Eighteen hours covers 180 days at the pace this
	# suite actually runs.
	var guard: float = start_wall + 64800.0
	var step: float = 1.0 / 15.0
	var last_day: int = app.household.day
	while _now() < target and Time.get_ticks_msec() / 1000.0 < guard:
		await _handle_family_ui_if_open()
		app._process(step)
		if app.household.day != last_day:
			last_day = app.household.day
			await _sample_day()
		if _now() - last_sample >= 1440.0:
			last_sample = _now()
			history.append(_snapshot("day_%d" % app.household.day))
	app.household.set_speed(0)
	check(_now() >= target, "The household really reaches day %d (reached day %d, %.0f game minutes)." % [days, app.household.day, _now()])


func _sample_day() -> void:
	await super()
	_note_tree()
	await _maybe_second_child()
	await _court_children()


func _handle_family_ui_if_open() -> void:
	await _dismiss_farewell()
	# Birth is deferred until an idle frame. Open it here so the next
	# conception cannot replace a baby that is still waiting to be named.
	if app.household.birth_ready() and str(app.mode) != "creator":
		app.show_baby_creator()
		await frames(4)
	if str(app.mode) == "creator" and str(app.creator_purpose) == "baby":
		var index: int = birth_names.size()
		var baby_name: String = CHILD_NAMES[mini(index, CHILD_NAMES.size() - 1)]
		if index >= CHILD_NAMES.size():
			baby_name = "Baby %d Reed" % (index + 1)
		var before: int = app.household.members.size()
		# Keep the rolled body. Only the display name is chosen here.
		app.profile.name = baby_name
		if app.has_method("confirm_baby_creator"):
			app.confirm_baby_creator()
		await frames(8)
		if str(app.mode) != "live":
			app.mode = "live"
			app.world.live_enabled = true
			if is_instance_valid(app.world.house):
				app.world.house.visible = true
		if app.household.members.size() <= before:
			var detail: String = "Birth confirm did not add a Lifelet (%d members). Last notices: %s" % [app.household.members.size(), str(notices.slice(maxi(0, notices.size() - 3)))]
			_log_glitch(int(app.household.day), "", "product", detail)
			print("FAMILY_MECHANIC baby_confirm_failed day=%d %s" % [app.household.day, detail])
		else:
			birth_names.append(str(app.household.members.back().sim.character.name))
			mechanics.baby_born = true
			mechanics.baby_name = birth_names.back()
			mechanics["births"] = birth_names.duplicate()
			print("FAMILY_MECHANIC baby_confirmed name=%s members=%d day=%d" % [birth_names.back(), app.household.members.size(), app.household.day])
			await screenshot("baby_%02d" % birth_names.size())
	if app.overlay_open and is_instance_valid(app.find_child("BirthNotifyDad", true, false)):
		var notify: Button = app.find_child("BirthNotifyDad", true, false)
		notify.pressed.emit()
		await frames(6)
		print("FAMILY_MECHANIC dad_notified day=%d" % app.household.day)
	var homecoming: Dictionary = app.household.birth_homecoming
	var baby_id: String = str(homecoming.get("baby_id", ""))
	if not baby_id.is_empty() and not welcomed_ids.has(baby_id) and app.has_method("welcome_baby_home") and LifeBirthHomecoming.can_welcome(homecoming):
		welcomed_ids.append(baby_id)
		mechanics.baby_welcomed = true
		app.welcome_baby_home()
		await frames(4)
		for _drive: int in range(240):
			if app.birth_arrival.is_empty():
				break
			app._process(1.0 / 15.0)
			await frames(1)
		if not app.birth_arrival.is_empty() and app.has_method("_end_birth_arrival_cinematic"):
			if app.household.has_method("finish_welcome_baby_home"):
				app.household.finish_welcome_baby_home()
			app._end_birth_arrival_cinematic()
			app.household.register_targets(app.world.simulation_targets())
			app.draw_live()
		print("FAMILY_MECHANIC baby_home id=%s day=%d" % [baby_id, app.household.day])
		await screenshot("baby_home_%02d" % welcomed_ids.size())
	for member: Dictionary in app.household.members:
		if is_instance_valid(member.sim) and not member.sim.is_spirit():
			member.sim.autonomy = true
	if app.household.speed <= 0 and not _farewell_open():
		app.household.set_speed(8)


func _farewell_open() -> bool:
	for node: Node in app.find_children("*", "Label", true, false):
		if node is Label and node.visible and str(node.text).contains("end of their life"):
			return true
	return false


func _dismiss_farewell() -> void:
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		if sim == null or sim.pending_passing_cause.is_empty() or _farewell_open():
			continue
		if app.overlay_open:
			continue
		app._on_member_passing_due(str(member.id), str(sim.pending_passing_cause))
		await frames(2)
	if not _farewell_open():
		return
	var button: Button = button_matching("OK")
	if button == null:
		_log_glitch(int(app.household.day), "", "product", "A farewell is open but OK is not available.")
		return
	var who: String = ""
	for node: Node in app.find_children("*", "Label", true, false):
		if node is Label and node.visible and str(node.text).contains("end of their life"):
			who = str(node.text)
	button.pressed.emit()
	await frames(4)
	print("FAMILY_MECHANIC farewell_ok day=%d %s" % [app.household.day, who])
	await screenshot("farewell_%d" % app.household.day)
	if app.household.speed <= 0:
		app.household.set_speed(8)


func _maybe_second_child() -> void:
	if founder_ids.size() < 2 or _children_of_founders() >= 2:
		return
	if app.household.day < next_conception_day:
		return
	# A resolved birth stays pending until the creator names the baby. Starting
	# another pregnancy then would drop the child who is waiting to come home.
	if bool(app.household.pregnancy.get("active", false)) or bool(app.household.pregnancy.get("pending", false)) or app.household.birth_ready() or str(app.mode) == "creator":
		return
	if LifeBabyPlan.has_baby(app.household.members):
		return
	next_conception_day = int(app.household.day) + 3
	var mother: LifeSim = app.household.member_sim(founder_ids[0])
	var father: LifeSim = app.household.member_sim(founder_ids[1])
	if mother == null or father == null or mother.is_spirit() or father.is_spirit():
		grandchild_blocker = ""
		var reason: String = "A founder had already passed before the household could start a second pregnancy."
		if str(mechanics.get("second_child_blocker", "")) != reason:
			mechanics["second_child_blocker"] = reason
			_log_glitch(int(app.household.day), "", "product", reason)
			print("FAMILY_MECHANIC second_child_blocked day=%d %s" % [app.household.day, reason])
		return
	if str(mother.character.life_stage) != "adult" or str(father.character.life_stage) != "adult":
		return
	if mother.is_away() or father.is_away():
		next_conception_day = int(app.household.day) + 1
		return
	print("FAMILY_MECHANIC second_conception day=%d" % app.household.day)
	await _conceive_pair(mother, father)


func _court_children() -> void:
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		if sim == null or sim.is_spirit() or founder_ids.has(str(member.id)):
			continue
		if str(sim.character.life_stage) != "adult":
			continue
		if not str(sim.romantic_partner).is_empty():
			await _try_grandchild(sim, str(member.id))
			continue
		var resident: String = _opposite_resident(sim)
		if resident.is_empty() or not app.residents.present(resident):
			continue
		if float(sim.needs.hunger) < 40.0 or float(sim.needs.energy) < 28.0 or float(sim.needs.bladder) < 20.0:
			continue
		var relation: Dictionary = sim.relationships.get(resident, {})
		var friendship: float = float(relation.get("friendship", 0.0))
		var romance: float = float(relation.get("romance", 0.0))
		# Flirt adds only a little friendship, so the chat stays friendly until
		# both sides can be asked. Switching at 30 left the friendship stuck
		# under the partnership line.
		var action_id: String = "friendly"
		if friendship >= 45.0 and romance >= 35.0:
			action_id = "ask_partner"
		elif friendship >= 45.0:
			action_id = "flirt"
		if not sim.action_queue.is_empty():
			continue
		var actor: Node = app.world.actors.get(resident)
		if not is_instance_valid(actor):
			continue
		sim.queue_action(action_id, resident, actor.position)
		courted[str(member.id)] = resident
		mechanics["meetings"] = courted.duplicate()
		print("FAMILY_MECHANIC meet child=%s resident=%s action=%s friendship=%.0f romance=%.0f day=%d" % [
			str(sim.character.name), resident, action_id, friendship, romance, app.household.day])


func _try_grandchild(sim: LifeSim, member_id: String) -> void:
	if bool(mechanics.get("grandchild_attempted", false)):
		return
	if bool(app.household.pregnancy.get("active", false)) or LifeBabyPlan.has_baby(app.household.members):
		return
	var partner_id: String = str(sim.romantic_partner)
	var partner_home: bool = false
	for member: Dictionary in app.household.members:
		if str(member.id) == partner_id:
			partner_home = true
	if not partner_home:
		grandchild_blocker = "%s became partners with %s, who does not live in the household. Try for Baby only accepts a household partner, and a neighbor has no move-in." % [str(sim.character.name), partner_id]
		mechanics["grandchild_attempted"] = true
		mechanics["grandchild_blocker"] = grandchild_blocker
		print("FAMILY_MECHANIC grandchild_blocked day=%d %s" % [app.household.day, grandchild_blocker])
		_log_glitch(int(app.household.day), "", "product", grandchild_blocker)
		return
	print("FAMILY_MECHANIC grandchild_conception day=%d pair=%s+%s" % [app.household.day, member_id, partner_id])
	var partner: LifeSim = app.household.member_sim(partner_id)
	if partner != null:
		await _conceive_pair(sim, partner)
	mechanics["grandchild_attempted"] = true


func _opposite_resident(sim: LifeSim) -> String:
	var gender: String = LifeBabyPlan.gender_of(sim.character)
	for resident_id: String in RESIDENTS:
		var frame: int = int(LifeResidentCatalogue.PEOPLE[resident_id].get("frame", 0))
		var resident_gender: String = "male" if frame == 1 else "female"
		if resident_gender != gender:
			return resident_id
	return ""


func _conceive_pair(initiator: LifeSim, partner: LifeSim) -> void:
	var bed: Dictionary = first_item("bed")
	if bed.is_empty():
		_log_glitch(int(app.household.day), "", "product", "No bed, so the couple cannot try for a baby.")
		return
	for member: Dictionary in app.household.members:
		if member.sim.is_away():
			continue
		member.sim.autonomy = false
		member.sim.action_queue.clear()
		member.sim.needs.energy = 20.0
	var pair: Array[LifeSim] = [initiator, partner]
	for person: LifeSim in pair:
		var index: int = _member_index(person)
		if index < 0:
			continue
		app.select_household_member(index)
		app.queue_interaction({"id": str(bed.id), "kind": str(bed.kind), "node": bed.node, "size": bed.size}, "sleep")
	await frames(6)
	for _i: int in range(80):
		app.household.set_speed(8)
		app._process(1.0 / 15.0)
		var both_asleep: bool = true
		for person: LifeSim in pair:
			var action: Dictionary = person.get_current_action()
			if str(action.get("id", "")) != "sleep" or str(action.get("phase", "")) != "active":
				both_asleep = false
				if str(action.get("id", "")) == "sleep" and str(action.get("phase", "")) in ["queued", "approach"]:
					app._bind_member(_id_of(person))
					if is_instance_valid(app.player) and action.has("target_position"):
						app.player.position = Vector3(action.target_position)
					app.household.begin_action(_id_of(person))
		if both_asleep:
			break
	app.household.set_speed(0)
	await frames(4)
	var started: Dictionary = app.household.begin_try_for_baby(_id_of(initiator), str(bed.id))
	if not bool(started.ok):
		var error: String = str(started.get("error", ""))
		print("FAMILY_MECHANIC conceive_refused day=%d %s" % [app.household.day, error])
		if error.contains("household partner") or error.contains("neighbor"):
			grandchild_blocker = error
			mechanics["grandchild_blocker"] = error
		for member: Dictionary in app.household.members:
			member.sim.autonomy = true
		return
	for _j: int in range(10):
		await frames(1)
		for person: LifeSim in pair:
			var beat: Dictionary = person.get_current_action()
			if str(beat.get("id", "")) != LifeBabyPlan.ACTION_ID:
				continue
			if str(beat.get("phase", "")) != "active":
				app._bind_member(_id_of(person))
				if is_instance_valid(app.player) and beat.has("target_position"):
					app.player.position = Vector3(beat.target_position)
				app.household.begin_action(_id_of(person))
	app.household.set_speed(1)
	for _k: int in range(8):
		app.household.tick((LifeBabyPlan.DURATION + 1.0) / LifeSim.GAME_MINUTES_PER_SECOND)
		await frames(1)
	app.household.set_speed(0)
	var conceived: bool = bool(app.household.pregnancy.get("active", false))
	mechanics.conceived = mechanics.conceived or conceived
	print("FAMILY_MECHANIC conceived=%s day=%d" % [str(conceived), app.household.day])
	for member: Dictionary in app.household.members:
		member.sim.autonomy = true


func _id_of(sim: LifeSim) -> String:
	for member: Dictionary in app.household.members:
		if member.sim == sim:
			return str(member.id)
	return ""


func _member_index(sim: LifeSim) -> int:
	for index: int in range(app.household.members.size()):
		if app.household.members[index].sim == sim:
			return index
	return -1


func _children_of_founders() -> int:
	var count: int = 0
	if founder_ids.is_empty():
		return birth_names.size()
	for member: Dictionary in app.household.members:
		if founder_ids.has(str(member.id)):
			continue
		if app.household.family_relationship(founder_ids[0], str(member.id)) == "child":
			count += 1
	return count


func _grandchildren() -> int:
	var count: int = 0
	if founder_ids.is_empty():
		return 0
	for member: Dictionary in app.household.members:
		if app.household.family_relationship(founder_ids[0], str(member.id)) == "grandchild":
			count += 1
	return count


func _note_tree() -> void:
	var rows: Array = []
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		if sim == null:
			continue
		rows.append("%s:%s:%s" % [str(sim.character.name), str(sim.character.age_stage), "spirit" if sim.is_spirit() else "living"])
	tree_log.append({"day": app.household.day, "members": rows, "children": _children_of_founders(), "grandchildren": _grandchildren()})
	if app.household.day % 15 == 0:
		print("FAMILY_TREE day=%d children=%d grandchildren=%d %s" % [app.household.day, _children_of_founders(), _grandchildren(), " | ".join(PackedStringArray(rows))])


func _report_progress(start: Dictionary) -> void:
	var end: Dictionary = _snapshot("end")
	history.append(end)
	var children: int = _children_of_founders()
	var grandchildren: int = _grandchildren()
	if grandchildren < 1 and grandchild_blocker.is_empty():
		grandchild_blocker = "No child reached a household partnership in time. Romantic actions require two adults, Try for Baby requires a household partner, and neighbors do not move in."
		mechanics["grandchild_blocker"] = grandchild_blocker
	var report: Dictionary = {
		"days": days, "start": start, "end": end, "history": history,
		"glitches": glitches, "children": children, "grandchildren": grandchildren,
		"grandchild_blocker": grandchild_blocker, "births": birth_names,
		"founders": founder_ids, "meetings": courted, "tree": tree_log,
		"mechanics": mechanics,
	}
	print("FAMILY_SUMMARY ", JSON.stringify({
		"day": int(end.day), "children": children, "grandchildren": grandchildren,
		"births": birth_names, "blocker": grandchild_blocker, "glitches": glitches.size(),
		"partners": bool(mechanics.partners),
	}))
	var progress: FileAccess = FileAccess.open(screenshot_dir.path_join("family_progress.json"), FileAccess.WRITE)
	if progress != null:
		progress.store_string(JSON.stringify(report, "\t"))
		progress.close()
	var glitch_file: FileAccess = FileAccess.open(screenshot_dir.path_join("glitch_log.json"), FileAccess.WRITE)
	if glitch_file != null:
		glitch_file.store_string(JSON.stringify({"days": days, "glitches": glitches, "blocker": grandchild_blocker}, "\t"))
		glitch_file.close()
	var user_copy: FileAccess = FileAccess.open("user://one_eighty_glitches.json", FileAccess.WRITE)
	if user_copy != null:
		user_copy.store_string(JSON.stringify({"days": days, "glitches": glitches, "blocker": grandchild_blocker}, "\t"))
		user_copy.close()
	check(int(end.day) >= days + 1, "One hundred eighty days really elapsed (%d)." % int(end.day))
	check(bool(mechanics.partners), "The new household starts as partners.")
	check(children >= 2, "The partners have two children (born %d, named %s)." % [children, str(birth_names)])
	for entry: Dictionary in end.members:
		check(not bool(entry.dead) or str(entry.cause) != "hunger",
			"%s did not die of hunger (%s)." % [str(entry.name), str(entry.cause)])
	await press("My Lifelet")
	if is_instance_valid(button_matching("Family tree")):
		await press("Family tree")
		await frames(4)
		await screenshot("180_family_tree")
		await press("Back to life")
	else:
		await screenshot("180_lifelet")
		await press("Back to life")


func _save_family() -> void:
	var expected: Dictionary = {"state": app.sim.get_state(), "player": vec(app.player.position),
		"world": app.world.serialize_items(), "selected_index": app.household.selected_index,
		"lot": app.selected_lot, "floor": app.floor_color, "members": []}
	for member: Dictionary in app.household.members:
		expected.members.append({"id": member.id, "state": member.sim.get_state(),
			"position": vec(app.world.actors[member.id].position)})
	await _public_save("Reed family — one hundred eighty days")
	var file: FileAccess = FileAccess.open("user://one_eighty_expected.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(expected))
	file.close()


func _resume_family() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://one_eighty_expected.json"))
	await _public_load()
	await _compare_saved(expected, "one-eighty-day fresh process")
	check(app.household.members.size() == expected.members.size(), "The fresh process restores every member.")
	var restored: LifeSim = app.household.member_sim(str(expected.members[0].id))
	check(int(restored.day) >= days + 1, "The restored household is still on a late day (%d)." % int(restored.day))
