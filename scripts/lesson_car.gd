extends RefCounted
class_name LifeLessonCar
## The driving instructor's car: a standard Juniper in the driving school's blue,
## with the learner's plates every learner car wears: a white board with a red L on
## the bonnet and on the boot lid, and a white sign with an L on all four faces on
## the roof, so it can be read from the high camera as well as from the street.
##
## The plates are plain boxes (no font), so they look the same everywhere. The car
## is the same model and the same size as the household car, so the wheel rig, the
## door leaf and the kerb route all work on it unchanged.

const MODEL: String = "res://assets/models/juniper_car.glb"
const PLATE_SIZE: float = 0.52
const ROOF_SIGN: Vector3 = Vector3(0.52, 0.38, 0.52)
const WHITE: Color = Color("f6f4ec")
const RED: Color = Color("d02a1f")
const LIVERY: Color = Color("4f7fb5")
## The parts of the body that take the school's colour. The roof, sills and trim stay ivory.
const BODY_PARTS: Array[String] = ["Rounded lower body", "Rear hatch deck", "Short sculpted hood", "Side mirror"]
## The lesson car that is on the lot now, so street routes can wait for it.
static var active: Node3D


## A new lesson car, parked at the origin and facing +Z like every car model.
static func build() -> Node3D:
	var car: Node3D = load(MODEL).instantiate()
	car.name = "DrivingLessonCar"
	car.set_meta("learner_plates", true)
	for mesh: MeshInstance3D in car.find_children("*", "MeshInstance3D", true, false):
		if not BODY_PARTS.any(func(part: String) -> bool: return str(mesh.name).begins_with(part)): continue
		var paint: Material = mesh.get_active_material(0)
		if paint is StandardMaterial3D:
			var coat: StandardMaterial3D = (paint as StandardMaterial3D).duplicate()
			coat.albedo_color = LIVERY
			mesh.material_override = coat
	# Lying nearly flat on the bonnet and the boot lid, with the L's top towards the cabin.
	_plate(car, "LearnerPlateFront", Vector3(0, 1.115, 1.18), 0.0, -PI * .5 + 0.10)
	_plate(car, "LearnerPlateRear", Vector3(0, 1.115, -1.46), PI, -PI * .5 + 0.06)
	_roof_sign(car)
	return car


## A white square of side `size` with a red L on its +Z face.
static func plate_face(parent: Node3D, size: float, at: Vector3 = Vector3.ZERO, facing: float = 0.0) -> Node3D:
	var face: Node3D = Node3D.new()
	face.name = "LPlate"
	parent.add_child(face)
	face.position = at
	face.rotation.y = facing
	var board: MeshInstance3D = MeshInstance3D.new()
	board.name = "Board"
	var slab: BoxMesh = BoxMesh.new()
	slab.size = Vector3(size, size, 0.012)
	board.mesh = slab
	board.material_override = _paint(WHITE, 0.55)
	face.add_child(board)
	# The L: an upright bar and a foot, red, standing proud of the white board.
	var bar: float = size * 0.16
	var tall: float = size * 0.64
	var upright: MeshInstance3D = MeshInstance3D.new()
	upright.name = "LUpright"
	var upright_mesh: BoxMesh = BoxMesh.new()
	upright_mesh.size = Vector3(bar, tall, 0.012)
	upright.mesh = upright_mesh
	upright.material_override = _paint(RED, 0.5)
	upright.position = Vector3(-size * 0.14, 0.0, 0.009)
	face.add_child(upright)
	var foot: MeshInstance3D = MeshInstance3D.new()
	foot.name = "LFoot"
	var foot_mesh: BoxMesh = BoxMesh.new()
	foot_mesh.size = Vector3(size * 0.46, bar, 0.012)
	foot.mesh = foot_mesh
	foot.material_override = _paint(RED, 0.5)
	foot.position = Vector3(-size * 0.14 + size * 0.23 - bar * 0.5, -tall * 0.5 + bar * 0.5, 0.009)
	face.add_child(foot)
	return face


static func _plate(car: Node3D, plate_name: String, at: Vector3, yaw: float, pitch: float) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = plate_name
	holder.set_meta("plate_size", PLATE_SIZE)
	car.add_child(holder)
	holder.position = at
	holder.rotation = Vector3(pitch, yaw, 0.0)
	plate_face(holder, PLATE_SIZE)
	return holder


static func _roof_sign(car: Node3D) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = "LearnerRoofSign"
	holder.set_meta("plate_size", ROOF_SIGN.y)
	car.add_child(holder)
	# The roof is ivory from y 1.53 to 1.66 and runs from z -1.18 to 0.80.
	holder.position = Vector3(0.0, 1.66 + ROOF_SIGN.y * 0.5, -0.19)
	var box: MeshInstance3D = MeshInstance3D.new()
	box.name = "SignBox"
	var shell: BoxMesh = BoxMesh.new()
	shell.size = ROOF_SIGN
	box.mesh = shell
	box.material_override = _paint(WHITE, 0.55)
	holder.add_child(box)
	var faces: Array = [[Vector3(0, 0, ROOF_SIGN.z * 0.5 + 0.007), 0.0], [Vector3(0, 0, -ROOF_SIGN.z * 0.5 - 0.007), PI],
		[Vector3(ROOF_SIGN.x * 0.5 + 0.007, 0, 0), PI * 0.5], [Vector3(-ROOF_SIGN.x * 0.5 - 0.007, 0, 0), -PI * 0.5]]
	for face: Array in faces: plate_face(holder, ROOF_SIGN.y * 0.86, face[0], float(face[1]))
	return holder


static func _paint(colour: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	return material
