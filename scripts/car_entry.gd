extends RefCounted
## Getting a travelling party into the shared car once everyone has walked to
## the curb: each Lifelet steps to a door, opens it, gets in and pulls it shut.
## A baby or child goes first: a grown-up opens the rear door, settles them in
## their car seat, leans in to fasten the harness and closes the door on them.
##
## The car's own shell has no moving parts, so the doors that swing are the
## authored `car_door.glb` leaf (tools/create_car_door.py), hinged over the
## body's door line on the kerb side, with its dark doorway behind it.

const DOOR_MODEL: String = "res://assets/models/car_door.glb"
const AUTHORED_LENGTH: float = 1.1
## Kerb-side doors of the Juniper car, in the car's own axes (+x kerb, +z front).
const DOORS: Dictionary = {
	"front": {"hinge": Vector3(.885, 0, .70), "length": 1.1, "seat": Vector3(.36, 0, .05)},
	"rear": {"hinge": Vector3(.885, 0, -.26), "length": .78, "seat": Vector3(.36, 0, -.62)},
}
const SWING: float = 1.1
const CHILD_STAGES: Array[String] = ["baby", "child"]
## Seconds for each part of a beat.
const BUCKLE_BEATS: Array = [["approach", .7], ["open", .8], ["seat", .9], ["buckle", 1.6], ["close", .7]]
const BOARD_BEATS: Array = [["approach", .7], ["open", .8], ["in", 1.1], ["close", .6]]
const TIMEOUT: float = 45.0

var car: Node3D
var doors: Dictionary = {}
var steps: Array = []
var index: int = 0
var time: float = 0.0
var total: float = 0.0
var finished: bool = false
var buckled: Array[String] = []
var boarded: Array[String] = []
## Where each Lifelet started its current beat, so walks start from there.
var _from: Dictionary = {}


func _init(owner_car: Node3D = null, party: Array = []) -> void:
	car = owner_car
	steps = plan(party)
	if is_instance_valid(car): _build_doors()


## The order the party gets in. `party` holds {id, stage} in boarding order.
## Children are buckled in by the first grown-up, who then drives; any other
## grown-ups use the rear door.
static func plan(party: Array) -> Array:
	var adults: Array = party.filter(func(member: Dictionary) -> bool: return str(member.stage) not in CHILD_STAGES)
	var children: Array = party.filter(func(member: Dictionary) -> bool: return str(member.stage) in CHILD_STAGES)
	var out: Array = []
	var helper: String = str(adults[0].id) if not adults.is_empty() else ""
	for child: Dictionary in children:
		out.append({"kind": "buckle", "helper": helper, "child": str(child.id)} if not helper.is_empty() else {"kind": "board", "who": str(child.id), "door": "rear"})
	for i: int in range(adults.size()):
		out.append({"kind": "board", "who": str(adults[i].id), "door": "front" if i == 0 else "rear"})
	return out


func _build_doors() -> void:
	if not ResourceLoader.exists(DOOR_MODEL): return
	var paint: Color = _car_paint()
	for door_name: String in DOORS:
		var spec: Dictionary = DOORS[door_name]
		var rig: Node3D = load(DOOR_MODEL).instantiate()
		rig.name = "CarDoor_" + door_name
		car.add_child(rig)
		rig.position = spec.hinge
		rig.scale = Vector3(1, 1, float(spec.length) / AUTHORED_LENGTH)
		var hinge: Node3D = rig.find_child("Hinge", true, false)
		var opening: Node3D = rig.find_child("Opening", true, false)
		for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
			if not LifeCatalogVariants.is_tint(mesh.name): continue
			var skin := StandardMaterial3D.new(); skin.albedo_color = paint; skin.roughness = .35; skin.metallic = .2
			mesh.material_override = skin
		if is_instance_valid(opening): opening.visible = false
		doors[door_name] = {"rig": rig, "hinge": hinge, "opening": opening, "amount": 0.0}


## The body colour of the car shell, so the swinging leaf matches it.
func _car_paint() -> Color:
	var best: MeshInstance3D = null
	for mesh: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).to_lower().contains("lower body") or LifeCatalogVariants.is_tint(mesh.name): best = mesh; break
	if best != null and best.mesh != null and best.mesh.get_surface_count() > 0:
		var material: Material = best.get_active_material(0)
		if material is StandardMaterial3D: return (material as StandardMaterial3D).albedo_color
	return Color("4a6b5c")


func set_door(door_name: String, amount: float) -> void:
	var door: Dictionary = doors.get(door_name, {})
	if door.is_empty(): return
	door.amount = clampf(amount, 0.0, 1.0)
	if is_instance_valid(door.hinge): (door.hinge as Node3D).rotation.y = -SWING * float(door.amount)
	if is_instance_valid(door.opening): (door.opening as Node3D).visible = float(door.amount) > .02


func door_amount(door_name: String) -> float:
	return float(doors.get(door_name, {}).get("amount", 0.0))


func handle_point(door_name: String) -> Vector3:
	var door: Dictionary = doors.get(door_name, {})
	if not door.is_empty() and is_instance_valid(door.hinge):
		return (door.hinge as Node3D).to_global(Vector3(.04, .93, -AUTHORED_LENGTH + .17))
	var spec: Dictionary = DOORS[door_name]
	return car.to_global(Vector3(spec.hinge) + Vector3(.04, .93, -float(spec.length) + .17))


## Where a Lifelet stands to use a door: beside the car, behind the swung leaf.
func stand_point(door_name: String) -> Vector3:
	var spec: Dictionary = DOORS[door_name]
	return car.to_global(Vector3(1.42, 0, float(spec.hinge.z) - float(spec.length) * .72))


func seat_point(door_name: String) -> Vector3:
	return car.to_global(Vector3(DOORS[door_name].seat))


func facing_car() -> float:
	var inward: Vector3 = car.global_basis * Vector3(-1, 0, 0)
	return atan2(inward.x, inward.z)


func facing_forward() -> float:
	var ahead: Vector3 = car.global_basis * Vector3(0, 0, 1)
	return atan2(ahead.x, ahead.z)


## The current beat and how far into it we are: {step, part, progress, part_time}.
func current() -> Dictionary:
	if index >= steps.size(): return {}
	var step: Dictionary = steps[index]
	var beats: Array = BUCKLE_BEATS if str(step.kind) == "buckle" else BOARD_BEATS
	var left: float = time
	for beat: Array in beats:
		if left < float(beat[1]): return {"step": step, "part": str(beat[0]), "progress": left / float(beat[1]), "part_time": left}
		left -= float(beat[1])
	return {"step": step, "part": "done", "progress": 1.0, "part_time": 0.0}


## Advance the choreography and pose every Lifelet in the party. `actors` maps id
## to LifeActor. Returns true once everyone is in and the doors are shut.
func tick(delta: float, actors: Dictionary) -> bool:
	if finished: return true
	time += delta
	total += delta
	if total > TIMEOUT: return _finish(actors)
	var beat: Dictionary = current()
	if beat.is_empty(): return _finish(actors)
	if str(beat.part) == "done":
		_complete(beat.step, actors)
		index += 1; time = 0.0; _from.clear()
		return tick(0.0, actors)
	var busy: Array[String] = []
	var step: Dictionary = beat.step
	if str(step.kind) == "buckle": busy = _buckle(step, beat, actors, delta)
	else: busy = _board(step, beat, actors, delta)
	for id: String in actors:
		if id in busy or id in boarded or id in buckled: continue
		var body: LifeActor = actors[id]
		if is_instance_valid(body) and body.visible:
			body.clear_activity_anchor(); body.animate(delta, 1.0, false, "")
	return false


func caption() -> String:
	var beat: Dictionary = current()
	if beat.is_empty(): return ""
	return "Buckling a little one into the car seat" if str(beat.step.kind) == "buckle" else "Getting into the car"


func _walk(body: LifeActor, id: String, to: Vector3, progress: float, delta: float) -> void:
	if not _from.has(id): _from[id] = body.global_position
	var from: Vector3 = _from[id]
	body.clear_activity_anchor()
	var heading: Vector3 = to - from
	if heading.length() > .02: body.rotation.y = atan2(heading.x, heading.z)
	body.global_position = from.lerp(to, smoothstep(0.0, 1.0, progress))
	body.animate(delta, 1.0, progress < 1.0 and heading.length() > .02, "")


func _pose(body: LifeActor, at: Vector3, yaw: float, action: String, details: Dictionary, delta: float) -> void:
	details["care_time"] = float(details.get("care_time", time))
	body.global_position = at
	body.rotation.y = yaw
	body.set_activity_anchor(at, yaw, "standing", action, details)
	body.animate(delta, 1.0, false, action)


func _buckle(step: Dictionary, beat: Dictionary, actors: Dictionary, delta: float) -> Array[String]:
	var helper: LifeActor = actors.get(str(step.helper))
	var child: LifeActor = actors.get(str(step.child))
	var stand: Vector3 = stand_point("rear")
	var beside: Vector3 = stand + car.global_basis * Vector3(0, 0, -.62)
	var part: String = str(beat.part)
	var p: float = float(beat.progress)
	if part == "approach":
		if is_instance_valid(helper): _walk(helper, str(step.helper), stand, p, delta)
		if is_instance_valid(child): _walk(child, str(step.child), beside, p, delta)
	elif is_instance_valid(helper):
		match part:
			"open":
				set_door("rear", p)
				_pose(helper, stand, facing_car(), "car_open_door", {"care_target": handle_point("rear")}, delta)
			"seat", "buckle":
				set_door("rear", 1.0)
				_pose(helper, stand, facing_car(), "car_open_door" if part == "seat" else "car_buckle",
					{"care_target": seat_point("rear") + Vector3.UP * .62 + car.global_basis * Vector3(.18, 0, 0), "care_time": float(beat.part_time)}, delta)
			"close":
				set_door("rear", 1.0 - p)
				_pose(helper, stand, facing_car(), "car_close_door", {"care_target": handle_point("rear")}, delta)
	if is_instance_valid(child) and part != "approach":
		if part == "open":
			_pose(child, beside, facing_car(), "", {}, delta)
		else:
			var into: float = p if part == "seat" else 1.0
			var at: Vector3 = beside.lerp(seat_point("rear"), smoothstep(0.0, 1.0, into))
			var yaw: float = lerp_angle(facing_car(), facing_forward(), into)
			_pose(child, at, yaw, "car_get_in" if part == "seat" else "car_seated", {"care_progress": into}, delta)
	return [str(step.helper), str(step.child)]


func _board(step: Dictionary, beat: Dictionary, actors: Dictionary, delta: float) -> Array[String]:
	var id: String = str(step.who)
	var body: LifeActor = actors.get(id)
	var door: String = str(step.door)
	if not is_instance_valid(body): return [id]
	var stand: Vector3 = stand_point(door)
	var p: float = float(beat.progress)
	match str(beat.part):
		"approach": _walk(body, id, stand, p, delta)
		"open":
			set_door(door, p)
			_pose(body, stand, facing_car(), "car_open_door", {"care_target": handle_point(door)}, delta)
		"in":
			set_door(door, 1.0)
			var at: Vector3 = stand.lerp(seat_point(door), smoothstep(0.0, 1.0, p))
			_pose(body, at, lerp_angle(facing_car(), facing_forward(), smoothstep(.1, .8, p)), "car_get_in", {"care_progress": p}, delta)
		"close":
			# Stay seated and visible while the door swings shut, then disappear
			# into the cabin. Hiding on the first frame of the close was a pop.
			set_door(door, 1.0 - p)
			_pose(body, seat_point(door), facing_forward(), "car_seated", {"care_progress": 1.0}, delta)
			body.visible = p < 0.82
	return [id]


func _complete(step: Dictionary, actors: Dictionary) -> void:
	if str(step.kind) == "buckle":
		set_door("rear", 0.0)
		buckled.append(str(step.child))
		var child: LifeActor = actors.get(str(step.child))
		if is_instance_valid(child): child.visible = false
	else:
		set_door(str(step.door), 0.0)
		boarded.append(str(step.who))
		var body: LifeActor = actors.get(str(step.who))
		if is_instance_valid(body): body.visible = false


func _finish(actors: Dictionary) -> bool:
	for door_name: String in doors: set_door(door_name, 0.0)
	for id: String in actors:
		var body: LifeActor = actors[id]
		if is_instance_valid(body):
			body.clear_activity_anchor()
			body.visible = false
	finished = true
	return true
