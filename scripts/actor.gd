extends Node3D
class_name LifeActor
## Articulated original character. The parent world owns all navigation/movement.

const JOINT_NAMES: Array[String] = ["Head", "Arm_L", "Arm_R", "Forearm_L", "Forearm_R", "Leg_L", "Leg_R", "Shin_L", "Shin_R"]
const HAIR_NAMES: Array[String] = ["Hair_Crop", "Hair_Bob", "Hair_Curls", "Hair_Pony", "Hair_Long", "Hair_Buzz", "Hair_Waves", "Hair_Bun"]
const OUTFIT_NAMES: Array[String] = ["Outfit_Casual", "Outfit_Jacket", "Outfit_Cardigan", "Outfit_Tee", "Outfit_Hoodie"]
const BOTTOM_NAMES: Array[String] = ["Trousers", "Shorts"]
const VERIFIED_AGE_ASSETS: Array[String] = ["child","teen","elder"]
const IDENTITY_KEYS: Array[String] = ["face_round", "jaw_strong", "nose_wide", "eye_spacing"]

var profile: Dictionary = {}
var visual: Node3D
var selected: bool = false
var voice_enabled: bool = true:
	set(value):
		voice_enabled = value
		if not value and _voice != null:
			_voice.stop()
var _voice: AudioStreamPlayer3D
var _voice_streams: Dictionary = {}
var _voice_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _voice_cooldown: float = 0.0
var _voice_base_pitch: float = 1.0
var _voice_suspended: bool = false
var _last_voice_action: String = ""
var _pending_voice: String = ""
var interaction_offset: Vector3 = Vector3.ZERO
var _model: Node3D
var _joints: Dictionary = {}
var _rest_rotations: Dictionary = {}
var _ring: MeshInstance3D
var _marker: Node3D
var _speech: Label3D
var screen_speech: bool = false
var _book: Node3D
var _brush: Node3D
var _snack: Node3D
var _watering_can: Node3D
var _mop: Node3D
var _birthday_cake: Node3D
var _cake_center: Node3D
var _cake_flames: Array[Node3D] = []
var _birthday_weight: float = 0.0
var _cooking_bowl: Node3D
var _cooking_spoon: Node3D
var _bowl_center: Node3D
var _spoon_tip: Node3D
var _arm_rest: Dictionary = {}
var _leg_rest: Dictionary = {}
var _motion_action: String = ""
var _action_time: float = 0.0
# Short presentation event; never an action, route or saved simulation timer.
var _accident_time: float = -1.0
var _accident_visible: bool = false
var _cook_weight: float = 0.0
var _snack_weight: float = 0.0
var _time: float = 0.0
var _speech_remaining: float = 0.0
var _height: float = 1.0
var _authored_height: float = 1.76
var _hip_height: float = .90
var _knee_height: float = .548
var _proportion: float = 1.0
var _mouth_anchor: Vector3 = Vector3(0,.054,.114)
var _palm_anchors: Dictionary = {}
var _model_age: String = "young_adult"
var _phase_offset: float = 0.0
var _rig_bones: Array = []
var _blink_shapes: Array = []
var _smile_shapes: Array = []
var _sit_shapes: Array = []
var _identity_shapes: Dictionary = {}
var _grip_shapes: Dictionary = {"L":[],"R":[]}
var _grip_amounts: Dictionary = {"L":0.0,"R":0.0}
var _grip_anchors: Dictionary = {}
var _hand_props: Array = []
var _sit_amount: float = 0.0
var _hair_bob: Node3D
var _hair_bob_rest_scale: Vector3 = Vector3.ONE
var _blink_wait: float = 2.5
var _blink_elapsed: float = -1.0
var _smile: float = 0.0
var _activity_anchor: Dictionary = {}
var meal_presentation: Dictionary = {}
# Controller-owned recipe identity and normalized progress; visual state only.
var cooking_presentation: Dictionary = {}
var stair_presentation:Dictionary={}
var _reconstructing_stair:bool=false
var stair_pose_valid:bool=true
var stair_pose_error:String=""
var _stair_exit_carry:bool=false
var _reconstructing_cooking: bool = false
var _reconstructing_sanitation:bool=false
var _reconstructing_meal:bool=false
var _reconstructing_rest:bool=false
var _presented_cooking_recipe: String = "garden_skillet"
var _recipe_bowl: Node3D
var _recipe_bowl_food: Node3D
var _baking_tray: Node3D
var _baking_food: Node3D
var _seasoning_jar: Node3D
var _seasoning_grains: Array[MeshInstance3D] = []
var _seasoning_weight: float = 0.0
var _preparation_tip: Vector3 = Vector3.ZERO
var _seasoning_axis: Vector3 = Vector3.DOWN
var _meal_fork: Node3D
var _meal_tip: Vector3 = Vector3.ZERO


func _ready() -> void:
	_ensure_nodes()
	if _model == null:
		configure(profile)


func _ensure_nodes() -> void:
	if visual != null:
		return
	visual = Node3D.new()
	visual.name = "AnimatedVisual"
	add_child(visual)
	_ring = MeshInstance3D.new()
	_ring.name = "SelectionRing"
	var ring_mesh: TorusMesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.31
	ring_mesh.outer_radius = 0.335
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 8
	_ring.mesh = ring_mesh
	_ring.position.y = 0.025
	_ring.material_override = _material(Color("77bd9d"), true)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_marker = Node3D.new()
	_marker.name = "SelectedSprout"
	add_child(_marker)
	var stem: MeshInstance3D = _cylinder(_marker, 0.011, 0.14, Color("467967"))
	stem.position.y = 0.03
	var leaf_left: MeshInstance3D = _sphere(_marker, Vector3(0.044, 0.095, 0.026), Color("77bd9d"))
	leaf_left.position = Vector3(-0.045, 0.078, 0.0)
	leaf_left.rotation.z = 0.7
	var leaf_right: MeshInstance3D = _sphere(_marker, Vector3(0.048, 0.105, 0.027), Color("b3dca6"))
	leaf_right.position = Vector3(0.047, 0.095, 0.0)
	leaf_right.rotation.z = -0.7
	_speech = Label3D.new()
	_speech.name = "Speech"
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.font_size = 44
	_speech.pixel_size = 0.003
	_speech.outline_size = 14
	_speech.modulate = Color("29473f")
	_speech.outline_modulate = Color("fffcf0")
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.width = 640.0
	_speech.shaded = false
	_speech.visible = false
	if ResourceLoader.exists("res://assets/fonts/Body.ttf"):
		_speech.font = load("res://assets/fonts/Body.ttf")
	add_child(_speech)
	_voice = AudioStreamPlayer3D.new()
	_voice.name = "LifeletVoice"
	_voice.position.y = 1.5
	_voice.unit_size = 8.0
	_voice.max_distance = 42.0
	_voice.volume_db = -2.0
	_voice.max_polyphony = 1
	add_child(_voice)
	for category: String in ["greeting", "happy", "thoughtful", "argument", "reaction"]:
		var audio_path: String = "res://assets/audio/voice_%s.wav" % category
		if ResourceLoader.exists(audio_path):
			var stream: AudioStreamWAV = load(audio_path) as AudioStreamWAV
			if stream != null:
				_voice_streams[category] = stream
	set_selected(selected)


func configure(new_profile: Dictionary) -> void:
	_ensure_nodes()
	if has_meta("layer_cache"): remove_meta("layer_cache")  # a new model needs its view layers and pick bodies assigned again
	profile = new_profile.duplicate(true)
	if _model != null:
		visual.remove_child(_model)
		_model.queue_free()
		_model = null
	_joints.clear()
	_rest_rotations.clear()
	_rig_bones.clear()
	_blink_shapes.clear()
	_smile_shapes.clear()
	_sit_shapes.clear()
	_identity_shapes.clear()
	_grip_shapes = {"L":[],"R":[]}
	_grip_amounts = {"L":0.0,"R":0.0}
	_hand_props.clear()
	_hair_bob = null
	_sit_amount = 0.0
	_cook_weight = 0.0
	_presented_cooking_recipe = "garden_skillet"
	_seasoning_weight = 0.0
	_seasoning_grains.clear()
	_birthday_weight = 0.0
	_cake_flames.clear()
	_snack_weight = 0.0
	_motion_action = ""
	_action_time = 0.0
	_accident_time = -1.0
	_accident_visible = false
	_arm_rest.clear()
	_leg_rest.clear()
	_smile = 0.0
	_activity_anchor = {}
	var frame: int = clampi(int(profile.get("frame", 0)), 0, 1)
	var path: String = "res://assets/models/character_broad.glb" if frame == 1 else "res://assets/models/character.glb"
	if bool(profile.get("low_detail", false)):
		var lod_path: String = "res://assets/models/character_broad_lod.glb" if frame == 1 else "res://assets/models/character_lod.glb"
		if ResourceLoader.exists(lod_path):
			path = lod_path
	var stage: String = str(profile.get("age_stage","young_adult"))
	if stage in ["child","teen","elder"]:
		path = _age_model_path(stage,frame,bool(profile.get("low_detail",false)))
	# Staged rigs can be reviewed without replacing the released articulated assets.
	if bool(profile.get("rig_preview", false)) and stage not in ["child","teen","elder"]:
		var rig_path: String = "res://assets/models/character_broad_rig" if frame == 1 else "res://assets/models/character_rig"
		rig_path += "_lod.glb" if bool(profile.get("low_detail", false)) else ".glb"
		if ResourceLoader.exists(rig_path):
			path = rig_path
	if not ResourceLoader.exists(path):
		push_error("JustLife character model is missing: " + path)
		return
	var scene: PackedScene = load(path)
	_model = scene.instantiate()
	visual.add_child(_model)
	_read_age_landmarks(stage)
	var body_scale: float = clampf(float(profile.get("body_scale", 1.0)), 0.85, 1.15)
	_height = clampf(float(profile.get("height_scale", 1.0)), 0.93, 1.08)
	visual.scale = Vector3(body_scale, _height, body_scale)
	visual.position = Vector3.ZERO
	visual.rotation = Vector3.ZERO
	_phase_offset = float(abs(str(profile.get("name", "Alex")).hash()) % 100) * 0.061
	_voice_rng.seed = abs(str(profile.get("name", "Alex")).hash()) + 71
	_voice_base_pitch = clampf(float(profile.get("voice_pitch", 0.91 + float(_voice_rng.randi_range(0, 20)) * 0.01)), 0.80, 1.30)
	_voice_cooldown = _voice_rng.randf_range(0.2, 1.0)
	_blink_wait = 1.5 + _phase_offset * 0.45
	_blink_elapsed = -1.0
	_voice.position.y = (_authored_height-.26) * _height
	var hair_index: int = clampi(int(profile.get("hair", 0)), 0, HAIR_NAMES.size() - 1)
	# Older exports lack the later styles; fall back to the first authored style rather than showing no hair.
	if _model.find_child(HAIR_NAMES[hair_index], true, false) == null: hair_index = 0
	for index: int in range(HAIR_NAMES.size()):
		var group: Node3D = _model.find_child(HAIR_NAMES[index], true, false) as Node3D
		if group != null:
			group.visible = index == hair_index
			if HAIR_NAMES[index] == "Hair_Bob":
				_hair_bob = group
				_hair_bob_rest_scale = group.scale
	for joint_name: String in JOINT_NAMES:
		var joint: Node3D = _model.find_child(joint_name, true, false) as Node3D
		if joint != null:
			_joints[joint_name] = joint
			_rest_rotations[joint_name] = joint.rotation
	for side: String in ["L", "R"]:
		if _joints.has("Arm_" + side) and _joints.has("Forearm_" + side):
			var shoulder: Node3D = _joints["Arm_" + side]
			var elbow: Node3D = _joints["Forearm_" + side]
			_arm_rest[side] = {"shoulder": _model.to_local(shoulder.global_position),
				"upper": elbow.position, "lower": _palm_offset(side), "local_shoulder":shoulder.position,
				"space":_model.global_transform.affine_inverse()*shoulder.get_parent().global_transform}
		if _joints.has("Leg_"+side) and _joints.has("Shin_"+side):
			var hip:Node3D=_joints["Leg_"+side]
			var knee:Node3D=_joints["Shin_"+side]
			var lower:Vector3=Vector3(0,-(_knee_height-.10*_proportion),0)
			var ankle:=Node3D.new();ankle.name="PlantedShoe_"+side;knee.add_child(ankle);ankle.position=lower
			for child:Node in knee.get_children().duplicate():
				if child is Node3D and child.name.begins_with("Shoes_"):child.reparent(ankle,true)
			_leg_rest[side]={"hip":hip.position,"upper":knee.position,"lower":lower,
				"foot":_model.to_local(knee.to_global(lower)),"space":_model.global_transform.affine_inverse()*hip.get_parent().global_transform,
				"shoe":ankle,"shoe_basis":global_basis.inverse()*ankle.global_basis}
	_cache_stair_sole_offsets()
	_discover_deformation(_model)
	for key: String in IDENTITY_KEYS:
		var value: Variant = profile.get(key, 0.0)
		set_face_feature(key, float(value) if value is float or value is int else 0.0)
	set_outfit(clampi(int(profile.get("outfit",0)),0,OUTFIT_NAMES.size()-1))
	set_bottom(clampi(int(profile.get("bottom",0)),0,BOTTOM_NAMES.size()-1))
	_recolor(_model)
	_create_props()
	_marker.position.y = (_authored_height+.21) * _height
	_speech.position.y = (_authored_height+.54) * _height


static func _age_model_path(stage: String, frame: int, low_detail: bool) -> String:
	return "res://assets/models/character_%s%s%s.glb" % [stage,"_broad" if frame == 1 else "","_lod" if low_detail else ""]


static func available_age_stages() -> Array[String]:
	var result: Array[String] = []
	for stage: String in ["child","teen","young_adult","adult","elder"]:
		var ready: bool = true
		if stage in ["child","teen","elder"]:
			ready = stage in VERIFIED_AGE_ASSETS
			for frame: int in range(2):
				for lod: bool in [false,true]:
					if not ResourceLoader.exists(_age_model_path(stage,frame,lod)): ready = false
		if ready: result.append(stage)
	return result


func supports_age(stage: String) -> bool:
	return stage in available_age_stages()


func get_display_height() -> float:
	return _authored_height * _height


func get_portrait_center() -> Vector3:
	var head: Node3D = _joints.get("Head")
	if head != null:
		return to_local(head.to_global(Vector3(0,_mouth_anchor.y+.03,.015)))
	return Vector3(0,get_display_height()*.86,0)


func get_body_landmarks() -> Dictionary:
	return {"age_stage":_model_age,"height":get_display_height(),"authored_height":_authored_height,
		"hip_height":_hip_height*_height,"knee_height":_knee_height*_height,
		"mouth_anchor":_mouth_anchor,"palm_anchor_l":_palm_offset("L"),"palm_anchor_r":_palm_offset("R")}


func _find_model_extras(node: Node) -> Dictionary:
	var extras: Variant = node.get_meta("extras",{})
	if extras is Dictionary and extras.has("height_m"): return extras
	for child: Node in node.get_children():
		var found: Dictionary = _find_model_extras(child)
		if not found.is_empty(): return found
	return {}


func _read_age_landmarks(stage: String) -> void:
	var extras: Dictionary = _find_model_extras(_model)
	_model_age = str(extras.get("age_stage",stage))
	_authored_height = _landmark_number(extras,"height_m",1.76,.75,2.3)
	_hip_height = _landmark_number(extras,"hip_height",.90,.3,1.2)
	_knee_height = _landmark_number(extras,"knee_height",.548,.15,.8)
	_proportion = _authored_height/1.76
	_mouth_anchor = _landmark_vector(extras.get("mouth_anchor"),Vector3(0,.054,.114))
	_palm_anchors = {"L":_landmark_vector(extras.get("palm_anchor_l"),Vector3(-.024,-.274,.026)),
		"R":_landmark_vector(extras.get("palm_anchor_r"),Vector3(.024,-.274,.026))}
	_grip_anchors = {"L":_landmark_vector(extras.get("grip_anchor_l"),_palm_anchors.L),
		"R":_landmark_vector(extras.get("grip_anchor_r"),_palm_anchors.R)}


func _landmark_number(extras: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = extras.get(key,fallback)
	return float(value) if (value is float or value is int) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum else fallback


func _landmark_vector(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array or value.size() != 3: return fallback
	for axis: Variant in value:
		if not (axis is float or axis is int) or not is_finite(float(axis)) or absf(float(axis)) > 1.0: return fallback
	return Vector3(float(value[0]),float(value[1]),float(value[2]))


func set_outfit(index: int) -> void:
	profile["outfit"] = clampi(index,0,OUTFIT_NAMES.size()-1)
	if _model != null:
		var selected: String = OUTFIT_NAMES[int(profile["outfit"])]
		if _model.find_child(selected, true, false) == null: selected = OUTFIT_NAMES[0]
		_apply_outfit_visibility(_model,selected)


func set_bottom(index: int) -> void:
	profile["bottom"] = clampi(index,0,BOTTOM_NAMES.size()-1)
	if _model != null:
		var shorts: bool = int(profile["bottom"]) == 1 and _model.find_child("Bottom_Shorts", true, false) != null
		_apply_bottom_visibility(_model,shorts)


func _apply_bottom_visibility(node: Node,shorts: bool) -> void:
	if node is Node3D:
		var node_name: String = str(node.name)
		if node_name.begins_with("Bottom_Shorts"): node.visible = shorts
		elif node_name.begins_with("Bottom_Continuous") or node_name.begins_with("Bottom_Cuff"): node.visible = not shorts
		elif node_name.begins_with("Skin_Leg"): node.visible = shorts  # hidden under trousers, so it costs nothing there
	for child: Node in node.get_children():
		_apply_bottom_visibility(child,shorts)


func set_face_feature(feature: String, value: float) -> void:
	var key: String = feature.to_lower()
	if key not in IDENTITY_KEYS:
		return
	var amount: float = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	profile[key] = amount
	for entry: Dictionary in _identity_shapes.get(key, []):
		entry.mesh.set_blend_shape_value(int(entry.index), amount)
	if _hair_bob != null:
		var expansion: float = 1.0 + .04 * float(profile.get("face_round", 0.0)) + .03 * float(profile.get("jaw_strong", 0.0))
		_hair_bob.scale = _hair_bob_rest_scale * Vector3(expansion, 1.0, 1.0)


func _apply_outfit_visibility(node: Node,selected_outfit: String) -> void:
	if node is Node3D and str(node.name).begins_with("Outfit_"):
		node.visible = str(node.name).begins_with(selected_outfit)
	for child: Node in node.get_children():
		_apply_outfit_visibility(child,selected_outfit)


func _discover_deformation(node: Node) -> void:
	if node is Skeleton3D:
		var skeleton: Skeleton3D = node
		for joint_name: String in JOINT_NAMES:
			var bone_index: int = skeleton.find_bone(joint_name)
			# Imported glTF bones share names with the retained accessory pivots.
			# Godot disambiguates those bone names as Arm_L_2, Head_2, and so on.
			if bone_index < 0:
				for candidate: int in range(skeleton.get_bone_count()):
					var imported_name: String = str(skeleton.get_bone_name(candidate))
					if imported_name.begins_with(joint_name + "_") and imported_name.trim_prefix(joint_name + "_").is_valid_int():
						bone_index = candidate
						break
			if bone_index >= 0:
				_rig_bones.append({"skeleton":skeleton,"index":bone_index,"name":joint_name,"rest":skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()})
	if node is MeshInstance3D and node.mesh != null:
		var mesh_node: MeshInstance3D = node
		for shape_index: int in range(mesh_node.mesh.get_blend_shape_count()):
			var shape_name: String = str(mesh_node.mesh.get_blend_shape_name(shape_index)).to_lower()
			if shape_name == "blink":
				_blink_shapes.append({"mesh":mesh_node,"index":shape_index})
				mesh_node.set_blend_shape_value(shape_index,0.0)
			elif shape_name == "smile":
				_smile_shapes.append({"mesh":mesh_node,"index":shape_index})
				mesh_node.set_blend_shape_value(shape_index,0.0)
			elif shape_name == "sit":
				_sit_shapes.append({"mesh":mesh_node,"index":shape_index})
				mesh_node.set_blend_shape_value(shape_index,0.0)
			elif shape_name in ["hand_grip_l","hand_grip_r"]:
				var side: String = "L" if shape_name.ends_with("_l") else "R"
				_grip_shapes[side].append({"mesh":mesh_node,"index":shape_index})
				mesh_node.set_blend_shape_value(shape_index,0.0)
			elif shape_name in IDENTITY_KEYS:
				if not _identity_shapes.has(shape_name):
					_identity_shapes[shape_name] = []
				_identity_shapes[shape_name].append({"mesh":mesh_node,"index":shape_index})
				mesh_node.set_blend_shape_value(shape_index,0.0)
	for child: Node in node.get_children():
		_discover_deformation(child)


func set_activity_anchor(world_position: Vector3,world_yaw: float,anchor_kind: String = "standing",action_id: String = "",details: Dictionary = {}) -> void:
	## seat: cushion top center; bed: mattress top center; standing: foot position.
	## The anchor's +Z faces forward; a lying Lifelet's head points toward its -Z.
	_activity_anchor = {"position":world_position,"yaw":world_yaw,"kind":anchor_kind,"action":action_id}
	if details.get("hand_center") is Vector3 and details.hand_center.is_finite(): _activity_anchor["hand_center"] = details.hand_center
	if details.get("hand_spread") is float or details.get("hand_spread") is int:
		_activity_anchor["hand_spread"] = clampf(float(details.hand_spread),.04,.2)

	if details.get("desk_surface_y") is float or details.get("desk_surface_y") is int:
		if is_finite(float(details.desk_surface_y)): _activity_anchor["desk_surface_y"] = float(details.desk_surface_y)
	for key: String in ["desk_front_edge","desk_forward","attention_target","plate_position","mop_contact"]:
		if details.get(key) is Vector3 and details[key].is_finite(): _activity_anchor[key] = details[key]
	if is_instance_valid(details.get("oven")):_activity_anchor["oven"]=details.oven


func clear_activity_anchor() -> void:
	_activity_anchor = {}
	interaction_offset = Vector3.ZERO


func _profile_color(key: String, fallback: String) -> Color:
	var value: Variant = profile.get(key, fallback)
	if value is Color:
		return value
	return Color.from_string(str(value), Color(fallback))


func _recolor(node: Node) -> void:
	var skin: Color = _profile_color("skin_color", "bf825f")
	var hair: Color = _profile_color("hair_color", "32221f")
	var top: Color = _profile_color("top_color", "658a83")
	var bottom: Color = _profile_color("bottom_color", "675d73")
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node
		if mesh_node.mesh != null:
			for surface_index: int in range(mesh_node.mesh.get_surface_count()):
				var original: Material = mesh_node.mesh.surface_get_material(surface_index)
				if not original is StandardMaterial3D:
					continue
				var material: StandardMaterial3D = original.duplicate() as StandardMaterial3D
				var name_key: String = original.resource_name
				match name_key:
					"Skin": material.albedo_color = skin
					"Ear_detail": material.albedo_color = skin.darkened(0.12).lerp(Color("b87565"), 0.12)
					"Nose_detail": material.albedo_color = skin.darkened(0.40)
					"Lips": material.albedo_color = skin.darkened(0.12).lerp(Color("b87070"), 0.42)
					"Hair": material.albedo_color = hair
					"Hair_highlight": material.albedo_color = hair.lightened(0.15)
					"Hair_shadow": material.albedo_color = hair.darkened(0.25)
					"Top": material.albedo_color = top
					"Top_seam": material.albedo_color = top.darkened(0.20)
					"Bottom": material.albedo_color = bottom
					"Bottom_seam": material.albedo_color = bottom.darkened(0.19)
					"Eyes": material.albedo_color = _profile_color("eye_color", "547365")
					"Eyes_edge": material.albedo_color = _profile_color("eye_color", "547365").darkened(0.40)
					"Shoes": material.albedo_color = _profile_color("shoe_color", "e9e4d9")
				mesh_node.set_surface_override_material(surface_index, material)
	for child: Node in node.get_children():
		_recolor(child)


func _create_props() -> void:
	if is_instance_valid(_mop):
		remove_child(_mop);_mop.queue_free()
	_mop=load("res://assets/models/juniper_mop.glb").instantiate()
	_mop.name="JuniperMop"
	add_child(_mop)
	_mop.visible=false
	_book = Node3D.new()
	_book.name = "ReadingBook"
	_model.add_child(_book)
	_book.position = Vector3(0.0, 1.10, 0.32)
	_book.position *= _proportion
	_book.scale = Vector3.ONE * _proportion
	_book.rotation.x = 0.35
	var cover: MeshInstance3D = _box(_book, Vector3(0.26, 0.019, 0.18), Color("ba735c"))
	cover.position.y = -0.009
	var pages: MeshInstance3D = _box(_book, Vector3(0.24, 0.027, 0.17), Color("eee7d0"))
	pages.position.y = 0.014
	var spine: MeshInstance3D = _box(_book, Vector3(0.006, 0.003, 0.164), Color("bfb392"))
	spine.position.y = 0.029
	_book.visible = false
	_brush = _hand_anchor("PaintBrush", "R")
	var handle: MeshInstance3D = _cylinder(_brush, 0.008, 0.22, Color("b88b53"))
	handle.rotation.x = PI / 2.0
	handle.position.z = 0.08
	var ferrule: MeshInstance3D = _cylinder(_brush, 0.009, 0.035, Color("d5c8a8"))
	ferrule.rotation.x = PI / 2.0
	ferrule.position.z = 0.192
	var bristles: MeshInstance3D = _sphere(_brush, Vector3(0.009, 0.010, 0.028), Color("5b8d8c"))
	bristles.position.z = 0.22
	_brush.scale = Vector3.ONE * _proportion
	_brush.visible = false
	_snack = _hand_anchor("Snack", "R")
	# A small vegetable roll, with separate bread, filling and lettuce silhouettes.
	var bread_bottom: MeshInstance3D = _sphere(_snack, Vector3(.044,.013,.035), Color("b87f43"))
	bread_bottom.position = Vector3(0,.011,.025)
	var filling: MeshInstance3D = _sphere(_snack, Vector3(.040,.008,.032), Color("be674e"))
	filling.position = Vector3(0,.024,.025)
	for index: int in range(5):
		var leaf: MeshInstance3D = _sphere(_snack, Vector3(.026,.005,.021), Color("6c8b47"))
		var angle: float = float(index) * TAU / 5.0
		leaf.position = Vector3(sin(angle)*.023,.029,.025+cos(angle)*.019)
		leaf.rotation.y = angle
	var bread_top: MeshInstance3D = _sphere(_snack, Vector3(.045,.019,.036), Color("d3a56b"))
	bread_top.position = Vector3(0,.046,.025)
	for index: int in range(6):
		var seed: MeshInstance3D = _sphere(_snack, Vector3(.0025,.0015,.005), Color("f0dbaf"))
		seed.position = Vector3(float(index%3-1)*.015,.064-absf(float(index%3-1))*.003,.013+float(index/3)*.025)
		seed.rotation.y = float(index)*.8
	_snack.visible = false
	_cooking_bowl = _hand_anchor("CookingBowlGrip", "L")
	_bowl_center = Node3D.new()
	_bowl_center.name = "BowlCenter"
	_bowl_center.position = Vector3(.035,.105,.025)
	_cooking_bowl.add_child(_bowl_center)
	# The support palm lies under the rounded base; the old side attachment
	# intersected the wall when the fingers curled.
	# A shallow glazed bowl: layered exterior, open rim and visible ingredients.
	var bowl_body: MeshInstance3D = _sphere(_bowl_center, Vector3(.147,.070,.147), Color("638c86"))
	bowl_body.position.y = -.028
	var bowl_inside: MeshInstance3D = _cylinder(_bowl_center, .133, .014, Color("e2cfac"))
	bowl_inside.position.y = .031
	var rim: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: TorusMesh = TorusMesh.new()
	rim_mesh.inner_radius = .130
	rim_mesh.outer_radius = .147
	rim_mesh.rings = 40
	rim_mesh.ring_segments = 8
	rim.mesh = rim_mesh
	rim.material_override = _material(Color("b1cac0"))
	rim.position.y = .044
	_bowl_center.add_child(rim)
	for index: int in range(9):
		var ingredient: MeshInstance3D = _sphere(_bowl_center, Vector3(.014,.008,.011), Color("be754c") if index%2 == 0 else Color("719149"))
		var angle: float = float(index)*2.4
		ingredient.position = Vector3(sin(angle)*.08,.043,cos(angle)*.08)
	_cooking_spoon = _hand_anchor("CookingSpoonGrip", "R")
	var spoon_handle: MeshInstance3D = _cylinder(_cooking_spoon,.009,.21,Color("ae7844"))
	spoon_handle.position.y = -.049
	var spoon_end: MeshInstance3D = _sphere(_cooking_spoon,Vector3(.023,.039,.011),Color("c6975d"))
	spoon_end.position.y = -.18
	_spoon_tip = Node3D.new()
	_spoon_tip.name = "SpoonContact"
	_spoon_tip.position.y = -.19
	_cooking_spoon.add_child(_spoon_tip)
	_cooking_bowl.visible = false
	_cooking_spoon.visible = false
	_create_recipe_props()
	_meal_fork = _hand_anchor("MealForkGrip", "R")
	if ResourceLoader.exists("res://assets/models/meal_fork.glb"):
		_meal_fork.add_child(load("res://assets/models/meal_fork.glb").instantiate())
	_meal_fork.visible = false
	_birthday_cake = _hand_anchor("BirthdayCakeGrip","L")
	_cake_center = Node3D.new()
	_cake_center.name = "CakeCenter"
	_cake_center.position = Vector3(.12,-.006,0)
	_birthday_cake.add_child(_cake_center)
	if ResourceLoader.exists("res://assets/models/birthday_cake.glb"):
		var cake_scene: PackedScene = load("res://assets/models/birthday_cake.glb")
		var cake: Node3D = cake_scene.instantiate()
		_cake_center.add_child(cake)
		for flame: Node in cake.find_children("Flame_*","Node3D",true,false):
			_cake_flames.append(flame as Node3D)
	_birthday_cake.visible = false
	_watering_can = _hand_anchor("WateringCan", "R")
	var can: MeshInstance3D = _cylinder(_watering_can, 0.072, 0.14, Color("97b5a3"))
	can.position = Vector3(0.03, -0.08, 0.0)
	var spout: MeshInstance3D = _cylinder(_watering_can, 0.017, 0.18, Color("7a9b89"))
	spout.rotation.x = 0.95
	spout.position = Vector3(0.03, -0.043, 0.12)
	_watering_can.scale = Vector3.ONE * _proportion
	_watering_can.visible = false


func _hand_anchor(anchor_name: String, side: String) -> Node3D:
	var anchor: Node3D = Node3D.new()
	anchor.name = anchor_name
	var parent_joint: Node3D = _joints.get("Forearm_" + side, _model)
	parent_joint.add_child(anchor)
	anchor.position = _palm_offset(side)
	_hand_props.append({"node":anchor,"side":side})
	return anchor


func _palm_offset(side: String) -> Vector3:
	return _palm_anchors.get(side,Vector3(.024 if side == "R" else -.024,-.274,.026))


func _grip_offset(side: String) -> Vector3:
	if _grip_shapes.get(side,[]).is_empty(): return _palm_offset(side)
	return _palm_offset(side).lerp(_grip_anchors.get(side,_palm_offset(side)),float(_grip_amounts.get(side,0.0)))


func _update_grips(delta: float, moving: bool, action_id: String) -> void:
	var targets: Dictionary = {"L":0.0,"R":0.0}
	if not moving:
		match action_id:
			"cook":
				targets = {"L":.25,"R":.95}
				if _presented_cooking_recipe=="harvest_bake":targets={"L":.20,"R":.65 if _is_seasoning() else .30}
				elif _is_seasoning():targets.R=.65
			"snack": targets.R = .45
			"eat_meal": targets.R = .78
			"paint": targets.R = .80
			"water": targets.R = .55
			"mop_puddle": targets = {"L":.8,"R":.8}
			"read": targets = {"L":.20,"R":.20}
			"study","homework":
				if str(_activity_anchor.get("kind","")) == "standing": targets = {"L":.20,"R":.20}
			"birthday":
				if _action_time < 3.85: targets = {"L":.30,"R":.30}
	if bool(meal_presentation.get("carrying",false)):
		var hold:float=.38 if bool(meal_presentation.get("platter",false)) else .20
		targets={"L":hold,"R":hold}
	var blend: float = 1.0 if _reconstructing_stair or not stair_presentation.is_empty() or _reconstructing_cooking or _reconstructing_sanitation or _reconstructing_meal or _reconstructing_rest or (not moving and action_id=="cook" and _has_oven()) else 1.0-exp(-delta*8.0)
	for side: String in ["L","R"]:
		_grip_amounts[side] = float(targets[side]) if blend>=1.0 else lerpf(float(_grip_amounts[side]),float(targets[side]),blend)
		for entry: Dictionary in _grip_shapes[side]:
			entry.mesh.set_blend_shape_value(int(entry.index),float(_grip_amounts[side]))
	for entry: Dictionary in _hand_props:
		entry.node.position = _grip_offset(str(entry.side))


func _reach_hand(pose: Dictionary, side: String, target: Vector3, elbow_direction: Vector3, handle_axis: Vector3 = Vector3.ZERO, contact_axis: Vector3 = Vector3.RIGHT) -> void:
	if not _arm_rest.has(side):
		return
	var solution: Dictionary = _arm_solution(side,target,elbow_direction,handle_axis,contact_axis)
	pose["Arm_"+side] = Quaternion(solution.arm).get_euler()
	pose["Forearm_"+side] = Quaternion(solution.forearm).get_euler()


func _arm_solution(side: String, target: Vector3, elbow_direction: Vector3, handle_axis: Vector3 = Vector3.ZERO, contact_axis: Vector3 = Vector3.RIGHT) -> Dictionary:
	var rest: Dictionary = _arm_rest[side]
	# Solve before the authored broad-frame scale, then report model-space landmarks.
	var space: Transform3D = rest.space
	target = space.affine_inverse()*target
	elbow_direction = space.basis.inverse()*elbow_direction
	handle_axis = space.basis.inverse()*handle_axis
	var shoulder: Vector3 = rest.local_shoulder
	var upper: Vector3 = rest.upper
	var lower: Vector3 = _grip_offset(side)
	var reach: Vector3 = target-shoulder
	var distance: float = clampf(reach.length(),absf(upper.length()-lower.length())+.005,upper.length()+lower.length()-.005)
	var forward: Vector3 = reach.normalized()
	var bend: Vector3 = (elbow_direction-forward*elbow_direction.dot(forward)).normalized()
	var along: float = (upper.length_squared()-lower.length_squared()+distance*distance)/(2.0*distance)
	var away: float = sqrt(maxf(0.0,upper.length_squared()-along*along))
	var desired_axis: Vector3 = Vector3.ZERO
	# The hand encloses a shaft along local X. Choose the elbow on its reach circle
	# so that axis can follow the shaft without displacing the palm target.
	if not handle_axis.is_zero_approx():
		desired_axis = -handle_axis.normalized() if side == "R" else handle_axis.normalized()
		var flat: Vector3 = desired_axis-forward*desired_axis.dot(forward)
		if away > .0001 and flat.length() > .0001:
			var tangent: Vector3 = forward.cross(flat).normalized()
			var coefficient: float = clampf(((distance-along)*forward.dot(desired_axis)-lower.dot(contact_axis))/(away*flat.length()),-1.0,1.0)
			var remainder: float = sqrt(maxf(0.0,1.0-coefficient*coefficient))
			if tangent.dot(bend) < 0.0: tangent = -tangent
			bend = flat.normalized()*coefficient+tangent*remainder
	var upper_goal: Vector3 = forward*along+bend*away
	var lower_goal: Vector3 = forward*distance-upper_goal
	var arm: Quaternion = Quaternion(upper.normalized(),upper_goal.normalized())
	var forearm: Quaternion = Quaternion(lower.normalized(),arm.inverse()*lower_goal.normalized())
	if not handle_axis.is_zero_approx():
		var pivot_axis: Vector3 = lower_goal.normalized()
		var current_axis: Vector3 = arm*forearm*contact_axis
		var current_plane: Vector3 = (current_axis-pivot_axis*current_axis.dot(pivot_axis)).normalized()
		var desired_plane: Vector3 = (desired_axis-pivot_axis*desired_axis.dot(pivot_axis)).normalized()
		var twist: float = atan2(pivot_axis.dot(current_plane.cross(desired_plane)),current_plane.dot(desired_plane))
		forearm = arm.inverse()*Quaternion(pivot_axis,twist)*arm*forearm
	return {"arm":arm,"forearm":forearm,"shoulder":space*shoulder,"elbow":space*(shoulder+upper_goal),"hand":space*(shoulder+forward*distance)}


func _typing_elbow(side: String, model_basis: Basis) -> Vector3:
	var outward: Vector3 = Basis(Vector3.UP,float(_activity_anchor.get("yaw",0.0)))*Vector3(-.45 if side == "L" else .45,0,-.10)
	return model_basis.inverse()*(Vector3.UP+outward)


func _desk_segment_clearance(start: Vector3, end: Vector3, radius: float) -> float:
	# Clip the whole padded limb segment to the desk's front plane. Endpoints alone
	# can reach the keyboard while a bent elbow passes through the desktop.
	if not _activity_anchor.has("desk_surface_y") or not _activity_anchor.has("desk_front_edge") or not _activity_anchor.has("desk_forward"): return INF
	var forward: Vector3 = Vector3(_activity_anchor.desk_forward).normalized()
	var edge: Vector3 = _activity_anchor.desk_front_edge
	var a: float = (start-edge).dot(forward)+radius
	var b: float = (end-edge).dot(forward)+radius
	if a < 0.0 and b < 0.0: return INF
	var first: Vector3 = start
	var last: Vector3 = end
	if a < 0.0: first = start.lerp(end,-a/(b-a))
	if b < 0.0: last = start.lerp(end,a/(a-b))
	return minf(first.y,last.y)-float(_activity_anchor.desk_surface_y)-radius


func _desk_lean() -> float:
	var best: float = .15
	var least_cost: float = INF
	var yaw: float = float(_activity_anchor.yaw)
	var anchor: Vector3 = _activity_anchor.position
	var keyboard: Vector3 = _activity_anchor.hand_center
	var spread: float = float(_activity_anchor.get("hand_spread",.105))
	for step: int in range(33):
		var angle: float = .15+float(step)*.025
		var orientation: Basis = Basis(Vector3.UP,yaw)*Basis.from_euler(Vector3(angle,0,0))
		var origin: Vector3 = anchor-orientation*Vector3(0,_hip_height*_height,0)
		var model_pose: Transform3D = Transform3D(orientation*Basis.IDENTITY.scaled(visual.scale),origin)*_model.transform
		var inverse: Transform3D = model_pose.affine_inverse()
		var excess: float = 0.0
		var clearance: float = INF
		for side: String in ["L","R"]:
			if not _arm_rest.has(side): continue
			var hand: Vector3 = keyboard+Basis(Vector3.UP,yaw)*Vector3(-spread if side == "L" else spread,0,0)
			var arm_length: float = Vector3(_arm_rest[side].upper).length()+_grip_offset(side).length()-.010
			var arm_space: Transform3D = _arm_rest[side].space
			excess = maxf(excess,(arm_space.affine_inverse()*(inverse*hand)-Vector3(_arm_rest[side].local_shoulder)).length()-arm_length)
			var solution: Dictionary = _arm_solution(side,inverse*hand,_typing_elbow(side,model_pose.basis))
			var shoulder_world: Vector3 = model_pose*Vector3(solution.shoulder)
			var elbow_world: Vector3 = model_pose*Vector3(solution.elbow)
			var palm_world: Vector3 = model_pose*Vector3(solution.hand)
			var limb_scale: float = maxf(visual.scale.x,visual.scale.y)*_proportion
			clearance = minf(clearance,_desk_segment_clearance(shoulder_world,elbow_world,.047*limb_scale))
			clearance = minf(clearance,_desk_segment_clearance(elbow_world,palm_world,.032*limb_scale))
		var cost: float = maxf(0.0,excess)*4.0+maxf(0.0,-clearance)*8.0+angle*.0005
		if cost < least_cost:
			best = angle
			least_cost = cost
		if excess <= 0.0 and clearance >= .002: break
	return best


func _typing_pose(pose: Dictionary, t: float, anchor_kind: String) -> void:
	var center: Vector3 = Vector3(0,_hip_height+.285,.29 if _model_age == "child" else .36)
	if anchor_kind == "standing": center.y = _authored_height*.66
	var side: Vector3 = Vector3(float(_activity_anchor.get("hand_spread",.075 if _model_age == "child" else .105)),0,0)
	if _activity_anchor.has("hand_center"):
		center = _model.to_local(_activity_anchor.hand_center)
		var world_side: Vector3 = Basis(Vector3.UP,float(_activity_anchor.yaw))*side
		side = _model.global_basis.inverse()*world_side
	var typing:float=1.0-_coaching_attention_weight() if _activity_anchor.has("attention_target") else 1.0
	_reach_hand(pose,"L",center-side+Vector3(0,sin(t*8.0)*.006*typing,0),_typing_elbow("L",_model.global_basis))
	_reach_hand(pose,"R",center+side+Vector3(0,cos(t*8.0)*.006*typing,0),_typing_elbow("R",_model.global_basis))


func _orient_held_prop(prop: Node3D, model_basis: Basis) -> void:
	var parent: Node3D = prop.get_parent() as Node3D
	var parent_basis: Basis = _model.global_basis.inverse()*parent.global_basis
	prop.basis = parent_basis.inverse()*model_basis


func _update_held_props(delta: float, moving: bool, action_id: String) -> void:
	var blend: float = 1.0 if _reconstructing_stair or not stair_presentation.is_empty() or _reconstructing_cooking or _reconstructing_sanitation or _reconstructing_meal or _reconstructing_rest or (not moving and action_id=="cook" and _has_oven()) else 1.0-exp(-delta*12.0)
	if is_instance_valid(_meal_fork):
		_meal_fork.visible=not moving and action_id=="eat_meal"
		if _meal_fork.visible:
			var grip:Vector3=_model.to_local(_meal_fork.global_position)
			var direction:Vector3=(_meal_tip-grip).normalized()
			_orient_held_prop(_meal_fork,Basis(Quaternion(Vector3.FORWARD,direction)).scaled(Vector3.ONE*_proportion))
	var show_cake: bool = not moving and action_id == "birthday" and _action_time < 3.85
	_birthday_weight = lerpf(_birthday_weight,1.0 if show_cake else 0.0,blend)
	_birthday_cake.visible = _birthday_weight > .015
	var cake_scale: float = clampf(_proportion,.8,1.0)
	_orient_held_prop(_birthday_cake,Basis.IDENTITY.scaled(Vector3.ONE*maxf(.001,_birthday_weight)*cake_scale))
	for flame: Node3D in _cake_flames: flame.visible = action_id == "birthday" and _action_time < 3.12
	_cook_weight = lerpf(_cook_weight,1.0 if not moving and action_id == "cook" else 0.0,blend)
	_snack_weight = lerpf(_snack_weight,1.0 if not moving and action_id == "snack" else 0.0,blend)
	var bake:bool=_presented_cooking_recipe=="harvest_bake"
	_cooking_bowl.visible = _cook_weight > .015 and not bake
	_seasoning_weight=lerpf(_seasoning_weight,1.0 if not moving and action_id=="cook" and _is_seasoning() else 0.0,blend)
	_cooking_spoon.visible = _cook_weight > .015 and not bake and _seasoning_weight<.05
	_seasoning_jar.visible=_seasoning_weight>.015 and not bool(cooking_presentation.get("oven_suspended",false)) and not bool(cooking_presentation.get("oven_interior",false))
	_baking_tray.visible=not moving and action_id=="cook" and bake and not bool(cooking_presentation.get("oven_interior",false)) and not bool(cooking_presentation.get("oven_suspended",false))
	for child:Node3D in _bowl_center.get_children():
		child.visible=child==_recipe_bowl if _presented_cooking_recipe=="herb_pasta" and is_instance_valid(_recipe_bowl) else child!=_recipe_bowl
	_snack.visible = _snack_weight > .015
	# Counter-rotate each grip so the ceramic stays level while its palm moves.
	_orient_held_prop(_cooking_bowl,Basis.IDENTITY.scaled(Vector3.ONE*maxf(.001,_cook_weight)*_proportion))
	_orient_held_prop(_snack,Basis.IDENTITY.scaled(Vector3.ONE*maxf(.001,_snack_weight)*_proportion))
	# Keep the hidden actor cache on the same progress-derived transform as
	# the world-owned interior dish; visibility is not preparation ownership.
	if not moving and action_id=="cook" and bake and not bool(cooking_presentation.get("oven_suspended",false)):
		_baking_tray.global_transform=_preparation_tray_transform()
	if _seasoning_jar.visible:
		_orient_held_prop(_seasoning_jar,Basis(Quaternion(Vector3.UP,_seasoning_axis)).scaled(Vector3.ONE*_proportion*maxf(.001,_seasoning_weight)))
		_update_seasoning_grains()
	else:
		for grain:MeshInstance3D in _seasoning_grains:grain.hide()
	if _cooking_spoon.visible:
		var grip: Vector3 = _model.to_local(_cooking_spoon.global_position)
		var target:Vector3=_preparation_tip
		if _presented_cooking_recipe=="garden_skillet":
			var center: Vector3 = _model.to_local(_bowl_center.global_position)
			target=center+Vector3(sin(_action_time*2.3)*.048,.027,cos(_action_time*2.3)*.042)*_proportion
		var direction: Vector3 = (target-grip).normalized()
		_orient_held_prop(_cooking_spoon,Basis(Quaternion(Vector3.DOWN,direction)).scaled(Vector3.ONE*maxf(.001,_cook_weight)*_proportion))


func set_selected(value: bool) -> void:
	selected = value
	if _ring != null:
		_ring.visible = value
	if _marker != null:
		_marker.visible = value


func clear_speech() -> void:
	_speech_remaining=0.0
	_pending_voice=""
	if is_instance_valid(_speech):_speech.text="";_speech.visible=false


func speech_presentation() -> Dictionary:
	if _speech_remaining <= 0.0 or not is_instance_valid(_speech) or _speech.text.is_empty(): return {}
	return {"text": _speech.text, "remaining": _speech_remaining}


func speech(text: String) -> void:
	_ensure_nodes()
	_speech.text = text.strip_edges().left(96)
	_speech_remaining = clampf(2.5 + float(text.length()) * 0.04, 3.0, 7.0)
	_speech.visible = not screen_speech and not _speech.text.is_empty()
	# Queue sound until animate supplies the current game speed; pause stays silent.
	var lower: String = text.to_lower()
	_pending_voice = "reaction"
	if lower.contains("hello") or lower.contains("welcome") or lower.contains("hey"):
		_pending_voice = "greeting"
	elif lower.contains("!") or lower.contains("love") or lower.contains("laugh"):
		_pending_voice = "happy"
	elif lower.contains("?") or lower.contains("think"):
		_pending_voice = "thoughtful"


func reconstruct_cooking_pose() -> void:
	# Rebuild only the presentation from its current authoritative cook data.
	# Ordinary animate(..., speed=0) remains an exact freeze. No synthetic dt,
	# simulation progress, clock reset, blink sampling or voice update is used.
	if _model == null:return
	_reconstructing_cooking=true
	var action:String="cook" if not cooking_presentation.is_empty() and not bool(cooking_presentation.get("oven_suspended",false)) else ""
	animate(0.0,0.0,false,action)
	_reconstructing_cooking=false

func reconstruct_meal_pose(eating:bool)->void:
	_reconstructing_meal=true
	animate(0.0,0.0,false,"eat_meal" if eating else "")
	_reconstructing_meal=false

func reconstruct_rest_pose(action_id:String)->void:
	# Loading a paused sleeper evaluates only its authored bed/seat pose.
	# Ordinary pause, animation clocks, blink sampling and voice stay frozen.
	if _model==null or action_id not in ["sleep","nap"] or str(_activity_anchor.get("action",""))!=action_id or str(_activity_anchor.get("kind","")) not in ["bed","seat"]:return
	if not _activity_anchor.get("position") is Vector3 or not Vector3(_activity_anchor.position).is_finite() or not is_finite(float(_activity_anchor.get("yaw",NAN))):return
	_reconstructing_rest=true
	animate(0.0,0.0,false,action_id)
	_reconstructing_rest=false
	for entry:Dictionary in _blink_shapes:entry.mesh.set_blend_shape_value(int(entry.index),1.0)
	_smile=0.0
	for entry:Dictionary in _smile_shapes:entry.mesh.set_blend_shape_value(int(entry.index),0.0)

func reconstruct_sanitation_pose(action_id:String)->void:
	if action_id not in ["plant_wee","mop_puddle"]:return
	_reconstructing_sanitation=true
	animate(0.0,0.0,false,action_id)
	_reconstructing_sanitation=false

func react_to_accident() -> void:
	# Animation ownership is checked on the next real Live pose update. An
	# occupied actor loses this brief gesture rather than playing it much later.
	_accident_time = 0.0


func _can_react_to_accident(moving:bool,action_id:String) -> bool:
	return not moving and action_id.is_empty() and not bool(meal_presentation.get("carrying",false)) and cooking_presentation.is_empty() and _cook_weight<.01 and _snack_weight<.01 and _birthday_weight<.01 and _seasoning_weight<.01


func animate(delta: float, speed_factor: float, moving: bool, action_id: String) -> void:
	if _model == null or (delta <= 0.0 and not _reconstructing_cooking and not _reconstructing_stair and not _reconstructing_sanitation and not _reconstructing_meal and not _reconstructing_rest):
		return
	if not _reconstructing_cooking and not _reconstructing_stair and not _reconstructing_sanitation and not _reconstructing_meal and not _reconstructing_rest:_update_voice(delta, speed_factor, moving, action_id)
	if is_instance_valid(_mop) and action_id!="mop_puddle":_mop.visible=false
	var animation_delta: float = delta * clampf(speed_factor, 0.0, 3.0)
	# Pause freezes the entire presentation, including props and transition clocks.
	if animation_delta <= 0.0 and not _reconstructing_cooking and not _reconstructing_stair and not _reconstructing_sanitation and not _reconstructing_meal and not _reconstructing_rest:
		return
	if not _reconstructing_cooking and not _reconstructing_stair and not _reconstructing_sanitation and not _reconstructing_meal and not _reconstructing_rest:
		if stair_presentation.is_empty():_stair_exit_carry=false
		var motion_action: String = "walk" if moving else action_id
		if motion_action != _motion_action:
			_motion_action = motion_action
			_action_time = 0.0
		_action_time += animation_delta
	_accident_visible = false
	if not _reconstructing_cooking and not _reconstructing_stair and not _reconstructing_sanitation and not _reconstructing_meal and not _reconstructing_rest and _accident_time >= 0.0:
		if not _can_react_to_accident(moving,action_id):
			_accident_time = -1.0
		else:
			_accident_time += animation_delta
			_accident_visible = _accident_time < 2.0
			if not _accident_visible:_accident_time = -1.0
	if not moving and action_id=="cook":
		_presented_cooking_recipe=_cooking_recipe()
		_ensure_cooking_recipe_props()
	_update_grips(animation_delta,moving,action_id)
	if not _reconstructing_cooking and not _reconstructing_stair and not _reconstructing_sanitation and not _reconstructing_meal and not _reconstructing_rest:
		_time += animation_delta
		_speech_remaining = maxf(0.0, _speech_remaining - delta)
		_speech.visible = not screen_speech and _speech_remaining > 0.0 and not _speech.text.is_empty()
	_marker.position.y = (_authored_height+.21) * _height + sin(_time * 2.0 + _phase_offset) * 0.026
	_marker.rotation.y = sin(_time * 0.8) * 0.20
	var t: float = _time + _phase_offset
	# Oven handling already has smooth progress curves. Evaluating its pose
	# directly makes live and paused reconstruction agree without frame lag.
	var blend: float = 1.0 if _reconstructing_cooking or _reconstructing_sanitation or _reconstructing_meal or _reconstructing_rest or (not moving and action_id=="cook" and _has_oven()) else 1.0 - exp(-animation_delta * 8.0)
	var anchored: bool = not moving and not action_id.is_empty() and not _activity_anchor.is_empty()
	anchored = anchored and (str(_activity_anchor.get("action","")) in ["",action_id])
	var anchor_kind: String = str(_activity_anchor.get("kind","")) if anchored else ""
	var pose: Dictionary = {}
	for joint_name: String in JOINT_NAMES:
		pose[joint_name] = Vector3.ZERO
	var offset: Vector3 = interaction_offset
	var lean: Vector3 = Vector3.ZERO
	var breathe: float = sin(t * 2.0)
	pose["Head"] = Vector3(0.010 * breathe, 0.04 * sin(t * 0.43), 0.013 * sin(t * 0.71))
	pose["Arm_L"] = Vector3(0.012 * breathe, 0.0, -0.015)
	pose["Arm_R"] = Vector3(-0.012 * breathe, 0.0, 0.015)
	_book.visible = false
	_brush.visible = false
	_watering_can.visible = false
	_mop.visible=false
	if moving:
		var cycle: float = t * 7.6
		var swing: float = sin(cycle)
		pose["Leg_L"] = Vector3(swing * 0.48, 0, 0)
		pose["Leg_R"] = Vector3(-swing * 0.48, 0, 0)
		pose["Shin_L"] = Vector3(maxf(0.0, -cos(cycle)) * 0.62, 0, 0)
		pose["Shin_R"] = Vector3(maxf(0.0, cos(cycle)) * 0.62, 0, 0)
		pose["Arm_L"] = Vector3(-swing * 0.37, 0, -0.025)
		pose["Arm_R"] = Vector3(swing * 0.37, 0, 0.025)
		pose["Forearm_L"] = Vector3(-0.16 - maxf(0.0, swing) * 0.18, 0, 0)
		pose["Forearm_R"] = Vector3(-0.16 - maxf(0.0, -swing) * 0.18, 0, 0)
		offset.y += absf(sin(cycle)) * 0.020
		lean = Vector3(0.025, 0.025 * swing, -0.013 * swing)
	else:
		offset.y += breathe * 0.003
		match action_id:
			"birthday":
				var cake_scale: float = clampf(_proportion,.8,1.0)
				var tray: Vector3 = Vector3(0,_hip_height+.30*_proportion,.36*_proportion)
				if _action_time < 4.1:
					_reach_hand(pose,"L",tray+Vector3(-.12*cake_scale,0,0),Vector3(-.7,-.8,-.1))
					_reach_hand(pose,"R",tray+Vector3(.12*cake_scale,0,0),Vector3(.7,-.8,-.1))
					var blow: float = smoothstep(1.7,2.45,_action_time)*(1.0-smoothstep(3.1,3.7,_action_time))
					pose["Head"] = Vector3(.23*blow,0,0)
					lean.x = .055*blow
				else:
					var clap: float = .5+.5*sin((_action_time-4.1)*8.0)
					var hands: Vector3 = Vector3(0,_hip_height+.39*_proportion,.28*_proportion)
					_reach_hand(pose,"L",hands+Vector3(-(.020+.085*clap)*_proportion,0,0),Vector3(-.7,-.6,-.1))
					_reach_hand(pose,"R",hands+Vector3((.020+.085*clap)*_proportion,0,0),Vector3(.7,-.6,-.1))
					pose["Head"] = Vector3(-.025+sin(t*2.0)*.025,0,.035*sin(t*1.2))
			"sleep", "nap":
				if anchor_kind == "seat":
					_seated_pose(pose)
					lean = Vector3(-0.10,0.0,0.065)
					offset.y -= .43 * _height * _proportion
					pose["Head"] = Vector3(0.19,-0.09,0.12)
					pose["Forearm_L"] = Vector3(-0.8,0.0,0.0)
					pose["Forearm_R"] = Vector3(-0.8,0.0,0.0)
				else:
					lean = Vector3(-PI / 2.0 + 0.025, 0, 0)
					offset += Vector3(0, 0.57, 0.63)*_proportion
					pose["Head"] = Vector3(0, -0.12, 0.04)
					pose["Arm_L"] = Vector3(-0.18, 0, -0.1)
					pose["Arm_R"] = Vector3(-0.25, 0, 0.08)
					pose["Forearm_L"] = Vector3(-0.45, 0, 0)
					pose["Forearm_R"] = Vector3(-0.55, 0, 0)
					pose["Leg_L"] = Vector3(-0.08, 0, 0)
					pose["Shin_L"] = Vector3(0.12, 0, 0)
			"relax", "watch", "toilet", "work", "study", "job", "school", "homework", "play_games":
				if anchor_kind != "standing":
					_seated_pose(pose)
					offset.y -= 0.43 * _height * _proportion
				if action_id in ["work", "study", "job", "school", "homework", "play_games"]:
					pose["Arm_L"] = Vector3(-0.42, 0, 0.05)
					pose["Arm_R"] = Vector3(-0.42, 0, -0.05)
					pose["Forearm_L"] = Vector3(-0.85 + sin(t * 9.0) * 0.05, 0, 0)
					pose["Forearm_R"] = Vector3(-0.85 + cos(t * 9.0) * 0.05, 0, 0)
					pose["Head"] = Vector3(0.16, sin(t * 0.7) * 0.035, 0)
					if action_id in ["school","homework"] or _activity_anchor.has("hand_center"):
						_typing_pose(pose,t,anchor_kind)
					if anchor_kind == "standing" and action_id in ["study","homework"]:
						pose["Arm_L"] = Vector3(-.43,0,.17)
						pose["Arm_R"] = Vector3(-.43,0,-.17)
						pose["Forearm_L"] = Vector3(-1.05,0,.06)
						pose["Forearm_R"] = Vector3(-1.05,0,-.06)
						_book.visible = true
				elif action_id == "watch":
					pose["Head"] = Vector3(-0.06, sin(t * 0.3) * 0.1, 0)
					pose["Forearm_R"] = Vector3(-0.42, 0, 0)
				elif action_id == "relax":
					pose["Head"] = Vector3(-0.08, 0.05, 0.05)
					pose["Arm_L"] = Vector3(0.02, 0, -0.32)
					pose["Arm_R"] = Vector3(0.02, 0, 0.32)
			"homework_wait":
				if anchor_kind == "seat":
					_seated_pose(pose)
					pose["Arm_L"] = Vector3(-.16,0,.08)
					pose["Arm_R"] = Vector3(-.16,0,-.08)
					pose["Forearm_L"] = Vector3(-.90,0,0)
					pose["Forearm_R"] = Vector3(-.90,0,0)
				pose["Head"] = Vector3(.06,.06*sin(t*.45),0)
			"help_homework":
				# Stand at the controller's clear side position, explain a step,
				# then lower the hand to listen. No reach through the child's desk.
				var explain: float = _coaching_attention_weight()
				var hand:Vector3=Vector3(.25,1.08+.23*explain,.28+.08*explain)*_proportion
				_reach_hand(pose,"R",hand,Vector3(.8,-.45,.05),Vector3.DOWN,Vector3(0,0,1))
				pose["Arm_L"] = Vector3(-.12,0,.06)
				pose["Forearm_L"] = Vector3(-.32-.10*(1.0-explain),0,0)
				pose["Head"] = Vector3(.18+.03*sin(_action_time*2.1),.04*sin(t*.7),-.015)
			"eat_meal":
				if anchor_kind=="seat":_seated_pose(pose)
				_meal_eating_pose(pose)
			"plant_wee":
				# A quick privacy glance, braced knees and an exhale. Hands stay
				# over clothing at the upper waist; there is no anatomy or stream.
				var brace:float=_pot_brace()
				var release:float=smoothstep(.80,1.35,_action_time)
				var glance:float=sin(clampf(_action_time/.65,0,1)*TAU)*.36*(1.0-release)
				pose["Head"]=Vector3(.07+.17*brace-.10*release,glance,-.025*brace)
				lean.x=.045+.07*brace-.035*release
				var waist:float=_hip_height+.23*_proportion
				_reach_hand(pose,"L",Vector3(-.16*_proportion,waist,.245*_proportion),Vector3(-.45,-1.0,-.2))
				_reach_hand(pose,"R",Vector3(.21*_proportion,waist-.055*_proportion,.24*_proportion),Vector3(.45,-1.0,-.2))
			"mop_puddle":
				# Lean from supported hips to reach the unchanged low shaft grip.
				lean.x=.75
			"clean_plate":
				pose["Arm_L"]=Vector3(-.5,0,.16);pose["Forearm_L"]=Vector3(-.8,0,0)
				pose["Arm_R"]=Vector3(-.5+sin(_action_time*4.0)*.08,0,-.16);pose["Forearm_R"]=Vector3(-.8,0,0)
			"snack":
				var cycle: float = fmod(_action_time, 5.4)
				var bite: float = smoothstep(.45,1.25,cycle) * (1.0-smoothstep(2.05,2.95,cycle))
				pose["Head"] = Vector3(.018*bite,-.018*bite,0)
				var head: Node3D = _joints.get("Head")
				var mouth: Vector3 = _model.to_local(head.to_global(_mouth_anchor)) if head != null else Vector3(0,1.507,.10)
				var hand_target: Vector3 = (Vector3(.17,1.12,.31)*_proportion).lerp(mouth+Vector3(.004,-.026,.013)*_proportion,bite)
				_reach_hand(pose,"R",hand_target,Vector3(.65,-.7,-.05))
				pose["Arm_L"] = Vector3(-.10,0,.025)
				pose["Forearm_L"] = Vector3(-.20,0,0)
			"cook":
				if _has_oven():lean.x=.90*LifeOvenSequence.crouch(_cooking_progress())
				else:_cooking_pose(pose)
			"read":
				pose["Arm_L"] = Vector3(-0.43, 0, 0.17)
				pose["Arm_R"] = Vector3(-0.43, 0, -0.17)
				pose["Forearm_L"] = Vector3(-1.05, 0, 0.06)
				pose["Forearm_R"] = Vector3(-1.05 + sin(t * 0.8) * 0.06, 0, -0.06)
				pose["Head"] = Vector3(0.27, sin(t * 0.55) * 0.025, 0)
				_book.visible = true
			"paint":
				pose["Arm_R"] = Vector3(-0.80 + sin(t * 2.1) * 0.20, 0.08 * cos(t * 1.5), -0.13)
				pose["Forearm_R"] = Vector3(-0.68 + sin(t * 2.1 + 1.0) * 0.22, 0, 0)
				pose["Arm_L"] = Vector3(-0.10, 0, -0.08)
				pose["Forearm_L"] = Vector3(-0.38, 0, 0)
				pose["Head"] = Vector3(-0.02 + sin(t * 1.0) * 0.07, 0.04, 0.03)
				_brush.visible = true
			"shower":
				pose["Arm_L"] = Vector3(-2.40 + sin(t * 2.4) * 0.10, 0, -0.24)
				pose["Arm_R"] = Vector3(-2.25 - sin(t * 2.4) * 0.10, 0, 0.24)
				pose["Forearm_L"] = Vector3(-1.15 + cos(t * 2.4) * 0.18, 0, 0)
				pose["Forearm_R"] = Vector3(-1.15 - cos(t * 2.4) * 0.18, 0, 0)
				pose["Head"] = Vector3(0.17, 0.08 * sin(t * 2.4), 0)
			"water":
				pose["Arm_R"] = Vector3(-0.40, 0, -0.1)
				pose["Forearm_R"] = Vector3(-0.33 + sin(t * 1.5) * 0.13, 0, -0.08)
				pose["Head"] = Vector3(0.24, 0.05, 0)
				_watering_can.visible = true
			"bath":
				if anchor_kind != "standing":
					_seated_pose(pose)
					offset.y -= 0.43 * _height * _proportion
				pose["Arm_L"] = Vector3(-0.15, 0, -0.38)
				pose["Arm_R"] = Vector3(-0.15, 0, 0.38)
				pose["Forearm_L"] = Vector3(-0.50, 0, 0)
				pose["Forearm_R"] = Vector3(-0.50, 0, 0)
				pose["Head"] = Vector3(-0.16 + 0.03 * sin(t * 0.8), 0.05 * sin(t * 0.4), 0)
			"play_piano":
				if anchor_kind != "standing":
					_seated_pose(pose)
					offset.y -= 0.43 * _height * _proportion
				pose["Arm_L"] = Vector3(-0.40, 0, 0.10)
				pose["Arm_R"] = Vector3(-0.40, 0, -0.10)
				pose["Forearm_L"] = Vector3(-0.95 + sin(t * 6.0) * 0.07, 0, 0)
				pose["Forearm_R"] = Vector3(-0.95 + cos(t * 5.0) * 0.07, 0, 0)
				pose["Head"] = Vector3(0.12 + 0.04 * sin(t * 1.3), 0.08 * sin(t * 0.9), 0)
			"play_chess":
				if anchor_kind != "standing":
					_seated_pose(pose)
					offset.y -= 0.43 * _height * _proportion
				var think: float = 0.5 + 0.5 * sin(t * 0.7)
				pose["Arm_L"] = Vector3(-0.30, 0, 0.10)
				pose["Forearm_L"] = Vector3(-0.90, 0, 0)
				pose["Arm_R"] = Vector3(-0.45 - 0.25 * think, 0, -0.05)
				pose["Forearm_R"] = Vector3(-0.70 - 0.30 * think, 0, 0)
				pose["Head"] = Vector3(0.30 - 0.10 * think, 0.05 * sin(t * 0.5), 0)
			"jog":
				var run_cycle: float = t * 10.5
				var stride: float = sin(run_cycle)
				pose["Leg_L"] = Vector3(stride * 0.62, 0, 0)
				pose["Leg_R"] = Vector3(-stride * 0.62, 0, 0)
				pose["Shin_L"] = Vector3(maxf(0.0, -cos(run_cycle)) * 0.95, 0, 0)
				pose["Shin_R"] = Vector3(maxf(0.0, cos(run_cycle)) * 0.95, 0, 0)
				pose["Arm_L"] = Vector3(-0.35 - stride * 0.45, 0, -0.06)
				pose["Arm_R"] = Vector3(-0.35 + stride * 0.45, 0, 0.06)
				pose["Forearm_L"] = Vector3(-1.25, 0, 0)
				pose["Forearm_R"] = Vector3(-1.25, 0, 0)
				pose["Head"] = Vector3(0.05, 0, 0)
				offset.y += absf(sin(run_cycle)) * 0.035
				lean = Vector3(0.10, 0.02 * stride, -0.01 * stride)
			"stretch":
				# A slow reach up and out in a V, kept short of a full overhead raise so
				# the long-sleeved shells keep their shoulders through the stretch.
				var rise: float = 0.5 + 0.5 * sin(t * 0.9)
				pose["Arm_L"] = Vector3(-1.0 - 1.2 * rise, 0, -0.2 - 0.15 * rise)
				pose["Arm_R"] = Vector3(-1.0 - 1.2 * rise, 0, 0.2 + 0.15 * rise)
				pose["Forearm_L"] = Vector3(-0.12 * rise, 0, 0)
				pose["Forearm_R"] = Vector3(-0.12 * rise, 0, 0)
				pose["Head"] = Vector3(-0.15 * rise, 0, 0)
				lean = Vector3(-0.03 * rise, 0, 0.05 * sin(t * 0.45))
			"dance":
				var beat: float = sin(t * 6.0)
				pose["Arm_L"] = Vector3(-0.9 + 0.3 * beat, 0, -0.55)
				pose["Arm_R"] = Vector3(-0.9 - 0.3 * beat, 0, 0.55)
				pose["Forearm_L"] = Vector3(-1.0 + 0.25 * beat, 0, 0)
				pose["Forearm_R"] = Vector3(-1.0 - 0.25 * beat, 0, 0)
				pose["Leg_L"] = Vector3(0.06 * beat, 0, 0)
				pose["Leg_R"] = Vector3(-0.06 * beat, 0, 0)
				pose["Head"] = Vector3(0.05 * beat, 0.12 * sin(t * 3.0), 0)
				offset.y += absf(beat) * 0.018
				lean = Vector3(0.03, 0, 0.06 * sin(t * 3.0))
			"play_toys":
				var play: float = 0.5 + 0.5 * sin(t * 2.4)
				_reach_hand(pose,"L",Vector3(-.14*_proportion,_hip_height+(.22+.05*play)*_proportion,.30*_proportion),Vector3(-.7,-.8,-.1))
				_reach_hand(pose,"R",Vector3(.14*_proportion,_hip_height+(.20+.08*(1.0-play))*_proportion,.32*_proportion),Vector3(.7,-.8,-.1))
				pose["Head"] = Vector3(0.30, 0.06 * sin(t * 1.5), 0)
				lean.x = 0.12
			"practice_speech":
				_conversation_pose(pose, "friendly" if fmod(t, 8.0) < 4.0 else "joke", t)
			"change_outfit":
				pose["Arm_L"] = Vector3(-1.1, 0, 0.12)
				pose["Forearm_L"] = Vector3(-1.3, 0, 0)
				pose["Arm_R"] = Vector3(-1.1, 0, -0.12)
				pose["Forearm_R"] = Vector3(-1.3 + 0.1 * sin(t * 5.0), 0, 0)
				pose["Head"] = Vector3(0.12, 0, 0)
			"warm_up":
				pose["Arm_L"] = Vector3(-0.75, 0, 0.15)
				pose["Arm_R"] = Vector3(-0.75, 0, -0.15)
				pose["Forearm_L"] = Vector3(-0.55 + 0.05 * sin(t * 1.5), 0, 0)
				pose["Forearm_R"] = Vector3(-0.55 + 0.05 * cos(t * 1.5), 0, 0)
				pose["Head"] = Vector3(0.06, 0.05 * sin(t * 0.5), 0)
			"friendly", "joke", "deep_talk", "flirt", "argue", "ask_partner", "commit", "break_up":
				var gesture_aliases: Dictionary = {"ask_partner":"deep_talk", "commit":"flirt", "break_up":"deep_talk"}
				_conversation_pose(pose, str(gesture_aliases.get(action_id, action_id)), t)
	if _accident_visible:_accident_pose(pose)
	if bool(meal_presentation.get("carrying",false)):
		# Props keep their authored metre scale across ages. Solve the hands from
		# the actual held transform so smaller Lifelets reach the same ceramic.
		_reach_hand(pose,"L",_meal_carry_hand("L"),Vector3(-.25,-1.0,-.35))
		_reach_hand(pose,"R",_meal_carry_hand("R"),Vector3(.25,-1.0,-.35))
	if anchored and _activity_anchor.has("attention_target") and action_id in ["homework","help_homework"]:
		var attention_weight:float=_coaching_attention_weight() if action_id=="homework" else .85
		var direction:Vector3=_model.to_local(_activity_anchor.attention_target)-_model.to_local(_joints.Head.global_position)
		var gaze:Vector3=Vector3(clampf(-atan2(direction.y,Vector2(direction.x,direction.z).length()),-.38,.4),clampf(atan2(direction.x,direction.z),-.72,.72),0)
		pose["Head"]=Vector3(pose.Head).lerp(gaze,attention_weight)
	if anchored and anchor_kind == "seat" and _activity_anchor.has("hand_center") and action_id in ["work","study","job","school","homework","play_games"]:
		lean.x = _desk_lean()
		# Keep thighs horizontal while the torso leans from its supported hips.
		pose["Leg_L"].x -= lean.x
		pose["Leg_R"].x -= lean.x
	if anchored and anchor_kind=="seat" and action_id=="eat_meal":
		# Lean from supported hips, rather than locking short arms at full reach.
		lean.x=.18 if _model_age=="child" else .045
		pose["Leg_L"].x-=lean.x
		pose["Leg_R"].x-=lean.x
	if anchored:
		var world_orientation: Basis = Basis(Vector3.UP,float(_activity_anchor.yaw)) * Basis.from_euler(lean)
		var reference: Vector3 = Vector3.ZERO
		if anchor_kind == "seat":
			reference = Vector3(0.0,_hip_height * _height,0.0)
		elif anchor_kind == "bed":
			# Match the back of the body at its midpoint to the mattress surface.
			reference = Vector3(0.0,_hip_height * _height,-.10 * _proportion * visual.scale.z)
		var world_origin: Vector3 = _activity_anchor.position - world_orientation * reference
		if action_id=="cook" and _has_oven():
			var bend:float=LifeOvenSequence.crouch(_cooking_progress())
			var upright:Basis=Basis(Vector3.UP,float(_activity_anchor.yaw))
			var hips:Vector3=Vector3(0,_hip_height*_height,0)
			world_origin=_activity_anchor.position+upright*(hips+Vector3(0,-.42*_height,-.20+.55*(1.0-_proportion*visual.scale.x))*bend)-world_orientation*hips
			var rack:Node3D=_activity_anchor.oven.find_child("OvenRack",true,false)
			if is_instance_valid(rack) and _arm_rest.has("L") and _arm_rest.has("R"):
				var shoulders:Vector3=(Vector3(_arm_rest.L.shoulder)+Vector3(_arm_rest.R.shoulder))*.5*visual.scale
				var shoulder_height:float=(world_origin+world_orientation*shoulders).y
				world_origin.y+=maxf(0,rack.global_position.y+.19-shoulder_height)*bend*LifeOvenSequence.transfer_height(_cooking_progress())
		if action_id=="plant_wee":
			var upright:Basis=Basis(Vector3.UP,float(_activity_anchor.yaw))
			var hips:Vector3=Vector3(0,_hip_height*_height,0)
			world_origin=_activity_anchor.position+upright*(hips+Vector3(0,-.065*_height*_proportion,0)*_pot_brace())-world_orientation*hips
		if action_id=="mop_puddle":
			var upright:Basis=Basis(Vector3.UP,float(_activity_anchor.yaw))
			var hips:Vector3=Vector3(0,_hip_height*_height,0)
			# The supported stance can sit farther from a real floor patch than
			# the legacy prop origin. Transfer the rendered hips toward that
			# contact, bending the knees while the original feet stay planted.
			var contact:Vector3=_activity_anchor.get("mop_contact",_activity_anchor.position+upright*Vector3(.035,0,.68))
			var reach_shift:Vector3=upright.inverse()*(contact-Vector3(_activity_anchor.position))-Vector3(.035,0,.68)
			reach_shift.y=-Vector2(reach_shift.x,reach_shift.z).length()*.55
			world_origin=_activity_anchor.position+upright*(hips+Vector3(0,-.09*_height*_proportion,.04+.50*(1.0-_proportion))+reach_shift)-world_orientation*hips
		offset = to_local(world_origin) + interaction_offset
		lean = (global_basis.orthonormalized().inverse() * world_orientation).get_euler()
	var body_blend:float=1.0 if anchored and action_id=="mop_puddle" else blend
	visual.position = offset if _reconstructing_rest else visual.position.lerp(offset, body_blend)
	visual.rotation = _angle_lerp(visual.rotation, lean, body_blend)
	_update_visual_followers(anchored,action_id)
	if not moving and action_id=="cook" and _has_oven():
		_oven_cooking_pose(pose)
		_oven_leg_pose(pose)
	if anchored and action_id in ["plant_wee","mop_puddle"]:_sanitation_leg_pose(pose)
	if anchored and action_id=="mop_puddle":_mopping_pose(pose)
	for joint_name: String in _joints:
		var joint: Node3D = _joints[joint_name]
		var goal_rotation: Vector3 = _rest_rotations[joint_name] + pose[joint_name]
		var joint_blend:float=1.0 if (action_id=="cook" and _has_oven() and joint_name!="Head") or (anchored and action_id=="plant_wee" and (joint_name.begins_with("Leg_") or joint_name.begins_with("Shin_"))) or (anchored and action_id=="mop_puddle" and joint_name!="Head") else blend
		joint.quaternion = joint.quaternion.slerp(Quaternion.from_euler(goal_rotation),joint_blend)
	for entry: Dictionary in _rig_bones:
		var skeleton: Skeleton3D = entry.skeleton
		var bone_index: int = int(entry.index)
		var rest: Quaternion = entry.rest
		var target_rotation: Quaternion = rest.inverse() * Quaternion.from_euler(pose[entry.name]) * rest
		var joint_blend:float=1.0 if (action_id=="cook" and _has_oven() and entry.name!="Head") or (anchored and action_id=="plant_wee" and (str(entry.name).begins_with("Leg_") or str(entry.name).begins_with("Shin_"))) or (anchored and action_id=="mop_puddle" and entry.name!="Head") else blend
		skeleton.set_bone_pose_rotation(bone_index,skeleton.get_bone_pose_rotation(bone_index).slerp(target_rotation,joint_blend))
	for rest:Dictionary in _leg_rest.values():
		var shoe:Node3D=rest.shoe
		if not moving and ((action_id=="cook" and _has_oven()) or (anchored and action_id in ["plant_wee","mop_puddle"])):shoe.global_basis=Basis(Vector3.UP,float(_activity_anchor.yaw))*Basis(rest.shoe_basis)
		else:shoe.basis=Basis.IDENTITY
	var seated: bool = not moving and ((action_id in ["relax", "watch", "toilet", "work", "study", "job", "school", "homework", "play_games", "homework_wait", "eat_meal", "bath", "play_piano", "play_chess"] and anchor_kind != "standing") or (action_id in ["sleep", "nap"] and anchor_kind == "seat"))
	_sit_amount = lerpf(_sit_amount, 1.0 if seated else 0.0, blend)
	for entry: Dictionary in _sit_shapes:
		entry.mesh.set_blend_shape_value(int(entry.index), _sit_amount)
	if not _reconstructing_cooking and not _reconstructing_stair and not _reconstructing_sanitation and not _reconstructing_meal and not _reconstructing_rest:_update_expression(animation_delta,action_id,blend)
	if not stair_presentation.is_empty():_apply_stair_pose()
	_update_held_props(animation_delta,moving,action_id)


func _mopping_pose(pose:Dictionary)->void:
	# Solve world-space shaft contacts only after the anchored body transform
	# is installed, including during the first zero-time physical restore.
	var mop_scale:float=clampf(_proportion,.72,1.10)
	var orientation:Basis=Basis(Vector3.UP,float(_activity_anchor.get("yaw",rotation.y)))
	var origin:Vector3=_activity_anchor.get("position",global_position)
	var sweep:float=sin(_action_time*2.4)*.10
	var contact:Vector3=_activity_anchor.get("mop_contact",origin+orientation*Vector3(.035,0,.68))
	_mop.global_transform=Transform3D(orientation.scaled(Vector3.ONE*mop_scale),contact+orientation*Vector3(0,0,sweep))
	_mop.visible=true
	_reach_hand(pose,"L",_model.to_local(_mop.to_global(Vector3(0,.96,-.287))),Vector3(-.55,-.65,-.20))
	_reach_hand(pose,"R",_model.to_local(_mop.to_global(Vector3(0,.68,-.198))),Vector3(.55,-.65,-.20))
	pose["Head"]=Vector3(.18,0,.02)


func _pot_brace() -> float:
	return smoothstep(0.0,.25,_action_time)*(1.0-.65*smoothstep(.80,1.35,_action_time))


func _accident_pose(pose:Dictionary) -> void:
	var t:float=_accident_time
	var notice:float=smoothstep(0.0,.18,t)*(1.0-smoothstep(1.25,1.9,t))
	var cover:float=smoothstep(.20,.65,t)*(1.0-smoothstep(1.05,1.65,t))
	pose["Head"]=Vector3(.34*notice,-.16*cover,.055*cover)
	var hand:Vector3=Vector3(.24*_proportion,_hip_height+.18*_proportion,.24*_proportion)
	var forehead:Vector3=_model.to_local(_joints.Head.global_position)+Vector3(.145,.10,.16)*_proportion
	var relaxed_arm:Quaternion=Quaternion.from_euler(pose.Arm_R)
	var relaxed_forearm:Quaternion=Quaternion.from_euler(pose.Forearm_R)
	_reach_hand(pose,"R",hand.lerp(forehead,cover),Vector3(.45,-.9,.05))
	pose.Arm_R=relaxed_arm.slerp(Quaternion.from_euler(pose.Arm_R),notice).get_euler()
	pose.Forearm_R=relaxed_forearm.slerp(Quaternion.from_euler(pose.Forearm_R),notice).get_euler()
	pose["Arm_L"]=Vector3(-.06*notice,0,-.08*notice)
	pose["Forearm_L"]=Vector3(-.20*notice,0,0)


func _sanitation_leg_pose(pose:Dictionary)->void:
	# Keep the original ankle contacts as the sanitation pose moves the hips.
	# This changes rendered joints only; the controller owns the actor root.
	var orientation:Basis=Basis(Vector3.UP,float(_activity_anchor.yaw))
	for side:String in _leg_rest:
		var rest:Dictionary=_leg_rest[side]
		var target:Vector3=_activity_anchor.position+orientation*(Vector3(rest.foot)*visual.scale)
		var local:Vector3=Transform3D(rest.space).affine_inverse()*_model.to_local(target)
		var upper:Vector3=rest.upper;var lower:Vector3=rest.lower
		var reach:Vector3=local-Vector3(rest.hip)
		var distance:float=clampf(reach.length(),absf(upper.length()-lower.length())+.005,upper.length()+lower.length()-.005)
		var forward:Vector3=reach.normalized()
		var pole:Vector3=Transform3D(rest.space).basis.inverse()*_model.global_basis.inverse()*(orientation*Vector3(0,.2,1))
		var bend:Vector3=(pole-forward*pole.dot(forward)).normalized()
		var along:float=(upper.length_squared()-lower.length_squared()+distance*distance)/(2*distance)
		var away:float=sqrt(maxf(0,upper.length_squared()-along*along))
		var upper_goal:Vector3=forward*along+bend*away
		var lower_goal:Vector3=forward*distance-upper_goal
		var thigh:Quaternion=Quaternion(upper.normalized(),upper_goal.normalized())
		pose["Leg_"+side]=thigh.get_euler()
		pose["Shin_"+side]=Quaternion(lower.normalized(),thigh.inverse()*lower_goal.normalized()).get_euler()


func _coaching_attention_weight() -> float:
	var phase:float=fmod(_action_time,5.0)
	return smoothstep(.15,.6,phase)*(1.0-smoothstep(1.5,2.1,phase))


func _update_visual_followers(anchored: bool,action_id: String) -> void:
	if anchored or action_id in ["sleep","nap"]:
		var sleeping: bool = action_id in ["sleep","nap"] and str(_activity_anchor.get("kind","")) != "seat"
		var marker_height: float = _authored_height*.71 if sleeping else _authored_height+.21
		_marker.position = visual.position + visual.basis * Vector3(0.0,marker_height,0.0) + Vector3(0.0,.46 if sleeping else 0.0,0.0)
		_marker.position.y += sin(_time * 2.0 + _phase_offset) * .025
		_speech.position = visual.position + visual.basis * Vector3(0.0,_authored_height-.06,0.0) + Vector3(0.0,.55,0.0)
		_voice.position = visual.position + visual.basis * Vector3(0.0,_authored_height-.22,.025)
		if anchored:
			var anchor_position: Vector3 = _activity_anchor.position
			_ring.position = to_local(Vector3(anchor_position.x,global_position.y+.025,anchor_position.z))
	else:
		_marker.position = Vector3(0.0,(_authored_height+.21) * _height + sin(_time * 2.0 + _phase_offset) * .026,0.0)
		_speech.position = Vector3(0.0,(_authored_height+.54) * _height,0.0)
		_voice.position = Vector3(0.0,(_authored_height-.26) * _height,0.0)
	if not anchored:
		_ring.position = Vector3(0.0,.025,0.0)


func _update_expression(delta: float,action_id: String,blend: float) -> void:
	if _blink_shapes.is_empty() and _smile_shapes.is_empty():
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0 and _blink_elapsed < 0.0:
		_blink_elapsed = 0.0
		_blink_wait = _voice_rng.randf_range(2.8,5.6)
	var blink: float = 0.0
	if _blink_elapsed >= 0.0:
		_blink_elapsed += delta
		blink = sin(clampf(_blink_elapsed / .19,0.0,1.0) * PI)
		if _blink_elapsed >= .19:
			_blink_elapsed = -1.0
	if action_id in ["sleep","nap"]:
		blink = 1.0
	for entry: Dictionary in _blink_shapes:
		entry.mesh.set_blend_shape_value(int(entry.index),blink)
	var target_smile: float = 0.10
	if action_id in ["friendly","joke","flirt","ask_partner","commit","help_homework"]:
		target_smile = 0.55 if action_id == "joke" else 0.34
	elif action_id == "birthday":
		target_smile = .12 if _action_time > 1.7 and _action_time < 3.2 else .55
	elif action_id in ["argue","sleep","nap","break_up","plant_wee"] or _accident_visible:
		target_smile = 0.0
	if _voice != null and _voice.playing and action_id!="plant_wee" and not _accident_visible:
		target_smile += (0.5 + 0.5 * sin(_time * 12.0)) * 0.10
	_smile = lerpf(_smile,target_smile,blend)
	for entry: Dictionary in _smile_shapes:
		entry.mesh.set_blend_shape_value(int(entry.index),_smile)


func _update_voice(delta: float, speed_factor: float, moving: bool, action_id: String) -> void:
	if _voice == null:
		return
	_voice_suspended = speed_factor <= 0.0
	if not voice_enabled or _voice_suspended:
		if _voice.playing:
			_voice.stop()
		if not voice_enabled:
			_pending_voice = ""
		return
	_voice_cooldown = maxf(0.0, _voice_cooldown - delta)
	if not _pending_voice.is_empty() and _voice_cooldown <= 0.0:
		if _speech_remaining > 0.0:
			_play_voice(_pending_voice)
		_pending_voice = ""
	var categories: Dictionary = {"friendly": "greeting", "joke": "happy", "deep_talk": "thoughtful", "flirt": "happy", "argue": "argument", "ask_partner":"thoughtful", "commit":"happy", "break_up":"thoughtful","birthday":"happy","help_homework":"thoughtful"}
	if moving or not categories.has(action_id):
		_last_voice_action = ""
		return
	if action_id != _last_voice_action:
		_last_voice_action = action_id
		# Slight response latency also keeps a pair of Lifelets from speaking in sync.
		_voice_cooldown = maxf(_voice_cooldown, _voice_rng.randf_range(0.15, 0.65))
	if _voice_cooldown <= 0.0 and not _voice.playing:
		_play_voice(str(categories[action_id]))


func _play_voice(category: String) -> void:
	if not voice_enabled or _voice_suspended or not _voice_streams.has(category) or _voice.playing:
		return
	_voice.stream = _voice_streams[category]
	_voice.pitch_scale = _voice_base_pitch * _voice_rng.randf_range(0.95, 1.05)
	_voice.play()
	# Real-time cooldown: fast-forward changes gameplay speed, not chatter density.
	_voice_cooldown = _voice_rng.randf_range(4.0, 8.0)


func _seated_pose(pose: Dictionary) -> void:
	pose["Leg_L"] = Vector3(-PI / 2.0, 0, 0.03)
	pose["Leg_R"] = Vector3(-PI / 2.0, 0, -0.03)
	pose["Shin_L"] = Vector3(PI / 2.0, 0, 0)
	pose["Shin_R"] = Vector3(PI / 2.0, 0, 0)
	pose["Arm_L"] = Vector3(-0.25, 0, 0)
	pose["Arm_R"] = Vector3(-0.25, 0, 0)
	pose["Forearm_L"] = Vector3(-0.4, 0, 0)
	pose["Forearm_R"] = Vector3(-0.4, 0, 0)


func _conversation_pose(pose: Dictionary, action_id: String, t: float) -> void:
	var gesture: float = 0.5 + 0.5 * sin(t * 2.1)
	pose["Arm_R"] = Vector3(-0.18 - gesture * 0.30, 0, 0.08 + gesture * 0.12)
	pose["Forearm_R"] = Vector3(-0.40 - gesture * 0.65, 0, 0)
	pose["Arm_L"] = Vector3(-0.1, 0, -0.1)
	pose["Forearm_L"] = Vector3(-0.2 - gesture * 0.15, 0, 0)
	pose["Head"] = Vector3(sin(t * 1.7) * 0.06, sin(t * 0.6) * 0.10, 0)
	match action_id:
		"joke":
			pose["Arm_L"] = Vector3(-0.25 - gesture * 0.20, 0, -0.24)
			pose["Forearm_L"] = Vector3(-0.40 - gesture * 0.40, 0, 0)
			pose["Head"].x = -0.08 + sin(t * 4.0) * 0.05
		"deep_talk":
			pose["Head"].z = 0.07
			pose["Forearm_R"].x = -0.75 - gesture * 0.30
		"flirt":
			pose["Head"] = Vector3(-0.03, -0.06, 0.12)
			pose["Arm_R"] = Vector3(-0.8, 0, -0.18)
			pose["Forearm_R"] = Vector3(-1.5 + gesture * 0.18, 0, 0)
		"argue":
			pose["Arm_R"] = Vector3(-0.85 - gesture * 0.22, 0, 0.02)
			pose["Forearm_R"] = Vector3(-0.25 - gesture * 0.60, 0, 0)
			pose["Head"] = Vector3(0.10, sin(t * 3.0) * 0.17, 0)


func _angle_lerp(from: Vector3, to: Vector3, weight: float) -> Vector3:
	return Vector3(lerp_angle(from.x, to.x, weight), lerp_angle(from.y, to.y, weight), lerp_angle(from.z, to.z, weight))


func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _box(parent: Node3D, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = _material(color)
	parent.add_child(node)
	return node


func _sphere(parent: Node3D, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	node.mesh = mesh
	node.scale = dimensions
	node.material_override = _material(color)
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, radius: float, length: float, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	node.mesh = mesh
	node.material_override = _material(color)
	parent.add_child(node)
	return node


func _meal_carry_point() -> Vector3:
	if not stair_presentation.is_empty():
		var phase:float=float(stair_presentation.phase)*PI
		return Vector3(sin(phase)*.003,_hip_height+(.22+sin(phase*2)*.003)*_proportion,.29*_proportion)
	if _reconstructing_stair or _stair_exit_carry:return Vector3(0,_hip_height+.22*_proportion,.29*_proportion)
	var walking:bool=_motion_action=="walk"
	var sway:float=sin((_time+_phase_offset)*3.8)*.003 if walking else 0.0
	var lift:float=sin((_time+_phase_offset)*7.6)*.003 if walking else sin(_time*2.0)*.0015
	return Vector3(sway,_hip_height+(.22+lift)*_proportion,.29*_proportion)

func _meal_carry_hand(side:String) -> Vector3:
	var platter:bool=bool(meal_presentation.get("platter",false))
	var contact:Vector3=Vector3(.2395 if platter else .12,.037 if platter else .005,0)
	if side=="L":contact.x=-contact.x
	var grips:Dictionary=meal_presentation.get("grips",{})
	if grips.get(side) is Vector3 and Vector3(grips[side]).is_finite():contact=grips[side]
	return _model.to_local(meal_carry_transform()*contact)

func meal_carry_transform() -> Transform3D:
	return Transform3D(global_basis.orthonormalized(),_model.to_global(_meal_carry_point()))

func _meal_eating_pose(pose:Dictionary) -> void:
	var cycle:float=fmod(_action_time,5.8)
	var bite:float=smoothstep(.5,1.55,cycle)*(1.0-smoothstep(2.5,3.9,cycle))
	var source:Vector3=_model.to_local(_activity_anchor.get("plate_position",to_global(Vector3(0,1.0,.35))))+Vector3(0,.035,0)
	var mouth:Vector3=_model.to_local(_joints.Head.to_global(_mouth_anchor))
	_meal_tip=source.lerp(mouth+Vector3(0,-.003,.010)*_proportion,bite)
	# Scoop with the handle toward the diner, then turn the tines toward the
	# mouth during the lift. A permanently reversed fork forced the wrist
	# past the plate and outside the arm's reach at the bottom of the cycle.
	var fork_pitch:float=lerpf(-.30,-PI,bite)
	var forward:Vector3=Vector3(-.08,sin(fork_pitch),cos(fork_pitch)).normalized()
	var hand:Vector3=_meal_tip-forward*.14*_proportion
	_reach_hand(pose,"R",hand,Vector3(.75,-.45,-.05),forward,Vector3.FORWARD)
	# Rest beside the near rim, then draw the free hand back while chewing.
	# The short settling arc avoids a rigid extended arm without moving the plate.
	var support:Vector3=source+Vector3(-.18+.02*bite,.003+sin(bite*PI)*.007,-.19-.075*bite)*_proportion
	_reach_hand(pose,"L",support,Vector3(-.25,-.12,-1.0))
	pose["Head"]=Vector3(.08*(1.0-bite),sin(_action_time*.5)*.025,0)


func _cooking_recipe() -> String:
	var recipe:Variant=cooking_presentation.get("recipe","garden_skillet")
	return recipe if recipe is String and recipe in ["garden_skillet","herb_pasta","harvest_bake"] else "garden_skillet"

func _cooking_progress() -> float:
	var progress:Variant=cooking_presentation.get("progress",0.0)
	return clampf(float(progress),0.0,1.0) if (progress is int or progress is float) and is_finite(float(progress)) else 0.0

func _is_seasoning() -> bool:
	var progress:float=_cooking_progress()
	return (_presented_cooking_recipe=="herb_pasta" and progress>=.48 and progress<.68) or (_presented_cooking_recipe=="harvest_bake" and (LifeOvenSequence.phase(progress)=="season" if _has_oven() else progress<.62))

func _create_recipe_props() -> void:
	_recipe_bowl=null;_recipe_bowl_food=null
	_baking_food=null
	_baking_tray=Node3D.new();_baking_tray.name="OvenReadyTray";_model.add_child(_baking_tray);_baking_tray.hide()
	_seasoning_jar=_hand_anchor("HerbJarGrip","R")
	# Original small ceramic herb shaker: waist at the finger contact, neck +Y.
	_cylinder(_seasoning_jar,.030,.076,Color("e4d8ba"))
	var band:MeshInstance3D=_cylinder(_seasoning_jar,.0308,.022,Color("638c86"));band.position.y=-.010
	var neck:MeshInstance3D=_cylinder(_seasoning_jar,.020,.022,Color("d9caab"));neck.position.y=.047
	var lid:MeshInstance3D=_cylinder(_seasoning_jar,.024,.014,Color("ae7844"));lid.position.y=.064
	for i:int in range(5):
		var hole:MeshInstance3D=_sphere(_seasoning_jar,Vector3(.002,.0007,.002),Color("514b32"))
		hole.position=Vector3(sin(i*TAU/5.0)*.011,.0715,cos(i*TAU/5.0)*.011)
	var mouth:Node3D=Node3D.new();mouth.name="SprinkleMouth";mouth.position.y=.072;_seasoning_jar.add_child(mouth)
	_seasoning_jar.hide()
	for i:int in range(7):
		var grain:MeshInstance3D=_sphere(_model,Vector3(.0025,.0015,.0035),Color("72904d") if i%2==0 else Color("c8b18b"))
		grain.name="FallingHerb"+str(i);grain.hide();_seasoning_grains.append(grain)

func _preparation_tray_transform() -> Transform3D:
	if _has_oven():
		var p:float=_cooking_progress()
		var orientation:Basis=Basis(Vector3.UP,float(_activity_anchor.yaw))
		var bend:float=LifeOvenSequence.crouch(p)
		var side_carry:float=LifeOvenSequence.side_carry(p)
		var rack_anchor:Node3D=_activity_anchor.oven.find_child("OvenRack",true,false)
		var standing_clearance:float=maxf(0,visual.scale.x-1.0)*.12+(.04 if _model_age=="elder" else 0.0)
		var center:Vector3=_activity_anchor.position+orientation*Vector3(-(.285+.13*visual.scale.x)*side_carry,(_hip_height+.22*_proportion)*_height-.40*_height*bend,(.30+standing_clearance*(1-bend)+.08*bend)*_proportion)
		if is_instance_valid(rack_anchor):center.y=maxf(center.y,rack_anchor.global_position.y+.30*side_carry)
		var phase:String=LifeOvenSequence.phase(p)
		var gather:float=0.0
		if phase=="load":gather=smoothstep(0,.50,LifeOvenSequence.fraction(p,phase))
		elif phase=="unload":gather=1.0
		elif phase=="push_unload":gather=1.0-smoothstep(0,.50,LifeOvenSequence.fraction(p,phase))
		if gather>0:
			var rack:Node3D=_activity_anchor.oven.find_child("OvenRack",true,false)
			var centered:Vector3=_activity_anchor.position+orientation*Vector3(0,0,(.45+.35*maxf(0,1.0-_proportion*visual.scale.x))*_proportion)
			centered.y=minf(center.y,rack.global_position.y+.07) if is_instance_valid(rack) else center.y
			var local_start:Vector3=orientation.inverse()*(center-Vector3(_activity_anchor.position))
			var local_finish:Vector3=orientation.inverse()*(centered-Vector3(_activity_anchor.position))
			var local_center:Vector3=Vector3(lerpf(local_start.x,local_finish.x,smoothstep(.50,1,gather)),lerpf(local_start.y,local_finish.y,smoothstep(0,.30,gather)),lerpf(local_start.z,local_finish.z,smoothstep(.20,.50,gather)))
			center=Vector3(_activity_anchor.position)+orientation*local_center
		return LifeOvenSequence.tray(_activity_anchor.oven,p,Transform3D(orientation,center))
	return Transform3D(global_basis.orthonormalized(),_model.to_global(Vector3(0,_hip_height+.22*_proportion,.30*_proportion)))

func _has_oven()->bool:
	return _presented_cooking_recipe=="harvest_bake" and is_instance_valid(_activity_anchor.get("oven"))

func _oven_cooking_pose(pose:Dictionary)->void:
	var oven:Node3D=_activity_anchor.oven
	var p:float=_cooking_progress()
	var phase:String=LifeOvenSequence.phase(p)
	var part:float=LifeOvenSequence.fraction(p,phase)
	LifeOvenSequence.apply_door(oven,p)
	if phase=="season":_cooking_pose(pose);return
	pose.Head=Vector3(.10*LifeOvenSequence.crouch(p),0,0)
	var held:Transform3D=_preparation_tray_transform()
	var door:Node3D=oven.find_child("OvenHandleGrip",true,false)
	var rack:Node3D=oven.find_child("OvenRackGrip",true,false)
	if not is_instance_valid(door) or not is_instance_valid(rack):return
	var support:Vector3=held*LifeOvenSequence.support_offset(p)
	var left_grip:Vector3=held*Vector3(-.2395,.046,0)
	var right_grip:Vector3=held*Vector3(.2395,.046,0)
	var left_rest:Vector3=_model.to_global(Vector3(-.23,_hip_height+.15,.12)*_proportion)
	var right_rest:Vector3=_model.to_global(Vector3(.23,_hip_height+.15,.12)*_proportion)
	var left:Vector3=left_rest;var right:Vector3=right_rest
	var handoff:float=smoothstep(0,.50,part)
	match phase:
		"reach_load":
			left=support
			right=_model.to_global(_recipe_food_point()+Vector3(.055,.205,.020)*_proportion).lerp(door.global_position,smoothstep(0,1,part))
		"open_load":left=support;right=door.global_position
		"pull_load":left=support;right=door.global_position.lerp(rack.global_position,handoff)
		"load":
			left=support.lerp(left_grip,smoothstep(0,.50,part))
			right=rack.global_position.lerp(right_grip,smoothstep(0,.50,part))
		"push_load":left=left_grip.lerp(left_rest,smoothstep(0,.65,part));right=right_grip.lerp(rack.global_position,handoff)
		"close_load":right=rack.global_position.lerp(door.global_position,handoff)
		"release_load":right=door.global_position.lerp(right_rest,smoothstep(0,1,part))
		"reach_unload":right=right_rest.lerp(door.global_position,smoothstep(0,1,part))
		"open_unload":right=door.global_position
		"pull_unload":right=door.global_position.lerp(rack.global_position,handoff)
		"unload":
			left=left_rest.lerp(left_grip,smoothstep(0,.50,part))
			right=rack.global_position.lerp(right_grip,smoothstep(0,.50,part))
		"push_unload":left=left_grip.lerp(support,handoff);right=right_grip.lerp(rack.global_position,handoff)
		"close_unload":left=support;right=rack.global_position.lerp(door.global_position,handoff)
		"release_unload":left=support.lerp(left_grip,smoothstep(0,1,part));right=door.global_position.lerp(right_grip,smoothstep(0,1,part))
	_reach_hand(pose,"L",_model.to_local(left),Vector3(-.4,-.6,0))
	_reach_hand(pose,"R",_model.to_local(right),Vector3(.4,-.6,0))


func _oven_leg_pose(pose:Dictionary)->void:
	# Feet retain their neutral ankle destinations while the knees bend and the
	# body lowers to the real rack. Navigation ownership remains in main.gd.
	var orientation:Basis=Basis(Vector3.UP,float(_activity_anchor.yaw))
	for side:String in _leg_rest:
		var rest:Dictionary=_leg_rest[side]
		var target:Vector3=_activity_anchor.position+orientation*(Vector3(rest.foot)*visual.scale)
		var local:Vector3=Transform3D(rest.space).affine_inverse()*_model.to_local(target)
		var upper:Vector3=rest.upper;var lower:Vector3=rest.lower
		var reach:Vector3=local-Vector3(rest.hip)
		var distance:float=clampf(reach.length(),absf(upper.length()-lower.length())+.005,upper.length()+lower.length()-.005)
		var forward:Vector3=reach.normalized()
		var pole:Vector3=Transform3D(rest.space).basis.inverse()*_model.global_basis.inverse()*(orientation*Vector3(0,.2,1))
		var bend:Vector3=(pole-forward*pole.dot(forward)).normalized()
		var along:float=(upper.length_squared()-lower.length_squared()+distance*distance)/(2*distance)
		var away:float=sqrt(maxf(0,upper.length_squared()-along*along))
		var upper_goal:Vector3=forward*along+bend*away
		var lower_goal:Vector3=forward*distance-upper_goal
		var thigh:Quaternion=Quaternion(upper.normalized(),upper_goal.normalized())
		pose["Leg_"+side]=thigh.get_euler()
		pose["Shin_"+side]=Quaternion(lower.normalized(),thigh.inverse()*lower_goal.normalized()).get_euler()

func _recipe_food_point() -> Vector3:
	if _presented_cooking_recipe=="harvest_bake":
		return _model.to_local(_preparation_tray_transform()*_food_surface_point(_baking_tray,_baking_food))
	if is_instance_valid(_recipe_bowl_food):return _model.to_local(_recipe_bowl.to_global(_food_surface_point(_recipe_bowl,_recipe_bowl_food)))
	return _model.to_local(_bowl_center.global_position)+Vector3(0,.027,0)*_proportion

func _preparation_sample_time() -> float:
	# Oven preparation must reconstruct from paid progress in a fresh actor.
	# This is a read-only sample coordinate, never an animation-clock update.
	if _has_oven():return _cooking_progress()*float(LifeMeals.RECIPES.harvest_bake.duration)/LifeSim.GAME_MINUTES_PER_SECOND
	return _action_time

func _cooking_pose(pose:Dictionary) -> void:
	var recipe:String=_presented_cooking_recipe
	var sample_time:float=_preparation_sample_time()
	var stir:float=sample_time*(1.7 if recipe=="herb_pasta" else 2.3)
	var bowl_hand:Vector3=Vector3(-.070,1.120,.350)*_proportion
	bowl_hand.y+=sin(stir*.5)*.005*_proportion
	if recipe=="harvest_bake":
		var held:Transform3D=_preparation_tray_transform()
		var left:Vector3=Vector3(-.105,-.004,0) if _is_seasoning() else Vector3(-.2395,.037,0)
		_reach_hand(pose,"L",_model.to_local(held*left),Vector3(-.25,-1.0,-.3))
		if not _is_seasoning():
			_reach_hand(pose,"R",_model.to_local(held*Vector3(.2395,.037,0)),Vector3(.25,-1.0,-.3))
			pose.Head=Vector3(.12,sin(sample_time*.6)*.035,0)
			return
	else:
		_reach_hand(pose,"L",bowl_hand,Vector3(-.7,-.8,-.1),Vector3.UP,Vector3(0,0,1))
	if _is_seasoning():
		var food:Vector3=_recipe_food_point()
		var hand:Vector3=food+Vector3(.055+sin(sample_time*1.8)*.022,.205+sin(sample_time*8)*.009,.020)*_proportion
		_seasoning_axis=(food-hand).normalized()
		_reach_hand(pose,"R",hand,Vector3(.6,-.45,-.1),_seasoning_axis)
		_preparation_tip=food
		pose.Head=Vector3(.14,-.04+sin(sample_time*.7)*.025,0)
		return
	if recipe=="herb_pasta":
		var food:Vector3=_recipe_food_point()
		_preparation_tip=food+Vector3(sin(stir)*.064,.006+cos(stir*2)*.008,cos(stir)*.027)*_proportion
		var hand:Vector3=_preparation_tip+Vector3(.015,.19,-.012)*_proportion
		_reach_hand(pose,"R",hand,Vector3(.8,-.6,-.1),_preparation_tip-hand)
	else:
		var hand:Vector3=Vector3(-.010+sin(stir)*.045,1.44,.39+cos(stir)*.038)*_proportion
		_preparation_tip=bowl_hand+Vector3(.035+sin(stir)*.048,.132,.025+cos(stir)*.042)*_proportion
		_reach_hand(pose,"R",hand,Vector3(.8,-.6,-.1),_preparation_tip-hand if not _grip_shapes.R.is_empty() else Vector3.ZERO)
	pose.Head=Vector3(.16,-.025+sin(stir*.5)*.018,0)

func _update_seasoning_grains() -> void:
	var sample_time:float=_preparation_sample_time()
	var mouth:Node3D=_seasoning_jar.get_node("SprinkleMouth")
	var start:Vector3=_model.to_local(mouth.global_position)
	var finish:Vector3=_recipe_food_point()
	for i:int in range(_seasoning_grains.size()):
		var grain:MeshInstance3D=_seasoning_grains[i]
		grain.visible=_seasoning_weight>.8
		var fall:float=fmod(sample_time*2.8+float(i)*.143,1.0)
		grain.position=start.lerp(finish,fall)+Vector3(sin(i*2.4)*.014,0,cos(i*2.4)*.014)*fall*_proportion

func _food_surface_point(dish:Node3D,food:Node3D) -> Vector3:
	var top:float=0.0
	if is_instance_valid(food):
		for mesh:MeshInstance3D in food.find_children("*","MeshInstance3D",true,false):
			for i:int in range(8):top=maxf(top,dish.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(i))).y)
	return Vector3(0,maxf(0.0,top-.005),0)

func _ensure_cooking_recipe_props() -> void:
	# Load the larger recipe artwork only for a Lifelet who prepares that recipe.
	if _presented_cooking_recipe=="herb_pasta" and not is_instance_valid(_recipe_bowl):
		var path:String="res://assets/models/meal_herb_pasta_serving.glb"
		if ResourceLoader.exists(path):
			_recipe_bowl=load(path).instantiate();_bowl_center.add_child(_recipe_bowl)
			_recipe_bowl.position=Vector3(0,-.098,0);_recipe_bowl.scale=Vector3.ONE*.70
			_recipe_bowl_food=_recipe_bowl.find_child("Food",true,false);_recipe_bowl.hide()
	if _presented_cooking_recipe=="harvest_bake" and _baking_tray.get_child_count()==0:
		var path:String="res://assets/models/meal_harvest_bake_serving.glb"
		if not ResourceLoader.exists(path):path="res://assets/models/meal_serving.glb"
		if ResourceLoader.exists(path):
			_baking_tray.add_child(load(path).instantiate());_baking_food=_baking_tray.find_child("Food",true,false)


func _cache_stair_sole_offsets()->void:
	for side:String in _leg_rest:
		var rest:Dictionary=_leg_rest[side]
		var shoe:Node3D=rest.shoe
		var minimum:Vector3=Vector3.INF;var maximum:Vector3=-Vector3.INF
		for mesh:MeshInstance3D in shoe.find_children("Shoes_Sole*","MeshInstance3D",true,false):
			for corner:int in range(8):
				var point:Vector3=_model.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
				minimum=minimum.min(point);maximum=maximum.max(point)
		if minimum.is_finite():
			rest["sole_offset"]=Vector3((minimum.x+maximum.x)*.5,minimum.y,(minimum.z+maximum.z)*.5)-Vector3(rest.foot)
			rest["sole_size"]=maximum-minimum
			var center:Vector3=Vector3(rest.foot)+Vector3(rest.sole_offset)
			minimum=Vector3.INF;maximum=-Vector3.INF
			for mesh:MeshInstance3D in shoe.find_children("*","MeshInstance3D",true,false):
				for corner:int in range(8):
					var point:Vector3=_model.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))-center
					minimum=minimum.min(point);maximum=maximum.max(point)
			rest["shoe_min"]=minimum;rest["shoe_max"]=maximum

func present_stair(state:Dictionary,reconstruct:bool=false)->void:
	stair_presentation=state.duplicate(true)
	_stair_exit_carry=state.is_empty()
	if state.is_empty():
		_reconstructing_stair=true
		_reset_stair_pose()
		_reconstructing_stair=false
		return
	if reconstruct:
		_reconstructing_stair=true
		animate(0,0,true,"")
		_reconstructing_stair=false

func _apply_stair_pose()->void:
	# Stair contacts describe a standing body even when reconstruction follows a
	# seated activity and the animation clock is paused.
	_sit_amount=0.0
	for entry:Dictionary in _sit_shapes:entry.mesh.set_blend_shape_value(int(entry.index),0.0)
	stair_pose_valid=true;stair_pose_error=""
	var old_visual:Transform3D=visual.transform
	var state:Dictionary=stair_presentation
	var orientation:=Basis(Vector3.UP,float(state.yaw))
	# Navigation remains the actor root. This is a small deterministic pelvis bend.
	visual.position=Vector3(0,-.035*_proportion,0)
	visual.rotation=Vector3.ZERO
	# Intersect both maximum-reach intervals and exclude folded minimum-reach
	# intervals. Feasibility is not monotonic across the whole crouch range.
	if not _solve_stair_pelvis(state,orientation):
		visual.transform=old_visual
		stair_pose_valid=false;stair_pose_error="The requested stair contacts are outside this Lifelet's leg reach."
		return
	var pose:Dictionary={}
	for side:String in _leg_rest:
		var rest:Dictionary=_leg_rest[side]
		var contact:Vector3=state.feet[side]+orientation*Vector3(Vector3(rest.foot).x*visual.scale.x,0,0)
		var target:Vector3=contact-orientation*(Vector3(rest.sole_offset)*visual.scale)
		var local:Vector3=Transform3D(rest.space).affine_inverse()*_model.to_local(target)
		var upper:Vector3=rest.upper;var lower:Vector3=rest.lower
		var reach:Vector3=local-Vector3(rest.hip)
		var distance:float=clampf(reach.length(),absf(upper.length()-lower.length())+.005,upper.length()+lower.length()-.005)
		var forward:Vector3=reach.normalized()
		var pole:Vector3=Transform3D(rest.space).basis.inverse()*_model.global_basis.inverse()*(orientation*Vector3(0,.2,1))
		var bend:Vector3=(pole-forward*pole.dot(forward)).normalized()
		var along:float=(upper.length_squared()-lower.length_squared()+distance*distance)/(2*distance)
		var away:float=sqrt(maxf(0,upper.length_squared()-along*along))
		var upper_goal:Vector3=forward*along+bend*away
		var lower_goal:Vector3=forward*distance-upper_goal
		var thigh:Quaternion=Quaternion(upper.normalized(),upper_goal.normalized())
		pose["Leg_"+side]=thigh.get_euler()
		pose["Shin_"+side]=Quaternion(lower.normalized(),thigh.inverse()*lower_goal.normalized()).get_euler()
	# Distance-based arm balance; carried-meal arms retain their existing ownership.
	if not bool(meal_presentation.get("carrying",false)):
		var swing:float=sin(float(state.phase)*PI)
		pose["Arm_L"]=Vector3(-.16*swing,0,-.07)
		pose["Arm_R"]=Vector3(.16*swing,0,.07)
		pose["Forearm_L"]=Vector3(-.28,0,0);pose["Forearm_R"]=Vector3(-.28,0,0)
	else:
		# Re-solve from the FINAL pelvis transform and distance-derived dish pose.
		_reach_hand(pose,"L",_meal_carry_hand("L"),Vector3(-.25,-1.0,-.35))
		_reach_hand(pose,"R",_meal_carry_hand("R"),Vector3(.25,-1.0,-.35))
	pose["Head"]=Vector3(.07,0,0)
	for name:String in pose:
		_joints[name].quaternion=Quaternion.from_euler(Vector3(_rest_rotations[name])+Vector3(pose[name]))
	for entry:Dictionary in _rig_bones:
		if not pose.has(entry.name):continue
		var rest:Quaternion=entry.rest
		entry.skeleton.set_bone_pose_rotation(int(entry.index),rest.inverse()*Quaternion.from_euler(pose[entry.name])*rest)
	for rest:Dictionary in _leg_rest.values():rest.shoe.global_basis=orientation*Basis(rest.shoe_basis)


func _stair_targets_reachable(state:Dictionary,orientation:Basis)->bool:
	for side:String in _leg_rest:
		var rest:Dictionary=_leg_rest[side]
		var contact:Vector3=state.feet[side]+orientation*Vector3(Vector3(rest.foot).x*visual.scale.x,0,0)
		var target:Vector3=contact-orientation*(Vector3(rest.sole_offset)*visual.scale)
		var local:Vector3=Transform3D(rest.space).affine_inverse()*_model.to_local(target)
		var distance:float=local.distance_to(rest.hip)
		var maximum:float=Vector3(rest.upper).length()+Vector3(rest.lower).length()-.012
		var minimum:float=absf(Vector3(rest.upper).length()-Vector3(rest.lower).length())+.006
		if distance>maximum or distance<minimum:return false
	return true


func stair_rear_extent(direction:int)->float:
	# Clearance toward the next higher riser includes the complete rigid shoe,
	# not only the sole. Descending shoes present their heel toward that riser.
	var extent:float=0
	for rest:Dictionary in _leg_rest.values():
		extent=maxf(extent,(Vector3(rest.shoe_max).z if direction==1 else -Vector3(rest.shoe_min).z)*visual.scale.z)
	return extent


func _reset_stair_pose()->void:
	# The controller calls this only after the reserved landing is reached.
	# Paused exit is deterministic, including carried dishes and finger shapes.
	visual.position=Vector3.ZERO;visual.rotation=Vector3.ZERO
	stair_pose_valid=true;stair_pose_error=""
	_book.visible=false;_brush.visible=false;_watering_can.visible=false
	var pose:Dictionary={}
	for name:String in JOINT_NAMES:pose[name]=Vector3.ZERO
	_update_grips(0,false,"")
	if bool(meal_presentation.get("carrying",false)):
		_reach_hand(pose,"L",_meal_carry_hand("L"),Vector3(-.25,-1.0,-.35))
		_reach_hand(pose,"R",_meal_carry_hand("R"),Vector3(.25,-1.0,-.35))
	for name:String in _joints:_joints[name].quaternion=Quaternion.from_euler(Vector3(_rest_rotations[name])+Vector3(pose[name]))
	for entry:Dictionary in _rig_bones:
		var rest:Quaternion=entry.rest
		entry.skeleton.set_bone_pose_rotation(int(entry.index),rest.inverse()*Quaternion.from_euler(pose[entry.name])*rest)
	for rest:Dictionary in _leg_rest.values():rest.shoe.basis=Basis.IDENTITY
	_sit_amount=0
	for entry:Dictionary in _sit_shapes:entry.mesh.set_blend_shape_value(int(entry.index),0)
	_update_held_props(0,false,"")


func _solve_stair_pelvis(state:Dictionary,orientation:Basis)->bool:
	visual.position.y=0
	var lowest:float=-.40*_proportion
	var highest:float=-.035*_proportion
	var exclusions:Array[Vector2]=[]
	for side:String in _leg_rest:
		var rest:Dictionary=_leg_rest[side]
		var contact:Vector3=state.feet[side]+orientation*Vector3(Vector3(rest.foot).x*visual.scale.x,0,0)
		var target:Vector3=contact-orientation*(Vector3(rest.sole_offset)*visual.scale)
		var inverse:Transform3D=Transform3D(rest.space).affine_inverse()
		var reach:Vector3=inverse*_model.to_local(target)-Vector3(rest.hip)
		var axis:Vector3=inverse.basis*_model.global_basis.inverse()*(global_basis*Vector3.UP)
		var squared:float=axis.length_squared()
		var center:float=reach.dot(axis)/squared
		var perpendicular:float=maxf(0,reach.length_squared()-pow(reach.dot(axis),2)/squared)
		var maximum:float=Vector3(rest.upper).length()+Vector3(rest.lower).length()-.012
		var minimum:float=absf(Vector3(rest.upper).length()-Vector3(rest.lower).length())+.006
		if perpendicular>maximum*maximum:return false
		var radius:float=sqrt((maximum*maximum-perpendicular)/squared)
		lowest=maxf(lowest,center-radius+.000001);highest=minf(highest,center+radius-.000001)
		if perpendicular<minimum*minimum:
			var inner:float=sqrt((minimum*minimum-perpendicular)/squared)
			exclusions.append(Vector2(center-inner,center+inner))
	for iteration:int in range(exclusions.size()+1):
		for interval:Vector2 in exclusions:
			if highest>=interval.x and highest<=interval.y:highest=interval.x-.000001
	if highest<lowest:return false
	visual.position.y=highest
	return _stair_targets_reachable(state,orientation)
