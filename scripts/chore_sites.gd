extends RefCounted
## Where the chores are done. Every cleanable thing in the home becomes a station: a
## dirt zone with the spot to stand, which way to face, where the work lands (a patch of
## floor, a pane of glass, a cushion) and how high that is. Stations are a pure function
## of the world, rebuilt when furniture, walls or doors change; `LifeChoreFlow` publishes
## them as simulation targets so a queued chore survives the controller's target refresh.

const Defs = preload("res://scripts/chore_defs.gd")
const Building = preload("res://scripts/building_state.gd")

const SPACING: float = 2.5
const WET_SPACING: float = 2.0
const GLASS_STAND: float = .50
const DOOR_STAND: float = .62
const SINK_STAND: float = .24
## How much surface one stand can work, metres: wider things get a station for each part.
const REACH_SPAN: float = 1.0
const DUST_MODE: Dictionary = Defs.DUST_MODE
const CUSHION_KINDS: Array[String] = Defs.CUSHION_KINDS


## Every station the home has right now. Empty away from home.
static func build(app: Node) -> Array:
	var out: Array = []
	if str(app.current_venue) != "home" or not is_instance_valid(app.world) or not is_instance_valid(app.world.house): return out
	var context: Dictionary = _context(app)
	out.append_array(_floors(app, context))
	out.append_array(_windows(app, context))
	out.append_array(_doors(app, context))
	out.append_array(_items(app, context))
	return out


static func _context(app: Node) -> Dictionary:
	var checked: Dictionary = app.world.construction.validated_state()
	var state: Dictionary = checked.state if bool(checked.ok) else {}
	var wet: Array = []
	for item: Dictionary in app.world.items:
		if str(item.kind) not in ["toilet", "shower", "bathtub"] or state.is_empty() or not is_instance_valid(item.get("node")): continue
		var level: int = app.world.item_level(item)
		# The fixture's own spot is always inside its room; the standing spot in front of a
		# small en-suite can fall outside the door.
		var at: Vector3 = item.node.global_position
		var room: Dictionary = LifeBuildingEdits._enclosed_cells(state, level, Vector2(at.x, at.z))
		if room.is_empty() or bool(room.get("escaped", true)) or room.cells.is_empty(): continue
		var duplicate: bool = false
		for known: Dictionary in wet:
			if int(known.level) == level and known.cells.size() == room.cells.size() and known.cells.has(room.cells.keys()[0]): duplicate = true
		if not duplicate: wet.append({"level": level, "cells": room.cells})
	var rugs: Array = []
	for item: Dictionary in app.world.items:
		if str(item.kind) in ["rug", "child_rug"] and is_instance_valid(item.get("node")): rugs.append(item)
	return {"state": state, "wet": wet, "rugs": rugs}


static func _cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / Building.CELL), floori(point.z / Building.CELL))


static func _in_wet(context: Dictionary, level: int, point: Vector3) -> bool:
	for room: Dictionary in context.wet:
		if int(room.level) == level and room.cells.has(_cell(point)): return true
	return false


static func _on_rug(context: Dictionary, point: Vector3) -> bool:
	for rug: Dictionary in context.rugs:
		var local: Vector3 = rug.node.to_local(point)
		if absf(local.x) <= float(rug.size.x) * .5 and absf(local.z) <= float(rug.size.y) * .5: return true
	return false


static func _carpeted(context: Dictionary, level: int, point: Vector3) -> bool:
	if context.state.is_empty(): return false
	for tile: Dictionary in Building.surface_tiles(context.state, level):
		if tile.rect.has_point(Vector2(point.x, point.z)): return str(tile.carpet) != ""
	return false


static func _slug(text: String) -> String:
	var out: String = ""
	for index: int in text.length():
		var code: int = text.unicode_at(index)
		if code >= 65 and code <= 90: code += 32
		var ok: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code in [46, 45, 95]
		out += char(code) if ok else "_"
	return out


static func _flat(vector: Vector3) -> Vector3:
	var flat: Vector3 = Vector3(vector.x, 0.0, vector.z)
	return flat.normalized() if flat.length() > .0001 else Vector3.BACK


static func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var flat: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	return atan2(flat.x, flat.z) if flat.length() > .01 else 0.0


static func _parts(width: float) -> int:
	return maxi(1, roundi(width / REACH_SPAN))


## A catalog label as a plain noun. Whimsical names that lead with an article ("A little
## ambition" for the desk) fall back to the kind itself, so labels read "the desk".
static func _noun(kind: String) -> String:
	var name: String = str(LifeCatalog.get_item(kind).get("label", kind)).to_lower()
	if name.begins_with("a ") or name.begins_with("an ") or name.begins_with("the "): name = kind.replace("_", " ")
	return name

## "left" or "right" as the cleaner facing `facing` would say it, for a part `offset` along `along`.
static func _side_word(facing: Vector3, along: Vector3, offset: float) -> String:
	var right: Vector3 = Vector3(facing.z, 0.0, -facing.x)
	return "right" if offset * along.dot(right) > 0.0 else "left"


## A snapped clear spot near `wanted`, or INF when none lies within `drift` metres.
static func _snap(app: Node, level: int, wanted: Vector3, drift: float) -> Vector3:
	var at: Vector3 = app.world.nearest_clear_point(wanted, level, 4)
	if not at.is_finite() or Vector2(at.x - wanted.x, at.z - wanted.z).length() > drift: return Vector3.INF
	return at


static func _station(chore: String, key: String, dirt: String, category: String) -> Dictionary:
	return {"id": Defs.STATION_PREFIX + key, "key": key, "dirt": dirt, "chore": chore, "category": category, "kind": "chore_station", "item_id": "", "level": 0,
		"position": Vector3.INF, "anchor": Vector3.INF, "yaw": 0.0, "aim": Vector3.ZERO, "u": Vector3.RIGHT, "n": Vector3.BACK, "half": Vector2(.5, .5), "y_lo": 0.0, "y_hi": 1.0,
		"outdoor": false, "need_top": 0.0, "min_top": 0.0, "aids": "", "units": 0.0, "label": "", "room": "", "ok": false, "refusal": "", "wet": false}


## The direction with the most clear floor ahead of `stand`, preferring `toward`.
static func _open_direction(app: Node, level: int, stand: Vector3, toward: Vector3) -> Vector3:
	var best: Vector3 = toward
	var best_score: int = -1
	var base: float = atan2(toward.x, toward.z)
	for index: int in 8:
		var angle: float = base + float(index) * TAU / 8.0
		var direction: Vector3 = Vector3(sin(angle), 0.0, cos(angle))
		var score: int = 0
		for step: float in [.4, .65, .9]:
			if app.world.lot_navigation.point_clear(level, stand + direction * step): score += 1
		if score > best_score:
			best_score = score; best = direction
			if score == 3: break
	return best


# ------------------------------------------------------------------- floors

static func _floors(app: Node, context: Dictionary) -> Array:
	var out: Array = []
	var state: Dictionary = context.state
	if state.is_empty(): return out
	var room_names: Dictionary = {}
	for level: int in Building.MAX_LEVEL + 1:
		var bounds: Rect2 = Rect2()
		var found: bool = false
		for floor: Dictionary in state.floors:
			if int(floor.level) != level: continue
			var area: Rect2 = Building.rect(floor)
			bounds = area if not found else bounds.merge(area)
			found = true
		if not found: continue
		var y: float = Building.level_y(level)
		# Dry floors: a lattice of patches, each vacuumed and (if hard) mopped.
		var first_x: int = floori(bounds.position.x / SPACING)
		var first_z: int = floori(bounds.position.y / SPACING)
		for i: int in range(first_x, ceili(bounds.end.x / SPACING) + 1):
			for j: int in range(first_z, ceili(bounds.end.y / SPACING) + 1):
				var centre: Vector3 = Vector3((float(i) + .5) * SPACING, y, (float(j) + .5) * SPACING)
				if not app.world.construction.floor_contains(Vector2(centre.x, centre.z), level): continue
				var stand: Vector3 = _snap(app, level, centre, SPACING * .5 + .25)
				var tail: String = "%d:%d:%d" % [level, i, j]
				if stand.is_finite() and not app.world.construction.floor_contains(Vector2(stand.x, stand.z), level): stand = Vector3.INF
				if stand.is_finite() and _in_wet(context, level, stand): continue
				if not stand.is_finite() and _in_wet(context, level, centre): continue
				var forward: Vector3 = _open_direction(app, level, stand if stand.is_finite() else centre, _flat(centre - stand) if stand.is_finite() and stand.distance_to(centre) > .2 else Vector3.BACK)
				var rug: bool = stand.is_finite() and _on_rug(context, stand + forward * .6)
				var hard: bool = stand.is_finite() and not rug and not _carpeted(context, level, stand)
				out.append(_floor_station("chore_vacuum", "fvac:" + tail, "fvac", stand, level, forward, centre, false, app))
				if hard: out.append(_floor_station("chore_mop", "fmop:" + tail, "fmop", stand, level, forward, centre, false, app))
		# Wet rooms: a finer lattice, mopped only.
		for room: Dictionary in context.wet:
			if int(room.level) != level: continue
			var low: Vector2 = Vector2(1e9, 1e9)
			var high: Vector2 = Vector2(-1e9, -1e9)
			for cell: Vector2i in room.cells:
				low = Vector2(minf(low.x, float(cell.x) * Building.CELL), minf(low.y, float(cell.y) * Building.CELL))
				high = Vector2(maxf(high.x, float(cell.x + 1) * Building.CELL), maxf(high.y, float(cell.y + 1) * Building.CELL))
			var patched: bool = false
			for i: int in range(floori(low.x / WET_SPACING), ceili(high.x / WET_SPACING) + 1):
				for j: int in range(floori(low.y / WET_SPACING), ceili(high.y / WET_SPACING) + 1):
					var centre: Vector3 = Vector3((float(i) + .5) * WET_SPACING, y, (float(j) + .5) * WET_SPACING)
					if not room.cells.has(_cell(centre)): continue
					var stand: Vector3 = _snap(app, level, centre, WET_SPACING * .5 + .2)
					if stand.is_finite() and not room.cells.has(_cell(stand)): stand = Vector3.INF
					var forward: Vector3 = _open_direction(app, level, stand if stand.is_finite() else centre, Vector3.BACK)
					out.append(_floor_station("chore_mop", "wmop:%d:%d:%d" % [level, i, j], "wmop", stand, level, forward, centre, true, app))
					patched = true
			# A small en-suite can fall between the lattice's points: it still gets its floor.
			if not patched:
				var sum: Vector2 = Vector2.ZERO
				var low_cell: Vector2i = Vector2i(1000000, 1000000)
				for cell: Vector2i in room.cells:
					sum += Vector2((float(cell.x) + .5) * Building.CELL, (float(cell.y) + .5) * Building.CELL)
					low_cell = Vector2i(mini(low_cell.x, cell.x), mini(low_cell.y, cell.y))
				var middle: Vector3 = Vector3(sum.x / float(room.cells.size()), y, sum.y / float(room.cells.size()))
				var seat: Vector3 = _snap(app, level, middle, 1.0)
				if seat.is_finite() and not room.cells.has(_cell(seat)): seat = Vector3.INF
				var facing: Vector3 = _open_direction(app, level, seat if seat.is_finite() else middle, Vector3.BACK)
				out.append(_floor_station("chore_mop", "wmop:%d:r%d_%d" % [level, low_cell.x, low_cell.y], "wmop", seat, level, facing, middle, true, app))
	for station: Dictionary in out:
		var name: String = _room_name(app, station.position if station.ok else station.aim, int(station.level), bool(station.wet))
		station["room"] = name
		var noun: String = "bathroom floor" if bool(station.wet) else ("%s floor" % name if not name.is_empty() else "floor")
		station["label"] = "the " + noun
	return out


## The room a point is in, by the nearest ceiling light; a dry patch never counts as the bathroom.
static func _room_name(app: Node, point: Vector3, level: int, wet: bool) -> String:
	var best: String = ""
	var nearest: float = INF
	for entry: Dictionary in app.world.indoor_lights:
		var light: Node3D = entry.light
		if not is_instance_valid(light) or absf(light.global_position.y - (Building.level_y(level) + 2.55)) > .6: continue
		if str(entry.room) == "bathroom" and not wet: continue
		var distance: float = Vector2(light.global_position.x - point.x, light.global_position.z - point.z).length()
		if distance < nearest:
			nearest = distance; best = str(entry.room)
	return best


static func _floor_station(chore: String, key: String, dirt: String, stand: Vector3, level: int, forward: Vector3, centre: Vector3, wet: bool, _app: Node) -> Dictionary:
	var station: Dictionary = _station(chore, key, dirt, "bathroom" if wet else "floors")
	station["level"] = level
	station["wet"] = wet
	station["aim"] = centre
	if stand.is_finite():
		station["ok"] = true
		station["position"] = stand
		station["anchor"] = stand
		station["yaw"] = atan2(forward.x, forward.z)
		station["aim"] = stand + forward * .62
		station["u"] = Vector3(forward.z, 0.0, -forward.x)
		station["n"] = -forward
		station["half"] = Vector2(.9, .55)
		station["y_lo"] = 0.0; station["y_hi"] = .05
	return station


# ------------------------------------------------------------------ windows

static func _glass_of(node: Node3D) -> MeshInstance3D:
	var panes: Array = node.find_children("Glass*", "MeshInstance3D", true, false)
	return panes[0] as MeshInstance3D if not panes.is_empty() else null


## One station per usable face of one window: inside and (on the ground floor) outside.
static func _window_faces(app: Node, node: Node3D, id: String, item_id: String, level: int) -> Array:
	var out: Array = []
	var glass: MeshInstance3D = _glass_of(node)
	if glass == null or not is_instance_valid(glass): return out
	var floor_y: float = Building.level_y(level)
	var pane: Vector3 = glass.global_position
	var size: Vector2 = Vector2(1.756, 1.384)
	if glass.mesh is QuadMesh: size = (glass.mesh as QuadMesh).size
	var normal: Vector3 = _flat(node.global_basis.z)
	var inside_sign: float = 0.0
	for sign_value: float in [1.0, -1.0]:
		var probe: Vector3 = pane + normal * sign_value * .9
		if app.world.construction.floor_contains(Vector2(probe.x, probe.z), level): inside_sign = sign_value; break
	if inside_sign == 0.0: return out
	var along: Vector3 = Vector3(normal.z, 0.0, -normal.x)
	var parts: int = _parts(size.x)
	for face: String in ["in", "out"]:
		if face == "out" and level != 0: continue
		var toward: Vector3 = normal * (inside_sign if face == "in" else -inside_sign)
		for part: int in parts:
			var offset: float = (float(part) - float(parts - 1) * .5) * size.x / float(parts)
			var key: String = "win_%s:%s%s" % [face, id, ":%d" % part if parts > 1 else ""]
			var station: Dictionary = _station("chore_wash_window", key, "win_" + face, "windows")
			station["level"] = level
			station["item_id"] = item_id
			station["outdoor"] = face == "out"
			station["aim"] = pane + along * offset
			station["u"] = along
			station["n"] = toward
			station["half"] = Vector2(size.x * .5 / float(parts), size.y * .5)
			station["y_lo"] = pane.y - floor_y - size.y * .5 + .03
			station["y_hi"] = minf(pane.y - floor_y + size.y * .5 - .25, 2.05)
			station["need_top"] = float(station.y_hi)
			station["min_top"] = 1.5
			station["aids"] = "pole"
			station["face"] = face
			station["node"] = node
			station["pane_height"] = size.y
			var ideal: Vector3 = Vector3(pane.x, floor_y, pane.z) + along * offset + toward * GLASS_STAND
			var stand: Vector3 = _snap(app, level, ideal, .26)
			var side_note: String = "" if parts == 1 else (" (%s)" % _side_word(-toward, along, offset))
			station["label"] = "the %s of the window%s" % ["inside" if face == "in" else "outside", side_note]
			if stand.is_finite():
				station["ok"] = true
				station["position"] = stand
				var plane_distance: float = (stand - Vector3(pane.x, floor_y, pane.z)).dot(toward)
				station["anchor"] = stand - toward * clampf(plane_distance - .40, 0.0, .20)
				station["yaw"] = atan2(-toward.x, -toward.z)
			else:
				station["refusal"] = "Move the furniture to reach this window." if face == "in" else "There is no clear ground outside this window."
			out.append(station)
	return out


static func _windows(app: Node, _context: Dictionary) -> Array:
	var out: Array = []
	# A window whose wall was taken down is not there to be cleaned.
	var held: Dictionary = app.world.construction.windows_with_walls() if not app.world.construction.building_state.is_empty() else {}
	# The starter home's windows are bare nodes of the house; bought ones are furnishings.
	for child: Node in app.world.house.get_children():
		if not child is Node3D or not child.has_meta("window_aperture"): continue
		if not held.is_empty() and not bool(held.get(child, true)): continue
		var node: Node3D = child
		var glass: MeshInstance3D = _glass_of(node)
		if glass == null: continue
		var level: int = clampi(floori((node.global_position.y - Building.GROUND_Y) / Building.RISE), 0, 1)
		var id: String = "win_%d_%d_%d" % [level, roundi(glass.global_position.x * 100.0), roundi(glass.global_position.z * 100.0)]
		out.append_array(_window_faces(app, node, _slug(id), "", level))
	for item: Dictionary in app.world.items:
		if str(item.kind) != "house_window" or not is_instance_valid(item.get("node")): continue
		if not held.is_empty() and not bool(held.get(item.node, true)): continue
		out.append_array(_window_faces(app, item.node, _slug(str(item.id)), str(item.id), app.world.item_level(item)))
	return out


# -------------------------------------------------------------------- doors

static func _doors(app: Node, _context: Dictionary) -> Array:
	var out: Array = []
	var flow: Variant = app.world.construction.doors
	if flow == null: return out
	for gap: String in flow.doors:
		var door: Dictionary = flow.doors[gap]
		var root: Node3D = door.root
		if not is_instance_valid(root): continue
		var level: int = int(door.level)
		var floor_y: float = Building.level_y(level)
		var origin: Vector3 = Vector3(root.global_position.x, floor_y, root.global_position.z)
		var forward: Vector3 = _flat(root.global_basis.z)
		var outside: float = 0.0
		for sign_value: float in [1.0, -1.0]:
			var probe: Vector3 = origin + forward * sign_value * .8
			var other: Vector3 = origin - forward * sign_value * .8
			if not app.world.construction.floor_contains(Vector2(probe.x, probe.z), level) and app.world.construction.floor_contains(Vector2(other.x, other.z), level): outside = sign_value; break
		if outside == 0.0 or level != 0: continue
		var toward: Vector3 = forward * outside
		var width: float = float(door.width)
		var slug: String = _slug(gap)
		var along: Vector3 = Vector3(toward.z, 0.0, -toward.x)
		var parts: int = _parts(width)
		for part: int in parts:
			var offset: float = (float(part) - float(parts - 1) * .5) * width / float(parts)
			var wipe: Dictionary = _station("chore_wipe_door", "door:%s%s" % [slug, ":%d" % part if parts > 1 else ""], "door", "entry")
			wipe["level"] = level; wipe["outdoor"] = true
			wipe["aim"] = origin + along * offset + Vector3(0, 1.05, 0)
			wipe["u"] = along; wipe["n"] = toward
			wipe["half"] = Vector2(width * .5 / float(parts), .9)
			wipe["y_lo"] = .35; wipe["y_hi"] = 1.75
			wipe["need_top"] = 1.75; wipe["min_top"] = 1.0; wipe["aids"] = ""
			wipe["units"] = width
			wipe["node"] = root; wipe["door_key"] = gap; wipe["floor_y"] = floor_y
			var handle_x: float = 0.0
			var nearest_handle: float = INF
			for marker: Variant in door.get("handles", []):
				if not marker is Node3D or not is_instance_valid(marker): continue
				var across: float = (Vector3(marker.global_position) - Vector3(wipe.aim)).dot(along)
				if absf(across) < nearest_handle: nearest_handle = absf(across); handle_x = across
			wipe["handle_x"] = handle_x
			var door_name: String = "the front door" if origin.z > 0.0 else "the back door"
			wipe["label"] = door_name + ("" if parts == 1 else " (%s)" % _side_word(-toward, along, offset))
			var stand: Vector3 = _snap(app, level, origin + along * offset + toward * DOOR_STAND, .3)
			if stand.is_finite():
				wipe["ok"] = true; wipe["position"] = stand
				wipe["anchor"] = stand - toward * clampf((stand - origin).dot(toward) - .50, 0.0, .15)
				wipe["yaw"] = atan2(-toward.x, -toward.z)
			else:
				wipe["refusal"] = "Something blocks the doorstep."
			out.append(wipe)
		var sweep: Dictionary = _station("chore_sweep_entry", "entry:" + slug, "entry", "entry")
		sweep["level"] = level; sweep["outdoor"] = true; sweep["floor_y"] = floor_y
		sweep["half"] = Vector2(minf(width * .5 + .2, 1.2), .6)
		sweep["u"] = along; sweep["n"] = -toward
		sweep["y_lo"] = 0.0; sweep["y_hi"] = .1
		sweep["label"] = "the %s entry" % ("front" if origin.z > 0.0 else "back")
		var step: Vector3 = _snap(app, level, origin + toward * .85, .3)
		if not step.is_finite(): step = _snap(app, level, origin + toward * DOOR_STAND, .3)
		if step.is_finite():
			sweep["ok"] = true; sweep["position"] = step; sweep["anchor"] = step
			sweep["yaw"] = atan2(toward.x, toward.z)
			sweep["aim"] = step + toward * .75
		else:
			sweep["refusal"] = "Something blocks the doorstep."
		out.append(sweep)
	return out


# -------------------------------------------------------------------- items

## Item-local front (the +z face) and the extent in front of its centre.
static func _front(app: Node, item: Dictionary) -> float:
	var variant: Dictionary = item.get("variant", {}) if item.get("variant", {}) is Dictionary else {}
	return maxf(float(item.size.y) * .5, app.world.front_extent(str(item.kind), str(variant.get("size", "")), str(variant.get("style", ""))))


static func _item_station(app: Node, _context: Dictionary, item: Dictionary, chore: String, key: String, dirt: String, category: String, gap: float, offset: float = 0.0) -> Dictionary:
	var node: Node3D = item.node
	var level: int = app.world.item_level(item)
	var station: Dictionary = _station(chore, key, dirt, category)
	station["level"] = level
	station["item_id"] = str(item.id)
	var front: float = _front(app, item)
	var normal: Vector3 = _flat(node.global_basis.z)
	var along: Vector3 = _flat(node.global_basis.x)
	var floor_y: float = Building.level_y(level)
	var centre: Vector3 = Vector3(node.global_position.x, floor_y, node.global_position.z) + along * offset
	station["n"] = normal
	station["u"] = along
	station["aim"] = centre
	station["half"] = Vector2(float(item.size.x) * .5, float(item.size.y) * .5)
	var ideal: Vector3 = centre + normal * (front + gap)
	var stand: Vector3 = _snap(app, level, ideal, .40)
	if absf(offset) < .01:
		# The piece's own standing place, when it is where somebody would stand to work: one that
		# lies beyond another piece is not a place to clean it from.
		var own: Vector3 = app.world._simulation_approach(item)
		if own.is_finite() and Vector2(own.x - ideal.x, own.z - ideal.z).length() <= .7: stand = own
	if stand.is_finite():
		station["ok"] = true
		station["position"] = stand
		var distance: float = (stand - (centre + normal * front)).dot(normal)
		station["anchor"] = stand - normal * clampf(distance - gap, 0.0, .5)
		station["yaw"] = atan2(-normal.x, -normal.z)
	else:
		station["refusal"] = "Nothing clear to stand on beside this. Move the furniture to reach it."
	return station


static func _items(app: Node, context: Dictionary) -> Array:
	var out: Array = []
	for item: Dictionary in app.world.items:
		if bool(item.get("transient_food", false)) or bool(item.get("transient_puddle", false)) or bool(item.get("derived", false)) or not is_instance_valid(item.get("node")): continue
		var kind: String = str(item.kind)
		var id: String = _slug(str(item.id))
		var level: int = app.world.item_level(item)
		var floor_y: float = Building.level_y(level)
		var node: Node3D = item.node
		if DUST_MODE.has(kind):
			var mode: String = str(DUST_MODE[kind])
			var volume: AABB = app.world.furnishing_volume(item)
			var top: float = volume.end.y - floor_y
			var width: float = float(item.size.x)
			var parts: int = _parts(width)
			for part: int in parts:
				var offset: float = (float(part) - float(parts - 1) * .5) * width / float(parts)
				var station: Dictionary = _item_station(app, context, item, "chore_dust", "dust:%s%s" % [id, ":%d" % part if parts > 1 else ""], "dust", "dust", .30 if mode == "top" else .34, offset)
				station["aim"] = Vector3(station.aim.x, volume.end.y if mode == "top" else floor_y + 1.0, station.aim.z)
				station["half"] = Vector2(width * .5 / float(parts), float(item.size.y) * .5)
				station["y_hi"] = top if mode == "top" else minf(top, 1.6)
				station["y_lo"] = top if mode == "top" else .85
				station["need_top"] = minf(top + .1, 1.6) if mode == "top" else minf(top, 1.6)
				station["min_top"] = station.need_top if mode == "top" else .6
				station["aids"] = ""
				station["units"] = width / float(parts)
				station["label"] = "the " + _noun(kind) + ("" if parts == 1 else " (%s)" % _side_word(-station.n, station.u, offset))
				station["dust_mode"] = mode
				out.append(station)
		if kind in CUSHION_KINDS:
			var offsets: Array = LifeCatalog.get_item(kind).get("seat_offsets", [0.0])
			var buckets: Array = []
			for column: int in offsets.size(): buckets.append([])
			for cushion: Node in node.find_children("*ushion*", "Node3D", true, false):
				var local_x: float = node.to_local((cushion as Node3D).global_position).x
				var nearest: int = 0
				for column: int in offsets.size():
					if absf(local_x - float(offsets[column])) < absf(local_x - float(offsets[nearest])): nearest = column
				buckets[nearest].append(cushion)
			for column: int in offsets.size():
				if buckets[column].is_empty(): continue
				var station: Dictionary = _item_station(app, context, item, "chore_fluff", "cush:%s%s" % [id, ":%d" % column if offsets.size() > 1 else ""], "cush", "cushions", .16, float(offsets[column]))
				station["aim"] = Vector3(station.aim.x, floor_y + .55, station.aim.z)
				station["y_lo"] = .3; station["y_hi"] = .95
				station["units"] = float(buckets[column].size())
				station["column"] = float(offsets[column])
				station["half"] = Vector2(.42, float(item.size.y) * .5)
				var noun: String = _noun(kind)
				station["label"] = "the %s cushions%s" % [noun, "" if offsets.size() == 1 else " (%s)" % _side_word(-station.n, station.u, float(offsets[column]))]
				out.append(station)
		if kind == "curtains":
			var tint: Node = node.find_child("Tint", true, false)
			var centre: Vector3 = node.global_position + Vector3(0, 1.2, 0)
			var width: float = 2.4
			var low: float = .55
			var high: float = 2.0
			if tint is MeshInstance3D and (tint as MeshInstance3D).mesh != null:
				var bounds: AABB = (tint as MeshInstance3D).global_transform * (tint as MeshInstance3D).mesh.get_aabb()
				centre = bounds.get_center()
				width = bounds.size.x if absf(_flat(node.global_basis.x).x) > .5 else bounds.size.z
				low = bounds.position.y - floor_y + .05
				high = minf(bounds.end.y - floor_y - .25, 2.0)
			var parts: int = maxi(1, roundi(width / 1.1))
			for part: int in parts:
				var offset: float = (float(part) - float(parts - 1) * .5) * width / float(parts)
				var station: Dictionary = _item_station(app, context, item, "chore_vacuum_curtains", "curt:%s%s" % [id, ":%d" % part if parts > 1 else ""], "curt", "curtains", .34, offset)
				station["aim"] = Vector3(centre.x, centre.y, centre.z) + station.u * offset
				station["half"] = Vector2(width * .5 / float(parts), (high - low) * .5)
				station["y_lo"] = low; station["y_hi"] = high
				station["need_top"] = high; station["min_top"] = 1.4; station["aids"] = "stool"
				station["label"] = "the curtains" + ("" if parts == 1 else " (%s)" % _side_word(-station.n, station.u, offset))
				out.append(station)
		if kind == "sink":
			var bathroom: bool = _in_wet(context, level, app.world._simulation_approach(item) if app.world._simulation_approach(item).is_finite() else node.global_position)
			var station: Dictionary = _item_station(app, context, item, "chore_wipe_sink", "sink:" + id, "sink", "bathroom" if bathroom else "kitchen", SINK_STAND)
			station["aim"] = node.to_global(Vector3(0, .98, .04))
			station["y_lo"] = .9; station["y_hi"] = 1.05
			station["need_top"] = 1.1; station["min_top"] = .9
			station["wet"] = bathroom
			station["label"] = "the bathroom sink" if bathroom else "the kitchen sink"
			out.append(station)
		if kind == "toilet":
			var station: Dictionary = _item_station(app, context, item, "chore_scrub_toilet", "toilet:" + id, "toilet", "bathroom", .30)
			station["aim"] = node.to_global(Vector3(0, .55, .13))
			station["y_lo"] = .4; station["y_hi"] = .7
			station["need_top"] = .8; station["min_top"] = .6
			station["label"] = "the toilet"
			out.append(station)
	return out
