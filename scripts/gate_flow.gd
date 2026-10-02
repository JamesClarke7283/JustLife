extends RefCounted
## Garden gates are presentation of a passable gap: nobody has to wait for one.
## A leaf swings open, away from whoever is coming, as a Lifelet or a driven car
## nears it, stays open while anyone is in the way, and closes itself a moment
## after the last of them has gone through.
##
## Time is the caller's own simulation step, so a paused game holds a gate
## wherever it was and a fast game swings it as quickly as the car drives.
const GATE_KINDS: Array[String] = ["garden_gate", "garden_gate_double", "garden_gate_drive"]
const SWING_TIME: float = .7
const CLOSE_DELAY: float = .9
const OPEN_ANGLE: float = PI * .5
## How far ahead of the gate, along its own axis, a driven car already counts as
## arriving, so the leaves are open before the bonnet reaches them.
const VEHICLE_AHEAD: float = 10.0
## The strip either side of a gate's posts that a car's body fills.
const VEHICLE_SIDE: float = 1.2
const WALKER_AHEAD: float = 1.1
const WALKER_SIDE: float = .35
## Group a driven vehicle joins while it is moving, so a parked car beside a gate
## never holds it open.
const DRIVING_GROUP: StringName = &"driving_vehicle"

var world: Node3D

func _init(owner_world: Node3D = null) -> void:
	world = owner_world

static func is_gate(kind: String) -> bool:
	return kind in GATE_KINDS

## Hinge nodes a gate model carries, in the order they are built.
static func hinges(node: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child: Node in node.get_children():
		if child is Node3D and str(child.name).begins_with("GateHinge"):out.append(child)
	return out

## How far open one gate is, 0 closed to 1 fully open.
static func openness(node: Node3D) -> float:
	return float(node.get_meta("gate_open", 0.0))

## Swing every gate toward what its surroundings ask for. `walker_ids` names the
## people whose approach counts, normally the household and any guest: a
## neighbour strolling along the street does not swing a garden gate. Left
## `null`, everyone present counts.
func tick(delta: float, walker_ids: Variant = null) -> void:
	if delta <= 0.0 or not is_instance_valid(world):return
	var drivers: Array[Node3D] = []
	if world.is_inside_tree():
		for node: Node in world.get_tree().get_nodes_in_group(DRIVING_GROUP):
			if node is Node3D and (node as Node3D).visible and (node as Node3D).is_inside_tree():drivers.append(node)
	var walkers: Array[Node3D] = []
	for id: Variant in world.actors.keys():
		if walker_ids is Array and not (walker_ids as Array).has(str(id)):continue
		var actor: Node3D = world.actors[id] as Node3D
		if is_instance_valid(actor) and actor.visible:walkers.append(actor)
	for item: Dictionary in world.items:
		var kind: String = str(item.get("kind", ""))
		if kind not in GATE_KINDS:continue
		var node: Node3D = item.get("node") as Node3D
		if not is_instance_valid(node):continue
		step(node, kind, drivers, walkers, delta)

## Advance one gate. Split out so a test can drive a single gate.
func step(node: Node3D, kind: String, drivers: Array[Node3D], walkers: Array[Node3D], delta: float) -> void:
	var span: float = float(LifeCatalog.get_item(kind).size.x)
	var side: float = _arrival_side(node, span, drivers, walkers)
	var open: float = openness(node)
	if side != 0.0:
		node.set_meta("gate_clear", 0.0)
		if open <= .001:node.set_meta("gate_swing", side)
		open = minf(1.0, open + delta / SWING_TIME)
	else:
		var clear: float = float(node.get_meta("gate_clear", 0.0)) + delta
		node.set_meta("gate_clear", clear)
		if clear > CLOSE_DELAY:open = maxf(0.0, open - delta / SWING_TIME)
	if open == openness(node):return
	node.set_meta("gate_open", open)
	pose(node, open)

## Put the leaves at one openness. A swing of +1 opens toward the gate's -z side,
## which is away from a traveller standing on its +z side; a double gate's two
## leaves part symmetrically.
static func pose(node: Node3D, open: float) -> void:
	var swing: float = float(node.get_meta("gate_swing", 1.0))
	var eased: float = smoothstep(0.0, 1.0, open)
	for hinge: Node3D in hinges(node):
		var mirror: float = -1.0 if str(hinge.name).ends_with("_R") else 1.0
		hinge.rotation.y = swing * mirror * OPEN_ANGLE * eased

## 0 when nobody is coming, otherwise the sign of the gate-local z a traveller is
## on: positive when they are on the gate's +z side.
func _arrival_side(node: Node3D, span: float, drivers: Array[Node3D], walkers: Array[Node3D]) -> float:
	var half: float = span * .5
	var nearest: float = INF
	var side: float = 0.0
	for car: Node3D in drivers:
		var local: Vector3 = node.to_local(car.global_position)
		if absf(local.y) > 1.5 or absf(local.x) > half + VEHICLE_SIDE or absf(local.z) > VEHICLE_AHEAD:continue
		if absf(local.z) < nearest:nearest = absf(local.z);side = signf(local.z) if local.z != 0.0 else 1.0
	for actor: Node3D in walkers:
		var local: Vector3 = node.to_local(actor.global_position)
		if absf(local.y) > .6 or absf(local.x) > half + WALKER_SIDE or absf(local.z) > WALKER_AHEAD:continue
		if absf(local.z) < nearest:nearest = absf(local.z);side = signf(local.z) if local.z != 0.0 else 1.0
	return side
