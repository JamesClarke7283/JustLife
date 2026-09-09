extends "res://tests/test_guest_meal.gd"
func _capture(name:String,size:Vector2i)->void:
	DisplayServer.window_set_size(size)
	root.size=size;app.refresh_hud()
	await process_frame;await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	var picture:Image=root.get_texture().get_image()
	check(picture.save_png("user://guest_meal_ui/"+name+".png")==OK,"Actual Forward+ guest meal capture: "+name)
func _run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	root.gui_disable_input=true
	DirAccess.make_dir_recursive_absolute("user://guest_meal_ui")
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	var file:=FileAccess.open("user://guest_meal_slots.json",FileAccess.READ)
	if file==null:check(false,"Producer slots exist");await _finish();return
	var ids:Dictionary=JSON.parse_string(file.get_as_text());file.close()
	var phases:Array=["goodbye"] if "--release-only" in OS.get_cmdline_user_args() else ["pickup","to_place","eating","goodbye"]
	for phase:String in phases:
		_load(str(ids[phase]));await process_frame;app.meal_flow.sync_world(false)
		var before:Dictionary=_record()
		var camera_size:float=app.world.camera.size;var camera_target:Vector3=app.world.camera_target
		await _capture(phase,Vector2i(1440,900))
		if phase=="eating" or "--release-only" in OS.get_cmdline_user_args():
			await _capture(phase+"_960",Vector2i(960,600))
			app.world.camera.size=8.0
			app.world.camera_target=app.residents.home_visit.meal.body().position
			app.world.update_camera()
			await _capture(phase+"_close",Vector2i(1440,900))
		app.world.camera.size=camera_size;app.world.camera_target=camera_target;app.world.update_camera()
		check(_same_value(_record(),before),"Rendering paused guest meal leaves authoritative state unchanged: "+phase)
	await _finish()
