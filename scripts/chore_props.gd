extends Node3D
## The tools of household cleaning, built from boxes, cylinders and spheres: a vacuum
## cleaner (floor head, wand, canister and a hose that sags between them), a hand nozzle,
## feather duster, sponge, cloth, spray bottle, squeegee (short, or on a pole), toilet
## brush, broom and a step stool. The existing juniper mop stays with the actor.
##
## Every tool is built with its working end at its own origin and its handle along +Y, so
## the pose places one by putting that origin on the surface being cleaned. `present`
## shows exactly the tools it is given, in world space, and hides the rest.

const HOSE_SEGMENTS: int = 10
const MIST_BITS: int = 9
## Grip points on each tool (tool-local metres), right hand first, for a body of
## proportion 1.0. The pose scales them with the tool.
const GRIPS: Dictionary = {
	"hoover": {"R": Vector3(0, .93, .02), "L": Vector3(0, .79, 0)},
	"nozzle": {"R": Vector3(0, .10, 0), "L": Vector3(0, .21, 0)},
	"duster": {"R": Vector3(0, .35, 0)},
	"sponge": {"R": Vector3(0, .055, 0)},
	"cloth": {"R": Vector3(0, .04, 0)},
	"spray": {"L": Vector3(0, .09, 0), "R": Vector3(0, .09, 0)},
	"squeegee": {"R": Vector3(0, .17, 0)},
	"pole_squeegee": {"R": Vector3(0, .62, 0), "L": Vector3(0, 1.02, 0)},
	"brush": {"R": Vector3(0, .34, 0)},
	"broom": {"R": Vector3(0, 1.02, .03), "L": Vector3(0, .80, .04)},
}

var _tools: Dictionary = {}
var _hose: Array[MeshInstance3D] = []
var _mist: Array[MeshInstance3D] = []
var _materials: Dictionary = {}
var _squeegee_handle: MeshInstance3D
var _pole_handle: MeshInstance3D


func _init() -> void:
	name = "ChoreProps"
	top_level = true


func _ready() -> void:
	_build()
	hide_all()


func hide_all() -> void:
	for tool: Node3D in _tools.values(): tool.visible = false
	for segment: MeshInstance3D in _hose: segment.visible = false
	for bit: MeshInstance3D in _mist: bit.visible = false


## Show the tools `spec` names. Keys: hoover, canister, nozzle, duster, sponge, cloth, spray,
## squeegee, pole_squeegee, brush, broom, stool (Transform3D, world); `hose` ([from, to,
## sag]) and `mist` (world points).
func present(spec: Dictionary) -> void:
	if _tools.is_empty(): _build()
	global_transform = Transform3D.IDENTITY
	for key: String in _tools:
		var wanted: Variant = spec.get(key)
		_tools[key].visible = wanted is Transform3D
		if wanted is Transform3D: (_tools[key] as Node3D).global_transform = wanted
	_lay_hose(spec.get("hose", []))
	var points: Array = spec.get("mist", [])
	for index: int in _mist.size():
		_mist[index].visible = index < points.size()
		if index < points.size(): _mist[index].global_position = points[index]


## Where a tool's grip lands in the world for the given tool transform.
static func grip_point(tool: String, side: String, at: Transform3D, scale: float = 1.0) -> Variant:
	var grips: Dictionary = GRIPS.get(tool, {})
	if not grips.has(side): return null
	return at * (Vector3(grips[side]) * scale)


func _lay_hose(spec: Variant) -> void:
	var ready: bool = spec is Array and spec.size() >= 2 and spec[0] is Vector3 and spec[1] is Vector3
	for segment: MeshInstance3D in _hose: segment.visible = ready
	if not ready: return
	var from: Vector3 = spec[0]
	var to: Vector3 = spec[1]
	var sag: float = float(spec[2]) if spec.size() > 2 else .18
	var previous: Vector3 = from
	for index: int in range(HOSE_SEGMENTS):
		var s: float = float(index + 1) / float(HOSE_SEGMENTS)
		var point: Vector3 = from.lerp(to, s) + Vector3.DOWN * sag * sin(s * PI)
		_stretch(_hose[index], previous, point)
		previous = point


## Lay a straight cylinder (built one metre long, along Y) between two points.
func _stretch(cord: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var length: float = a.distance_to(b)
	if length < .005:
		cord.visible = false
		return
	var up: Vector3 = (b - a).normalized()
	var side: Vector3 = up.cross(Vector3.UP if absf(up.y) < .95 else Vector3.RIGHT).normalized()
	cord.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized() * Basis.from_scale(Vector3(1, length, 1)), (a + b) * .5)


# ------------------------------------------------------------------- building

func _material(color: Color, rough: float = .75, alpha: float = 1.0) -> StandardMaterial3D:
	var key: String = "%s_%.2f_%.2f" % [color.to_html(), rough, alpha]
	if _materials.has(key): return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = rough
	if alpha < 1.0: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = material
	return material


func _box(parent: Node3D, size: Vector3, color: Color, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, radius: float, height: float, color: Color, at: Vector3 = Vector3.ZERO, tilt: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = height
	mesh.radial_segments = 10; mesh.rings = 1
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = at
	node.rotation = tilt
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _ball(parent: Node3D, radius: float, color: Color, at: Vector3 = Vector3.ZERO, stretch: Vector3 = Vector3.ONE, alpha: float = 1.0) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius; mesh.height = radius * 2.0; mesh.radial_segments = 10; mesh.rings = 5
	node.mesh = mesh
	node.material_override = _material(color, .8, alpha)
	node.position = at
	node.scale = stretch
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _tool(key: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = key.capitalize().replace(" ", "")
	add_child(node)
	_tools[key] = node
	return node


func _build() -> void:
	if not _tools.is_empty(): return
	var teal: Color = Color("3f7f86")
	var steel: Color = Color("b9c0c6")
	var dark: Color = Color("2d3338")
	var wood: Color = Color("b88b53")
	# Vacuum cleaner: floor head and wand (working end at the head's centre on the floor).
	var hoover: Node3D = _tool("hoover")
	_box(hoover, Vector3(.30, .05, .13), teal, Vector3(0, .03, 0))
	_box(hoover, Vector3(.31, .022, .034), dark, Vector3(0, .015, .075))
	_box(hoover, Vector3(.10, .05, .08), Color("2f6a71"), Vector3(0, .075, -.045))
	_cylinder(hoover, .014, .90, steel, Vector3(0, .55, .0))
	_box(hoover, Vector3(.045, .035, .13), dark, Vector3(0, .985, .035))
	_cylinder(hoover, .021, .06, Color("586067"), Vector3(0, .90, -.012), Vector3(PI * .5, 0, 0))
	# The canister it is plugged into: a body with a lid, wheels and a hose inlet.
	var canister: Node3D = _tool("canister")
	_box(canister, Vector3(.30, .19, .26), teal, Vector3(0, .15, 0))
	_box(canister, Vector3(.28, .035, .24), Color("2f6a71"), Vector3(0, .26, 0))
	_box(canister, Vector3(.07, .05, .04), dark, Vector3(0, .31, -.02))
	for side: float in [-1.0, 1.0]:
		_cylinder(canister, .052, .035, dark, Vector3(side * .16, .052, -.07), Vector3(0, 0, PI * .5))
		_cylinder(canister, .052, .035, dark, Vector3(side * .16, .052, .08), Vector3(0, 0, PI * .5))
	_cylinder(canister, .028, .09, Color("586067"), Vector3(0, .17, .17), Vector3(PI * .5, 0, 0))
	# Hand nozzle for the curtains.
	var nozzle: Node3D = _tool("nozzle")
	_box(nozzle, Vector3(.15, .022, .045), dark, Vector3(0, .01, 0))
	_box(nozzle, Vector3(.14, .03, .035), teal, Vector3(0, .04, 0))
	_cylinder(nozzle, .016, .20, steel, Vector3(0, .15, 0))
	_cylinder(nozzle, .02, .04, Color("586067"), Vector3(0, .26, 0))
	# Feather duster.
	var duster: Node3D = _tool("duster")
	for index: int in range(8):
		var around: float = float(index) * TAU / 8.0
		var feather: MeshInstance3D = _ball(duster, .5, Color("efe6d0") if index % 2 == 0 else Color("d9ccb0"), Vector3(sin(around) * .028, .075, cos(around) * .028), Vector3(.032, .15, .014))
		feather.rotation = Vector3(cos(around) * .42, around, -sin(around) * .42)
	_cylinder(duster, .011, .05, Color("c9b27e"), Vector3(0, .165, 0))
	_cylinder(duster, .009, .30, wood, Vector3(0, .33, 0))
	_ball(duster, .014, wood, Vector3(0, .485, 0))
	# Sponge and cloth.
	var sponge: Node3D = _tool("sponge")
	_box(sponge, Vector3(.115, .026, .078), Color("4f8f59"), Vector3(0, .013, 0))
	_box(sponge, Vector3(.115, .03, .078), Color("e7c75a"), Vector3(0, .041, 0))
	var cloth: Node3D = _tool("cloth")
	_box(cloth, Vector3(.21, .012, .17), Color("9fc3d6"), Vector3(0, .006, 0))
	_box(cloth, Vector3(.15, .014, .11), Color("b6d3e2"), Vector3(0.012, .019, 0.005))
	# Spray bottle, nozzle facing +Z.
	var spray: Node3D = _tool("spray")
	_cylinder(spray, .031, .17, Color("cfe6ee"), Vector3(0, .085, 0))
	_cylinder(spray, .027, .09, Color("86cfe0"), Vector3(0, .05, 0))
	_cylinder(spray, .015, .04, Color("eef2f4"), Vector3(0, .19, 0))
	_box(spray, Vector3(.034, .034, .085), Color("f0f4f6"), Vector3(0, .222, .02))
	_cylinder(spray, .008, .03, Color("f0f4f6"), Vector3(0, .222, .075), Vector3(PI * .5, 0, 0))
	_box(spray, Vector3(.016, .045, .014), dark, Vector3(0, .185, .045))
	# Squeegee (short, and a long-handled one for the top of a window).
	var squeegee: Node3D = _tool("squeegee")
	_box(squeegee, Vector3(.30, .022, .034), dark, Vector3(0, .014, 0))
	_box(squeegee, Vector3(.30, .008, .012), Color("14171a"), Vector3(0, -.001, 0))
	_squeegee_handle = _cylinder(squeegee, .011, 1.0, Color("e0e5e8"), Vector3(0, .13, 0))
	_squeegee_handle.scale = Vector3(1, .22, 1)
	var pole: Node3D = _tool("pole_squeegee")
	_box(pole, Vector3(.30, .022, .034), dark, Vector3(0, .014, 0))
	_box(pole, Vector3(.30, .008, .012), Color("14171a"), Vector3(0, -.001, 0))
	_pole_handle = _cylinder(pole, .011, 1.0, Color("c9d2d8"), Vector3(0, .67, 0))
	_pole_handle.scale = Vector3(1, 1.30, 1)
	# Toilet brush.
	var brush: Node3D = _tool("brush")
	_ball(brush, .036, dark, Vector3(0, .028, 0), Vector3(1, .85, 1))
	_cylinder(brush, .016, .04, Color("e8e4d8"), Vector3(0, .075, 0))
	_cylinder(brush, .0105, .40, Color("e8e4d8"), Vector3(0, .27, 0))
	_ball(brush, .016, Color("e8e4d8"), Vector3(0, .47, 0))
	# Broom: bristles at the origin, handle up.
	var broom: Node3D = _tool("broom")
	_box(broom, Vector3(.38, .05, .075), Color("c9a45a"), Vector3(0, .025, 0))
	_box(broom, Vector3(.38, .03, .085), Color("8a5a36"), Vector3(0, .065, 0))
	_cylinder(broom, .012, 1.28, wood, Vector3(0, .72, 0))
	# Step stool (origin on the floor, top at .30).
	var stool: Node3D = _tool("stool")
	_box(stool, Vector3(.44, .03, .32), Color("c6d1cf"), Vector3(0, .285, 0))
	for side: float in [-1.0, 1.0]:
		_box(stool, Vector3(.03, .27, .30), Color("a9b8b5"), Vector3(side * .19, .135, 0))
	_box(stool, Vector3(.36, .05, .03), Color("a9b8b5"), Vector3(0, .15, 0))
	for index: int in range(HOSE_SEGMENTS):
		var segment: MeshInstance3D = _cylinder(self, .0175, 1.0, Color("586067"))
		_hose.append(segment)
	for index: int in range(MIST_BITS):
		_mist.append(_ball(self, .007, Color("bfe6f2"), Vector3.ZERO, Vector3.ONE, .55))
