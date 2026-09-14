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


func tested_frames() -> Array[int]:
	return [0, 1]


func model_options() -> Dictionary:
	return {"low_detail":true}


func result_label() -> String:
	return "Actor integration"


func settle(actor: LifeActor, action_id: String, moving: bool = false) -> void:
	for frame_index: int in range(180):
		actor.animate(.016, 1.0, moving, action_id)


func actor_materials(actor: LifeActor) -> Dictionary:
	var shared: Dictionary = {}
	var by_name: Dictionary = {}
	var surface_count: int = 0
	for mesh_node: MeshInstance3D in actor._model.find_children("*", "MeshInstance3D", true, false):
		# Cooking utensils/books are created after character recolouring and
		# own independent material_override values. Inspect the actual imported
		# character scene, not those dynamically attached activity props.
		if mesh_node.owner != actor._model: continue
		for index: int in mesh_node.mesh.get_surface_count():
			var source: Material = mesh_node.mesh.surface_get_material(index)
			if not source is StandardMaterial3D: continue
			var material: Material = mesh_node.get_surface_override_material(index)
			check(material != null and material != source, "Actor styling must use a local material on " + str(mesh_node.name) + ".")
			var key: int = source.get_instance_id()
			if shared.has(key):
				check(shared[key] == material, "Surfaces using one source material share one actor-local recolour.")
			shared[key] = material
			by_name[source.resource_name] = material
			surface_count += 1
	check(surface_count > shared.size() * 3, "Shared styling avoids hundreds of duplicate surface materials.")
	return by_name


func run() -> void:
	for frame_index: int in tested_frames():
		var actor: LifeActor = Actor.new()
		root.add_child(actor)
		var test_profile: Dictionary = {"name":"Rig test", "frame":frame_index,
			"outfit":1, "hair":1, "height_scale":1.05, "body_scale":1.10}
		test_profile.merge(model_options(), true)
		actor.configure(test_profile)
		actor.voice_enabled = false
		var first_materials: Dictionary = actor_materials(actor)
		for surface_name: String in ["Skin_Face_Surface", "Eyes_Iris_Surface", "Eyes_Sclera_Surface"]:
			check(first_materials.has(surface_name), "The finished portrait exports " + surface_name + ".")
			if first_materials.has(surface_name):
				check(first_materials[surface_name].vertex_color_use_as_albedo, "Original facial colour zones survive glTF import for " + surface_name + ".")
		var painted_counts: Dictionary = {"Skin_Face_Surface":0, "Eyes_Iris_Surface":0, "Eyes_Sclera_Surface":0}
		for painted_mesh: MeshInstance3D in actor._model.find_children("*", "MeshInstance3D", true, false):
			if painted_mesh.owner != actor._model: continue
			for surface_index: int in painted_mesh.mesh.get_surface_count():
				var source_material: Material = painted_mesh.mesh.surface_get_material(surface_index)
				if source_material == null or not painted_counts.has(source_material.resource_name): continue
				painted_counts[source_material.resource_name] += 1
				var colors: Variant = painted_mesh.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_COLOR]
				check(colors is PackedColorArray and colors.size() == painted_mesh.mesh.surface_get_array_len(surface_index), "Vertex paint covers the complete portrait surface: " + str(painted_mesh.name))
		check(painted_counts.Skin_Face_Surface == 1, "The continuous face is fully painted.")
		check(painted_counts.Eyes_Iris_Surface == 2, "Both irises retain their colour data, regardless of imported name sanitization.")
		check(painted_counts.Eyes_Sclera_Surface == 2, "Both sclerae retain their colour data, regardless of imported name sanitization.")
		check(first_materials.has("Brows"), "Brows have their own material so pale hair does not erase the facial expression.")
		if first_materials.has("Brows"):
			check(first_materials.Brows != first_materials.Hair, "Brow styling is independent from the hair surface.")
		check(first_materials.has("Hair_Bob_Surface"), "The finished Bob exports its original directional surface material.")
		if first_materials.has("Hair_Bob_Surface"):
			var bob_material: StandardMaterial3D = first_materials.Hair_Bob_Surface
			check(bob_material.albedo_texture != null, "Bob retains original strand-tone texture.")
			check(bob_material.normal_enabled and bob_material.normal_texture != null, "Bob retains directional strand normals.")
			check(bob_material.roughness_texture != null, "Bob retains strand roughness variation.")
			check(bob_material.albedo_color.is_equal_approx(first_materials.Hair.albedo_color), "Bob and the other hairstyles use the same selected colour.")
		check(first_materials.has("Hair_Buzz_Surface"), "The close crop exports its original follicle surface material.")
		if first_materials.has("Hair_Buzz_Surface"):
			var buzz_material: StandardMaterial3D = first_materials.Hair_Buzz_Surface
			check(buzz_material.albedo_texture != null, "Buzz retains its original follicle tone and density map.")
			check(buzz_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "Buzz preserves the cutout density boundary without blended-hair sorting.")
			check(buzz_material.albedo_color.is_equal_approx(first_materials.Hair.albedo_color), "Buzz takes the same selected colour as the other hairstyles.")
		var neighbor: LifeActor = Actor.new()
		root.add_child(neighbor)
		var neighbor_profile: Dictionary = {"name":"Independent styling", "frame":frame_index,
			"skin_color":"492f26", "hair_color":"d7c19a", "brow_color":"574633", "top_color":"3e5879"}
		neighbor_profile.merge(model_options(), true)
		neighbor.configure(neighbor_profile)
		neighbor.voice_enabled = false
		var neighbor_materials: Dictionary = actor_materials(neighbor)
		if first_materials.has("Skin_Face_Surface") and neighbor_materials.has("Skin_Face_Surface"):
			check(first_materials.Skin_Face_Surface != neighbor_materials.Skin_Face_Surface, "Painted facial surfaces remain actor-local.")
			check(neighbor_materials.Skin_Face_Surface.albedo_color.is_equal_approx(Color("492f26")), "Facial paint multiplies the exact selected complexion, without replacing it.")
			check(first_materials.Skin_Face_Surface.albedo_color.is_equal_approx(first_materials.Skin.albedo_color), "Head and body retain the same base complexion.")
		if neighbor_materials.has("Brows"):
			check(neighbor_materials.Brows.albedo_color.is_equal_approx(Color("574633")), "An explicit brow colour overrides the natural fallback without changing hair.")
		if first_materials.has("Hair_Bob_Surface") and neighbor_materials.has("Hair_Bob_Surface"):
			check(first_materials.Hair_Bob_Surface != neighbor_materials.Hair_Bob_Surface, "Housemates have independently recoloured textured hair.")
			check(neighbor_materials.Hair_Bob_Surface.albedo_color.is_equal_approx(Color("d7c19a")), "Textured hair takes the exact selected colour.")
		if first_materials.has("Hair_Buzz_Surface") and neighbor_materials.has("Hair_Buzz_Surface"):
			check(first_materials.Hair_Buzz_Surface != neighbor_materials.Hair_Buzz_Surface, "Housemates do not share mutable close-crop materials.")
			check(neighbor_materials.Hair_Buzz_Surface.albedo_color.is_equal_approx(Color("d7c19a")), "Buzz density and follicle texture survive independent blond recolouring.")
		for name_key: String in ["Skin", "Hair", "Top"]:
			check(first_materials[name_key] != neighbor_materials[name_key], "Housemates must not share mutable appearance materials.")
		check(neighbor_materials.Skin.albedo_color.is_equal_approx(Color("492f26")), "Neighbor keeps the selected complexion.")
		check(first_materials.Skin.albedo_color.is_equal_approx(Color("bf825f")), "Creating a neighbor cannot recolour the first actor.")
		neighbor.queue_free()
		await process_frame
		check(actor._rig_bones.size() == 9, "All nine skeletal joints must resolve after glTF import.")
		check(actor._blink_shapes.size() >= 3, "Blink must include the face and eyes.")
		check(actor._smile_shapes.size() >= 1, "The face must support expression.")
		check(actor._sit_shapes.size() >= 1, "The trousers must expose the seated corrective morph.")
		check(actor._mouth_identity_offsets.has("face_length"), "Structural face morphs export the transported mouth contact landmark.")
		for feature: String in Actor.IDENTITY_KEYS:
			check(actor._identity_shapes.has(feature) and not actor._identity_shapes[feature].is_empty(), "Every facial control must drive real coupled morphs.")
			actor.set_face_feature(feature, .35)
			var contact: Vector3 = actor._mouth_anchor_rest + Vector3(actor._mouth_identity_offsets.get(feature, Vector3.ZERO)) * .35
			check(actor._mouth_anchor.is_equal_approx(contact), "Mouth contact follows the authored " + feature + " seam displacement.")
			for shape: Dictionary in actor._identity_shapes.get(feature, []):
				check(is_equal_approx(shape.mesh.get_blend_shape_value(shape.index), .35), "Every related face mesh must receive the selected identity value.")
			actor.set_face_feature(feature, 2.0)
			check(actor.profile[feature] == 1.0, "Facial controls must clamp to their supported range.")
			actor.set_face_feature(feature, -.5)
			check(actor.profile[feature] == (-.5 if feature in Actor.SIGNED_IDENTITY_KEYS else 0.0), "Signed facial controls preserve negative values; legacy controls clamp to neutral.")
			actor.set_face_feature(feature, -2.0)
			check(actor.profile[feature] == (-1.0 if feature in Actor.SIGNED_IDENTITY_KEYS else 0.0), "Facial controls clamp to their supported minimum.")
			actor.set_face_feature(feature, 0.0)
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
	print("%s: %d checks, %d failures." % [result_label(), checks, failures])
	quit(1 if failures > 0 else 0)
