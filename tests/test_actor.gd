extends SceneTree
## Run in an isolated project without the editor MCP autoload.
const Actor = preload("res://scripts/actor.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, explanation: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(explanation)


func settle(actor: LifeActor, action_id: String, moving: bool = false) -> void:
	for frame_index: int in range(180):
		actor.animate(.016, 1.0, moving, action_id)


func run() -> void:
	for frame_index: int in range(2):
		var actor: LifeActor = Actor.new()
		root.add_child(actor)
		actor.configure({"name":"Rig test", "frame":frame_index,
			"low_detail":true, "outfit":1, "hair":1, "height_scale":1.05, "body_scale":1.10})
		actor.voice_enabled = false
		check(actor._rig_bones.size() == 9, "All nine skeletal joints must resolve after glTF import.")
		check(actor._blink_shapes.size() >= 3, "Blink must include the face and eyes.")
		check(actor._smile_shapes.size() >= 1, "The face must support expression.")
		check(actor._sit_shapes.size() >= 1, "The trousers must expose the seated corrective morph.")
		for feature: String in Actor.IDENTITY_KEYS:
			check(actor._identity_shapes.has(feature) and not actor._identity_shapes[feature].is_empty(), "Every facial control must drive real coupled morphs.")
			actor.set_face_feature(feature, .35)
			for shape: Dictionary in actor._identity_shapes.get(feature, []):
				check(is_equal_approx(shape.mesh.get_blend_shape_value(shape.index), .35), "Every related face mesh must receive the selected identity value.")
			actor.set_face_feature(feature, 2.0)
			check(actor.profile[feature] == 1.0, "Facial controls must clamp to their supported range.")
			actor.set_face_feature(feature, -.5)
			check(actor.profile[feature] == 0.0, "Facial controls must clamp negative values to neutral.")
		for shape: Dictionary in actor._blink_shapes:
			check(is_zero_approx(shape.mesh.get_blend_shape_value(shape.index)), "Configuration opens every eye morph.")
		var jacket_count: int = 0
		var hidden_count: int = 0
		for mesh: Node3D in actor._model.find_children("Outfit_*", "MeshInstance3D", true, false):
			if str(mesh.name).begins_with("Outfit_Jacket"):
				check(mesh.visible, "Selected jacket meshes must be visible.")
				jacket_count += 1
			else:
				check(not mesh.visible, "Other wardrobe meshes must be hidden.")
				hidden_count += 1
		check(jacket_count > 0 and hidden_count > 0, "Wardrobe selection must affect real mesh variants.")
		actor.position = Vector3(3, .16, 4)
		actor.rotation.y = .8
		var navigation_position: Vector3 = actor.position
		var navigation_rotation: Vector3 = actor.rotation
		var anchor: Vector3 = Vector3(2, .68, 2)
		actor.set_activity_anchor(anchor, -.4, "seat", "relax")
		settle(actor, "relax")
		check(actor.position == navigation_position and actor.rotation == navigation_rotation, "Seat posing must preserve the navigation root.")
		check(actor.visual.to_global(Vector3(0, actor._hip_height, 0)).distance_to(anchor) < .015, "Scaled hips must meet the rotated seat top.")
		for shape: Dictionary in actor._sit_shapes:
			check(is_equal_approx(shape.mesh.get_blend_shape_value(shape.index), 1.0), "The seated clothing correction must follow a relaxed seat pose.")
		actor.set_activity_anchor(anchor, -.4, "bed", "sleep")
		settle(actor, "sleep")
		check(actor.visual.to_global(Vector3(0, actor._hip_height, -.10*actor._proportion)).distance_to(anchor) < .015, "Scaled body support must meet the rotated mattress top.")
		check(actor.position == navigation_position and actor.rotation == navigation_rotation, "Sleeping must preserve the navigation root.")
		for shape: Dictionary in actor._sit_shapes:
			check(is_zero_approx(shape.mesh.get_blend_shape_value(shape.index)), "Bed sleep must release the seated clothing correction.")
		for shape: Dictionary in actor._blink_shapes:
			check(is_equal_approx(shape.mesh.get_blend_shape_value(shape.index), 1.0), "Sleeping closes every eyelid morph.")
		actor.set_activity_anchor(anchor, -.4, "seat", "nap")
		settle(actor, "nap")
		check(actor.visual.to_global(Vector3(0, actor._hip_height, 0)).distance_to(anchor) < .015, "A sofa nap must keep its hips on the seat.")
		check(actor.visual.global_basis.y.normalized().dot(Vector3.UP) > .95, "A sofa nap must remain seated, with a slight dozing lean.")
		check(is_equal_approx(actor._sit_amount, 1.0), "Sofa naps must include the seated clothing correction.")
		actor.set_activity_anchor(anchor, -.4, "standing", "study")
		settle(actor, "study")
		check(actor.visual.global_position.distance_to(anchor) < .015, "A standing study anchor must align the feet.")
		check(actor._book.visible, "Standing study must show a book.")
		check(absf(actor._joints.Leg_L.rotation.x) < .01, "Standing study must keep the legs straight.")
		check(is_zero_approx(actor._sit_amount), "Standing study must release the seated corrective morph.")
		actor.set_activity_anchor(anchor, -.4, "standing", "work")
		settle(actor, "work")
		check(absf(actor._joints.Leg_R.rotation.x) < .01, "A desk without a chair must support standing work.")
		var paused_transform: Transform3D = actor.visual.transform
		var paused_arm: Vector3 = actor._joints.Arm_L.rotation
		actor.animate(.3, 0.0, true, "")
		check(actor.visual.transform.is_equal_approx(paused_transform), "Pause must freeze the visual pose.")
		check(actor._joints.Arm_L.rotation.is_equal_approx(paused_arm), "Pause must freeze the limbs.")
		check(not actor._voice.playing, "Pause and mute must silence the Lifelet voice.")
		actor.clear_activity_anchor()
		settle(actor, "", true)
		check(actor.visual.position.length() < .04, "Walking must return the visual to its navigation root.")
		check(absf(actor._marker.position.x) < .001 and absf(actor._marker.position.z) < .001, "Selection marker must leave the furniture anchor on walking.")
		for action_id: String in ["cook", "snack", "read", "paint", "water", "shower", "friendly", "joke", "argue", "ask_partner", "commit", "break_up"]:
			settle(actor, action_id)
			for bone: Dictionary in actor._rig_bones:
				var rotation: Quaternion = bone.skeleton.get_bone_pose_rotation(bone.index)
				check(rotation.is_finite() and rotation.is_normalized(), "Activity %s must leave a valid skeletal rotation." % action_id)
		actor.queue_free()
		await process_frame
	await create_timer(.15).timeout
	print("Actor integration: %d checks, %d failures." % [checks, failures])
	quit(1 if failures > 0 else 0)
