extends RefCounted
class_name LifeVehiclePlanner
## Where a parked car drives to reach the road, and how it comes home again.
##
## The planner is pure: it works on a "scene", plain data made once from the
## world (see scene_from_world), so tests can build a street out of rectangles.
##
## Leaving: the car drives forward off its parking spot, a short straight first,
## then a turn of the tightest radius it can make onto the lane that matches its
## heading (left onto the near lane, right across it onto the far lane), then
## straight along the lane and out of the view. A car that faces away from the
## street, or cannot turn forward without hitting something, reverses instead:
## one reverse curve to the lane, one stop, then forward. Coming home is the same
## geometry the other way round: along the lane, a turn off the road, and onto
## the spot exactly, forward when a forward way in exists (the mirror image of
## reversing out) and otherwise past the entrance, stop and reverse in (the mirror
## image of driving out).
##
## Candidates are generated cheaply, ordered by length, and each is swept with the
## car's body against every wall, furnishing, fence, hedge and the posts of any
## gate. A gate is crossed only through its gap, nearly square to its leaf.

const Path = preload("res://scripts/vehicle_path.gd")
const Road = preload("res://scripts/road.gd")
const BODY_HALF_WIDTH: float = .91
const BODY_HALF_LENGTH: float = 2.10
## The slack kept around the body when sweeping it, on every side.
const INFLATE: float = .10
const TURN_RADIUS: float = 3.7
const SAMPLE: float = .4
const COARSE_STEP: float = 1.6
const TAIL_SAMPLE: float = 1.2
const MAX_TESTS: int = 120
const STUBS: Array[float] = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.5, 8.0]
const X_OFFSETS: Array[float] = [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 13.0, 16.0, 20.0, 25.0]
## A leaf is crossed within this cosine of its normal (about 35 degrees).
const GATE_ALIGN: float = .82
## How far before and after a gate's centre the route is squared up to it.
const GATE_APPROACHES: Array[float] = [2.0, 3.0]
## Hedges and the lot's own edges: how far in from the edge a body must stay.
const SIDE_CLEARANCE: float = 1.0
const BACK_CLEARANCE: float = 1.4
## A hedge is leaf, not wall: a passing body may brush this much of it.
const HEDGE_GIVE: float = .3
const CELL: float = 2.0
## Half the width of a tree's trunk: what a car cannot drive through.
const TRUNK: float = .35
const BIG_AREA: float = 80.0
const FAR_MARGIN: float = .6
## Crossing to the far lane costs this many metres more than staying by the kerb.
const FAR_LANE_COST: float = 6.0
## A forward way in that turns the car more than this (a loop round the yard) is
## passed over for reversing in.
const LOOP_TURN: float = 2.3
## A route that begins turning at once, or ends turning into the spot, costs this many
## metres more than one with a short straight there, so cars start and park straight.
const STRAIGHT_START_COST: float = 2.5

# -------------------------------------------------------------------- scenes

## A scene from plain pieces. `solid` and `street` are Rect2 lists (street ones
## are temporary: a van at the kerb, a bus), `gates` come from gate().
static func make_scene(lot: Rect2, solid: Array = [], gates: Array = [], street: Array = [], soft: Array = []) -> Dictionary:
	var all: Array[Rect2] = []
	for rect: Rect2 in solid: all.append(rect)
	all.append(Rect2(lot.position.x - 150.0, Road.ROAD_FAR_EDGE + FAR_MARGIN, lot.size.x + 300.0, 30.0))
	all.append(Road.MAILBOX)
	# Planting and the lot's hedged edges: a car may start inside them (it was parked
	# there) and drive out, but never drive into them or through them.
	var hedges: Array[Rect2] = []
	for rect: Rect2 in soft: hedges.append(rect)
	var hedge_end: float = lot.end.y - 2.0 + .45
	hedges.append(Rect2(lot.position.x - 40.0, lot.position.y - 40.0, lot.size.x + 80.0, 40.0 + BACK_CLEARANCE))
	hedges.append(Rect2(lot.position.x - 40.0, lot.position.y - 40.0, 40.0 + SIDE_CLEARANCE, hedge_end - (lot.position.y - 40.0)))
	hedges.append(Rect2(lot.end.x - SIDE_CLEARANCE, lot.position.y - 40.0, 40.0 + SIDE_CLEARANCE, hedge_end - (lot.position.y - 40.0)))
	var streets: Array[Rect2] = []
	for rect: Rect2 in street: streets.append(rect)
	return {"lot": lot, "solid": all, "soft": hedges, "street": streets, "gates": gates}


## A gate as the planner sees it: its centre, the way its leaf faces and its span.
static func gate(centre: Vector2, yaw: float, span: float) -> Dictionary:
	var along := Vector2(cos(yaw), -sin(yaw))
	var normal := Vector2(sin(yaw), cos(yaw))
	var half := Vector2(absf(along.x) * span * .5 + absf(normal.x) * .3, absf(along.y) * span * .5 + absf(normal.y) * .3)
	return {"c": centre, "yaw": yaw, "span": span, "along": along, "normal": normal, "zone": Rect2(centre - half, half * 2.0)}


## The scene of a world's lot for the car `ignore_id`. Hidden furnishings are not
## in the way unless named in `present_ids` (a car that is hidden because a copy
## of it sits at its own spot, being boarded).
static func scene_from_world(world: Node3D, ignore_id: String = "", present_ids: Array = []) -> Dictionary:
	var solid: Array = []
	var gates: Array = []
	var street: Array = []
	var soft: Array = []
	for wall: Dictionary in world.construction.records:
		if int(wall.get("level", 0)) == 0: solid.append(world.construction.wall_rect(wall))
	for item: Dictionary in world.items:
		var id: String = str(item.get("id", ""))
		var kind: String = str(item.get("kind", ""))
		if id == ignore_id or not is_instance_valid(item.get("node")) or world.item_level(item) != 0: continue
		if kind in ["meal", "plate", "puddle"] or bool(item.get("derived", false)) or bool(item.get("carried", false)): continue
		var node: Node3D = item.node
		if not node.visible and not present_ids.has(id): continue
		if LifeCatalog.is_gate(kind):
			gates.append(gate(Vector2(node.position.x, node.position.z), node.rotation.y, float(LifeCatalog.get_item(kind).size.x)))
			continue
		if LifeCatalog.passable(kind): continue
		for panel: Rect2 in world.item_panels(item): solid.append(panel)
	# Hedges, trees and bushes stop a car; flower beds are driven over.
	# A tree is its trunk, and anything growing under the car's own parking spot gives
	# way to it (the household parked there), as the ground does under a new furnishing.
	var own: Rect2 = Rect2()
	var found_own: bool = false
	for item: Dictionary in world.items:
		if str(item.get("id", "")) == ignore_id and is_instance_valid(item.get("node")):
			for panel: Rect2 in world.item_panels(item): own = panel if not found_own else own.merge(panel); found_own = true
	for node: Node3D in world._live_vegetation():
		if not node.visible or not node.has_meta("vegetation_footprint"): continue
		var vegetation_id: String = str(node.get_meta("vegetation_id", ""))
		if vegetation_id.begins_with("flowers"): continue
		var footprint: Rect2 = node.get_meta("vegetation_footprint")
		if vegetation_id.begins_with("tree"): footprint = Rect2(node.position.x - TRUNK, node.position.z - TRUNK, TRUNK * 2.0, TRUNK * 2.0)
		elif vegetation_id.begins_with("hedge"): footprint = footprint.grow(-HEDGE_GIVE)
		if found_own and own.grow(.1).intersects(footprint): continue
		soft.append(footprint)
	for record: Dictionary in world.extra_obstacles:
		if int(record.get("level", 0)) != 0: continue
		var half := Vector2(float(record.get("w", 0)), float(record.get("d", 0))) * .5
		street.append(Rect2(Vector2(float(record.get("x", 0)), float(record.get("z", 0))) - half, half * 2.0))
	if is_instance_valid(world.delivery_van): street.append(oriented_box_rect(world.delivery_van.position, world.delivery_van.rotation.y, BODY_HALF_WIDTH, BODY_HALF_LENGTH))
	if LifeSchoolBus.active != null and LifeSchoolBus.active.phase != "gone":
		var bus: Vector3 = LifeSchoolBus.active.position
		street.append(Rect2(Vector2(bus.x - 3.45, bus.z - 1.1), Vector2(6.9, 2.2)))
	return make_scene(LifeBuildingState.lot(), solid, gates, street, soft)


## The axis-aligned rectangle a yawed car-sized box covers.
static func oriented_box_rect(position: Vector3, yaw: float, half_width: float, half_length: float) -> Rect2:
	var ex: float = absf(sin(yaw)) * half_length + absf(cos(yaw)) * half_width
	var ez: float = absf(cos(yaw)) * half_length + absf(sin(yaw)) * half_width
	return Rect2(position.x - ex, position.z - ez, ex * 2.0, ez * 2.0)

# --------------------------------------------------------------------- field

static func _field(scene: Dictionary, with_street: bool) -> Dictionary:
	var key: String = "_field_street" if with_street else "_field_bare"
	if scene.has(key): return scene[key]
	var rects: Array[Rect2] = []
	for rect: Rect2 in scene.solid: rects.append(rect)
	for door: Dictionary in scene.gates:
		for sign: float in [-1.0, 1.0]:
			var post: Vector2 = door.c + door.along * sign * (float(door.span) * .5 - .1)
			rects.append(Rect2(post - Vector2(.1, .1), Vector2(.2, .2)))
	if with_street:
		for rect: Rect2 in scene.street: rects.append(rect)
	var soft_from: int = rects.size()
	for rect: Rect2 in scene.soft: rects.append(rect)
	var data := PackedFloat64Array()
	var cells: Dictionary = {}
	var big: Array[int] = []
	for index: int in rects.size():
		var rect: Rect2 = rects[index]
		data.append(rect.position.x); data.append(rect.position.y); data.append(rect.end.x); data.append(rect.end.y)
		if rect.get_area() > BIG_AREA:
			big.append(index)
			continue
		for cz: int in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
			for cx: int in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
				var cell: int = (cx + 512) * 2048 + (cz + 512)
				if not cells.has(cell): cells[cell] = []
				(cells[cell] as Array).append(index)
	var field: Dictionary = {"data": data, "cells": cells, "big": big, "count": rects.size(), "soft_from": soft_from, "stamp": [], "token": 0, "gates": scene.gates}
	(field.stamp as Array).resize(rects.size())
	(field.stamp as Array).fill(0)
	scene[key] = field
	return field


## Whether the body (half width hw, half length hl, at x, z facing yaw) overlaps
## any obstacle. The body is inflated by INFLATE; the rectangles named in `relax`
## are met by the bare body instead (they already touch the parked car).
static func body_blocked(field: Dictionary, x: float, z: float, yaw: float, hw: float, hl: float, relax: Dictionary = {}) -> bool:
	var sy: float = sin(yaw)
	var cy: float = cos(yaw)
	var ex: float = absf(sy) * hl + absf(cy) * hw
	var ez: float = absf(cy) * hl + absf(sy) * hw
	var data: PackedFloat64Array = field.data
	var stamp: Array = field.stamp
	field.token = int(field.token) + 1
	var token: int = field.token
	var candidates: Array = []
	for index: int in field.big: candidates.append(index)
	var cells: Dictionary = field.cells
	for cz: int in range(floori((z - ez) / CELL), floori((z + ez) / CELL) + 1):
		for cx: int in range(floori((x - ex) / CELL), floori((x + ex) / CELL) + 1):
			var cell: int = (cx + 512) * 2048 + (cz + 512)
			if not cells.has(cell): continue
			for index: int in (cells[cell] as Array):
				if stamp[index] == token: continue
				stamp[index] = token
				candidates.append(index)
	for index: int in candidates:
		var base: int = index * 4
		var x0: float = data[base]; var z0: float = data[base + 1]; var x1: float = data[base + 2]; var z1: float = data[base + 3]
		if x1 < x - ex or x0 > x + ex or z1 < z - ez or z0 > z + ez: continue
		# Planting is met by the bare body (it gives way a little); a wall by the inflated one.
		var shrink: float = INFLATE if index >= int(field.soft_from) else 0.0
		if not relax.is_empty() and relax.has(index):
			if int(relax[index]) == 2: continue
			shrink = INFLATE
		var rhx: float = (x1 - x0) * .5
		var rhz: float = (z1 - z0) * .5
		var dx: float = (x0 + x1) * .5 - x
		var dz: float = (z0 + z1) * .5 - z
		if absf(dx * sy + dz * cy) > hl - shrink + rhx * absf(sy) + rhz * absf(cy): continue
		if absf(dx * cy - dz * sy) > hw - shrink + rhx * absf(cy) + rhz * absf(sy): continue
		return true
	# A gate's leaf may be crossed, but only nearly square to it.
	for door: Dictionary in field.gates:
		var zone: Rect2 = door.zone
		if zone.end.x < x - ex or zone.position.x > x + ex or zone.end.y < z - ez or zone.position.y > z + ez: continue
		var normal: Vector2 = door.normal
		if absf(sy * normal.x + cy * normal.y) < GATE_ALIGN: return true
	return false


## What already touches the parked body: rectangles that only touch its margin are
## judged against the bare body (1), and planting or hedge it already stands in is
## ignored while it drives out (2). A wall or furnishing under the bare body stays
## an obstacle, so such a start is refused.
static func _touching(field: Dictionary, x: float, z: float, yaw: float, hw: float, hl: float) -> Dictionary:
	var out: Dictionary = {}
	var data: PackedFloat64Array = field.data
	var sy: float = sin(yaw)
	var cy: float = cos(yaw)
	var ex: float = absf(sy) * hl + absf(cy) * hw
	var ez: float = absf(cy) * hl + absf(sy) * hw
	for index: int in field.count:
		var base: int = index * 4
		var x0: float = data[base]; var z0: float = data[base + 1]; var x1: float = data[base + 2]; var z1: float = data[base + 3]
		var rhx: float = (x1 - x0) * .5
		var rhz: float = (z1 - z0) * .5
		var dx: float = (x0 + x1) * .5 - x
		var dz: float = (z0 + z1) * .5 - z
		if absf(dx) > ex + rhx or absf(dz) > ez + rhz: continue
		var along: float = absf(dx * sy + dz * cy)
		var across: float = absf(dx * cy - dz * sy)
		if along > hl + rhx * absf(sy) + rhz * absf(cy) or across > hw + rhx * absf(cy) + rhz * absf(sy): continue
		var bare: bool = along <= hl - INFLATE + rhx * absf(sy) + rhz * absf(cy) and across <= hw - INFLATE + rhx * absf(cy) + rhz * absf(sy)
		if bare and index >= int(field.soft_from): out[index] = 2
		elif not bare: out[index] = 1
		else: out[index] = 1
	return out


## Whether the whole path, swept by the body, is clear. The rectangles in `relax`
## are judged against the bare body for the first `relax_metres` of the way.
static func path_clear(field: Dictionary, path: Dictionary, car_scale: float, step: float = SAMPLE, relax: Dictionary = {}, relax_metres: float = 6.0) -> bool:
	var hw: float = BODY_HALF_WIDTH * car_scale + INFLATE
	var hl: float = BODY_HALF_LENGTH * car_scale + INFLATE
	# A coarse sweep first throws out most blocked routes cheaply.
	if step < COARSE_STEP and Path.length_of(path) > COARSE_STEP * 2.0:
		var rough: PackedVector3Array = Path.sample(path, COARSE_STEP).poses
		for index: int in rough.size():
			var pose: Vector3 = rough[index]
			if body_blocked(field, pose.x, pose.y, pose.z, hw, hl, relax if float(index) * COARSE_STEP <= relax_metres else {}): return false
	var poses: PackedVector3Array = Path.sample(path, step).poses
	var forgiven: int = ceili(relax_metres / step) if not relax.is_empty() else 0
	for index: int in poses.size():
		var pose: Vector3 = poses[index]
		if body_blocked(field, pose.x, pose.y, pose.z, hw, hl, relax if index <= forgiven else {}): return false
	return true

# ----------------------------------------------------------------- candidates

static func _lane_z(sign: float, car_scale: float) -> float:
	var half: float = BODY_HALF_WIDTH * car_scale + INFLATE
	return clampf(Road.lane_z(sign), Road.ROAD_NEAR_EDGE + half, Road.ROAD_FAR_EDGE - half)


static func _radius(car_scale: float) -> float:
	return TURN_RADIUS * car_scale


## The straight run along a lane from a lane pose to the edge of the view (leaving),
## and the run in from the edge of the view to the lane pose (arriving).
static func tail_to(x: float, sign: float) -> float:
	return maxf(8.0, Road.EXIT_X - sign * x)


static func lead_in_from(x: float, sign: float) -> float:
	return maxf(8.0, Road.EXIT_X + sign * x)


## The lane run beyond a core's end: ahead of it when leaving, behind it when arriving.
static func _lane_run(end: Vector3, sign: float, arriving: bool) -> Dictionary:
	if arriving:
		var lead: float = lead_in_from(end.x, sign)
		var run: Dictionary = Path.create(end.x - sign * lead, end.y, end.z)
		Path.add(run, 0.0, lead, 1)
		return run
	var out: Dictionary = Path.create(end.x, end.y, end.z)
	Path.add(out, 0.0, tail_to(end.x, sign), 1)
	return out


## Every candidate core, cheapest first. A core runs from the parked pose to a
## pose on a lane with the car's nose along the lane, all in `gear`. `via` gates
## chain the route through each gate's gap. Returned entries are {path, cost, sign, x}.
static func _cores(home: Vector3, car_scale: float, gear: int, gates: Array) -> Array:
	var rho: float = _radius(car_scale)
	var out: Array = []
	var forward := Vector2(sin(home.z), cos(home.z)) * float(gear)
	for stub: float in STUBS:
		var from := Vector3(home.x + forward.x * stub, home.y + forward.y * stub, home.z)
		for sign: float in [1.0, -1.0]:
			var lane: float = _lane_z(sign, car_scale)
			var yaw: float = Road.lane_yaw(sign)
			for offset: float in X_OFFSETS:
				var x: float = snappedf(from.x + offset * sign * float(gear), .5)
				var found: Dictionary = Path.dubins(from.x, from.y, from.z, x, lane, yaw, rho, gear)
				if found.is_empty(): continue
				var cost: float = stub + float(found.length) + (FAR_LANE_COST if sign < 0.0 else 0.0) + (STRAIGHT_START_COST if stub < .5 else 0.0)
				out.append({"cost": cost, "stub": stub, "sign": sign, "x": x, "lane": lane, "dubins": found, "via": -1})
	for index: int in gates.size():
		_gate_cores(out, home, car_scale, gear, gates[index], index)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.cost) < float(b.cost))
	return out


static func _gate_cores(out: Array, home: Vector3, car_scale: float, gear: int, door: Dictionary, index: int) -> void:
	var rho: float = _radius(car_scale)
	var centre: Vector2 = door.c
	if Vector2(centre.x - home.x, centre.y - home.y).length() > 30.0: return
	var forward := Vector2(sin(home.z), cos(home.z)) * float(gear)
	for side: float in [1.0, -1.0]:
		# The way the car travels through the leaf; a reversing car faces the other way.
		var travel: Vector2 = door.normal * side
		var heading: Vector2 = travel * float(gear)
		var yaw: float = atan2(heading.x, heading.y)
		for reach: float in GATE_APPROACHES:
			var approach := Vector3(centre.x - travel.x * reach, centre.y - travel.y * reach, yaw)
			var leave := Vector3(centre.x + travel.x * reach, centre.y + travel.y * reach, yaw)
			for stub: float in [0.0, 2.0, 4.0]:
				var from := Vector3(home.x + forward.x * stub, home.y + forward.y * stub, home.z)
				var first: Dictionary = Path.dubins(from.x, from.y, from.z, approach.x, approach.y, approach.z, rho, gear)
				if first.is_empty(): continue
				for sign: float in [1.0, -1.0]:
					var lane: float = _lane_z(sign, car_scale)
					for offset: float in [-2.0, 2.0, 5.0, 9.0, 14.0]:
						var x: float = snappedf(leave.x + offset * sign * float(gear), .5)
						var second: Dictionary = Path.dubins(leave.x, leave.y, leave.z, x, lane, Road.lane_yaw(sign), rho, gear)
						if second.is_empty(): continue
						var cost: float = stub + float(first.length) + reach * 2.0 + float(second.length) + (FAR_LANE_COST if sign < 0.0 else 0.0) + 2.0
						out.append({"cost": cost, "stub": stub, "sign": sign, "x": x, "lane": lane, "dubins": second, "first": first, "reach": reach, "via": index})


## The path of one candidate core (without any tail).
static func _core_path(home: Vector3, gear: int, candidate: Dictionary) -> Dictionary:
	var path: Dictionary = Path.create(home.x, home.y, home.z)
	Path.add(path, 0.0, float(candidate.stub), gear)
	if int(candidate.via) >= 0:
		Path.add_all(path, candidate.first.segs)
		Path.add(path, 0.0, float(candidate.reach) * 2.0, gear)
	Path.add_all(path, candidate.dubins.segs)
	return path


## Plan the cheapest clear core; returns {path, sign, tests, via} or {}. The lane
## run beyond the core (ahead of it, or behind it when `arriving`) must be clear too.
static func _best_core(scene: Dictionary, with_street: bool, home: Vector3, car_scale: float, gear: int, arriving: bool) -> Dictionary:
	var field: Dictionary = _field(scene, with_street)
	var hw: float = BODY_HALF_WIDTH * car_scale + INFLATE
	var hl: float = BODY_HALF_LENGTH * car_scale + INFLATE
	var skip: Dictionary = _touching(field, home.x, home.y, home.z, hw, hl)
	# The parked pose must itself be clear (the touching rectangles aside).
	if body_blocked(field, home.x, home.y, home.z, hw, hl, skip): return {}
	var candidates: Array = _cores(home, car_scale, gear, scene.gates)
	var runs: Dictionary = {}
	var tests: int = 0
	for candidate: Dictionary in candidates:
		if tests >= MAX_TESTS: break
		tests += 1
		var path: Dictionary = _core_path(home, gear, candidate)
		if not path_clear(field, path, car_scale, SAMPLE, skip): continue
		var end: Vector3 = Path.end_pose(path)
		var run_key: String = "%s_%s" % [str(candidate.sign), str(snappedf(end.x, .5))]
		if not runs.has(run_key): runs[run_key] = path_clear(field, _lane_run(end, float(candidate.sign), arriving), car_scale, TAIL_SAMPLE)
		if not bool(runs[run_key]): continue
		return {"path": path, "sign": float(candidate.sign), "tests": tests, "via": int(candidate.via)}
	return {}


static func _finish(core: Dictionary, home: Vector3, kind: String, extra: Dictionary = {}) -> Dictionary:
	var path: Dictionary = core.path
	return {"ok": true, "path": path, "kind": kind, "cusps": Path.cusps(path), "length": Path.length_of(path), "seconds": Path.duration(path),
		"sign": float(core.sign), "tests": int(core.tests), "gate": int(core.via) >= 0}.merged(extra, true)

# ------------------------------------------------------------------ the plans

## With a van or a bus in the road the plan is tried with it, and then without it
## (it will have moved); with nothing temporary there is one pass.
static func _street_passes(scene: Dictionary) -> Array:
	return [true, false] if not (scene.street as Array).is_empty() else [false]


## Drive off the spot, forward when a forward way out exists, otherwise in
## reverse (one cusp), and away along the matching lane to the edge of the view.
## {"ok": false, "error"} when nothing clear exists on this street.
static func plan_departure(scene: Dictionary, home: Vector3, car_scale: float = 1.0) -> Dictionary:
	for with_street: bool in _street_passes(scene):
		for gear: int in [1, -1]:
			var core: Dictionary = _best_core(scene, with_street, home, car_scale, gear, false)
			if core.is_empty(): continue
			var path: Dictionary = core.path
			var end: Vector3 = Path.end_pose(path)
			Path.add(path, 0.0, tail_to(end.x, float(core.sign)), 1)
			path["v1"] = Path.V_MAX
			return _finish(core, home, "forward" if gear > 0 else "reverse")
	return {"ok": false, "error": "No clear way from the parking spot to the road."}


## Come home along the road to the spot: forward in when a forward way in exists,
## otherwise past the entrance and reverse in. The path ends exactly on `home`.
static func plan_arrival(scene: Dictionary, home: Vector3, car_scale: float = 1.0) -> Dictionary:
	# A spot whose nose points at the street cannot be driven into forward but by a
	# loop round the yard: reversing in is the natural way, so that is tried first.
	var nose_out: bool = cos(home.z) > .7
	for with_street: bool in _street_passes(scene):
		var forward_in: Dictionary = {}
		var chosen: Dictionary = {}
		var gear: int = -1
		if not nose_out:
			# A forward way in is a reverse way out played backwards, and vice versa.
			forward_in = _best_core(scene, with_street, home, car_scale, -1, true)
			if not forward_in.is_empty() and Path.turning(forward_in.path) <= LOOP_TURN: chosen = forward_in
		if chosen.is_empty():
			chosen = _best_core(scene, with_street, home, car_scale, 1, true)
			gear = 1
		if chosen.is_empty():
			if nose_out: forward_in = _best_core(scene, with_street, home, car_scale, -1, true)
			chosen = forward_in
			gear = -1
		if chosen.is_empty(): continue
		var sign: float = float(chosen.sign)
		var run: Dictionary = _lane_run(Path.end_pose(chosen.path), sign, true)
		Path.add_all(run, Path.reversed(chosen.path).segs)
		run["v0"] = Path.V_MAX
		chosen["path"] = run
		return _finish(chosen, home, "forward_in" if gear < 0 else "reverse_in")
	return {"ok": false, "error": "No clear way from the road to the parking spot."}


## The way home that mirrors a saved departure: along the lane to where the route
## met it, stop, and the route driven backwards to the spot. Used only when no
## fresh plan exists; {} when the route has no lane to come in on.
static func arrival_from_departure(departure: Dictionary) -> Dictionary:
	var segs: Array = departure.segs.duplicate(true)
	if segs.size() > 1:
		var last: Array = segs[segs.size() - 1]
		if int(last[2]) > 0 and absf(float(last[0])) < 1e-9: segs.pop_back()
	var core: Dictionary = Path.create(float(departure.start[0]), float(departure.start[1]), float(departure.start[2]))
	Path.add_all(core, segs)
	var end: Vector3 = Path.end_pose(core)
	var sign: float = Road.lane_sign_for_yaw(end.z)
	if is_zero_approx(sign): return {}
	var run: Dictionary = _lane_run(end, sign, true)
	Path.add_all(run, Path.reversed(core).segs)
	run["v0"] = Path.V_MAX
	return run


# ------------------------------------------------------------- shared roads

## Poses (x, z, yaw) of a path every dt seconds from `from_time` (negative while the
## car waits), up to the end of the path.
static func poses_of(path: Dictionary, from_time: float, dt: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var steps: int = ceili(maxf(Path.duration(path) - from_time, 0.0) / dt) + 1
	for index: int in range(steps + 1):
		var state: Dictionary = Path.state_at(path, maxf(0.0, from_time + float(index) * dt))
		out.append(Vector3(float(state.x), float(state.z), float(state.yaw)))
	return out


## How many sampled moments the two journeys put the cars' bodies on top of one
## another: A from `poses_a` (parked at its end if `stays_a`, gone otherwise), B
## from `poses_b` after waiting `hold_steps` samples. Margin widens both bodies.
static func overlap_count(poses_a: PackedVector3Array, stays_a: bool, scale_a: float, poses_b: PackedVector3Array, stays_b: bool, scale_b: float, hold_steps: int, margin: float = 0.0, first_only: bool = false) -> int:
	var hw_a: float = BODY_HALF_WIDTH * scale_a + margin
	var hl_a: float = BODY_HALF_LENGTH * scale_a + margin
	var hw_b: float = BODY_HALF_WIDTH * scale_b + margin
	var hl_b: float = BODY_HALF_LENGTH * scale_b + margin
	var reach: float = hl_a + hl_b
	var na: int = poses_a.size()
	var nb: int = poses_b.size()
	var count: int = 0
	for k: int in range(maxi(na, nb + hold_steps) + 1):
		var ia: int = k if k < na else (na - 1 if stays_a else -1)
		var jb: int = k - hold_steps
		var ib: int = 0 if jb < 0 else (jb if jb < nb else (nb - 1 if stays_b else -1))
		if ia < 0 or ib < 0: break
		var a: Vector3 = poses_a[ia]
		var b: Vector3 = poses_b[ib]
		var dx: float = b.x - a.x
		var dz: float = b.y - a.y
		if dx * dx + dz * dz > reach * reach: continue
		if boxes_overlap(a.x, a.y, a.z, hw_a, hl_a, b.x, b.y, b.z, hw_b, hl_b):
			count += 1
			if first_only: return count
	return count


## Seconds car B must wait, parked, so that it never touches a car already on the
## move (each {path, time, scale, stays}); in steps of a quarter second, 12 at most.
static func hold_seconds(path_b: Dictionary, scale_b: float, others: Array, stays_b: bool = false, max_hold: float = 12.0) -> float:
	var dt: float = .125
	var poses_b: PackedVector3Array = poses_of(path_b, 0.0, dt)
	var prepared: Array = []
	for other: Dictionary in others: prepared.append(poses_of(other.path, float(other.time), dt))
	var hold: float = 0.0
	while hold <= max_hold:
		var clear: bool = true
		for index: int in others.size():
			if overlap_count(prepared[index], bool(others[index].get("stays", false)), float(others[index].scale), poses_b, stays_b, scale_b, roundi(hold / dt), .15, true) > 0:
				clear = false
				break
		if clear: return hold
		hold += .25
	return max_hold


## Two yawed boxes (half width, half length) overlap: separating axis test.
static func boxes_overlap(ax: float, az: float, ayaw: float, ahw: float, ahl: float, bx: float, bz: float, byaw: float, bhw: float, bhl: float) -> bool:
	var asy: float = sin(ayaw); var acy: float = cos(ayaw)
	var bsy: float = sin(byaw); var bcy: float = cos(byaw)
	var dx: float = bx - ax
	var dz: float = bz - az
	# axes of A: forward (sin, cos) and side (cos, -sin); same for B
	for axis: Vector2 in [Vector2(asy, acy), Vector2(acy, -asy), Vector2(bsy, bcy), Vector2(bcy, -bsy)]:
		var distance: float = absf(dx * axis.x + dz * axis.y)
		var radius_a: float = ahl * absf(asy * axis.x + acy * axis.y) + ahw * absf(acy * axis.x - asy * axis.y)
		var radius_b: float = bhl * absf(bsy * axis.x + bcy * axis.y) + bhw * absf(bcy * axis.x - bsy * axis.y)
		if distance > radius_a + radius_b: return false
	return true
