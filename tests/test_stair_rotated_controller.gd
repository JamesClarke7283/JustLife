extends "res://tests/test_stair_controller.gd"

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_setup(1,90);app.household.set_speed(8)
	for destination:Vector3 in [Vector3(2,3.16,3.5),Vector3(-2,.16,-3.5)]:
		app.on_ground_clicked(destination)
		check(_until_transit("player"),"Real route reaches the rotated physical stair.")
		var route:Dictionary=_route("player");var leg:Dictionary=route.legs[int(route.cursor)]
		check(is_equal_approx(absf(leg.schedule.transform.basis.get_euler().y),PI/2),"Controller uses the actual quarter-turn stair transform.")
		for frame:int in 1000:
			_step()
			if not app.walk_only:break
		check(not app.walk_only and app.player.position.distance_to(destination)<.001,"Rotated stair crossing reaches its exact intended floor destination.")
	DirAccess.make_dir_recursive_absolute("user://regression/stair_integration")
	var file:=FileAccess.open("user://regression/stair_integration/rotated_controller.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("STAIR_ROTATED_CONTROLLER checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
