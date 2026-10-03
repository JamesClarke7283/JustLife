extends RefCounted
## What dirt and cleaning look like in the world, drawn from the same numbers the chores
## use: a grey haze on window glass (cleared in the squeegee's lanes), a smudge by the door
## handle, leaves and grit on the doorstep (swept off by the broom), and a sparkle when a
## pane is clean.
## While a window or door is being cleaned it is shown even when the walls are lowered,
## and soft furnishings the chores handled are put back exactly as they were.

const Defs = preload("res://scripts/chore_defs.gd")
const Motion = preload("res://scripts/chore_motion.gd")
const UP: Vector3 = Vector3.UP
const HAZE_MAX: float = .56
const STRIPS: int = 3
const LEAF_COLORS: Array[String] = ["8a6b3a", "a98a4c", "6f7f45", "7d6a52", "b39a6a"]

## The controller; taken from the flow on every call so a loaded game's adopted service
## always draws into the live world.
var app: Node
var _haze: Dictionary = {}
var _smudge: Dictionary = {}
var _litter: Dictionary = {}
var _revealed: Dictionary = {}
var _touched: Array = []
var _sparkles: Array = []
var _materials: Dictionary = {}


func clear() -> void:
	for table: Dictionary in [_haze, _smudge, _litter]:
		for entry: Variant in table.values():
			var root: Variant = entry.get("root") if entry is Dictionary else entry
			if root is Node and is_instance_valid(root): root.queue_free()
		table.clear()
	for sparkle: Dictionary in _sparkles:
		if is_instance_valid(sparkle.node): sparkle.node.queue_free()
	_sparkles.clear()
	_revealed.clear()


func _material(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var key: String = "%s_%.2f" % [color.to_html(), alpha]
	if _materials.has(key): return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = .9
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material


# ---------------------------------------------------------------- building

## Bring every overlay in line with the stations and their dirt. Cheap enough for each game hour.
func sync(flow: Node) -> void:
	app = flow.app
	var present: Dictionary = {}
	for station: Dictionary in flow.list:
		if not bool(station.ok): continue
		var id: String = str(station.id)
		var dirt: float = flow.dirt_of(station)
		match str(station.chore):
			"chore_wash_window":
				present[id] = true
				_window(station, dirt)
			"chore_wipe_door":
				present[id] = true
				_door(station, dirt)
			"chore_sweep_entry":
				present[id] = true
				_entry(station, dirt)
	for table: Dictionary in [_haze, _smudge, _litter]:
		for id: Variant in table.keys():
			if not present.has(id):
				var root: Variant = table[id].get("root")
				if root is Node and is_instance_valid(root): root.queue_free()
				table.erase(id)


func _window(station: Dictionary, dirt: float) -> void:
	var id: String = str(station.id)
	var node: Variant = station.get("node")
	if not node is Node3D or not is_instance_valid(node): return
	var entry: Dictionary = _haze.get(id, {})
	if entry.is_empty() or not is_instance_valid(entry.get("root")) or entry.root.get_parent() != node:
		if not entry.is_empty() and is_instance_valid(entry.get("root")): entry.root.queue_free()
		var root: Node3D = Node3D.new()
		root.name = "GrimeHaze"
		node.add_child(root)
		# Drawn on the floor its window belongs to, not on every floor's view at once.
		app.world.assign_structure_layer(root, int(station.get("level", 0)))
		var strips: Array = []
		var pane: Vector3 = station.aim
		var width: float = float(station.half.x) * 2.0
		var height: float = float(station.get("pane_height", 1.38))
		var along: Vector3 = station.u
		var toward: Vector3 = station.n
		for index: int in STRIPS:
			var quad: MeshInstance3D = MeshInstance3D.new()
			var mesh: QuadMesh = QuadMesh.new()
			mesh.size = Vector2(width / float(STRIPS) + .004, height)
			quad.mesh = mesh
			quad.material_override = _material(Color(.54, .50, .42), .3)
			quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(quad)
			var centre: Vector3 = Vector3(pane.x, float(station.get("pane_y", pane.y)), pane.z) + along * ((float(index) - 1.0) * width / float(STRIPS)) + toward * .012
			quad.global_transform = Transform3D(Basis(along, UP, along.cross(UP)), centre)
			strips.append(quad)
		entry = {"root": root, "strips": strips}
		_haze[id] = entry
	entry["dirt"] = dirt
	_paint_strips(entry, dirt, -1.0, 0.0)


## Alpha of each strip from the dirt, with strips before `lane` already wiped and the strip
## at `lane` wiped as far as `amount`.
func _paint_strips(entry: Dictionary, dirt: float, lane: float, amount: float) -> void:
	var base: float = clampf((dirt - 15.0) / 85.0, 0.0, 1.0) * HAZE_MAX
	var strips: Array = entry.strips
	for index: int in strips.size():
		var strip: MeshInstance3D = strips[index]
		if not is_instance_valid(strip): continue
		var left: float = 1.0
		if lane >= 0.0:
			if float(index) < floorf(lane): left = 0.0
			elif float(index) == floorf(lane): left = 1.0 - amount
		strip.visible = base * left > .01
		if strip.visible: strip.material_override = _material(Color(.54, .50, .42), snappedf(base * left, .02))


func _door(station: Dictionary, dirt: float) -> void:
	var id: String = str(station.id)
	var node: Variant = station.get("node")
	if not node is Node3D or not is_instance_valid(node): return
	var entry: Dictionary = _smudge.get(id, {})
	if entry.is_empty() or not is_instance_valid(entry.get("root")) or entry.root.get_parent() != node:
		if not entry.is_empty() and is_instance_valid(entry.get("root")): entry.root.queue_free()
		var quad: MeshInstance3D = MeshInstance3D.new()
		var mesh: QuadMesh = QuadMesh.new()
		mesh.size = Vector2(.44, .34)
		quad.mesh = mesh
		quad.material_override = _material(Color(.32, .27, .22), .3)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(quad)
		app.world.assign_structure_layer(quad, int(station.get("level", 0)))
		var along: Vector3 = station.u
		var toward: Vector3 = station.n
		var origin: Vector3 = Vector3(station.aim.x, float(station.get("floor_y", .16)) + 1.0, station.aim.z) + along * float(station.get("handle_x", 0.0)) + toward * .058
		quad.global_transform = Transform3D(Basis(along, UP, along.cross(UP)), origin)
		entry = {"root": quad}
		_smudge[id] = entry
	entry["dirt"] = dirt
	_paint_smudge(entry, dirt, 0.0)


func _paint_smudge(entry: Dictionary, dirt: float, wiped: float) -> void:
	var quad: MeshInstance3D = entry.root
	var alpha: float = clampf((dirt - 15.0) / 85.0, 0.0, 1.0) * .36 * (1.0 - wiped)
	quad.visible = alpha > .01
	if quad.visible: quad.material_override = _material(Color(.32, .27, .22), snappedf(alpha, .02))


func _entry(station: Dictionary, dirt: float) -> void:
	var id: String = str(station.id)
	var entry: Dictionary = _litter.get(id, {})
	if entry.is_empty() or not is_instance_valid(entry.get("root")):
		var root: Node3D = Node3D.new()
		root.name = "EntryLitter"
		app.world.house.add_child(root)
		var bits: Array = []
		var out: Vector3 = -Vector3(station.n)
		var along: Vector3 = station.u
		var base: Vector3 = station.position
		for index: int in 10:
			var bit: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			var seed_a: float = sin(float(index) * 12.9898 + str(id).hash() % 97) * 43758.5453
			var seed_b: float = sin(float(index) * 78.233 + str(id).hash() % 89) * 24634.6345
			var lat: float = (seed_a - floorf(seed_a) - .5) * 2.0 * minf(float(station.half.x), 1.0)
			var depth: float = -.45 + (seed_b - floorf(seed_b)) * .85
			mesh.size = Vector3(.06 + .05 * float(index % 3), .008, .045 + .03 * float(index % 2))
			bit.mesh = mesh
			bit.material_override = _material(Color(LEAF_COLORS[index % LEAF_COLORS.size()]))
			bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(bit)
			bit.global_position = Vector3(base.x, float(station.get("floor_y", .16)) - .036, base.z) + out * depth + along * lat
			bit.rotation.y = float(index) * 1.7
			bit.set_meta("rest", bit.global_position)
			bit.set_meta("out", out)
			bits.append(bit)
		entry = {"root": root, "bits": bits}
		_litter[id] = entry
	entry["dirt"] = dirt
	_show_litter(entry, dirt, 0.0)


## Show as many leaves as the dirt says, minus those the broom has already taken.
func _show_litter(entry: Dictionary, dirt: float, swept: float) -> void:
	var bits: Array = entry.bits
	var count: int = clampi(int(round(dirt / 11.0)), 0, bits.size())
	for index: int in bits.size():
		var bit: MeshInstance3D = bits[index]
		if not is_instance_valid(bit): continue
		var threshold: float = (float(index) + .5) / float(maxi(1, count))
		var gone: bool = index >= count or swept > threshold * .92
		bit.visible = not gone
		var push: float = clampf((swept - threshold * .92 + .12) / .12, 0.0, 1.0) if swept > 0.0 else 0.0
		bit.global_position = Vector3(bit.get_meta("rest")) + Vector3(bit.get_meta("out")) * (.55 * push)


# ---------------------------------------------------------------- each frame

## Called once a frame: show what the chores under way are doing to the world, and put
## away whatever no chore is touching any more.
func frame(flow: Node, delta: float) -> void:
	app = flow.app
	var wanted: Dictionary = {}
	var active: Dictionary = {}
	for member: Dictionary in app.household.members:
		var action: Dictionary = member.sim.get_current_action()
		if action.is_empty() or str(action.get("phase", "")) not in ["approach", "active"]: continue
		var station: Dictionary = flow.stations.get(str(action.get("target_id", "")), {})
		if station.is_empty() or str(station.chore) != str(action.id): continue
		var live: bool = str(action.phase) == "active"
		var progress: float = float(action.get("progress", 0.0))
		active[str(station.id)] = true
		var node: Variant = station.get("node")
		match str(station.chore):
			"chore_wash_window":
				if node is Node3D and is_instance_valid(node): wanted[node.get_instance_id()] = node
				var entry: Dictionary = _haze.get(str(station.id), {})
				if live and not entry.is_empty():
					var q: float = clampf((progress - .14) / .72, 0.0, 1.0) * float(STRIPS)
					_paint_strips(entry, float(entry.get("dirt", 100.0)), minf(q, float(STRIPS) - .001), q - floorf(q))
			"chore_wipe_door":
				if node is Node3D and is_instance_valid(node):
					wanted[node.get_instance_id()] = node
					var hinge: Variant = _door_hinge(station)
					if hinge is Node3D: wanted[hinge.get_instance_id()] = hinge
				var entry: Dictionary = _smudge.get(str(station.id), {})
				if live and not entry.is_empty(): _paint_smudge(entry, float(entry.get("dirt", 100.0)), clampf((progress - .1) / .6, 0.0, 1.0))
			"chore_sweep_entry":
				var entry: Dictionary = _litter.get(str(station.id), {})
				if live and not entry.is_empty(): _show_litter(entry, float(entry.get("dirt", 100.0)), clampf((progress - .05) / .8, 0.0, 1.0))
			"chore_fluff", "chore_vacuum_curtains":
				if live:
					for toucher: Variant in flow.anchor(str(member.id), action).get("chore_nodes", []):
						if toucher is Node3D and not _touched.has(toucher): _touched.append(toucher)
	_reveal(wanted)
	_restore(active, flow)
	_tick_sparkles(delta)
	# Whatever a finished round left behind catches up on the next hour; a task that ended
	# this frame has already cleaned its zone, so the overlays follow at once.
	for id: Variant in _haze.keys():
		if not active.has(id) and _haze[id].has("dirt"):
			var station: Dictionary = flow.stations.get(str(id), {})
			if not station.is_empty():
				var dirt: float = flow.dirt_of(station)
				if absf(dirt - float(_haze[id].dirt)) > .5:
					_haze[id]["dirt"] = dirt
					_paint_strips(_haze[id], dirt, -1.0, 0.0)
	for id: Variant in _smudge.keys():
		if not active.has(id):
			var station: Dictionary = flow.stations.get(str(id), {})
			if not station.is_empty() and absf(flow.dirt_of(station) - float(_smudge[id].get("dirt", 0.0))) > .5:
				_smudge[id]["dirt"] = flow.dirt_of(station)
				_paint_smudge(_smudge[id], flow.dirt_of(station), 0.0)
	for id: Variant in _litter.keys():
		if not active.has(id):
			var station: Dictionary = flow.stations.get(str(id), {})
			if not station.is_empty() and absf(flow.dirt_of(station) - float(_litter[id].get("dirt", 0.0))) > .5:
				_litter[id]["dirt"] = flow.dirt_of(station)
				_show_litter(_litter[id], flow.dirt_of(station), 0.0)


func _door_hinge(station: Dictionary) -> Variant:
	var door: Dictionary = app.world.construction.doors.doors.get(str(station.get("door_key", "")), {})
	return door.get("fixture_hinge")


## Windows and doors are hidden when the walls are lowered. One being cleaned is shown.
func _reveal(wanted: Dictionary) -> void:
	for id: Variant in wanted:
		var node: Node3D = wanted[id]
		if not node.visible and bool(app.world.cutaway): node.visible = true
		_revealed[id] = node
	for id: Variant in _revealed.keys():
		if wanted.has(id): continue
		var node: Variant = _revealed[id]
		if is_instance_valid(node): node.visible = not bool(app.world.cutaway)
		_revealed.erase(id)


## Cushions and curtains handled by a chore that is no longer going on go back as they were.
func _restore(active: Dictionary, flow: Node) -> void:
	var in_use: Dictionary = {}
	for member: Dictionary in app.household.members:
		var action: Dictionary = member.sim.get_current_action()
		if action.is_empty() or str(action.get("phase", "")) != "active" or str(action.id) not in ["chore_fluff", "chore_vacuum_curtains"]: continue
		var anchor: Dictionary = flow.anchor(str(member.id), action)
		for node: Variant in anchor.get("chore_nodes", []):
			if node is Node3D: in_use[node.get_instance_id()] = true
	for node: Variant in _touched.duplicate():
		if not is_instance_valid(node):
			_touched.erase(node); continue
		if in_use.has(node.get_instance_id()): continue
		if node.has_meta("chore_rest"):
			node.transform = node.get_meta("chore_rest")
			node.remove_meta("chore_rest")
		_touched.erase(node)


## A pane that has just been cleaned sparkles.
func sparkle(flow: Node, at: Vector3, toward: Vector3, along: Vector3) -> void:
	app = flow.app
	var root: Node3D = Node3D.new()
	root.name = "Sparkle"
	app.world.house.add_child(root)
	root.global_position = at
	app.world.assign_structure_layer(root, clampi(roundi((at.y - LifeBuildingState.GROUND_Y) / LifeBuildingState.RISE), 0, LifeBuildingState.MAX_LEVEL))
	for index: int in 9:
		var bit: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = .014; mesh.height = .028; mesh.radial_segments = 6; mesh.rings = 3
		bit.mesh = mesh
		bit.material_override = _material(Color(1, 1, .9), .9)
		bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bit)
		var angle: float = float(index) * 2.4
		bit.set_meta("velocity", along * (cos(angle) * .35) + UP * (sin(angle) * .35) + toward * .12)
		bit.position = Vector3.ZERO
	_sparkles.append({"node": root, "age": 0.0})


func _tick_sparkles(delta: float) -> void:
	for index: int in range(_sparkles.size() - 1, -1, -1):
		var entry: Dictionary = _sparkles[index]
		if not is_instance_valid(entry.node):
			_sparkles.remove_at(index); continue
		entry["age"] = float(entry.age) + maxf(delta, .02) * clampf(float(app.household.speed), 1.0, 3.0)
		for bit: Node in entry.node.get_children():
			(bit as Node3D).position = Vector3(bit.get_meta("velocity")) * float(entry.age)
			(bit as Node3D).scale = Vector3.ONE * clampf(1.2 - float(entry.age) / .9, 0.0, 1.0)
		if float(entry.age) > .9:
			entry.node.queue_free()
			_sparkles.remove_at(index)
