extends Node3D
class_name LifeActor
## Articulated original character. The parent world owns all navigation/movement.

const JOINT_NAMES: Array[String] = ["Head", "Arm_L", "Arm_R", "Forearm_L", "Forearm_R", "Leg_L", "Leg_R", "Shin_L", "Shin_R"]
const HAIR_NAMES: Array[String] = ["Hair_Crop", "Hair_Bob", "Hair_Curls"]
const OUTFIT_NAMES: Array[String] = ["Outfit_Casual", "Outfit_Jacket", "Outfit_Cardigan"]

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
var _book: Node3D
var _brush: Node3D
var _snack: Node3D
var _watering_can: Node3D
var _time: float = 0.0
var _speech_remaining: float = 0.0
var _height: float = 1.0
var _phase_offset: float = 0.0
var _rig_bones: Array = []
var _blink_shapes: Array = []
var _smile_shapes: Array = []
var _blink_wait: float = 2.5
var _blink_elapsed: float = -1.0
var _smile: float = 0.0


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
		if FileAccess.file_exists(audio_path):
			var stream: AudioStreamWAV = AudioStreamWAV.load_from_file(audio_path)
			if stream != null:
				_voice_streams[category] = stream
	set_selected(selected)


func configure(new_profile: Dictionary) -> void:
	_ensure_nodes()
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
	var frame: int = clampi(int(profile.get("frame", 0)), 0, 1)
	var path: String = "res://assets/models/character_broad.glb" if frame == 1 else "res://assets/models/character.glb"
	if bool(profile.get("low_detail", false)):
		var lod_path: String = "res://assets/models/character_broad_lod.glb" if frame == 1 else "res://assets/models/character_lod.glb"
		if ResourceLoader.exists(lod_path):
			path = lod_path
	# Staged rigs can be reviewed without replacing the released articulated assets.
	if bool(profile.get("rig_preview", false)):
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
	_voice.position.y = 1.5 * _height
	var hair_index: int = clampi(int(profile.get("hair", 0)), 0, 2)
	for index: int in range(HAIR_NAMES.size()):
		var group: Node3D = _model.find_child(HAIR_NAMES[index], true, false) as Node3D
		if group != null:
			group.visible = index == hair_index
	for joint_name: String in JOINT_NAMES:
		var joint: Node3D = _model.find_child(joint_name, true, false) as Node3D
		if joint != null:
			_joints[joint_name] = joint
			_rest_rotations[joint_name] = joint.rotation
	_discover_deformation(_model)
	set_outfit(clampi(int(profile.get("outfit",0)),0,2))
	_recolor(_model)
	_create_props()
	_marker.position.y = 1.97 * _height
	_speech.position.y = 2.30 * _height


func set_outfit(index: int) -> void:
	profile["outfit"] = clampi(index,0,2)
	if _model != null:
		_apply_outfit_visibility(_model,OUTFIT_NAMES[int(profile["outfit"])])


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
			if bone_index >= 0:
				_rig_bones.append({"skeleton":skeleton,"index":bone_index,"name":joint_name,"rest":skeleton.get_bone_rest(bone_index).basis.get_rotation_quaternion()})
	if node is MeshInstance3D and node.mesh != null:
		var mesh_node: MeshInstance3D = node
		for shape_index: int in range(mesh_node.mesh.get_blend_shape_count()):
			var shape_name: String = str(mesh_node.mesh.get_blend_shape_name(shape_index)).to_lower()
			if shape_name == "blink":
				_blink_shapes.append({"mesh":mesh_node,"index":shape_index})
			elif shape_name == "smile":
				_smile_shapes.append({"mesh":mesh_node,"index":shape_index})
	for child: Node in node.get_children():
		_discover_deformation(child)


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
	_book = Node3D.new()
	_book.name = "ReadingBook"
	_model.add_child(_book)
	_book.position = Vector3(0.0, 1.10, 0.32)
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
	_brush.visible = false
	_snack = _hand_anchor("Snack", "R")
	var food: MeshInstance3D = _box(_snack, Vector3(0.049, 0.023, 0.065), Color("d7b479"))
	food.position.z = 0.027
	_snack.visible = false
	_watering_can = _hand_anchor("WateringCan", "R")
	var can: MeshInstance3D = _cylinder(_watering_can, 0.072, 0.14, Color("97b5a3"))
	can.position = Vector3(0.03, -0.08, 0.0)
	var spout: MeshInstance3D = _cylinder(_watering_can, 0.017, 0.18, Color("7a9b89"))
	spout.rotation.x = 0.95
	spout.position = Vector3(0.03, -0.043, 0.12)
	_watering_can.visible = false


func _hand_anchor(anchor_name: String, side: String) -> Node3D:
	var anchor: Node3D = Node3D.new()
	anchor.name = anchor_name
	var parent_joint: Node3D = _joints.get("Forearm_" + side, _model)
	parent_joint.add_child(anchor)
	anchor.position = Vector3(0.023 if side == "R" else -0.023, -0.262, 0.026)
	return anchor


func set_selected(value: bool) -> void:
	selected = value
	if _ring != null:
		_ring.visible = value
	if _marker != null:
		_marker.visible = value


func speech(text: String) -> void:
	_ensure_nodes()
	_speech.text = text.strip_edges().left(96)
	_speech_remaining = clampf(2.5 + float(text.length()) * 0.04, 3.0, 7.0)
	_speech.visible = not _speech.text.is_empty()
	# Queue sound until animate supplies the current game speed; pause stays silent.
	var lower: String = text.to_lower()
	_pending_voice = "reaction"
	if lower.contains("hello") or lower.contains("welcome") or lower.contains("hey"):
		_pending_voice = "greeting"
	elif lower.contains("!") or lower.contains("love") or lower.contains("laugh"):
		_pending_voice = "happy"
	elif lower.contains("?") or lower.contains("think"):
		_pending_voice = "thoughtful"


func animate(delta: float, speed_factor: float, moving: bool, action_id: String) -> void:
	if _model == null or delta <= 0.0:
		return
	_update_voice(delta, speed_factor, moving, action_id)
	var animation_delta: float = delta * clampf(speed_factor, 0.0, 3.0)
	_time += animation_delta
	_speech_remaining = maxf(0.0, _speech_remaining - delta)
	_speech.visible = _speech_remaining > 0.0 and not _speech.text.is_empty()
	_marker.position.y = 1.97 * _height + sin(_time * 2.0 + _phase_offset) * 0.026
	_marker.rotation.y = sin(_time * 0.8) * 0.20
	var t: float = _time + _phase_offset
	var blend: float = 1.0 - exp(-delta * 10.0)
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
	_snack.visible = false
	_watering_can.visible = false
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
			"sleep", "nap":
				lean = Vector3(-PI / 2.0 + 0.025, 0, 0)
				offset += Vector3(0, 0.57, 0.63)
				pose["Head"] = Vector3(0, -0.12, 0.04)
				pose["Arm_L"] = Vector3(-0.18, 0, -0.1)
				pose["Arm_R"] = Vector3(-0.25, 0, 0.08)
				pose["Forearm_L"] = Vector3(-0.45, 0, 0)
				pose["Forearm_R"] = Vector3(-0.55, 0, 0)
				pose["Leg_L"] = Vector3(-0.08, 0, 0)
				pose["Shin_L"] = Vector3(0.12, 0, 0)
			"relax", "watch", "toilet", "work", "study", "job":
				_seated_pose(pose)
				offset.y -= 0.43 * _height
				if action_id in ["work", "study", "job"]:
					pose["Arm_L"] = Vector3(-0.42, 0, 0.05)
					pose["Arm_R"] = Vector3(-0.42, 0, -0.05)
					pose["Forearm_L"] = Vector3(-0.85 + sin(t * 9.0) * 0.05, 0, 0)
					pose["Forearm_R"] = Vector3(-0.85 + cos(t * 9.0) * 0.05, 0, 0)
					pose["Head"] = Vector3(0.16, sin(t * 0.7) * 0.035, 0)
				elif action_id == "watch":
					pose["Head"] = Vector3(-0.06, sin(t * 0.3) * 0.1, 0)
					pose["Forearm_R"] = Vector3(-0.42, 0, 0)
				elif action_id == "relax":
					pose["Head"] = Vector3(-0.08, 0.05, 0.05)
					pose["Arm_L"] = Vector3(0.02, 0, -0.32)
					pose["Arm_R"] = Vector3(0.02, 0, 0.32)
			"snack":
				var bite: float = 0.5 + 0.5 * sin(t * 2.0)
				pose["Arm_R"] = Vector3(lerpf(-0.40, -1.02, bite), 0, -0.30 * bite)
				pose["Forearm_R"] = Vector3(lerpf(-0.70, -2.45, bite), 0, 0)
				pose["Head"] = Vector3(0.08 * bite, -0.05, 0)
				_snack.visible = true
			"cook":
				pose["Arm_L"] = Vector3(-0.50, 0, 0.08)
				pose["Arm_R"] = Vector3(-0.60 + sin(t * 3.0) * 0.10, 0.13 * cos(t * 3.0), -0.05)
				pose["Forearm_L"] = Vector3(-0.65, 0, 0)
				pose["Forearm_R"] = Vector3(-0.68 + cos(t * 3.0) * 0.15, 0, 0)
				pose["Head"] = Vector3(0.20, -0.05, 0)
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
			"friendly", "joke", "deep_talk", "flirt", "argue":
				_conversation_pose(pose, action_id, t)
	visual.position = visual.position.lerp(offset, blend)
	visual.rotation = _angle_lerp(visual.rotation, lean, blend)
	for joint_name: String in _joints:
		var joint: Node3D = _joints[joint_name]
		var goal_rotation: Vector3 = _rest_rotations[joint_name] + pose[joint_name]
		joint.rotation = _angle_lerp(joint.rotation, goal_rotation, blend)


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
	var categories: Dictionary = {"friendly": "greeting", "joke": "happy", "deep_talk": "thoughtful", "flirt": "happy", "argue": "argument"}
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
