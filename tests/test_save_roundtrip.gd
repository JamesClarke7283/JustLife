extends SceneTree
## A life saved with the newer systems in play must come back from a fresh
## process exactly as it was left. The producer drives the real game into three
## moments and saves each through `save_game`: mid-pregnancy (with a pet that
## knows a trick, home and Baby & Child cover, a bought plot, a nursery wall in
## a patterned paint, a cot, a pram, a car, a coffee's second wind, a chosen
## career and a chosen autosave interval, conceived at a fractional minute), the
## newborn waiting at the hospital, and the newborn home
## with its own needs. A second, fresh process sharing the data dir consumes
## them: it opens each save through the pause menu's picker ("Load selected
## life") and reads back what a player would see, including that no refusal
## notice replaces "Welcome back".
##
##   export JUSTLIFE_DATA_DIR=$(mktemp -d) XDG_DATA_HOME=$(mktemp -d)
##   godot --headless --path . --audio-driver Dummy --script res://tests/test_save_roundtrip.gd
##   ROUNDTRIP_PHASE=consume godot --headless --path . --audio-driver Dummy --script res://tests/test_save_roundtrip.gd

const Properties = preload("res://scripts/properties.gd")
const Land = preload("res://scripts/land.gd")
const SAVES: Array[String] = ["Roundtrip pregnancy", "Roundtrip hospital", "Roundtrip newborn"]
const BABY_NEEDS: Dictionary = {"hunger": 37.5, "energy": 61.25, "hygiene": 44.0, "fun": 72.5}

var app: Node
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _initialize() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("The round-trip test requires an isolated JUSTLIFE_DATA_DIR.")
		quit(2); return
	_run.call_deferred()

func _expect_path() -> String:
	return OS.get_environment("JUSTLIFE_DATA_DIR").path_join("roundtrip_expect.json")

func _finish(phase: String) -> void:
	if is_instance_valid(app): app.queue_free()
	await frames(2)
	print("ROUNDTRIP_RESULT ", JSON.stringify({"phase": phase, "checks": checks, "failures": failures}))

func _run() -> void:
	if OS.get_environment("ROUNDTRIP_PHASE") == "consume":
		await _consume()
		await _finish("consume")
		quit(0 if failures.is_empty() else 1); return
	await _produce()
	await _finish("produce")
	quit(0 if failures.is_empty() else 1)

# ----------------------------------------------------------------- producer

func _baby_id() -> String:
	for member: Dictionary in app.household.members:
		if str(member.sim.character.age_stage) == "baby": return str(member.id)
	return ""

func _find_kind(kind: String) -> Dictionary:
	for entry: Dictionary in app.world.serialize_items():
		if str(entry.get("kind", "")) == kind: return entry
	return {}

func _spot(kind: String, style: String = "", size: String = "") -> Vector3:
	for radius: int in range(0, 40):
		for x: int in range(-radius, radius + 1):
			for z: int in range(-radius, radius + 1):
				if maxi(abs(x), abs(z)) != radius: continue
				var at := Vector3(float(x) * .5, .16, float(z) * .5)
				if app.world.can_place(kind, at, 0.0, style, size): return at
	return Vector3.INF

func _notice() -> String:
	return str(app.notice_label.text) if is_instance_valid(app.notice_label) else ""

func _save(title: String) -> bool:
	var saved: bool = app.save_game("", title)
	if not saved: print("Save refused: ", _notice())
	return saved

func _conceive(owner_id: String, father_id: String, days_along: float) -> void:
	# The household's own conception writes this record and advances the counter.
	var household: LifeHousehold = app.household
	household.pregnancy = LifeBabyPlan.conceive(household.member_sim(owner_id), owner_id,
		household.member_sim(father_id), father_id, household.day, household.minutes, household.birth_serial)
	household.birth_serial = mini(int(household.pregnancy.serial) + 1, LifeBabyPlan.MAX_BIRTHS)
	var now: float = LifeBabyPlan.now_of(household.day, household.minutes)
	household.pregnancy.conceived_at = now - days_along * LifeBabyPlan.MINUTES_PER_DAY
	household.pregnancy.due_at = float(household.pregnancy.conceived_at) + LifeBabyPlan.PREGNANCY_MINUTES

func _produce() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.household_profiles = [
		{"name": "Avery Stone", "age_stage": "young_adult", "traits": [], "hair": 0, "gender": "female"},
		{"name": "River Stone", "age_stage": "young_adult", "traits": [], "hair": 0, "gender": "male"}]
	app.creator_family_links = []
	app.selected_lot = 0
	app.start_household(); await frames(10)
	app.household.set_speed(0)
	app.household.set_funds(200000)
	var owner_id: String = str(app.household.selected_id())
	var father_id: String = "housemate_1"
	var expect: Dictionary = {"owner": owner_id, "father": father_id}

	# Settings, a coffee's second wind and a career.
	app.autosave_minutes = 15
	app.sim.second_wind = 21.5
	check(app.sim.choose_career("barista"), "The selected Lifelet takes a coffee-shop career.")
	expect.career = str(app.sim.career.track)

	# A dog that has really learned a trick through the household's lesson.
	var review: Dictionary = LifePets.candidate(int(app.household.pets.next_serial), 0)
	review.species = "dog"; review.sex = "male"; review.name = "Bramble"
	var prepared: Dictionary = app.household.prepare_pet(review)
	check(bool(prepared.get("ok", false)), "The dog review prepares (%s)." % str(prepared.get("error", "")))
	if bool(prepared.get("ok", false)):
		var spawn: Vector3 = app.world.lot_exit_position(app.household.members.size())
		var committed: Dictionary = app.household.commit_pet(prepared.request, spawn)
		check(bool(committed.get("ok", false)), "The dog comes home (%s)." % str(committed.get("error", "")))
		if bool(committed.get("ok", false)):
			var dog: String = str(committed.pet.id)
			app.spawn_pet(dog, committed.pet, spawn, app.pet_arrival_destination(spawn))
			var trick: String = ""
			for session: int in range(LifePets.TRICK_SESSIONS):
				trick = str(app.household_flow.teach_pet_trick(dog, "Avery Stone").get("trick", ""))
			check((app._pet_record(dog).get("tricks", []) as Array).has(trick), "The dog learned a trick (%s)." % trick)
			expect.pet = {"id": dog, "trick": trick}

	# Home cover and Baby & Child cover through the property panel's own buttons.
	var funds_before: int = app.household.funds
	app._buy_property_policy("home"); await frames(2)
	app._buy_property_policy("baby"); await frames(2)
	app.close_overlay(false)
	var house_id: String = Properties.active(app.properties)
	check(app.household.funds == funds_before - 1100, "Home (ℒ600) and Baby & Child (ℒ500) cover are each charged once (ℒ%d -> ℒ%d)." % [funds_before, app.household.funds])
	check(Properties.policy(app.properties, house_id).get("id", "") == "home" and str(Properties.house(app.properties, house_id).get("baby_policy", "")) == "baby",
		"The home carries both policies before saving.")
	expect.house = house_id

	# Build & buy: a bought plot, nursery paint, a cot, a pram and a car.
	app.set_build_mode(true); await frames(4)
	var bought: Dictionary = app.build_transactions.buy_land("west")
	check(bool(bought.get("ok", false)), "A western plot is bought (%s)." % str(bought.get("error", "")))
	expect.plots = Land.plots(LifeBuildingState.land)
	expect.lot_width = LifeBuildingState.lot().size.x

	var nursery: Dictionary = LifeCatalog.get_item("nursery_paint")
	var pattern: String = str(LifeCatalogVariants.styles(nursery)[2])
	var colour: String = str(LifeCatalogVariants.colors(nursery)[1])
	var painted_id: String = ""
	app.begin_construction("paint")
	app.world.construction.paint_palette = "nursery"
	app.world.construction.paint_pattern = pattern
	app.world.construction.paint_material = colour
	app.world.construction.paint_scope = "wall"
	for wall: Dictionary in app.world.construction.records.duplicate(true):
		if int(wall.get("level", 0)) != 0 or maxf(float(wall.w), float(wall.d)) < 2.0: continue
		var proposal: Dictionary = app.world.construction.click(Vector3(float(wall.x), .16, float(wall.z)))
		if proposal.has("error") or not bool(proposal.get("valid", false)): continue
		app.on_construction(proposal); await frames(2)
		for after: Dictionary in app.world.construction.building_state.get("walls", []):
			if str(after.get("pattern", "")) == pattern and str(after.material) == colour: painted_id = str(after.id)
		if not painted_id.is_empty(): break
	app.world.construction.cancel()
	check(not painted_id.is_empty(), "A wall takes the %s nursery pattern in colour %s." % [pattern, colour])
	expect.paint = {"id": painted_id, "pattern": pattern, "colour": colour}

	var cot_at: Vector3 = _spot("cot")
	if cot_at.is_finite(): app.on_placement("cot", cot_at, 0.0); await frames(3)
	check(not _find_kind("cot").is_empty(), "A Baby & Kids cot is placed.")
	var pram_at: Vector3 = _spot("baby_pram")
	if pram_at.is_finite(): app.on_placement("baby_pram", pram_at, 0.0); await frames(3)
	check(not _find_kind("baby_pram").is_empty(), "A baby pram is placed.")
	var car_at: Vector3 = _spot("car", "estate", "medium")
	if car_at.is_finite(): app.on_placement("car", car_at, 0.0, "estate", "medium"); await frames(3)
	check(not _find_kind("car").is_empty(), "An estate car is parked on the lot.")
	var records: Dictionary = {}
	for kind: String in ["cot", "baby_pram", "car"]:
		var entry: Dictionary = _find_kind(kind)
		if not entry.is_empty(): records[kind] = entry
	expect.items = records
	app.set_build_mode(false); await frames(4)
	app.household.set_speed(0)

	# ------------------------------------------------------ 1: mid-pregnancy
	# Three weeks into the life at a fractional minute, as a played clock is: at
	# this moment `conceived_at + term - conceived_at` is not exactly the term.
	var clock_day: int = 22
	var clock_minutes: float = 480.0 + 1.0 / 64.0 + 1.0 / 3.0
	app.household.day = clock_day
	app.household.minutes = clock_minutes
	for member: Dictionary in app.household.members:
		var sim: LifeSim = member.sim
		sim.day = clock_day
		sim.minutes = clock_minutes
		sim.career.schedule = LifeCareerSchedule.advance(sim.career.schedule, clock_day, int(sim.career.worked_day), false).state
	_conceive(owner_id, father_id, 6.0)
	expect.progress = app.household.pregnancy_progress()
	expect.baby_name = str(app.household.pregnancy.baby.name)
	check(expect.progress > .4 and expect.progress < .45, "The pregnancy is mid-term (%.3f)." % expect.progress)
	check(_save(SAVES[0]), "A mid-pregnancy life saves.")
	var written: Dictionary = LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(written.get("ok", false)) and (written.data as Dictionary).has("journeys"),
		"The edited home is saved in the physical journey format, so the load takes the prepared-world path (%s, %s)." % [str(written.get("error", "")), str((written.get("data", {}) as Dictionary).get("household_version", ""))])

	# ---------------------------------------------- 2: newborn at the hospital
	app.household.pregnancy.due_at = LifeBabyPlan.now_of(app.household.day, app.household.minutes)
	app.household.set_speed(3)
	var guard: int = 0
	while not app.household.birth_ready() and guard < 60000:
		app._process(.2)
		guard += 1
		if guard % 50 == 0: await process_frame
	check(app.household.birth_ready(), "The pregnancy reaches its birth.")
	var pending: Dictionary = app.household.pending_baby_profile().duplicate(true)
	pending.age_stage = "baby"; pending.life_stage = "minor"
	app.profile = pending
	app.creator_purpose = "baby"
	app.confirm_baby_creator(); await frames(8)
	var baby_id: String = _baby_id()
	if baby_id.is_empty(): print("Baby creator: ", _notice(), " mode=", app.mode, " members=", app.household.members.size(), " ready=", app.household.birth_ready())
	check(not baby_id.is_empty() and bool(app.household.birth_homecoming.get("active", false)) and app.household.member_sim(baby_id).is_away(),
		"The newborn is a member waiting at the hospital.")
	app.household.set_speed(0)
	expect.baby = baby_id
	check(_save(SAVES[1]), "A life saved while the newborn is at the hospital saves.")

	# ------------------------------------------------------ 3: newborn at home
	app._choose_birth_dad(LifeBirthHomecoming.DAD_NOTIFY)
	app.welcome_baby_home()
	guard = 0
	while not app.birth_arrival.is_empty() and guard < 800:
		app._process(.2)
		guard += 1
		if guard % 20 == 0: await process_frame
	if not app.birth_arrival.is_empty():
		app.household.finish_welcome_baby_home()
		app._sync_all_away_presence()
		app._end_birth_arrival_cinematic()
	await frames(4)
	app.household.set_speed(0)
	var baby: LifeSim = app.household.member_sim(baby_id)
	check(baby != null and not baby.is_away(), "Welcome Baby Home brings the newborn onto the lot.")
	if baby != null:
		for need: String in BABY_NEEDS: baby.needs[need] = float(BABY_NEEDS[need])
		expect.infant_phase = str(baby.character.get("infant_phase", ""))
	expect.supplies = app.household.baby_supplies.duplicate(true)
	check(_save(SAVES[2]), "A life saved with the newborn at home saves.")

	var file: FileAccess = FileAccess.open(_expect_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(expect)); file.close()

# ----------------------------------------------------------------- consumer

func _press(text: String) -> bool:
	for node: Node in app.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree() and not node.disabled:
			node.pressed.emit(); return true
	return false

func _load_through_picker(title: String) -> bool:
	var slot: String = ""
	for entry: Dictionary in LifeSaveLibrary.list_saves():
		if str(entry.get("name", "")) == title:
			slot = str(entry.id)
			check(bool(entry.get("valid", false)), "The picker lists \"%s\" as loadable (%s)." % [title, str(entry.get("error", ""))])
	check(not slot.is_empty(), "\"%s\" is in the save picker." % title)
	if slot.is_empty(): return false
	if app.has_active_game:
		app.show_menu(); await frames(2)
		check(_press("Load a saved life"), "The pause menu opens the saved lives.")
		await frames(2)
	app.menus.show_picker("load", slot); await frames(2)
	var replacing: bool = app.has_active_game
	check(_press("Load selected life  →"), "\"Load selected life\" is enabled for \"%s\"." % title)
	if replacing: check(_press("Continue without saving"), "Replacing the open life asks first and can continue without saving.")
	var notice: String = _notice()
	check(notice.begins_with("Welcome back"), "\"%s\" loads without a refusal notice (\"%s\")." % [title, notice])
	for i: int in 30: await process_frame
	check(app.active_save_id == slot, "\"%s\" is the life now being played." % title)
	return app.active_save_id == slot

func _consume() -> void:
	var file: FileAccess = FileAccess.open(_expect_path(), FileAccess.READ)
	check(file != null, "The producer left its expectations.")
	if file == null: return
	var expect: Dictionary = JSON.parse_string(file.get_as_text())
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)

	# ------------------------------------------------------ 1: mid-pregnancy
	if await _load_through_picker(SAVES[0]):
		var household: LifeHousehold = app.household
		check(bool(household.pregnancy.get("active", false)) and str(household.pregnancy.mother_id) == str(expect.owner),
			"The pregnancy is still running for the same mother.")
		check(absf(household.pregnancy_progress() - float(expect.progress)) < .001,
			"Pregnancy progress round-trips (%.4f vs %.4f)." % [household.pregnancy_progress(), float(expect.progress)])
		check(str(household.pregnancy.baby.get("name", "")) == str(expect.baby_name), "The rolled baby is the same child after the load.")
		check(str(app.sim.career.track) == str(expect.career), "The career round-trips (%s)." % str(app.sim.career.track))
		check(app.autosave_minutes == 15, "The autosave interval round-trips (%d)." % app.autosave_minutes)
		check(app.sim.second_wind > 0.0, "A coffee's second wind is still there after the load (%.2f)." % app.sim.second_wind)
		var pet: Dictionary = household.pet_record(str(expect.get("pet", {}).get("id", "")))
		check(not pet.is_empty() and (pet.get("tricks", []) as Array).has(str(expect.pet.trick)),
			"The dog and its learned trick round-trip (%s)." % str(pet.get("tricks", [])))
		check(is_instance_valid(app.pet_actors.get(str(expect.pet.id))), "The dog has a body on the lot again.")
		var house_id: String = str(expect.house)
		check(Properties.active(app.properties) == house_id and Properties.count(app.properties) == 1,
			"The owned home round-trips (%s, %d owned)." % [Properties.active(app.properties), Properties.count(app.properties)])
		check(Properties.policy(app.properties, house_id).get("id", "") == "home", "Home insurance on the house round-trips.")
		check(str(Properties.house(app.properties, house_id).get("baby_policy", "")) == "baby", "Baby & Child Insurance on the house round-trips.")
		check(str(app.sim.insurance_policy_id) == "home", "The Lifelets are covered by the house's policy after the load.")
		check(Land.plots(LifeBuildingState.land) == int(expect.plots) and is_equal_approx(LifeBuildingState.lot().size.x, float(expect.lot_width)),
			"The bought plot round-trips (%d plots, %.1f m wide)." % [Land.plots(LifeBuildingState.land), LifeBuildingState.lot().size.x])
		var wall: Dictionary = {}
		for entry: Dictionary in app.world.construction.building_state.get("walls", []):
			if str(entry.id) == str(expect.paint.id): wall = entry
		check(str(wall.get("pattern", "")) == str(expect.paint.pattern) and str(wall.get("material", "")) == str(expect.paint.colour),
			"The nursery wall keeps its pattern and colour (%s, %s)." % [str(wall.get("pattern", "")), str(wall.get("material", ""))])
		var live: Array = app.world.serialize_items()
		for kind: String in (expect.get("items", {}) as Dictionary):
			var saved: Dictionary = expect.items[kind]
			var found: Dictionary = {}
			for entry: Dictionary in live:
				if str(entry.get("id", "")) == str(saved.id): found = entry
			var same: bool = not found.is_empty()
			for key: String in ["kind", "style", "color", "size", "paint"]:
				if saved.has(key) and str(found.get(key, "")) != str(saved[key]): same = false
			check(same and Vector2(float(found.get("x", 0)), float(found.get("z", 0))).distance_to(Vector2(float(saved.x), float(saved.z))) < .01,
				"The %s round-trips with its place and finish (%s)." % [kind, str(found)])

	# ---------------------------------------------- 2: newborn at the hospital
	if await _load_through_picker(SAVES[1]):
		var household: LifeHousehold = app.household
		var baby: LifeSim = household.member_sim(str(expect.baby))
		check(baby != null and str(baby.character.age_stage) == "baby", "The newborn is a household member after the load.")
		check(bool(household.birth_homecoming.get("active", false)) and str(household.birth_homecoming.get("baby_id", "")) == str(expect.baby),
			"The hospital homecoming is still waiting after the load.")
		check(baby != null and baby.is_away() and household.member_sim(str(expect.owner)).is_away(), "Mother and newborn are still at the hospital.")
		check(not bool(household.pregnancy.get("active", false)) and not household.birth_ready(), "The birth is not repeated after the load.")
		var chosen: Dictionary = household.choose_birth_dad(LifeBirthHomecoming.DAD_NOTIFY)
		check(bool(chosen.get("ok", false)) and LifeBirthHomecoming.can_welcome(household.birth_homecoming), "Welcome Baby Home can still be reached from the loaded save.")

	# ------------------------------------------------------ 3: newborn at home
	if await _load_through_picker(SAVES[2]):
		var household: LifeHousehold = app.household
		var baby: LifeSim = household.member_sim(str(expect.baby))
		check(baby != null and not baby.is_away() and not bool(household.birth_homecoming.get("active", false)), "The newborn is home after the load.")
		if baby != null:
			for need: String in BABY_NEEDS:
				check(is_equal_approx(float(baby.needs[need]), float(BABY_NEEDS[need])), "The baby's %s need round-trips (%.2f)." % [need, float(baby.needs[need])])
			check(str(baby.character.get("infant_phase", "")) == str(expect.infant_phase), "The infant stage round-trips (%s)." % str(baby.character.get("infant_phase", "")))
			check(is_instance_valid(app.world.actors.get(str(expect.baby))) and app.world.actors[str(expect.baby)].visible, "The newborn has a visible body on the lot.")
		check(household.baby_supplies == expect.supplies or (int(household.baby_supplies.bottles) == int(expect.supplies.bottles) and int(household.baby_supplies.food) == int(expect.supplies.food)),
			"The baby supplies round-trip (%s)." % str(household.baby_supplies))
