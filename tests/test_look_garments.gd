extends SceneTree
## Formal / Athletic / Sleep / Party clothes are original Blender meshes,
## not BoxMesh overlays on the five everyday tops.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func has_box(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh is BoxMesh:
		var mesh_node: MeshInstance3D = node
		if str(mesh_node.name).begins_with("Sleep") or str(mesh_node.get_parent().name) in ["SleepWrap", "FormalDrape", "PartySash", "AthleticBand"]:
			return true
	for child: Node in node.get_children():
		if has_box(child):
			return true
	return false

func check_garment_skin(node: Node) -> void:
	if node is MeshInstance3D:
		var garment: MeshInstance3D = node
		check(garment.skin != null and garment.get_node_or_null(garment.skeleton) is Skeleton3D, "Garment %s follows its exported skeleton" % garment.name)
	for child: Node in node.get_children():
		check_garment_skin(child)

func check_matching_pose(actor: LifeActor) -> void:
	var body_poses: Dictionary = {}
	for entry: Dictionary in actor._rig_bones:
		if not actor._look_root.is_ancestor_of(entry.skeleton):
			body_poses[str(entry.name)] = entry.skeleton.get_bone_pose_rotation(int(entry.index))
	var checked: int = 0
	for entry: Dictionary in actor._rig_bones:
		if actor._look_root.is_ancestor_of(entry.skeleton) and body_poses.has(str(entry.name)):
			var actual: Quaternion = entry.skeleton.get_bone_pose_rotation(int(entry.index))
			var expected: Quaternion = body_poses[str(entry.name)]
			# Slerp's near-equal branch can return slightly non-unit values.
			# angle_to then reports a nonzero angle even for identical poses.
			check(actual.is_equal_approx(expected) or actual.is_equal_approx(-expected), "Garment joint %s keeps the body's activity pose" % entry.name)
			checked += 1
	check(checked == LifeActor.JOINT_NAMES.size(), "Every animated joint drives the garment")

func run() -> void:
	for family: String in ["adult", "child", "teen", "elder"]:
		for category: String in ["formal", "athletic", "sleep", "party"]:
			check(ResourceLoader.exists("res://assets/models/looks/%s_%s.glb" % [family, category]), "%s %s look mesh is present" % [family, category])
	var actor := LifeActor.new()
	root.add_child(actor)
	await process_frame
	actor.configure(LifeCharacterIdentity.generate(9104, {"age_stage": "adult", "name": "Remy Vale", "outfit_category": "formal"}))
	LifeCharacterIdentity.apply_category(actor.profile, "formal")
	actor.apply_wardrobe(actor.profile)
	await process_frame
	check(actor.visual.find_child("SleepWrap", true, false) == null, "Sleep is not a crate wrap")
	check(actor.visual.find_child("FormalDrape", true, false) == null, "Formal is not a crate drape")
	check(actor.visual.find_child("Outfit_Formal", true, false) != null, "Formal wears its own authored mesh")
	check(not has_box(actor), "Look clothes do not use BoxMesh silhouettes")
	for family: String in ["adult", "child", "teen", "elder"]:
		actor.configure(LifeCharacterIdentity.generate(9104, {"age_stage": family}))
		var body_bones: int = actor._rig_bones.size()
		for category: String in ["formal", "athletic", "sleep", "party"]:
			LifeCharacterIdentity.apply_category(actor.profile, category)
			actor.apply_wardrobe(actor.profile)
			await process_frame
			check(is_instance_valid(actor._look_root), "%s %s has a fitted garment" % [family, category])
			if not is_instance_valid(actor._look_root):
				continue
			check(actor._look_root.scale.is_equal_approx(Vector3.ONE), "%s garment keeps its authored size" % family)
			check_garment_skin(actor._look_root)
			actor.animate(0.2, 1.0, true, "")
			check_matching_pose(actor)
			check(actor._rig_bones.size() == body_bones + LifeActor.JOINT_NAMES.size(), "Changing outfits releases the old garment's joints")
		LifeCharacterIdentity.apply_category(actor.profile, "everyday")
		actor.apply_wardrobe(actor.profile)
		check(actor._rig_bones.size() == body_bones, "Everyday restores only the body's joint drivers")
	actor.configure(LifeCharacterIdentity.generate(9010, {"age_stage": "baby"}))
	LifeCharacterIdentity.apply_category(actor.profile, "sleep")
	actor.apply_wardrobe(actor.profile)
	check(not is_instance_valid(actor._look_root), "A baby's Sleep look keeps the fitted infant garment")
	var infant_clothes: Node3D = actor._model.find_child("Outfit_Casual_Romper", true, false) as Node3D
	check(infant_clothes != null and infant_clothes.visible, "Baby still wears its authored clothing")
	actor.queue_free()
	await process_frame
	print("LOOK_GARMENTS_RESULT ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
