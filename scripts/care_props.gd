extends Node3D
## The things a Lifelet holds while caring for a pet: a kibble bag with the food
## running out of it, a rope toy for tug-of-war and a lead clipped to the collar.
## Each is placed in world space from the pose that holds it, every frame, and
## hidden when the pose does not ask for it.

const KIBBLE_BITS: int = 7

var _bag: Node3D
var _kibble: Array[MeshInstance3D] = []
var _rope: MeshInstance3D
var _leash: MeshInstance3D


func _init() -> void:
	name = "CareProps"
	top_level = true


func _ready() -> void:
	_bag = Node3D.new(); _bag.name = "KibbleBag"; add_child(_bag)
	var sack := _box(_bag, Vector3(.17, .24, .09), Color("c9a36b")); sack.position.y = .02
	var band := _box(_bag, Vector3(.172, .07, .092), Color("417a71")); band.position.y = -.01
	var fold := _box(_bag, Vector3(.15, .03, .05), Color("b28d57")); fold.position.y = .15
	for i: int in range(KIBBLE_BITS):
		var bit := MeshInstance3D.new()
		var mesh := SphereMesh.new(); mesh.radius = .011; mesh.height = .016; mesh.radial_segments = 6; mesh.rings = 3
		bit.mesh = mesh; bit.material_override = _material(Color("8a5a36"))
		add_child(bit); _kibble.append(bit)
	_rope = _cord(Color("d9c7a0"), .016)
	_leash = _cord(Color("3d4145"), .007)
	hide_all()


func hide_all() -> void:
	if not is_instance_valid(_bag): return
	_bag.visible = false
	for bit: MeshInstance3D in _kibble: bit.visible = false
	_rope.visible = false
	_leash.visible = false


## Show exactly what `props` names: `bag` (Transform3D), `kibble` (points),
## `rope` and `leash` ([from, to] world points).
func present(props: Dictionary) -> void:
	if not is_instance_valid(_bag): return
	global_transform = Transform3D.IDENTITY
	_bag.visible = props.get("bag") is Transform3D
	if _bag.visible: _bag.global_transform = props.bag
	var bits: Array = props.get("kibble", [])
	for i: int in range(_kibble.size()):
		_kibble[i].visible = i < bits.size()
		if _kibble[i].visible: _kibble[i].global_position = bits[i]
	_stretch(_rope, props.get("rope", []))
	_stretch(_leash, props.get("leash", []))


## Lay a straight cord between two points.
func _stretch(cord: MeshInstance3D, ends: Variant) -> void:
	cord.visible = ends is Array and ends.size() == 2 and ends[0] is Vector3 and ends[1] is Vector3
	if not cord.visible: return
	var a: Vector3 = ends[0]; var b: Vector3 = ends[1]
	var length: float = a.distance_to(b)
	if length < .01: cord.visible = false; return
	var mid: Vector3 = (a + b) * .5
	var up: Vector3 = (b - a).normalized()
	var side: Vector3 = up.cross(Vector3.UP if absf(up.y) < .95 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up)).orthonormalized()
	cord.global_transform = Transform3D(basis.scaled(Vector3(1, length, 1)), mid)


func _cord(color: Color, radius: float) -> MeshInstance3D:
	var cord := MeshInstance3D.new()
	var mesh := CylinderMesh.new(); mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = 1.0; mesh.radial_segments = 8; mesh.rings = 1
	cord.mesh = mesh; cord.material_override = _material(color)
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cord)
	return cord


func _box(parent: Node3D, size: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size = size
	node.mesh = mesh; node.material_override = _material(color)
	parent.add_child(node)
	return node


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	return material
