extends SceneTree
## How every household chore looks on the rig. Each chore is posed on the real stations of
## the starter home (plus a pair of curtains and a toy box added to it), for fourteen body
## configurations: both frames, every age that may do it, small and large builds. At six
## points through each task the hands must be on what they hold and the feet planted, the
## right tool must be showing and nothing else, and a pause must freeze the pose exactly.
## Append `-- --capture` and omit `--headless` for rendered close-ups of every chore.
const Defs = preload("res://scripts/chore_defs.gd")
const DT: float = 1.0 / 30.0
const HAND_LIMIT: float = .03
const FOOT_LIMIT: float = .012
const BODIES: Array = [
	{"name": "Alex adult", "frame": 0, "age_stage": "adult"}, {"name": "Jamie adult broad", "frame": 1, "age_stage": "adult"},
	{"name": "Small adult", "frame": 0, "age_stage": "adult", "body_scale": .85, "height_scale": .93}, {"name": "Large broad adult", "frame": 1, "age_stage": "young_adult", "body_scale": 1.15, "height_scale": 1.08},
	{"name": "River teen", "frame": 0, "age_stage": "teen"}, {"name": "Quinn teen broad", "frame": 1, "age_stage": "teen"},
	{"name": "Small teen", "frame": 0, "age_stage": "teen", "body_scale": .85, "height_scale": .93},
	{"name": "Kit child", "frame": 0, "age_stage": "child"}, {"name": "Pip child broad", "frame": 1, "age_stage": "child"}, {"name": "Large child", "frame": 0, "age_stage": "child", "body_scale": 1.15, "height_scale": 1.08},
	{"name": "Morgan elder", "frame": 0, "age_stage": "elder"}, {"name": "Jules elder broad", "frame": 1, "age_stage": "elder"},
	{"name": "Small elder", "frame": 1, "age_stage": "elder", "body_scale": .85, "height_scale": .93}, {"name": "Large elder", "frame": 0, "age_stage": "elder", "body_scale": 1.15, "height_scale": 1.08},
]
const TOOLS: Dictionary = {
	"chore_vacuum": ["hoover", "canister"], "chore_vacuum_curtains": ["nozzle", "canister"], "chore_dust": ["duster"], "chore_wipe_sink": ["sponge"],
	"chore_scrub_toilet": ["brush"], "chore_fluff": [], "chore_sweep_entry": ["broom"],
}
var app: Node
var flow: Node
var checks: int = 0
var failures: Array[String] = []
var capture: bool = false
var report: Array = []
var capture_bodies: Array = ["Alex adult", "Jamie adult broad", "River teen", "Kit child", "Morgan elder"]
var only_chores: Array = []
var shots_dir: String = "/tmp/claude-1001/-home-james-Projects-JustLife/1e705e6b-64f2-44c8-9b30-d76de0e8b1ce/scratchpad/shots/cleaning/"

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	if OS.get_environment("CAPTURE_BODIES") != "": capture_bodies = OS.get_environment("CAPTURE_BODIES").split(",")
	if OS.get_environment("CAPTURE_CHORES") != "": only_chores = OS.get_environment("CAPTURE_CHORES").split(",")
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 4) -> void:
	for i: int in count: await process_frame

func station_of(chore: String, filter: Callable = Callable()) -> Dictionary:
	for station: Dictionary in flow.list:
		if str(station.chore) == chore and bool(station.ok) and (not filter.is_valid() or filter.call(station)): return station
	return {}

func allowed(stage: String, id: String, station: Dictionary) -> bool:
	if not Defs.stage_error(stage, id).is_empty(): return false
	if float(station.need_top) > 0.0 and str(Defs.reach(stage, false, float(station.need_top), float(station.min_top), str(station.aids)).aid) == "refused": return false
	return true

func hand_error(actor: LifeActor, plan: Dictionary, side: String) -> float:
	var hand: Dictionary = plan.hands[side]
	var wanted: Vector3 = hand.world if hand.has("world") else actor._model.to_global(hand.local)
	return actor.palm_world(side).distance_to(wanted)

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames()
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	app.world.add_item({"id": "cur_lab", "kind": "curtains", "x": -5.88, "z": 2.2, "rotation": 90.0})
	app.world.add_item({"id": "toy_lab", "kind": "toybox", "x": -2.0, "z": -0.2, "rotation": 0.0})
	app.world.rebuild_navigation()
	flow = app.chore_flow
	flow.rebuild_stations(true)
	flow.chores().toys["toy_lab"] = 4
	var picks: Dictionary = {
		"chore_vacuum": station_of("chore_vacuum", func(s: Dictionary) -> bool: return str(s.label).contains("lounge")),
		"chore_vacuum_curtains": station_of("chore_vacuum_curtains"),
		"chore_dust": station_of("chore_dust", func(s: Dictionary) -> bool: return str(s.get("dust_mode", "")) == "top" and str(s.item_id) == "item_5"),
		"chore_dust_face": station_of("chore_dust", func(s: Dictionary) -> bool: return str(s.get("dust_mode", "")) == "face"),
		"chore_wipe_sink": station_of("chore_wipe_sink", func(s: Dictionary) -> bool: return str(s.category) == "kitchen"),
		"chore_scrub_toilet": station_of("chore_scrub_toilet"),
		"chore_fluff": station_of("chore_fluff"),
		"chore_sweep_entry": station_of("chore_sweep_entry", func(s: Dictionary) -> bool: return str(s.label).contains("front")),
		"chore_wipe_door": station_of("chore_wipe_door", func(s: Dictionary) -> bool: return str(s.label).contains("front")),
		"chore_wash_window_in": station_of("chore_wash_window", func(s: Dictionary) -> bool: return not bool(s.outdoor)),
		"chore_wash_window_out": station_of("chore_wash_window", func(s: Dictionary) -> bool: return bool(s.outdoor)),
		"chore_mop": station_of("chore_mop", func(s: Dictionary) -> bool: return not bool(s.wet)),
	}
	for key: String in picks: check(not picks[key].is_empty(), "A station exists to pose %s" % key)
	var samples: Array = [.03, .18, .36, .55, .75, .93]
	var worst_by_chore: Dictionary = {}
	var shots: int = 0
	for body: Dictionary in BODIES:
		var stage: String = str(body.age_stage)
		var actor: LifeActor = LifeActor.new()
		app.world.add_child(actor)
		actor.configure(body.duplicate()); actor.voice_enabled = false
		for key: String in picks:
			var station: Dictionary = picks[key]
			if station.is_empty() or (not only_chores.is_empty() and key not in only_chores): continue
			var id: String = str(station.chore)
			if not allowed(stage, id, station): continue
			var worst_hand: float = 0.0
			var worst_foot: float = 0.0
			var tools_ok: bool = true
			for p: float in samples:
				actor.clear_activity_anchor()
				var anchor: Dictionary = flow.anchor_for(stage, false, id, station, p, p * 14.0)
				actor.position = anchor.position
				actor.rotation = Vector3.ZERO
				# Several frames at each point: the pose reads its own clock, so let it settle and run.
				for frame: int in 20:
					anchor = flow.anchor_for(stage, false, id, station, p, p * 14.0 + float(frame) * .02)
					actor.set_activity_anchor(anchor.position, anchor.yaw, "standing", id, anchor)
					actor.animate(DT, 1.0, false, id)
					if frame < 12: continue
					if id == "chore_mop":
						# A mopped patch of floor is mopped like a puddle: both hands on the shaft.
						for side: String in ["L", "R"]:
							var grip: Vector3 = Vector3(0, .96, -.287) if side == "L" else Vector3(0, .68, -.198)
							worst_hand = maxf(worst_hand, actor.palm_world(side).distance_to(actor._mop.to_global(grip)))
							var foot: Dictionary = actor._leg_rest[side]
							var ankle: Vector3 = actor._activity_anchor.position + Basis(Vector3.UP, float(actor._activity_anchor.yaw)) * (Vector3(foot.foot) * actor.visual.scale)
							worst_foot = maxf(worst_foot, ankle.distance_to(foot.shoe.global_position))
						tools_ok = tools_ok and actor._mop.visible
						continue
					var plan: Dictionary = actor._activity_anchor.get("chore_plan", {})
					if plan.is_empty():
						tools_ok = false; continue
					for side: String in plan.hands:
						worst_hand = maxf(worst_hand, hand_error(actor, plan, side))
					for side: String in ["L", "R"]:
						var rest: Dictionary = actor._leg_rest[side]
						var target: Vector3 = actor._activity_anchor.position + Basis(Vector3.UP, float(actor._activity_anchor.yaw)) * (Vector3(rest.foot) * actor.visual.scale)
						worst_foot = maxf(worst_foot, target.distance_to(rest.shoe.global_position))
				if capture and p in [.36, .75] and shots < 400 and str(body.name) in capture_bodies:
					await take_shot(actor, "%s_%s_%d" % [key, str(body.name).replace(" ", "_"), int(p * 100)], anchor)
					shots += 1
			var label: String = "%s %s" % [body.name, key]
			var entry: Dictionary = {"body": body.name, "chore": key, "hand": snappedf(worst_hand, .001), "foot": snappedf(worst_foot, .001)}
			report.append(entry)
			var previous: Dictionary = worst_by_chore.get(key, {"hand": 0.0, "foot": 0.0})
			worst_by_chore[key] = {"hand": maxf(float(previous.hand), worst_hand), "foot": maxf(float(previous.foot), worst_foot)}
			check(worst_hand < HAND_LIMIT, "%s: hands stay on what they hold (worst %.1f mm)" % [label, worst_hand * 1000.0])
			check(worst_foot < FOOT_LIMIT, "%s: feet stay planted (worst %.1f mm)" % [label, worst_foot * 1000.0])
			check(tools_ok, "%s: the pose always has a plan" % label)
		actor.queue_free()
	for key: String in worst_by_chore:
		print("WORST ", key, " hand=", snappedf(float(worst_by_chore[key].hand) * 1000.0, .1), "mm foot=", snappedf(float(worst_by_chore[key].foot) * 1000.0, .1), "mm")
	print("CHORE_MOTION %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)

func take_shot(actor: LifeActor, name: String, anchor: Dictionary) -> void:
	var yaw: float = float(anchor.get("yaw", 0.0))
	var angle: float = float(OS.get_environment("CAPTURE_ANGLE")) if OS.get_environment("CAPTURE_ANGLE") != "" else .85
	app.world.set_cutaway(not (name.begins_with("chore_wash_window") or name.begins_with("chore_wipe_door") or OS.get_environment("CAPTURE_WALLS_UP") != ""))
	app.world.camera_target = actor.position + Vector3(0, .85, 0)
	app.world.camera.size = 3.0
	var behind: bool = not (name.begins_with("chore_vacuum_") and not name.begins_with("chore_vacuum_curtains")) and not name.begins_with("chore_sweep") and not name.begins_with("chore_scrub")
	app.world.camera_angle = yaw + (PI - angle if behind else angle)
	app.world.camera_elevation = .5
	app.world.update_camera()
	app.ui.visible = false
	var bare: bool = (name.begins_with("chore_vacuum_") and not name.begins_with("chore_vacuum_curtains")) or name.begins_with("chore_sweep") or name.begins_with("chore_mop")
	app.world.furniture.visible = not bare
	await frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	root.get_texture().get_image().save_png(shots_dir + name + ".png")
	app.world.furniture.visible = true
