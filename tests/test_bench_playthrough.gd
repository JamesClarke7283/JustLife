extends "res://tests/test_playthrough.gd"
## Targeted real-frame diagnosis of a reported bench pose in the promoted rig.

var pose_diagnostics: Array = []

func _run() -> void:
	screenshot_dir = "res://art/bench_playthrough"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames(4)
	app.set_sound(false)
	await _enter_new_game()
	await press("Look")
	await press("Female")
	await press("Crop")
	await press("Wardrobe")
	await press("Casual")
	await press("Coastal")
	await press("Find my home", true)
	await press("Willow Cottage")
	await press("Start living", true)
	app.household.set_speed(0)
	app.sim.autonomy = false
	await press("Explore")
	await press("Juniper Gardens")
	await press("Travel here", true)
	await queue_via_menu("bench", "relax")
	app.household.set_speed(1)
	if await wait_until(func() -> bool: return active_is("relax", 0.50), "real normal-speed approach and settled bench pose", 40):
		_collect_pose("normal_speed_halfway")
		await screenshot("01_normal_speed_bench", true)
		app.household.set_speed(0)
		_collect_pose("paused_after_capture")
		app.world.camera_angle += PI / 2.0
		app.world.update_camera()
		await screenshot("02_normal_speed_side_view", true)
		app.household.set_speed(8)
		await wait_until(func() -> bool: return active_is("relax", 0.80), "later accelerated bench pose")
		_collect_pose("fast_speed_later")
		await screenshot("03_fast_speed_bench", true)
	var file := FileAccess.open(screenshot_dir.path_join("pose_diagnostics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(pose_diagnostics, "  "));file.close()
	_write_report()
	app.queue_free()
	await frames(3)
	print("BENCH_RESULT assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _collect_pose(label_text: String) -> void:
	var actor: Node3D = app.player
	var data: Dictionary = {"label":label_text,"action":app.sim.get_current_action().duplicate(true),"speed":app.sim.speed,"path":[],"pending_action":app.pending_action.duplicate(true),"actor_position":vec(actor.position),"visual_position":vec(actor.visual.position),"visual_rotation":vec(actor.visual.rotation),"sit_amount":actor.get("_sit_amount"),"activity_anchor":actor.get("_activity_anchor").duplicate(true),"rig_bone_count":actor.get("_rig_bones").size(),"bones":[],"skeletons":[]}
	for point: Vector3 in app.path:data.path.append(vec(point))
	for entry: Dictionary in actor.get("_rig_bones"):
		var skeleton: Skeleton3D = entry.skeleton
		var index: int = entry.index
		data.bones.append({"mapped_name":entry.name,"actual_name":skeleton.get_bone_name(index),"skeleton":str(actor.get_path_to(skeleton)),"rotation":vec(skeleton.get_bone_pose_rotation(index).get_euler()),"global_rotation":vec(skeleton.get_bone_global_pose(index).basis.get_euler())})
	for skeleton: Skeleton3D in actor.visual.find_children("*", "Skeleton3D", true, false):
		var entry: Dictionary = {"path":str(actor.get_path_to(skeleton)),"bones":[]}
		for i: int in range(skeleton.get_bone_count()):
			entry.bones.append({"name":skeleton.get_bone_name(i),"pose_rotation":vec(skeleton.get_bone_pose_rotation(i).get_euler()),"rest_rotation":vec(skeleton.get_bone_rest(i).basis.get_euler())})
		data.skeletons.append(entry)
	pose_diagnostics.append(data)
