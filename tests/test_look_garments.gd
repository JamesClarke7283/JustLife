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
	actor.queue_free()
	await process_frame
	print("LOOK_GARMENTS_RESULT ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
