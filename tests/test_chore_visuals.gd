extends SceneTree
## What dirt looks like and what cleaning does to it: haze on the glass that the squeegee
## clears lane by lane, a smudge by the door handle, leaves on the doorstep that the broom
## takes, toys on the floor that are picked up one at a time, a window or door shown while
## it is being cleaned even with the walls down, and cushions and curtains put back as they
## were. Append `-- --capture` and omit `--headless` for rendered before-and-after pictures.
const DT: float = 1.0 / 30.0
var app: Node
var flow: Node
var checks: int = 0
var failures: Array[String] = []
var capture: bool = false
var shots_dir: String = "/tmp/claude-1001/-home-james-Projects-JustLife/1e705e6b-64f2-44c8-9b30-d76de0e8b1ce/scratchpad/shots/cleaning/"

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i: int in count: await process_frame

func shot(name: String, target: Vector3, size: float = 3.4, angle: float = .62, elevation: float = .62, bare: bool = false) -> void:
	if not capture: return
	app.world.camera_target = target
	app.world.camera.size = size
	app.world.camera_angle = angle
	app.world.camera_elevation = elevation
	app.world.update_camera()
	app.ui.visible = false
	await frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	root.get_texture().get_image().save_png(shots_dir + name + ".png")
	app.ui.visible = true

func station_of(chore: String, filter: Callable = Callable()) -> Dictionary:
	for station: Dictionary in flow.list:
		if str(station.chore) == chore and bool(station.ok) and (not filter.is_valid() or filter.call(station)): return station
	return {}

func shown_strips(id: String) -> int:
	var entry: Dictionary = flow.vis()._haze.get(id, {})
	var count: int = 0
	for strip: MeshInstance3D in entry.get("strips", []):
		if is_instance_valid(strip) and strip.visible: count += 1
	return count

func run_until(sim: LifeSim, speed: int, limit: int, done: Callable) -> bool:
	app.household.set_speed(speed)
	for frame: int in limit:
		app._process(DT)
		if done.call(): return true
	return false

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false)
	app.world.add_item({"id": "cur_vis", "kind": "curtains", "x": -5.88, "z": 2.2, "rotation": 90.0})
	app.world.add_item({"id": "toy_vis", "kind": "toybox", "x": -2.0, "z": -0.2, "rotation": 0.0})
	app.world.rebuild_navigation()
	app._refresh_sim_targets()
	flow = app.chore_flow
	var sim: LifeSim = app.sim
	sim.autonomy = false
	for need: String in LifeSim.NEED_NAMES: sim.needs[need] = 95.0
	sim.day = 6; sim.minutes = 600.0; app.household.day = 6; app.household.minutes = 600.0
	flow.chores().reset(); flow.rebuild_stations(true)
	flow.sync_world(DT)
	await frames(2)
	var window: Dictionary = station_of("chore_wash_window", func(s: Dictionary) -> bool: return bool(s.outdoor) and str(s.id).contains("-604_220"))
	var door: Dictionary = station_of("chore_wipe_door", func(s: Dictionary) -> bool: return str(s.label).contains("front"))
	var entry: Dictionary = station_of("chore_sweep_entry", func(s: Dictionary) -> bool: return str(s.label).contains("front"))
	check(not window.is_empty() and not door.is_empty() and not entry.is_empty(), "The stations to show exist")
	# ---------------------------------------------------- a clean home shows no dirt
	check(shown_strips(str(window.id)) == 0, "A clean pane has no haze")
	check(not flow.vis()._smudge[str(door.id)].root.visible, "A clean door has no smudge")
	var litter_clean: int = flow.vis()._litter[str(entry.id)].bits.filter(func(b: MeshInstance3D) -> bool: return b.visible).size()
	check(litter_clean == 0, "A clean doorstep has no leaves")
	await shot("vis_clean_door", Vector3(0, .6, 5.8), 4.2, .5)
	# ------------------------------------------------------------------- dirty
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 20.0 * 1440.0
	flow.vis().sync(flow)
	app.world.set_cutaway(false)
	await frames(2)
	check(shown_strips(str(window.id)) == 3, "A dirty pane is hazy across all its strips (%d)" % shown_strips(str(window.id)))
	check(flow.vis()._smudge[str(door.id)].root.visible, "A dirty door has a smudge by its handle")
	var litter_dirty: int = flow.vis()._litter[str(entry.id)].bits.filter(func(b: MeshInstance3D) -> bool: return b.visible).size()
	check(litter_dirty >= 8, "A dirty doorstep is strewn with leaves (%d)" % litter_dirty)
	await shot("vis_dirty_door", Vector3(0, .6, 5.8), 4.2, .5)
	await shot("vis_dirty_toys", Vector3(-2.0, .3, .4), 2.6, .62, .6)
	await shot("vis_dirty_window", Vector3(-6.0, 1.5, 2.2), 3.2, 1.6, .35)
	app.world.set_cutaway(true)
	await frames(2)
	# ------------------------------------------------------------ reveal in cutaway
	var window_node: Node3D = window.node
	check(not window_node.visible, "The window is hidden with the walls down")
	sim.queue_action("chore_wash_window", str(window.id), window.position)
	check(run_until(sim, 8, 5000, func() -> bool: return str(sim.get_current_action().get("phase", "")) == "active"), "Ada walks round to the window and starts")
	app.household.set_speed(1)
	for frame: int in 40: app._process(DT)
	check(window_node.visible, "A window being washed is shown even with the walls down")
	await shot("vis_reveal_window", Vector3(-6.3, 1.4, 2.2), 3.6, 1.7, .4)
	# The haze clears lane by lane as the squeegee works.
	var seen_clearing: bool = false
	var before: int = shown_strips(str(window.id))
	for frame: int in 700:
		app._process(DT)
		var left: int = shown_strips(str(window.id))
		if left < before: seen_clearing = true
		if sim.action_queue.is_empty(): break
	check(seen_clearing, "The haze clears as the squeegee goes down the pane")
	app.household.set_speed(0)
	for frame: int in 6: app._process(DT)
	check(shown_strips(str(window.id)) == 0, "A washed pane is clear (%d)" % shown_strips(str(window.id)))
	check(not window_node.visible, "The window is put away again when the work is done")
	# --------------------------------------------------------------- the doorstep
	sim.queue_action("chore_sweep_entry", str(entry.id), entry.position)
	run_until(sim, 8, 5000, func() -> bool: return str(sim.get_current_action().get("phase", "")) == "active")
	app.household.set_speed(1)
	var halfway: int = -1
	for frame: int in 600:
		app._process(DT)
		var action: Dictionary = sim.get_current_action()
		if not action.is_empty() and float(action.progress) > .45 and halfway < 0:
			halfway = flow.vis()._litter[str(entry.id)].bits.filter(func(b: MeshInstance3D) -> bool: return b.visible).size()
			await shot("vis_sweeping", Vector3(0, .3, 6.0), 2.8, .5, .62)
		if action.is_empty(): break
	check(halfway >= 0 and halfway < litter_dirty, "The broom takes the leaves a few at a time (%d of %d at halfway)" % [halfway, litter_dirty])
	app.household.set_speed(0)
	for frame: int in 6: app._process(DT)
	var litter_after: int = flow.vis()._litter[str(entry.id)].bits.filter(func(b: MeshInstance3D) -> bool: return b.visible).size()
	check(litter_after == 0, "A swept doorstep is bare (%d)" % litter_after)
	# --------------------------------------------------------------- the door
	sim.queue_action("chore_wipe_door", str(door.id), door.position)
	run_until(sim, 8, 5000, func() -> bool: return str(sim.get_current_action().get("phase", "")) == "active")
	app.household.set_speed(1)
	for frame: int in 30: app._process(DT)
	var door_node: Node3D = door.node
	check(door_node.visible, "A door being wiped is shown with the walls down")
	var smudge_before: float = (flow.vis()._smudge[str(door.id)].root as MeshInstance3D).material_override.albedo_color.a
	for frame: int in 400:
		app._process(DT)
		if sim.action_queue.is_empty(): break
	app.household.set_speed(0)
	for frame: int in 6: app._process(DT)
	check(not flow.vis()._smudge[str(door.id)].root.visible, "The smudge is wiped away")
	check(not door_node.visible, "The door is put away again")
	# ------------------------------------------------------------------- toys
	# Toys are real items on the floor now: a round plans one real tidy for each.
	check(flow.make_plan(sim, "custom", ["toys"]).entries.is_empty(), "A tidy room has no toys to put away")
	app.world.add_item({"id": "vis_chest", "kind": "toy_chest", "x": 4.0, "z": 3.0, "rotation": 0.0}, false)
	for index: int in 2: app.world.add_item({"id": "vis_toy_%d" % index, "kind": "kids_toy", "style": "ball", "x": 3.0 + float(index) * .5, "z": 2.0, "rotation": 0.0}, false)
	app.world.rebuild_navigation(); app._refresh_sim_targets()
	var toy_plan: Dictionary = flow.make_plan(sim, "custom", ["toys"])
	check(toy_plan.entries.size() == 2 and str(toy_plan.entries[0].id) == "put_pet_toy", "Each toy on the floor is a real tidy in the round (%d)" % toy_plan.entries.size())
	# --------------------------------------------- cushions and curtains put back
	var sofa_station: Dictionary = station_of("chore_fluff")
	var sofa: Dictionary = app._find_item(str(sofa_station.item_id))
	var rest: Dictionary = {}
	for cushion: Node in sofa.node.find_children("*ushion*", "Node3D", true, false): rest[cushion] = (cushion as Node3D).transform
	sim.queue_action("chore_fluff", str(sofa_station.id), sofa_station.position)
	run_until(sim, 8, 5000, func() -> bool: return str(sim.get_current_action().get("phase", "")) == "active")
	app.household.set_speed(1)
	var moved: bool = false
	for frame: int in 240:
		app._process(DT)
		for cushion: Variant in rest:
			if not (cushion as Node3D).transform.is_equal_approx(rest[cushion]): moved = true
	check(moved, "Cushions are lifted and plumped while they are fluffed")
	sim.cancel_action()
	for frame: int in 10: app._process(DT)
	var restored: bool = true
	for cushion: Variant in rest:
		if not (cushion as Node3D).transform.is_equal_approx(rest[cushion]): restored = false
	check(restored, "Cancelling puts every cushion back exactly as it was")
	var curtain_station: Dictionary = station_of("chore_vacuum_curtains")
	var curtain: Dictionary = app._find_item(str(curtain_station.item_id))
	var tint: Node3D = curtain.node.find_child("Tint", true, false)
	var tint_rest: Transform3D = tint.transform
	sim.queue_action("chore_vacuum_curtains", str(curtain_station.id), curtain_station.position)
	run_until(sim, 8, 5000, func() -> bool: return str(sim.get_current_action().get("phase", "")) == "active")
	app.household.set_speed(1)
	var swayed: bool = false
	for frame: int in 240:
		app._process(DT)
		if not tint.transform.is_equal_approx(tint_rest): swayed = true
	check(swayed, "The curtain moves as the nozzle pulls at it")
	sim.cancel_action()
	for frame: int in 10: app._process(DT)
	check(tint.transform.is_equal_approx(tint_rest), "...and hangs as it did when the work stops")
	print("CHORE_VISUALS %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
