extends SceneTree
## Actual world input, immediate command interruption, skill effects and save compatibility.
var app: Node
var checks: int = 0
var failures: Array[String] = []
var dog: String = "pet_1"
var controller: RefCounted
func _initialize() -> void: run.call_deferred()
func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)
func frames(count: int = 2) -> void:
	for n: int in count: await process_frame
func click(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at; event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down
		root.push_input(event, true)
		await frames()
func step(count: int = 1) -> void:
	for n: int in count:
		controller.tick(.1, 1.0)
		app.pet_actors[dog].animate(.1, bool(app.pet_errands.get(dog, {}).get("walking", false)), 1.0)
func reach(at: Vector3, limit: int = 600) -> bool:
	for n: int in limit:
		if app.pet_actors[dog].position.distance_to(at) < .12: return true
		step()
	return false
func item(kind: String, at: Vector3, id: String) -> Dictionary:
	app.world.add_item({"id":id,"kind":kind,"x":at.x,"z":at.z,"level":0,"rotation":0.0}, false)
	return controller._item(id)
func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app); current_scene = app
	await frames(4)
	app.selected_lot = 0; app.start_household(); await frames(4)
	app.set_process(false); app.world.set_process(false); app.household.set_speed(0); app.sound_enabled = false
	for member: Dictionary in app.household.members: member.sim.autonomy = false
	var record: Dictionary = LifePets.record_from(LifePets.candidate(1, 1), dog, 1)
	app.household.pets.pets.append(record); app.household.pets.next_serial = 2
	var origin := Vector3(-8, .16, 4)
	app.spawn_pet(dog, record, origin, origin); app.pet_arrivals.clear()
	controller = app.pet_behavior()
	controller.idle_minutes[dog] = -1000.0
	var actor: LifePetActor = app.pet_actors[dog]
	var care: Dictionary = app.household.pet_care(dog)
	for need: String in LifePetCare.NEED_NAMES: care.needs[need] = 90.0
	var bowl: Dictionary = item("pet_bowl", Vector3(-8, .16, 2), "training_bowl")
	app.world.rebuild_navigation()
	check(bool(controller.command(dog,"pet_eat").ok), "Dog begins eating route")
	for n: int in 400:
		step()
		if actor.behavior == "eat": break
	check(actor.behavior == "eat", "Fixture reaches real bowl eating pose")
	# The card's world backdrop must dispatch the SAME physical floor click.
	app.show_pet_card(dog)
	await frames()
	var destination := Vector3(-10, .16, 4)
	var screen: Vector2 = app.world.camera.unproject_position(destination)
	# Move the camera so this point is in the open left strip outside the card.
	var desired: Vector2 = app.overlay.get_global_transform_with_canvas() * Vector2(360, 430)
	var ground: Vector3 = app.world.floor_point(desired)
	app.world.camera_target += destination - ground; app.world.update_camera()
	screen = app.world.camera.unproject_position(destination)
	await click(screen)
	check(not app.overlay_open and str(controller.state(dog).action)=="pet_move", "One real floor click through the open card immediately replaces eating")
	check(actor.behavior != "eat", "Move clears the eating pose immediately")
	check(reach(destination), "Dog reaches the clicked floor")
	# Tool -> dog -> Point & Move is separate from direct selection.
	app.show_pet_card(dog);await frames()
	var tool: Button = app.ui.find_child("LifeletPetTool",true,false)
	await click(tool.get_global_transform_with_canvas() * (tool.size * .5))
	check(app.pet_lifelet_tool_active and not app.overlay_open, "Lifelet tool remains clickable through the open dog card")
	app.on_object_clicked({"id":dog,"kind":"pet"},Vector2.ZERO)
	await frames()
	check(app.overlay.find_child("PetPointAndMove",true,false)!=null and app.overlay.find_child("PetMoveOutOfWay",true,false)!=null, "Lifelet tool opens both movement commands")
	app._lifelet_pet_command(dog,"point")
	check(app.pet_move_director == app.bound_member_id and not app.overlay_open, "Point & Move arms the selected Lifelet and waits for a floor point")
	app.on_ground_clicked(origin)
	check(reach(origin), "Lifelet Point & Move sends dog to the point")
	controller.command(dog,"pet_eat")
	for n: int in 400:
		step()
		if actor.behavior == "eat": break
	var before_clear: float = actor.position.distance_to(bowl.node.position)
	app._lifelet_pet_command(dog,"clear")
	var clear_goal: Vector3 = app.pet_errands.get(dog,{}).get("at",Vector3.INF)
	check(clear_goal.is_finite() and reach(clear_goal) and actor.position.distance_to(bowl.node.position)>before_clear+.4, "Move Out of the Way leaves the bowl and reaches clear space")
	# A Lifelet feeding session cannot reclaim the dog after an explicit move.
	var member_id: String = app.bound_member_id
	app.sim.action_queue.clear()
	app.sim.action_queue.append({"id":"pet_feed","target_id":dog,"phase":"active"})
	app.care_motion().sessions[member_id] = {"pet":dog,"action":"pet_feed","time":1.0}
	actor.set_interaction("pet_feed",2.0,app.player.position)
	check(bool(controller.command(dog,"pet_move",origin).ok) and not app.care_motion().holds(dog) and app.sim.action_queue.is_empty() and actor.interaction.is_empty(), "Direct move releases and cancels active Lifelet feeding")
	check(reach(origin), "Dog remains under direct control after feeding was interrupted")
	app.autosave_minutes = 0
	app.household.set_speed(1)
	var training_before: float = LifePetCare.xp(care,"logic")
	app._queue_pet_action(dog,"pet_train_logic")
	check(not app.sim.action_queue.is_empty() and str(app.sim.action_queue[0].id)=="pet_train_logic", "Logic training enters the real Lifelet activity queue")
	for n: int in 1000:
		app._process(.1)
		if app.sim.action_queue.is_empty(): break
	app.household.set_speed(0)
	check(LifePetCare.xp(care,"logic")>training_before, "Timed Lifelet logic lesson reaches the dog and awards progress on completion")
	# All three subjects train through household policy and cap at 10.
	for pair: Array in [["tricks","pet_teach_trick"],["social","pet_train_social"],["logic","pet_train_logic"]]:
		var old_xp: float = LifePetCare.xp(care,pair[0])
		var old_level: int = LifePetCare.level(care,pair[0])
		check(bool(app.household.do_pet_interaction(dog,member_id,pair[1]).ok) and (LifePetCare.xp(care,pair[0])>old_xp or LifePetCare.level(care,pair[0])>old_level), "%s lesson earns pet experience" % pair[0])
		LifePetCare.gain_xp(care,pair[0],100000)
		check(LifePetCare.level(care,pair[0])==10 and LifePetCare.xp(care,pair[0])==0, "%s caps at level 10" % pair[0])
	var novice: Dictionary = LifePetCare.fresh()
	var expert: Dictionary = LifePetCare.fresh(); LifePetCare.gain_xp(expert,"social",100000)
	LifePetCare.tick(novice,60); LifePetCare.tick(expert,60)
	check(float(expert.needs.social)>float(novice.needs.social) and float(expert.needs.fun)>float(novice.needs.fun), "Social training keeps the dog happier between interactions")
	check("training_bowl" in care.get("familiar_items",[]), "Dog remembers visited item identities")
	# Place a real obstacle across the route. A learned route must still use
	# authoritative collision/navigation, never cut through the furniture.
	var obstacle: Dictionary = item("sofa",Vector3(-8,.16,5),"training_obstacle")
	check(not obstacle.is_empty(), "Navigation regression places a real sofa obstacle")
	app.world.rebuild_navigation()
	controller.command(dog,"pet_move",Vector3(-8,.16,7))
	check(reach(Vector3(-8,.16,7)), "Level 10 Logic routes around furniture without getting stuck")
	check(bool(controller.command(dog,"pet_eat").ok), "Clever dog plans a bowl approach")
	var first_approach: Vector3 = app.pet_errands[dog].at
	var blocker: Dictionary = item("chair", first_approach, "training_approach_blocker")
	app.world.rebuild_navigation()
	for n: int in 600:
		step()
		if actor.behavior == "eat": break
	check(not blocker.is_empty() and actor.behavior=="eat" and actor.position.distance_to(first_approach)>.4, "High Logic discovers a different bowl approach after furniture blocks the planned one")
	var toy: Dictionary = item("pet_toy_dog",Vector3(-11,.16,6),"training_toy")
	app.world.rebuild_navigation()
	var fetch_start: Vector3 = actor.position
	var toy_start: Vector3 = toy.node.position
	check(bool(controller.command(dog,"pet_trick:fetch@training_toy").ok), "Learned fetch accepts a specific toy")
	for n: int in 800:
		step()
		if str(controller.state(dog).action)=="idle": break
	check(toy.node.position.distance_to(toy_start)>1.0 and toy.node.position.distance_to(fetch_start)<.6, "Fetch picks up the chosen toy and returns it to the starting spot")
	check(bool(controller.command(dog,"pet_trick:backflip").ok), "Learned high-level trick is performable")
	step(5)
	check(actor.behavior=="trick_backflip" and actor._model.position.y>0, "Backflip has a real airborne performance pose")
	controller.command(dog,"pet_move",Vector3(-13,.16,7))
	check(reach(Vector3(-13,.16,7)), "Dog reaches open space for an agility course")
	check(bool(controller.command(dog,"pet_trick:weave").ok), "Weave creates a safe slalom course")
	check(controller.agility_props.has(dog) and controller.agility_props[dog].get_child_count()==5, "Five visible poles mark the agility obstacles")
	if "--render" in OS.get_cmdline_user_args():
		app.world.camera_target = actor.position + Vector3(3,0,0);app.world.camera.size = 15;app.world.update_camera()
		await frames(4);await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/justlife-dog-slalom.png")
	var course: Array = app.pet_errands.get(dog,{}).get("course",[])
	check(course.size()==6 and Vector3(course[0]).distance_to(Vector3(course[1]))>2.0, "Slalom alternates sides and includes a return waypoint")
	for n: int in 1600:
		step()
		if str(controller.state(dog).action)=="idle": break
	check(str(controller.state(dog).action)=="idle" and not controller.agility_props.has(dog), "Dog completes the slalom and removes temporary course props")
	controller.command(dog,"pet_trick:weave")
	controller.command(dog,"pet_move",Vector3(-13,.16,6))
	check(not controller.agility_props.has(dog) and not controller.agility_obstacles.has(dog), "Interrupting a trick removes all temporary agility obstacles")
	if "--render" in OS.get_cmdline_user_args():
		app.show_pet_card(dog,true);await frames(4);await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/justlife-dog-training-menu.png")
		var scroll: ScrollContainer = app.overlay.find_child("PetCommands",true,false)
		scroll.scroll_vertical = 99999;await frames(3);await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/justlife-dog-tricks-menu.png")
		app.close_overlay()
	# Older care records and old trick IDs still load; malformed new skills fail.
	var legacy: Dictionary = care.duplicate(true)
	legacy.skills.erase("social");legacy.skills.erase("logic");legacy.tricks=["come","spin","bow","jump","tidy"]
	check(LifePetCare.validate(legacy,[]).is_empty(), "Pre-training care saves and legacy tricks remain compatible")
	var bad: Dictionary = care.duplicate(true);bad.skills.logic.level=11
	check(not LifePetCare.validate(bad,[]).is_empty(), "Invalid new skill levels are rejected")
	var saved: Dictionary = app.household.get_state(app.world.serialize_items())
	var restored := LifeHousehold.new();app.add_child(restored)
	var result: Dictionary = restored.restore_state(app.household.json_safe(saved))
	check(bool(result.get("ok",false)) and LifePetCare.level(restored.pet_care(dog),"logic")==10 and "training_bowl" in restored.pet_care(dog).get("familiar_items",[]), "All learned skills and furnishing memory survive a household save round trip")
	restored.free()
	print("DOG_COMMANDS_TRAINING %d checks, failures: %s" % [checks,str(failures)])
	app.queue_free();await frames();quit(0 if failures.is_empty() else 1)
