extends "res://tests/test_school_presentation.gd"
## Separate staged-asset child birthday contact gate; no school activity rerun.
var cake_mesh_samples: Array = []
var cake_frames: int = 0
var penetrated_frames: int = 0
var max_penetration: float = 0.0
var first_penetration_time: float = -1.0
func _run() -> void:
	screenshot_dir="res://art/grip_birthday"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):member_completed.append(id+":"+str(action.id)))
	await _create_school_household()
	check(app.player._grip_shapes.L.size()>0 and app.player._grip_shapes.R.size()>0,"Child imported actor contains the staged left and right hand morphs.")
	var funds_before:int=app.sim.funds
	process_frame.connect(_observe_cake)
	await _birthday_details()
	process_frame.disconnect(_observe_cake)
	check(cake_frames>20 and penetrated_frames==0,"Visible cake geometry stays outside the actual fridge volume throughout arrival, turn and presentation.")
	evidence.append({"cake_frames":cake_frames,"penetrated_frames":penetrated_frames,"max_penetration_m":max_penetration,"first_penetration_time":first_penetration_time})
	check(app.sim.funds==funds_before-30,"Rendered child birthday charges exactly30.")
	_write_report()
	app.queue_free();await frames(3)
	print("GRIP_BIRTHDAY_RESULT assertions=%d failures=%d" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func screenshot(label_text:String,focus_actor:bool=false,inspect_camera:bool=true)->void:
	await super.screenshot(label_text,focus_actor,inspect_camera)
	if not label_text.begins_with("17_") and not label_text.begins_with("18_"):return
	var palms:Dictionary={}
	for side:String in ["L","R"]:palms[side]=str(app.player._joints["Forearm_"+side].to_global(app.player._palm_offset(side)))
	evidence.append({"capture":label_text,"model":app.player._model.scene_file_path,"grip_amounts":app.player._grip_amounts.duplicate(true),"palms":palms,"cake_transform":str(app.player._birthday_cake.global_transform)})
	var original:Transform3D=app.world.camera.transform
	var size:float=app.world.camera.size
	var target:Vector3=app.player._birthday_cake.global_position
	var facing: Basis = app.player.visual.global_basis.orthonormalized()
	for side: int in [-1,1]:
		app.world.camera.size=.95
		app.world.camera.position=target+facing.x*float(side)*1.8+Vector3.UP*.45+facing.z*.05
		app.world.camera.look_at(target,Vector3.UP)
		await super.screenshot(label_text+"_hand_contact_"+str(side),false,false)
	app.world.camera.transform=original;app.world.camera.size=size

func _birthday_phases() -> Array:
	return [{"label":"16a_initial_turn","time":.18,"cake":true,"flames":true},{"label":"16b_turning_with_cake","time":.55,"cake":true,"flames":true}]+super._birthday_phases()

func _observe_cake() -> void:
	if not active_is("birthday") or not app.player._birthday_cake.is_visible_in_tree():return
	if cake_mesh_samples.is_empty():
		for mesh: MeshInstance3D in app.player._birthday_cake.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh==null:continue
			var points: PackedVector3Array = PackedVector3Array()
			for surface: int in range(mesh.mesh.get_surface_count()):points.append_array(mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
			cake_mesh_samples.append({"node":mesh,"points":points})
	var fridge: Dictionary = first_item("fridge")
	if fridge.is_empty():return
	var half_size: Vector2 = fridge.size*.5
	var height: float = 1.9
	var penetrated: bool = false
	for sample: Dictionary in cake_mesh_samples:
		if not is_instance_valid(sample.node) or not sample.node.is_visible_in_tree():continue
		var transform: Transform3D = fridge.node.global_transform.affine_inverse()*sample.node.global_transform
		for point: Vector3 in sample.points:
			var local: Vector3 = transform*point
			if absf(local.x)<half_size.x-.003 and absf(local.z)<half_size.y-.003 and local.y>.003 and local.y<height:
				penetrated=true
				max_penetration=maxf(max_penetration,half_size.y-local.z)
	cake_frames+=1
	if penetrated:
		penetrated_frames+=1
		if first_penetration_time<0:first_penetration_time=app.player._action_time
