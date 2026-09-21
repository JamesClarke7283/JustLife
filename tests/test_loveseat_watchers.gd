extends "res://tests/test_school_playthrough.gd"
## Public renderer flow: television seats a household. Two Lifelets share the
## loveseat by seat, and the third takes the free armchair instead of queueing
## behind a full loveseat.
const WATCHERS: Array[String] = ["Morgan Reed","Casey Vale","Ellis Reed"]

func _run() -> void:
	screenshot_dir="res://art/loveseat_watchers"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	await _enter_new_game()
	_set_name(WATCHERS[0]);await _choose_age("Adult")
	for i:int in [1,2]:
		await press("+ Add Lifelet");_set_name(WATCHERS[i]);await _choose_age("Adult")
	await press_member(WATCHERS[0])
	await press("Find my home",true);await press("A Fresh Canvas");await press("Start living",true)
	await press("Ⅱ")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	check(app.household.members.size()==3,"Three adults move into the empty lot.")
	app.household.set_funds(app.sim.funds+3000)
	await press("Build & buy")
	var before:int=app.world.items.size()
	for entry:Array in [["tv",-4.95,0.65,90.0],["loveseat",-3.4,3.75,180.0],["armchair",-1.4,3.2,0.0]]:
		var spot:Vector3=Vector3(float(entry[1]),0.16,float(entry[2]))
		print("PLACE %s mode=%s funds=%d can_place=%s level=%d floor=%s" % [str(entry[0]),app.mode,app.sim.funds,str(app.world.can_place(str(entry[0]),spot,float(entry[3]))),app.world.point_level(spot),str(app.world.construction.floor_contains(Vector2(spot.x,spot.z),0))])
		app.on_placement(str(entry[0]),spot,float(entry[3]))
	print("WALLS %s" % str(app.world.construction.building_state.get("walls",[]).map(func(w:Dictionary)->String:return "%.1f,%.1f %sx%s" % [float(w.x),float(w.z),str(w.get("w","?")),str(w.get("d","?"))])))
	check(app.world.items.size()==before+3,"A television, a loveseat and an armchair are bought through the public purchase path.")
	await press("Live")
	var tv:Dictionary=app.world.closest_item("tv",Vector3(-4.95,0.16,0.65))
	var loveseat:Dictionary=app.world.closest_item("loveseat",Vector3(-3.4,0.16,3.75))
	var armchair:Dictionary=app.world.closest_item("armchair",Vector3(-1.4,0.16,3.2))
	check(not tv.is_empty() and not loveseat.is_empty() and not armchair.is_empty(),"The three furnishings resolve in the world.")
	if tv.is_empty() or loveseat.is_empty() or armchair.is_empty():
		_write_report();app.queue_free();await frames(3)
		print("LOVESEAT_WATCHERS assertions=%d failures=%d"%[assertions,failures.size()]);quit(1);return
	for i:int in range(3):
		await press_member(WATCHERS[i])
		await _watch(tv)
		await press("▶")
		await wait_until(func()->bool:return active_is("watch"),WATCHERS[i]+" starts watching",40)
		await press("Ⅱ")
		var action:Dictionary=app.sim.get_current_action()
		if i<2:
			check(str(action.get("target_id",""))==str(loveseat.id) and str(action.get("seat_slot",""))==["seat_0","seat_1"][i],"%s takes the %s seat of the loveseat (target %s, seat %s)." % [WATCHERS[i],["left","right"][i],str(action.get("target_id","")),str(action.get("seat_slot",""))])
		else:
			check(str(action.get("target_id",""))==str(armchair.id),"The third watcher takes the free armchair instead of queueing at the full loveseat (target %s)." % str(action.get("target_id","")))
			check(not app.waiting_for_target,"The third watcher is seated, not waiting.")
	await screenshot("01_three_watchers",false,false)
	_write_report();app.queue_free();await frames(3)
	print("LOVESEAT_WATCHERS assertions=%d failures=%d"%[assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _watch(item:Dictionary) -> void:
	var screen:Vector2=app.world.camera.unproject_position(item.node.position+Vector3(0,.6,0))
	app.world.object_clicked.emit(item,screen);await frames(2)
	await press(str(app.sim.get_action_definition("watch").label),true)
	# The television resolves its seat as soon as the action starts, so the
	# queued action carries the seat, not the set.
	check(str(app.sim.get_current_action().get("id",""))=="watch","Public object interaction queues a show from the television.")
