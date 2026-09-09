extends "res://tests/test_home_visit.gd"
func _frames(count:int=4)->void:
	for index:int in count:await process_frame

func _capture(name:String)->void:
	app.refresh_hud();await _frames()
	RenderingServer.force_draw(false,0.0)
	var shot:Image=root.get_texture().get_image()
	check(shot.save_png("user://home_visit/"+name+".png")==OK,"Rendered actual viewport: "+name)
	events.append({"capture":name,"size":[shot.get_width(),shot.get_height()],"phase":_phase(),"visit":app.residents.home_visit.snapshot(),"camera":{"position":LifeSaveLibrary._json_safe(app.world.camera.position),"target":LifeSaveLibrary._json_safe(app.world.camera_target),"size":app.world.camera.size},"household":app.household.get_state(),"resident":app.residents.snapshot()})
func _run()->void:
	if DisplayServer.get_name()=="headless":check(false,"Actual rendering required");quit(2);return
	root.gui_disable_input=true
	DirAccess.make_dir_recursive_absolute("user://home_visit")
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);app.set_sound(false)
	await _frames();_setup();app.world.set_process(false);await _frames()
	var original_layout:Array=app.world.serialize_items().duplicate(true)
	app.show_relationships();await _capture("01_people_invite")
	var invite:Button=app.overlay.find_child("InviteResident_maya",true,false)
	check(is_instance_valid(invite) and not invite.disabled,"Public People invitation is enabled")
	invite.pressed.emit();_step(18);await _capture("02_arriving")
	check(_until("waiting"),"Actual resident route reaches waiting")
	await _capture("03_welcome")
	root.size=Vector2i(960,600);await _frames(8);await _capture("04_welcome_960")
	root.size=Vector2i(1440,900);await _frames(8)
	var welcome:Button=app.ui.find_child("WelcomeGuest",true,false)
	check(is_instance_valid(welcome) and not welcome.disabled,"Public Welcome in control is enabled")
	welcome.pressed.emit()
	for index:int in 400:
		if str(app.sim.get_current_action().get("phase",""))=="active":break
		_step()
	check(str(app.sim.get_current_action().get("phase",""))=="active","Welcome becomes an actual friendly conversation")
	await _capture("05_greeting")
	check(_until("inside"),"Accepted Welcome and route reach the inside phase")
	check(app.world.serialize_items()==original_layout,"Whole uninterrupted visit keeps original layout exact")
	await _capture("06_inside")
	var goodbye:Button=app.ui.find_child("GoodbyeGuest",true,false)
	goodbye.pressed.emit();_step(20);await _capture("07_goodbye")
	check(_until("absent"),"Public Goodbye walks to the sidewalk")
	await _capture("08_home_again")
	await _finish()
