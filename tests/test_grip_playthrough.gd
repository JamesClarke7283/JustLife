extends "res://tests/test_activity_playthrough.gd"
## Staged-candidate grip check on actual normal-speed kitchen activities.
## Parent runner provides isolation. This does not promote production assets.

func _prop_state() -> Dictionary:
	var result: Dictionary = super._prop_state()
	result["grip_shapes"] = {"L":app.player._grip_shapes.L.size(),"R":app.player._grip_shapes.R.size()}
	result["grip_amounts"] = app.player._grip_amounts.duplicate(true)
	var hand: Node3D = app.player._joints["Forearm_R"]
	var shaft: Vector3 = app.player._cooking_spoon.global_basis.y.normalized()
	var channel: Vector3 = hand.global_basis.x.normalized()
	result["spoon_grip_angle_degrees"] = rad_to_deg(acos(clampf(absf(shaft.dot(channel)),0,1)))
	result["model"] = app.player._model.scene_file_path
	return result

func _kitchen_action(action_id: String,furnishing: String,prefix: String,cost: int) -> void:
	var index: int = pose_evidence.size()
	await super._kitchen_action(action_id,furnishing,prefix,cost)
	var samples: Array = pose_evidence.slice(index)
	check(not samples.is_empty(),action_id+": staged grip has actual paused/activity evidence.")
	for sample: Dictionary in samples:
		check(int(sample.grip_shapes.L) > 0 and int(sample.grip_shapes.R) > 0,action_id+": imported rendered actor contains both actual hand morphs.")
		if action_id == "cook":
			check(float(sample.grip_amounts.R) > .85 and float(sample.spoon_grip_angle_degrees) < 10.0,"Cooking closes the right-hand grasp around an aligned spoon shaft.")
		else:
			check(float(sample.grip_amounts.R) > .35,"Snack uses its partial grasp during actual performance.")

func _close_detail(label_text: String) -> void:
	var old_transform: Transform3D = app.world.camera.transform
	var old_size: float = app.world.camera.size
	var body: Node3D = app.player.visual
	var target: Vector3 = app.player._snack.global_position if active_is("snack") else (app.player._cooking_spoon.global_position+app.player._bowl_center.global_position)*.5
	app.world.camera.size = 1.35
	app.world.camera.position = target-body.global_basis.x.normalized()*1.8+Vector3.UP*.7+body.global_basis.z.normalized()*.05
	app.world.camera.look_at(target,Vector3.UP)
	await screenshot(label_text,false)
	app.world.camera.transform = old_transform;app.world.camera.size = old_size
