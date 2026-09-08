extends "res://tests/test_sanitation_levels.gd"
var ray_facts:Array=[]
func framed(level:int)->void:
	app.world.set_view_level(level);app.world.camera_target=Vector3(.9,Building.RISE*level,2.2)
	app.world.camera_angle=2.25;app.world.camera.size=8.1;app.world.update_camera();app.draw_live()
func run()->void:
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_process(false);app.set_sound(false);captures=true
	stacked_floors()
	var records:Array=app.household.sanitation.puddles.duplicate(true)
	app.select_household_member(0);reset_needs();walk_to(Vector3(.75,3.16,3.75))
	app.select_household_member(1);walk_to(Vector3(3,.16,-3.5));app.select_household_member(0);app.household.set_speed(0)
	for actor:LifeActor in app.world.actors.values():actor.clear_speech()
	var picked:Array=[]
	app.world.object_clicked.connect(func(item:Dictionary,_at:Vector2):picked.append(str(item.id)))
	for level:int in [0,1]:
		framed(level);await frames(3)
		var own:Dictionary=records.filter(func(value:Dictionary)->bool:return int(value.level)==level)[0]
		var other:Dictionary=records.filter(func(value:Dictionary)->bool:return int(value.level)!=level)[0]
		var item:Dictionary=app._find_item(own.id)
		var screen:Vector2=app.world.camera.unproject_position(item.node.global_position+Vector3(.07,.016,0))
		picked.clear();app.world.pick(screen)
		check(picked==[str(own.id)] and not picked.has(str(other.id)),"Actual rendered camera picking selects only the wet patch on floor "+str(level)+" at stacked X/Z.")
		ray_facts.append({"level":level,"screen":[screen.x,screen.y],"picked":picked.duplicate(),"view_mask":app.world.camera.cull_mask})
		app.close_overlay();await capture("v2_0"+str(level+1)+("_ground_patch" if level==0 else "_upper_patch"))
	var upper:Dictionary=records.filter(func(value:Dictionary)->bool:return int(value.level)==1)[0]
	app.household.set_speed(1);app.queue_interaction(app._find_item(upper.id),"mop_puddle")
	check(until(func()->bool:return str(app.sim.get_current_action().get("phase",""))=="active",200.0),"Rendered upper cleaner arrives before actual mop presentation.")
	step(2.0);app.household.set_speed(0);framed(1)
	check(app.player._mop.visible and absf(app.player._mop.global_position.y-app._find_item(upper.id).node.global_position.y)<.00001,"Actual upper mop head contacts the measured wet floor without a downstairs offset.")
	await capture("v2_03_upper_mop")
	check(app.save_game("","Upper mop visual checkpoint"),"The rendered paused upper mop saves through the real physical path.")
	app.load_game(app.active_save_id);framed(1);await frames(3)
	check(app.player._mop.visible,"Same-process paused physical load reconstructs the held mop without a Live tick.")
	await capture("v2_04_loaded_upper_mop")
	var file:=FileAccess.open("user://sanitation_levels_render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rays":ray_facts},"  ",true,true));file.close()
	print("Sanitation render: %d checks, %d failures."%[checks,failures.size()])
	app.queue_free();await frames(5);await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
