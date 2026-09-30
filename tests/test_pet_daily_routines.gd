extends SceneTree
var app: Node
var checks: int = 0
var failures: Array[String] = []
var cat_id: String = "routine_cat"
var dog_id: String = "routine_dog"
var tray: Dictionary
var door_opened: bool = false
var saw_squat: bool = false
var saw_leg: bool = false
var walk_street: bool = false
var walk_clip: bool = false
var walk_open: bool = false
var max_lead: float = 0.0
var min_lead: float = 1000.0
var walk_completed: bool = false
var knee_bent: bool = false
var leash_visible: bool = false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, why: String) -> void:
	checks += 1; print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)
func frames(n: int=3) -> void:
	for i: int in n: await process_frame
func button_named(label: String) -> Button:
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node.text == label: return node
	return null
func fixture_pet(id: String, species: String, at: Vector3) -> void:
	var choice: Dictionary
	for i: int in LifePets.candidate_count():
		var candidate: Dictionary = LifePets.candidate(1, i)
		if str(candidate.species) == species: choice = candidate; break
	var pet: Dictionary = LifePets.record_from(choice, id, 1)
	app.household.pets.pets.append(pet)
	app.spawn_pet(id, pet, at, at)
	for need: String in LifePetCare.NEED_NAMES: app.household.pet_care(id).needs[need] = 90.0
func drive(limit: int, mode: String) -> void:
	app.household.set_speed(8)
	for i: int in limit:
		app._process(.05)
		var cat: LifePetActor = app.pet_actors[cat_id]
		var dog: LifePetActor = app.pet_actors[dog_id]
		for door: Dictionary in app.world.construction.doors.doors.values():
			if float(door.progress) > .9:
				if mode == "litter": door_opened = true
				if mode == "walk": walk_open = true
		if cat.behavior == "toilet_cat" and absf(cat._legs[2].rotation.x) > .2: saw_squat = true
		if dog.behavior == "toilet_dog" and absf(dog._legs[3].rotation.z) > .4: saw_leg = true
		if mode == "walk":
			var state: Dictionary = app.care_motion().walker.walks.get(app.household.selected_id(), {})
			if not state.is_empty():
				walk_clip = walk_clip or app.care_motion().walker.phase(app.household.selected_id()) == "clip"
				if app.care_motion().walker.phase(app.household.selected_id()) == "clip": knee_bent = knee_bent or absf(app.player._joints["Shin_R"].rotation.x) > .4
				if is_instance_valid(app.player._care_props): leash_visible = leash_visible or app.player._care_props._leash.visible
				max_lead = maxf(max_lead, app.player.position.distance_to(dog.position))
				min_lead = minf(min_lead, app.player.position.distance_to(dog.position))
			walk_street = walk_street or (app.player.position.z > 7.0 and dog.position.z > 7.0)
		if i % 10 == 0: await process_frame
		if mode == "litter" and int(app.household_flow.litter.get(str(tray.id),0)) > 0 and app._pet_errand(cat_id).is_empty(): break
		if mode == "outside" and float(app.household.pet_care(dog_id).needs.bladder) > 90 and app._pet_errand(dog_id).is_empty(): break
		if mode == "clean" and app.sim.get_current_action().is_empty(): break
		if mode == "walk" and app.sim.get_current_action().is_empty(): break
	app.household.set_speed(0)
func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app); current_scene=app
	await frames(5)
	print("PET_ROUTINES scene ready")
	app.set_sound(false); app.new_game(); app.start_household(); await frames(5)
	print("PET_ROUTINES household ready")
	app.set_process(false); app.household.set_speed(0); app.sim.autonomy=false
	for item: Dictionary in app.world.items: item.node.queue_free()
	app.world.items.clear()
	await frames()
	app.world.add_item({"id":"routine_tray","kind":"litter_tray","x":3.5,"z":-3.0,"rotation":0.0,"level":0},false)
	app.world.rebuild_navigation();app._refresh_sim_targets(false)
	tray=app._find_item("routine_tray")
	check(not tray.is_empty(),"Real litter tray exists in enclosed bathroom")
	if tray.is_empty():
		app.queue_free();await frames();quit(1);return
	app.player.position=Vector3(-3,.16,2)
	fixture_pet(cat_id,"cat",Vector3(0,.16,1))
	fixture_pet(dog_id,"dog",Vector3(-3,.16,4))
	app._refresh_pet_targets()
	app.on_object_clicked(tray,Vector2(700,400));await frames()
	var use: Button=button_named("Use")
	check(is_instance_valid(use) and not use.disabled,"Litter tray exposes an enabled real Use button")
	if is_instance_valid(use): use.pressed.emit()
	check(str(app._pet_errand(cat_id).get("target",""))==str(tray.id),"Use dispatch selects this exact tray for the cat")
	await drive(2200,"litter")
	check(door_opened,"Cat reaches bathroom via opening real doors")
	check(saw_squat,"Cat physically enters tray and performs a squat pose")
	check(float(app.household.pet_care(cat_id).needs.bladder)>85 and int(app.household_flow.litter.get(str(tray.id),0))==1,"Completed use restores bladder and dirties only the used tray")
	for stage: String in ["baby","child","teen","young_adult","adult","elder"]:
		var sim:=LifeSim.new();root.add_child(sim);sim.new_household({"name":"Cleaner","age_stage":stage});sim.household_service=app.household_flow
		sim.register_targets(app.world.simulation_targets())
		var allowed: bool = stage in ["teen","young_adult","adult"]
		check(bool(sim.get_action_availability("clean_litter_tray",str(tray.id)).available)==allowed,"Cleaning admission matches exact age "+stage)
		if not allowed:check(not sim.queue_action("clean_litter_tray",str(tray.id),app.world.approach(tray)),"Direct queue cannot bypass cleaning age "+stage)
		sim.free()
	app.household_flow.litter["sold_tray"]=1
	var saved: Dictionary=app.household_flow.get_state();app.household_flow.restore(saved)
	check(not saved.litter.has("sold_tray"),"Sold litter trays cannot accumulate invalid saved entries")
	check(LifeHouseholdFlow.validate(saved,app.world.serialize_items()).is_empty(),"Used litter extras satisfy the real save validator")
	check(int(app.household_flow.litter.get(str(tray.id),0))==1,"Used litter persists through household extras restore")
	app.on_object_clicked(tray,Vector2(700,400));await frames()
	var clean:Button=button_named("Clean Litter Tray")
	check(is_instance_valid(clean) and not clean.disabled,"Eligible Lifelet sees the real cleaning button")
	if is_instance_valid(clean):clean.pressed.emit()
	await drive(2200,"clean")
	check(int(app.household_flow.litter.get(str(tray.id),0))==0,"Lifelet walks to tray and completes cleaning")
	app.pet_behavior().command(cat_id,"pet_free")
	app.household.pet_care(cat_id).needs.bladder=10
	app.household.set_speed(8);app._process(.05);app.household.set_speed(0)
	check(str(app._pet_errand(cat_id).get("action",""))=="relieve","Low bladder autonomously chooses the clean litter tray")
	await drive(1800,"litter")
	check(float(app.household.pet_care(cat_id).needs.bladder)>85,"Autonomous litter use physically completes and restores bladder")
	app.pet_actors[cat_id].position=Vector3(5,.16,-4)
	app.household.pet_care(dog_id).needs.bladder=10
	check(bool(app.pet_behavior().command(dog_id,"relieve_outside").ok),"Dog accepts an outdoor toilet command")
	await drive(2200,"outside")
	check(saw_leg,"Dog raises a hind leg during outdoor toilet break")
	check(float(app.household.pet_care(dog_id).needs.bladder)>85 and not app.world.construction.floor_contains(Vector2(app.pet_actors[dog_id].position.x,app.pet_actors[dog_id].position.z),0),"Dog bladder recovers outdoors")
	app.pet_behavior().command(dog_id,"pet_free")
	app.pet_actors[dog_id].position=Vector3(-1,.16,2)
	app.player.position=Vector3(-2,.16,2)
	var resumed: Array = app.care_motion().walker._destinations(Vector3(0,.16,8))
	check(not resumed.is_empty() and app.world.construction.floor_contains(Vector2(resumed[-1].x,resumed[-1].z),0),"A street-resumed walk ends safely inside the front door")
	app.sim.action_finished.connect(func(action:Dictionary):
		if str(action.id)=="pet_walk":walk_completed=true)
	app.show_pet_card(dog_id,true);await frames()
	check(app.household.speed==0,"Inspecting needs preserves player's current pause state")
	var walk:Button=app.overlay.find_child("PetCare_pet_walk",true,false)
	check(is_instance_valid(walk) and not walk.disabled,"Dog card exposes a real enabled walk button")
	if is_instance_valid(walk):walk.pressed.emit()
	await drive(4000,"walk")
	print("WALK_DIAGNOSTIC ",app.player.position," dog=",app.pet_actors[dog_id].position," phase=",app.care_motion().walker.walks," notice=",app.notice_text)
	check(walk_clip and knee_bent and leash_visible,"Walk bends an actual knee and renders the attached lead")
	check(walk_open and walk_street,"Lifelet and dog physically cross front door and reach street together")
	check(max_lead<2.5 and min_lead>=.70,"Walking pair stays within a short lead (max %.2fm)"%max_lead)
	check(walk_completed and app.sim.get_current_action().is_empty() and app.player.position.distance_to(Vector3(-1.75,.16,2))<2.5,"Walk completes after physically returning home")
	app.household.set_speed(8)
	app.show_pet_card(dog_id);await frames()
	check(app.household.speed==8,"Inspecting the pet does not pause free-running simulation")
	var free:Button=app.overlay.find_child("PetFreeWill",true,false)
	check(is_instance_valid(free),"Needs inspection offers explicit Free Will control")
	if is_instance_valid(free):free.pressed.emit()
	check(app.selected_pet_id.is_empty() and not app.care_motion().holds(dog_id),"Free Will releases control and paired holds")
	print("PET_DAILY_ROUTINES ",checks," checks ",failures.size()," failures")
	app.queue_free();await frames();quit(0 if failures.is_empty() else 1)
