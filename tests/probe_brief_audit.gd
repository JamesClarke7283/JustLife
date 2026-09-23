extends SceneTree
## Runtime audit of brief items no other suite checks directly: maternity leave
## through the real work gate, the dog's click menu, the pet HUD's Logic bar,
## catalogue prices and variants, and the water and playground age windows.
##
##   JUSTLIFE_DATA_DIR=/tmp/x godot --headless --path . --audio-driver Dummy --script res://tests/probe_brief_audit.gd

var app: Node
var checks: int = 0
var failures: Array[String] = []


func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value: failures.append(message)


func frames(n: int = 2) -> void:
	for i: int in n: await process_frame


func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("This probe needs an isolated JUSTLIFE_DATA_DIR.")
		quit(2); return
	_run.call_deferred()


func _run() -> void:
	_catalogue()
	_acts()
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.selected_lot = 0
	app.start_household()
	await frames(6)
	app.household.set_speed(0)
	_maternity()
	await _dog_menu()
	print("BRIEF_AUDIT %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: print("  FAILED: ", failure)
	app.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)


func _catalogue() -> void:
	for kind: String in ["baby_pram", "pushchair", "baby_car_seat", "child_car_seat"]:
		var data: Dictionary = LifeCatalog.get_item(kind)
		check(int(data.price) == 50 and LifeCatalogVariants.styles(data).size() == 1 and LifeCatalogVariants.colors(data).size() == 10,
			"%s is one style in ten colours at ℒ50." % data.label)
	var curtains: Dictionary = LifeCatalog.get_item("curtains")
	check(int(curtains.price) == 100 and curtains.styles.size() == 10 and curtains.colors.size() == 10, "Curtain sets are ℒ100 in ten styles and ten colours.")
	for kind: String in ["nursery_room_pack", "child_bedroom_pack"]:
		check(int(LifeCatalog.get_item(kind).price) == 2000 and bool(LifeCatalog.get_item(kind).get("room_pack", false)), "%s is a ℒ2000 room pack." % LifeCatalog.get_item(kind).label)
		check(LifeCatalog.room_pack_layout(kind).size() >= 9, "%s furnishes a whole room." % LifeCatalog.get_item(kind).label)
	var paint: Dictionary = LifeCatalog.get_item("nursery_paint")
	check(paint.styles.size() == 5 and paint.colors.size() == 10 and int(paint.rate_per_square_metre) == 5, "Nursery paint: five patterns, ten colours, ℒ5/m².")
	check(LifeBabyPlan.PREGNANCY_MINUTES == 14.0 * LifeBabyPlan.MINUTES_PER_DAY, "A pregnancy lasts fourteen days.")
	check(LifePetCare.MAX_LEVEL == 10, "Pet skills, including tricks (Logic), run from 1 to 10.")


func _acts() -> void:
	check(LifeOutdoorActs.act_error("pool", "child").is_empty() and LifeOutdoorActs.act_error("pool", "teen").is_empty() and LifeOutdoorActs.act_error("pool", "young_adult").is_empty(), "Children, teens and young adults swim.")
	for stage: String in ["child", "young_adult", "adult"]:
		check(LifeOutdoorActs.act_error("hot_tub", stage).is_empty(), "A %s may soak in the hot tub." % stage)
	check(not LifeOutdoorActs.act_error("hot_tub", "adult", false, true, true).is_empty(), "A pregnant Lifelet is refused the hot tub.")
	check(LifeOutdoorActs.act_error("kids_slide", "child").is_empty() and not LifeOutdoorActs.act_error("kids_slide", "adult").is_empty(), "The kids slide is for children.")
	check(LifeOutdoorActs.act_error("adult_slide", "adult").is_empty() and not LifeOutdoorActs.act_error("adult_slide", "child").is_empty(), "The big slide is for teens and up.")
	check(LifeOutdoorActs.act_error("climbing_frame", "child").is_empty(), "Children climb the frame.")
	check(LifeOutdoorActs.can_push("kids_swing"), "A grown-up can push a child on the swings.")
	check(str(LifeOutdoorActs.acts("kids_swing").get("companion", "")) == "friendship", "Children on the swings together build friendship.")
	for kind: String in ["baby_pram", "pushchair"]:
		var changes: Dictionary = LifeOutdoorActs.acts(kind).get("changes", {})
		check(float(changes.get("social", 0)) > 0 and float(changes.get("fun", 0)) > 0, "Pushing the %s fills Social and Fun." % kind)


func _maternity() -> void:
	var sim: LifeSim = app.sim
	var id: String = app.household.selected_id()
	var day: int = int(sim.day)
	while not LifeEducation.weekday(day): day += 1
	sim.day = day; sim.minutes = 600.0
	sim.character.life_stage = "adult"
	sim.career.worked_day = -1
	var schedule: Dictionary = sim.career.get("schedule", LifeCareerSchedule.fresh(day))
	schedule["first_day"] = mini(int(schedule.get("first_day", day)), day)
	sim.career["schedule"] = schedule
	var now: float = LifeBabyPlan.now_of(day, 600.0)
	app.household.pregnancy = {"version": LifeBabyPlan.SAVE_VERSION, "active": true, "pending": false, "mother_id": id, "father_id": id,
		"conceived_at": now - LifeBabyPlan.PREGNANCY_MINUTES + 1.5 * LifeBabyPlan.MINUTES_PER_DAY, "due_at": now + 1.5 * LifeBabyPlan.MINUTES_PER_DAY, "serial": 1, "baby": {}}
	var late: Dictionary = sim.get_action_availability("career_day", "")
	check(not bool(late.available) and str(late.reason).contains("Maternity"), "On pregnancy day 13 the mother cannot go to work (%s)." % str(late.reason))
	app.household.pregnancy.conceived_at = now - 5.0 * LifeBabyPlan.MINUTES_PER_DAY
	app.household.pregnancy.due_at = now + 9.0 * LifeBabyPlan.MINUTES_PER_DAY
	var early: Dictionary = sim.get_action_availability("career_day", "")
	check(not str(early.reason).contains("Maternity"), "Earlier in the pregnancy work is not blocked by maternity leave (%s)." % str(early.reason))
	app.household.pregnancy = LifeBabyPlan.fresh()


func _dog_menu() -> void:
	app.adoption_flow.show_phone(); await frames(3)
	app.pet_shop.show_shop(); await frames(3)
	app.pet_shop.show_species(); await frames(3)
	app.pet_shop.set_species("dog"); await frames(2)
	app.pet_shop.confirm_pet(); await frames(6)
	app.close_overlay()
	var pets: Array = app.household.pets.get("pets", [])
	check(not pets.is_empty(), "A dog joins the household.")
	if pets.is_empty(): return
	var pet_id: String = str(pets[-1].id)
	var labels: Array = app.household.pet_actions(pet_id, app.household.selected_id()).map(func(a: Dictionary) -> String: return str(a.label))
	for wanted: String in ["Feed Dog", "Play with Dog", "Play Tricks", "Take for a Walk", "Tummy rub", "Tug-of-war", "Pet"]:
		check(labels.has(wanted), "Clicking the dog offers %s (%s)." % [wanted, ", ".join(labels)])
	app.show_pet_card(pet_id)
	await frames(2)
	var texts: Array[String] = []
	for label: Label in app.overlay.find_children("*", "Label", true, false): texts.append(label.text.to_lower())
	check(texts.any(func(t: String) -> bool: return t.contains("logic")), "The pet card shows the Logic (tricks) bar.")
	for need: String in ["hunger", "affection", "energy", "bladder"]:
		check(texts.any(func(t: String) -> bool: return t == need), "The pet HUD shows %s." % need)
	var bars: int = app.overlay.find_children("*", "ProgressBar", true, false).size()
	check(bars >= 5, "The pet card draws its need and Logic bars (%d)." % bars)
	app.close_overlay()
