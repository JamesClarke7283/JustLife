extends "res://tests/test_family_ui.gd"
var expected:Dictionary={}
var contact_samples:Array=[]
var contact_metrics:Dictionary={}
var last_sample:Dictionary={}
func _run() -> void:
	screenshot_dir="res://art/meals_playthrough";DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):member_completed.append(id+":"+str(action.id)))
	if resume_only:
		expected=JSON.parse_string(FileAccess.get_file_as_string("user://meals_expected.json"))
		await _public_load()
		await _resume_dinner()
	else:
		await _make_family()
		process_frame.connect(_sample_contact)
		await _cook_and_serve()
		process_frame.disconnect(_sample_contact)
	_write_report();app.queue_free();await frames(3)
	print("MEAL_PLAYTHROUGH assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
	quit(0 if failures.is_empty() else 1)

func _make_family() -> void:
	await _enter_new_game()
	for i:int in range(2):
		if i>0:await press("+ Add Lifelet")
		var edit:LineEdit=app.find_children("*","LineEdit",true,false)[0]
		edit.text=FAMILY_NAMES[i];edit.text_changed.emit(edit.text)
		await _age("Child" if i==0 else "Adult")
	await _link(1,0,4)
	await press_member(FAMILY_NAMES[1]);await press("Find my home",true);await press("Start living",true)
	await press("Ⅱ")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	await press_member(FAMILY_NAMES[1])
	expected={"funds":app.household.funds,"hunger":app.sim.needs.hunger}

func _cook_and_serve() -> void:
	var stove:Dictionary=first_item("stove")
	app.world.object_clicked.emit(stove,app.world.camera.unproject_position(stove.node.position+Vector3(0,.6,0)))
	await frames(3);await press("Cook a fresh meal",true);await press("Cook garden skillet");await press("▶")
	if not await wait_until(func()->bool:return active_is("cook",.1),"the cook reaches the stove",40):return
	await press("Ⅱ")
	check(app.household.funds==int(expected.funds)-25,"Cooking spends its ingredient cost once after physical arrival.")
	check(app.sim.needs.hunger<float(expected.hunger),"Preparing food does not feed the cook.")
	await screenshot("01_preparing",false,false)
	await press("▶")
	if not await wait_until(func()->bool:return app.sim.get_current_action().get("id")=="serve_meal","finished cooking creates a dish to carry",30):return
	await press("Ⅱ")
	check(app.household.meals.batches.size()==1 and app.household.meals.batches[0].remaining==4,"Cooking creates one four-serving batch.")
	check(app.household.meals.batches[0].owner=="housemate_1","The actual cook carries the serving dish.")
	await screenshot("02_carrying",false,false);await press("▶")
	if not await wait_until(func()->bool:return app.household.meals.batches[0].storage=="surface","the serving dish reaches a dining surface",40):return
	await press("Ⅱ");await frames(4)
	var batch_id:String=str(app.household.meals.batches[0].id)
	var dish:Dictionary=app._find_item(batch_id)
	check(not dish.is_empty(),"Served food exists as an interactive world object.")
	if dish.is_empty():return
	app.world.object_clicked.emit(dish,app.world.camera.unproject_position(dish.node.position))
	await frames(3);await press("Call everyone to eat")
	await press("▶")
	if not await wait_until(func()->bool:return _both_eating(),"adult and child take separate servings and sit independently",50):return
	await press("Ⅱ")
	check(app.household.meals.batches[0].remaining==2,"Two diners consume two distinct servings.")
	check(app.household.meals.portions.size()==2,"Each diner owns a separate plate.")
	var seats:Array=[]
	for member:Dictionary in app.household.members:seats.append(member.sim.get_current_action().get("meal_seat",""))
	check(seats[0]!="" and seats[1]!="" and seats[0]!=seats[1],"Two diners use different dining chairs.")
	await screenshot("03_family_dinner",false,false)
	await _meal_closeup()
	expected.food=app.household.meals.get_state();expected.funds=app.household.funds
	await _public_save("Dinner at home — two plates")
	var file:=FileAccess.open("user://meals_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected));file.close()

func _both_eating() -> bool:
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if action.get("id")!="eat_meal" or action.get("phase")!="active" or float(action.elapsed)<1:return false
	return true

func _resume_dinner() -> void:
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	check(app.household.funds==int(expected.funds),"Fresh-process load preserves the meal's ingredient charge.")
	check(_same_json(app.household.meals.get_state(),expected.food),"The served food and partial plates survive named restart exactly.")
	await press("▶")
	await wait_until(func()->bool:return app.household.members.all(func(m:Dictionary)->bool:return m.sim.action_queue.is_empty()),"both diners independently finish after reload",45)
	await press("Ⅱ")
	check(app.household.meals.portions.all(func(p:Dictionary)->bool:return p.progress==1.0 and p.storage=="dirty"),"Completed portions leave persistent dirty plates.")
	check(app.household.meals.batches[0].remaining==2,"Restart does not consume duplicate portions.")
	await screenshot("04_dinner_finished",false,false)
	await _leftovers_and_cleanup()


func _same_json(a:Variant,b:Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):return absf(float(a)-float(b))<.000001
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i:int in range(a.size()):
			if not _same_json(a[i],b[i]):return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not _same_json(a[key],b[key]):return false
		return true
	return a==b

func _meal_closeup() -> void:
	var before:Dictionary={"size":app.world.camera.size,"target":app.world.camera_target,"angle":app.world.camera_angle,"elevation":app.world.camera_elevation}
	app.world.camera_target=first_item("dining").node.position+Vector3(0,.85,0)
	app.world.camera.size=4.2;app.world.camera_angle=.60;app.world.camera_elevation=.65;app.world.update_camera()
	await screenshot("03_dinner_close",false,false)
	for index:int in range(3):
		await press("▶");await create_timer(.45).timeout;await press("Ⅱ")
		await screenshot("03_dining_contact_%d"%index,false,false)
	var trace:=FileAccess.open(screenshot_dir+"/meal_contact.json",FileAccess.WRITE);trace.store_string(JSON.stringify({"samples":contact_samples,"contact":contact_metrics},"\t"));trace.close()
	for person:String in contact_metrics:
		check(float(contact_metrics[person].anchor)<.002,person+" receives the actual plate position throughout dining.")
		check(float(contact_metrics[person].support)<.003,person+" plate bottom is supported by the imported tabletop.")
		check(float(contact_metrics[person].mouth)<.025,person+" fork tines reach the mouth during a bite.")
		check(float(contact_metrics[person].food)<.045,person+" fork tines return to the actual food.")
	app.world.camera.size=before.size;app.world.camera_target=before.target;app.world.camera_angle=before.angle;app.world.camera_elevation=before.elevation;app.world.update_camera()

func _leftovers_and_cleanup() -> void:
	var batch_id:String=str(app.household.meals.batches[0].id)
	var batch:Dictionary=app._find_item(batch_id)
	app.world.object_clicked.emit(batch,app.world.camera.unproject_position(batch.node.position))
	await frames(3);await press("Put away leftovers");await press("▶")
	if not await wait_until(func()->bool:return app.household.meals.batches[0].storage=="fridge","leftovers are physically carried to the fridge",45):return
	await press("Ⅱ")
	check(app.household.meals.batches[0].remaining==2,"Storing food preserves its remaining serving count.")
	var fridge:Dictionary=first_item("fridge")
	check(app.household.meals.batches[0].host==fridge.id,"Leftovers belong to the reached fridge.")
	app.world.object_clicked.emit(fridge,app.world.camera.unproject_position(fridge.node.position+Vector3(0,1,0)))
	await frames(3);await press("Choose leftovers…");await screenshot("05_leftover_picker",false,false)
	await press("Garden skillet · 2 servings",true)
	await press("▶")
	await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"a serving from the fridge is collected and eaten",50)
	await press("Ⅱ")
	check(app.household.meals.batches[0].remaining==1,"Eating leftovers claims exactly one more portion.")
	var plate_id:String=str(app.household.meals.portions[0].id)
	var plate:Dictionary=app._find_item(plate_id)
	app.world.object_clicked.emit(plate,app.world.camera.unproject_position(plate.node.position))
	await frames(3);await press("Wash this plate");await press("▶")
	await wait_until(func()->bool:return app.household.meals.portion(plate_id).is_empty(),"the dirty plate is carried to the sink and washed",45)
	await press("Ⅱ")
	check(app.household.meals.portions.size()==2,"Only the chosen dirty plate is removed.")
	check(app.household.meals.batches[0].remaining==1,"Washing a dish does not change stored servings.")
	await screenshot("06_dishes_and_leftovers",false,false)

func _mesh_top(node:Node3D,prefix:String) -> float:
	var top:float=-INF
	for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if not str(mesh.name).begins_with(prefix):continue
		for i:int in range(8):top=maxf(top,mesh.to_global(mesh.get_aabb().get_endpoint(i)).y)
	return top

func _sample_contact() -> void:
	if not is_instance_valid(app) or app.mode!="live":return
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if action.get("id")!="eat_meal" or action.get("phase")!="active":continue
		var lifelet:LifeActor=app.world.actors[str(member.id)]
		if lifelet._motion_action!="eat_meal":continue
		if lifelet._action_time<.3 or lifelet._action_time-float(last_sample.get(str(member.id),-1))<.08:continue
		var portion:Dictionary=app.household.meals.portion(str(action.get("meal_plate","")))
		var host:Dictionary=app._find_item(str(portion.get("host","")))
		if host.is_empty():continue
		var plate:Node3D=app.meal_flow.views.get(str(portion.get("id","")))
		var point:Node3D=lifelet._meal_fork.find_child("BitePoint",true,false)
		if not is_instance_valid(plate) or not is_instance_valid(point):continue
		last_sample[str(member.id)]=lifelet._action_time
		var mouth:Vector3=lifelet._joints.Head.to_global(lifelet._mouth_anchor)
		var plate_anchor:Vector3=lifelet._activity_anchor.get("plate_position",Vector3.INF)
		var support:float=_mesh_top(host.node,"Dining")
		if not contact_metrics.has(str(member.id)):contact_metrics[str(member.id)]={"mouth":INF,"food":INF,"anchor":0.0,"support":0.0}
		var metrics:Dictionary=contact_metrics[str(member.id)]
		metrics.mouth=minf(metrics.mouth,point.global_position.distance_to(mouth))
		metrics.food=minf(metrics.food,point.global_position.distance_to(plate.global_position+Vector3(0,.035,0)))
		metrics.anchor=maxf(metrics.anchor,plate_anchor.distance_to(plate.global_position))
		metrics.support=maxf(metrics.support,absf(plate.global_position.y-support-.002))
		contact_samples.append({"id":member.id,"time":lifelet._action_time,"fork":vec(point.global_position),"mouth":vec(mouth),"requested_tip":vec(lifelet._model.to_global(lifelet._meal_tip)),"plate":vec(plate_anchor),"actual_plate":vec(plate.global_position),"tabletop_y":support,"action":action.duplicate(true)})
