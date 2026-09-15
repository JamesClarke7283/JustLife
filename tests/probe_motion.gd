extends SceneTree
## Capture the shipped motion as evidence: a walk cycle driven by real routing,
## a seated pose at a real chair, and a sleeper on a real bed. Every pose is
## produced by the actor's own code, and each claim is read from the rig rather
## than inferred from a picture.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_motion.gd

const Building = preload("res://scripts/building_state.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://motion"))
	root.get_texture().get_image().save_png("user://motion/%s.png" % label)
	print("MOTION_SHOT ", ProjectSettings.globalize_path("user://motion/%s.png" % label))

func watch(zoom: float) -> void:
	var actor: Node3D = app.world.actors.get(str(app.household.selected_id()))
	if not is_instance_valid(actor): return
	app.world.camera_target = actor.position + Vector3(0, 0.5, 0)
	app.world.camera.size = zoom
	app.world.camera_angle = .62
	app.world.update_camera()
	await frames(4)

## The actor's own joint entry, from the table it discovered at load.
func joint(walker: LifeActor, name: String) -> Dictionary:
	for entry: Dictionary in walker._rig_bones:
		if str(entry.get("name", "")) == name: return entry
	return {}

func joint_pitch(entry: Dictionary) -> float:
	if entry.is_empty(): return 0.0
	var skeleton: Skeleton3D = entry["skeleton"]
	return skeleton.get_bone_pose_rotation(int(entry["index"])).get_euler().x

## The mesh's closed-eye amount, for the sleeping check.
func blink_amount(walker: LifeActor) -> float:
	if walker._blink_shapes.is_empty(): return -1.0
	var entry: Dictionary = walker._blink_shapes.front()
	return float((entry["mesh"] as MeshInstance3D).get_blend_shape_value(int(entry["index"])))

func item_of(kind: String) -> Dictionary:
	for item: Dictionary in app.world.items:
		if str(item.get("kind", "")) == kind: return item
	return {}

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(16)
	app.household.set_speed(0)
	var walker: LifeActor = app.world.actors.get(str(app.household.selected_id()))
	check(is_instance_valid(walker), "The Lifelet has a live actor")
	if not is_instance_valid(walker): return

	# --- A walk cycle, driven by the game's own routing ----------------------
	var start: Vector3 = walker.position
	var leg: Dictionary = joint(walker, "Leg_L")
	check(not leg.is_empty(), "The actor exposes its own leg joint")
	app.on_ground_clicked(Vector3(start.x + 3.0, Building.GROUND_Y, start.z + 2.0))
	check(not app.path.is_empty(), "A walk across the room really has a route (%d nodes)" % app.path.size())
	app.household.set_speed(1)
	var lowest: float = INF
	var highest: float = -INF
	var captured: int = 0
	for step: int in range(420):
		await frames(1)
		var angle: float = joint_pitch(leg)
		lowest = minf(lowest, angle)
		highest = maxf(highest, angle)
		if step % 70 == 0 and captured < 4:
			await watch(3.4)
			await shot("walk_%d" % captured)
			captured += 1
	app.household.set_speed(0)
	await frames(4)
	var travelled: float = walker.position.distance_to(start)
	var spread: float = highest - lowest
	print("walk: %.2f m travelled, leg pitch spread %.3f rad, %d frames" % [travelled, spread, captured])
	check(travelled > 0.5, "The Lifelet really walked across the room (%.2f m)" % travelled)
	check(captured == 4, "A four-frame walk cycle was captured (%d)" % captured)
	check(spread > 0.05, "The walk cycle really swings the leg over the stride (%.3f rad)" % spread)

	# --- A seated pose at a real chair, via the actor's own pose code ---------
	var chair: Dictionary = item_of("chair")
	check(not chair.is_empty(), "The home has a chair to sit on")
	if not chair.is_empty():
		var seat := Vector3(float(chair.x), Building.GROUND_Y, float(chair.z))
		# Queue the real activity through the public interaction path, so the
		# simulation drives the pose and the anchor itself.
		var queued: bool = app.sim.queue_action("relax", str(chair.id), seat)
		check(queued, "Sitting down on the chair is a real queued activity")
		app.household.set_speed(1)
		var deadline: int = Time.get_ticks_msec() + 90000
		while str(app.sim.get_current_action().get("phase", "")) != "active" and Time.get_ticks_msec() < deadline:
			await frames(5)
		for i: int in range(120): await frames(1)
		app.household.set_speed(0)
		await frames(4)
		var thigh: float = joint_pitch(joint(walker, "Leg_L"))
		await watch(2.4)
		await shot("seated_chair")
		print("seated thigh pitch %.3f rad" % thigh)
		check(absf(thigh) > 0.6, "A seated Lifelet really bends at the hip (%.3f rad)" % thigh)

	# --- A sleeper on a real bed, via the actor's rest reconstruction ---------
	var bed: Dictionary = item_of("bed")
	check(not bed.is_empty(), "The home has a bed to sleep in")
	if not bed.is_empty():
		var on_bed := Vector3(float(bed.x), Building.GROUND_Y + 0.30, float(bed.z))
		walker.clear_activity_anchor()
		walker.position = on_bed
		walker.set_activity_anchor(on_bed, 0.0, "bed", "sleep", {})
		# This is the game's own paused-sleeper path, so the pose is the shipped
		# one rather than a test-authored arrangement.
		walker.reconstruct_rest_pose("sleep")
		await frames(4)
		var eyes: float = blink_amount(walker)
		await watch(2.8)
		await shot("sleeping_bed")
		print("sleeper blink closure %.2f" % eyes)
		check(eyes > 0.9, "A sleeping Lifelet really closes its eyes (%.2f)" % eyes)
		# A lying body's own marker rides at the mattress, not upright.
		check(walker._marker.position.y < walker._authored_height * 0.5 or walker.visual.rotation.x < -0.5,
			"A sleeping Lifelet's body really lies down")

	print("MOTION_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
