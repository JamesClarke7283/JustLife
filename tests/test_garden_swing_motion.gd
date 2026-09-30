extends SceneTree
## Imported cushion contact, fixed suspension, shared seats, pause and exit.
const DT: float = 1.0 / 30.0
var checks: int = 0
var failures: Array[String] = []
var world: LifeWorld
var greatest_gap: float = 0.0
var pool: Array[LifeActor] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = LifeWorld.new(); root.add_child(world); world.set_process(false)
	world.furniture = Node3D.new(); world.add_child(world.furniture)
	world.box(world, Vector3(0, -.05, 0), Vector3(40, .1, 40), "749752")
	# Keep the adult meshes loaded while rotating and resizing furniture.
	for index: int in 4:
		var person := LifeActor.new(); world.add_child(person)
		person.configure({"name":"Swing rider", "age_stage":"adult", "frame":index % 2, "low_detail":true, "body_scale":1.1 if index % 2 else .9, "height_scale":1.06 if index % 2 else .94})
		person.voice_enabled = false;person.visible = false
		pool.append(person)
	var styles: Array = ["c"] if OS.get_cmdline_user_args().has("--basket-only") else ["a", "b", "c"]
	for style: String in styles:
		for size: String in ["small", "medium", "large"]:
			for yaw: float in [0.0, 90.0, 180.0, 270.0]:
				await variant(style, size, yaw)
	world.queue_free(); await process_frame
	if not OS.get_cmdline_user_args().has("--basket-only"): await live_action()
	print("GARDEN_SWING %d checks, %d failures; greatest settled seat gap %.6f m" % [checks, failures.size(), greatest_gap])
	var path: String = OS.get_environment("SWING_EVIDENCE_DIR")
	if path.is_absolute_path():
		var out := FileAccess.open(path.path_join("result.json"), FileAccess.WRITE)
		out.store_string(JSON.stringify({"checks": checks, "failures": failures, "greatest_seat_gap": greatest_gap, "styles":styles, "variants":styles.size()*12, "live_action":not OS.get_cmdline_user_args().has("--basket-only")}, "  "))
	quit(0 if failures.is_empty() else 1)

func variant(style: String, size: String, yaw: float) -> void:
	print("SWING_VARIANT ",style," ",size," ",yaw)
	world.add_item({"id":"motion_swing", "kind":"outdoor_swing", "x":0, "z":0, "rotation":yaw, "style":style, "size":size}, false)
	var item: Dictionary = world.items[-1]
	var slots: Array[String] = world.seat_slots(item)
	var capacity: int = 1 if style == "c" else {"small":2,"medium":3,"large":4}[size]
	check(world.seat_capacity(item) == capacity and slots.size() == capacity, "%s %s has only physically supported seats" % [style,size])
	if slots.size()!=capacity:
		world.remove_item(str(item.id));await process_frame;return
	var people: Array[LifeActor] = []
	for index: int in range(capacity):
		var person: LifeActor = pool[index]
		person.visible = true
		person.position = item.node.to_global(Vector3(world.seat_slot_offset(item,slots[index]).x,0,2.0))
		people.append(person)
	var fixed: Dictionary = {}
	var cushion: MeshInstance3D
	for mesh: MeshInstance3D in item.node.find_children("*", "MeshInstance3D", true, false):
		if (style != "c" and str(mesh.name).begins_with("Tint")) or (style == "c" and str(mesh.name).begins_with("Basket body")): cushion = mesh
		if str(mesh.name).begins_with("Frame") or str(mesh.name).begins_with("Pergola") or str(mesh.name).begins_with("Top"):
			fixed[mesh] = mesh.global_transform
	var first_root: Transform3D = people[0].transform
	var min_z: float = INF; var max_z: float = -INF
	var leg_min: float = INF; var leg_max: float = -INF
	var motion: Node3D
	for frame: int in range(210):
		world.begin_activity_frame(false, DT, 1.0)
		for index: int in people.size():
			var person: LifeActor = people[index]
			var anchor: Dictionary = world.activity_anchor(item, LifeOutdoorActs.ACTION_ID, {"seat_slot":slots[index]})
			if frame == 0: check(anchor.kind == "seat", "Garden action supplies a seat instead of a standing anchor")
			motion = anchor.swing_motion
			person.set_activity_anchor(anchor.position, anchor.yaw, anchor.kind, LifeOutdoorActs.ACTION_ID, anchor)
			person.animate(DT, 1.0, false, LifeOutdoorActs.ACTION_ID)
			if frame > 45:
				var hips: Vector3 = person.visual.to_global(Vector3(0,person._hip_height,0))
				var gap: float = hips.distance_to(anchor.position)
				greatest_gap = maxf(greatest_gap, gap)
				if frame % 30 == 0: check(gap < .002, "Adult pelvis remains supported throughout the moving swing cycle")
				if frame == 90:
					var on_mesh: Vector3 = cushion.to_local(hips)
					var bounds: AABB = cushion.get_aabb()
					check(absf(on_mesh.y-bounds.end.y)<.002 and absf(on_mesh.x)<bounds.size.x*.5 and absf(on_mesh.z)<bounds.size.z*.5,"Rider is supported by the actual imported cushion, within its edges")
				if style == "c" and frame % 30 == 0:
					var cables: Array[Node] = motion.pivot.find_children("BasketSuspension*","MeshInstance3D",false,false)
					check(cables.size()==2,"Basket has two continuous suspensions instead of a chain through the rider")
					for cable: MeshInstance3D in cables:
						var half: float = (cable.mesh as CylinderMesh).height*.5
						var head: Vector3 = person._joints.Head.to_global(Vector3(0,.06,.02))
						var near: Vector3 = Geometry3D.get_closest_point_to_segment(head,cable.to_global(Vector3(0,half,0)),cable.to_global(Vector3(0,-half,0)))
						check(head.distance_to(near)>.16,"Basket suspension clears the adult's head throughout the arc")
				var at: Vector3 = item.node.to_local(anchor.position)
				min_z = minf(min_z,at.z); max_z = maxf(max_z,at.z)
				leg_min = minf(leg_min,person._joints.Shin_L.rotation.x);leg_max = maxf(leg_max,person._joints.Shin_L.rotation.x)
		if frame == 100 and style == "b" and size == "small" and yaw == 0.0: await capture("bench_forward",item)
		if frame == 100 and style == "a" and size == "small" and yaw == 0.0: await capture("canopy_bench",item)
		if frame == 145 and style == "b" and size == "small" and yaw == 0.0: await capture("bench_back",item)
		if frame == 170 and style == "c" and size == "small" and yaw == 0.0: await capture("basket",item)
	check(max_z-min_z > .10, "The visible seat and riders travel through a real pendulum arc")
	check(leg_max-leg_min > .15, "Adult knees pump visibly while swinging")
	check(people[0]._sit_amount > .99 and absf(people[0]._joints.Leg_L.rotation.x) > 1.2, "Adult settles into a bent-knee sitting pose")
	check(people[0].transform.is_equal_approx(first_root), "Swing animation leaves navigation-root ownership intact")
	for mesh: MeshInstance3D in fixed: check(mesh.global_transform.is_equal_approx(fixed[mesh]), "Swing frame stays fixed while its cushion moves")
	for hanger: Dictionary in motion.hangers:
		var piece: MeshInstance3D = hanger.node
		var bounds := piece.get_aabb()
		var first_end: Vector3 = piece.transform * Vector3(0,bounds.position.y,0)
		var last_end: Vector3 = piece.transform * Vector3(0,bounds.end.y,0)
		check(minf(first_end.distance_to(hanger.upper),last_end.distance_to(hanger.upper)) < .001, "Each suspension hanger remains attached to its fixed upper mount")
	var paused_seat: Transform3D = motion.pivot.global_transform
	var paused_body: Transform3D = people[0].visual.global_transform
	var paused_clock: float = motion.clock
	for frame: int in 15:
		world.begin_activity_frame(true,DT,0.0)
		people[0].animate(DT,0.0,true,"")
	check(motion.pivot.global_transform.is_equal_approx(paused_seat) and motion.clock == paused_clock, "Pause freezes the shared swing clock and cushion")
	check(people[0].visual.global_transform.is_equal_approx(paused_body), "Pause freezes the rider even if an action is canceled")
	for person: LifeActor in people: person.clear_activity_anchor()
	for frame: int in 120:
		world.begin_activity_frame(false,DT,1.0)
		for person: LifeActor in people: person.animate(DT,1.0,true,"")
	check(absf(motion.angle) < .001, "An empty swing settles gently back to rest")
	check(people[0].visual.position.length() < .05 and people[0]._sit_amount < .01, "Canceled or completed riding returns the body to its walking root")
	for person: LifeActor in people: person.visible = false
	world.remove_item(str(item.id));await process_frame

func capture(label: String, item: Dictionary) -> void:
	var path: String = OS.get_environment("SWING_EVIDENCE_DIR")
	if path.is_empty() or DisplayServer.get_name() == "headless": return
	world.camera.position = item.node.global_position + Vector3(3.3,2.7,5.0)
	world.camera.look_at(item.node.global_position+Vector3(0,1.1,0))
	world.camera.size = 4.1
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join(label+".png"))

func live_action() -> void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		check(false,"Live check requires isolated player data"); return
	var app: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame; await process_frame
	app.set_sound(false)
	app.household_profiles = [{"name":"Avery", "age_stage":"adult", "traits":[]}]
	app.creator_family_links = []
	app.start_household()
	await process_frame; await process_frame
	app.set_process(false)
	app.household.set_speed(0)
	app.sim.autonomy = false
	app.sim.set_aging("normal",false)
	var item: Dictionary = app.world.closest_item("outdoor_swing",Vector3.ZERO)
	if item.is_empty():
		app.world.add_item({"id":"live_swing", "kind":"outdoor_swing", "x":-7.5, "z":2.5, "rotation":0, "style":"a", "size":"small"})
		item = app._find_item("live_swing")
	app._refresh_sim_targets(false)
	var legacy: Dictionary = {"seat_slot":"seat_7","target_id":item.id}
	app._assign_seat_slot(legacy,item)
	check(app.world.seat_slots(item).has(str(legacy.get("seat_slot",""))),"Legacy off-cushion seat slots are reassigned to a real seat")
	app.queue_interaction(item,LifeOutdoorActs.ACTION_ID)
	check(str(app.sim.get_current_action().get("id","")) == LifeOutdoorActs.ACTION_ID,"Real garden menu action enters the adult's queue")
	app.household.set_speed(3)
	var active: bool = false
	var seated: bool = false
	var departed: bool = false
	for frame: int in 2400:
		app._process(DT)
		if frame % 30 == 0: await process_frame
		var action: Dictionary = app.sim.get_current_action()
		if str(action.get("phase","")) == "active" and str(action.get("id","")) == LifeOutdoorActs.ACTION_ID:
			active = true
			if app.player._sit_amount > .99:
				if not seated:
					var anchor: Dictionary = app.player._activity_anchor
					check(str(anchor.get("outdoor_kind","")) == "outdoor_swing","Main game passes its real swing anchor through to the actor")
				seated = true
		if active and action.is_empty(): departed = true; break
	check(active and seated,"Adult walks from home, reaches the real swing and sits down")
	check(departed,"The full garden-swing activity completes normally")
	for frame: int in 60: app._process(DT)
	check(app.player._sit_amount < .01 and not app.player.is_anchored(),"Completion releases the adult from the swing")
	app.queue_free();await process_frame;await process_frame
