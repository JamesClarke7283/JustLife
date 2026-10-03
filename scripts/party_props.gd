extends RefCounted
## Party props drawn from plain shapes: balloons, streamers, the party food platter and
## the festive tablecloth's drape. Nothing here needs a model file or the world, so the
## placed piece, the placement ghost and the shop thumbnail all call the same builders.
##
## Every piece is a "PartyModel" root. A mesh named `Tint...` takes the player's colour
## (`TintGloss...` takes it with a shiny finish, for balloons); every other mesh keeps its
## own accent colour. A balloon bunch keeps inside its 0.6 m square and 1.9 m height, the
## streamers hang from their attachment line down to 0.55 m and no further than 0.04 m
## either side of the wall, and the platter lies on its footprint at the host's surface.

const KINDS: Array[String] = ["party_balloons", "party_streamers", "party_food"]
## The tables that can wear a festive cloth.
const CLOTH_HOSTS: Array[String] = ["dining"]
## The platter's places for food. A serving is shown while one is left.
const SERVING_SLOTS: int = 8
## The gathering table's top surface in its own model. The sheet is 1.6 mm thick and lies on
## it, so its upper face is under the 2 mm the meal dishes are set above the table: a
## plate, a bowl or a platter rests exactly where it did without a cloth.
const CLOTH_TABLE_TOP: float = .845
const CLOTH_THICKNESS: float = .0016
const CLOTH_SIZE: Vector2 = Vector2(1.64, 1.16)
const CLOTH_DROP: float = .22

static var _materials: Dictionary = {}


static func builds(kind: String) -> bool:
	return kind in KINDS


## The model for one party kind in the variant's style and colour.
static func build(kind: String, variant: Dictionary) -> Node3D:
	var colour: String = str(variant.get("color", "ef476f"))
	var style: String = str(variant.get("style", ""))
	var root := Node3D.new()
	root.name = "PartyModel"
	match kind:
		"party_balloons":
			match style:
				"column": _balloon_column(root, colour)
				"trio": _balloon_trio(root, colour)
				_: _balloon_bunch(root, colour)
		"party_streamers":
			match style:
				"crepe": _crepe_swags(root, colour)
				"tassel": _tassel_fringe(root, colour)
				_: _bunting(root, colour)
		"party_food":
			match style:
				"sandwiches": _sandwiches(root)
				"snacks": _snacks(root)
				_: _cupcakes(root)
	return root


## Show the first `count` servings of a platter and hide the rest.
static func show_servings(model: Node3D, count: int) -> void:
	if not is_instance_valid(model): return
	for index: int in range(SERVING_SLOTS):
		var serving: Node = model.find_child("Serving_%d" % index, true, false)
		if serving is Node3D: (serving as Node3D).visible = index < count


## How many servings of a platter model are showing.
static func servings_shown(model: Node3D) -> int:
	var shown: int = 0
	for index: int in range(SERVING_SLOTS):
		var serving: Node = model.find_child("Serving_%d" % index, true, false)
		if serving is Node3D and (serving as Node3D).visible: shown += 1
	return shown


## The contrasting colours worked in beside a chosen colour: white and gold, with blue or
## red stepped in where the choice is already close to one of them.
static func accents(colour: String) -> Array[String]:
	var tone: Color = Color(colour)
	if tone.s < .2 and tone.v > .8: return ["ef476f", "118ab2"]
	if tone.h > .09 and tone.h < .18 and tone.s > .3: return ["f4f1ea", "118ab2"]
	return ["f4f1ea", "ffd166"]


# ------------------------------------------------------------------ primitives

static func _material(hex: String, roughness: float = .7) -> StandardMaterial3D:
	var key: String = "%s|%.2f" % [hex, roughness]
	if not _materials.has(key):
		var made := StandardMaterial3D.new()
		made.albedo_color = Color(hex)
		made.roughness = roughness
		_materials[key] = made
	return _materials[key]


static func _mesh(parent: Node3D, label: String, mesh: Mesh, at: Vector3, hex: String, roughness: float = .7) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = _material(hex, .22 if label.begins_with("TintGloss") else roughness)
	node.position = at
	parent.add_child(node)
	return node


static func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, hex: String, roughness: float = .7) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, label, mesh, at, hex, roughness)


static func _ball(parent: Node3D, label: String, at: Vector3, diameters: Vector3, hex: String, roughness: float = .7) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 14
	mesh.rings = 7
	var node: MeshInstance3D = _mesh(parent, label, mesh, at, hex, roughness)
	node.scale = diameters
	return node


static func _tube(parent: Node3D, label: String, at: Vector3, top_radius: float, bottom_radius: float, height: float, hex: String, roughness: float = .7) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 14
	return _mesh(parent, label, mesh, at, hex, roughness)


## A thin rod from one point to another, for strings and cords.
static func _rod(parent: Node3D, label: String, from: Vector3, to: Vector3, radius: float, hex: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 5
	mesh.rings = 1
	var node: MeshInstance3D = _mesh(parent, label, mesh, (from + to) * .5, hex, .8)
	var along: Vector3 = (to - from).normalized()
	var axis: Vector3 = Vector3.UP.cross(along)
	if axis.length() < .0001:
		node.basis = Basis.IDENTITY if along.y > 0.0 else Basis(Vector3.RIGHT, PI)
	else:
		node.basis = Basis(axis.normalized(), Vector3.UP.angle_to(along))
	return node


## A hanging triangle, point down, thin front to back.
static func _pennant(parent: Node3D, label: String, at: Vector3, width: float, height: float, hex: String) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(width, height, .005)
	var node: MeshInstance3D = _mesh(parent, label, mesh, at - Vector3(0, height * .5, 0), hex, .85)
	node.rotation = Vector3(0, 0, PI)
	return node


# -------------------------------------------------------------------- balloons

## One balloon with its knot. A tinted balloon is the player's colour; the others are
## the accents. The knot's underside is where its string starts: the returned point.
static func _balloon(parent: Node3D, tag: String, centre: Vector3, width: float, height: float, hex: String, tinted: bool) -> Vector3:
	var prefix: String = "TintGloss" if tinted else ""
	_ball(parent, "%sBalloon_%s" % [prefix, tag], centre, Vector3(width, height, width), hex, .25)
	var foot: Vector3 = centre - Vector3(0, height * .5 + .014, 0)
	_tube(parent, "%sKnot_%s" % [prefix, tag], foot, 0.0, width * .07, .03, hex, .4)
	return foot - Vector3(0, .015, 0)


static func _balloon_bunch(root: Node3D, colour: String) -> void:
	var accent: Array[String] = accents(colour)
	_tube(root, "Weight", Vector3(0, .03, 0), .075, .085, .06, "e0b15a", .4)
	var spots: Array = [
		[Vector3(0.0, 1.68, 0.0), colour, true], [Vector3(-.13, 1.52, .05), accent[0], false],
		[Vector3(.14, 1.55, -.04), colour, true], [Vector3(-.05, 1.40, -.14), accent[1], false],
		[Vector3(.07, 1.38, .13), colour, true],
	]
	for index: int in range(spots.size()):
		var spot: Array = spots[index]
		var string_start: Vector3 = _balloon(root, str(index), spot[0] as Vector3, .26, .31, str(spot[1]), bool(spot[2]))
		_rod(root, "String_%d" % index, Vector3(0, .06, 0), string_start, .004, "e9e4d6")


static func _balloon_trio(root: Node3D, colour: String) -> void:
	var accent: Array[String] = accents(colour)
	_tube(root, "Weight", Vector3(0, .03, 0), .08, .09, .06, "e0b15a", .4)
	var spots: Array = [
		[Vector3(-.10, 1.44, .02), colour, true], [Vector3(.11, 1.57, -.03), accent[0], false],
		[Vector3(0.0, 1.28, .10), colour, true],
	]
	for index: int in range(spots.size()):
		var spot: Array = spots[index]
		var string_start: Vector3 = _balloon(root, str(index), spot[0] as Vector3, .34, .42, str(spot[1]), bool(spot[2]))
		_rod(root, "String_%d" % index, Vector3(0, .06, 0), string_start, .004, "e9e4d6")


## Four tiers of four balloons round a pole, alternately the player's colour and an accent.
static func _balloon_column(root: Node3D, colour: String) -> void:
	var accent: Array[String] = accents(colour)
	_tube(root, "Base", Vector3(0, .02, 0), .24, .24, .04, "e0b15a", .4)
	_tube(root, "Pole", Vector3(0, .90, 0), .018, .018, 1.72, "e9e4d6", .5)
	for tier: int in range(4):
		var height: float = .38 + float(tier) * .34
		for corner: int in range(4):
			var at := Vector3(.10 if corner % 2 == 0 else -.10, height, .10 if corner < 2 else -.10)
			if tier % 2 == 0:
				_ball(root, "TintGlossBalloon_%d_%d" % [tier, corner], at, Vector3(.2, .24, .2), colour, .25)
			else:
				_ball(root, "Balloon_%d_%d" % [tier, corner], at, Vector3(.2, .24, .2), accent[(tier / 2) % 2], .25)
	_ball(root, "TintGlossTopper", Vector3(0, 1.66, 0), Vector3(.2, .22, .2), colour, .25)
	_ball(root, "TopperPearl", Vector3(0, 1.79, 0), Vector3(.07, .07, .07), "e0b15a", .3)


# ------------------------------------------------------------------- streamers
# The origin is the attachment line on the wall and +z faces the room, so everything
# stays within a few centimetres of z = 0 and at or below y = 0.

## Points along a swag from one end to the other: the ends are on the line, the middle
## sags by `sag`.
static func _swag_points(from_x: float, to_x: float, sag: float, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for index: int in range(count + 1):
		var along: float = float(index) / float(count)
		var across: float = along * 2.0 - 1.0
		out.append(Vector3(lerpf(from_x, to_x, along), -sag * (1.0 - across * across), 0.0))
	return out


static func _bunting(root: Node3D, colour: String) -> void:
	var accent: Array[String] = accents(colour)
	for pin_x: float in [-1.13, 0.0, 1.13]:
		_ball(root, "Pin_%d" % int(pin_x * 100.0), Vector3(pin_x, .006, .005), Vector3(.03, .03, .03), "e0b15a", .3)
	for side: int in range(2):
		var from_x: float = -1.13 if side == 0 else .03
		var to_x: float = -.03 if side == 0 else 1.13
		var line: Array[Vector3] = _swag_points(from_x, to_x, .2, 6)
		for index: int in range(6):
			_rod(root, "Cord_%d_%d" % [side, index], line[index], line[index + 1], .005, "d9d1c0")
		var flags: Array[Vector3] = _swag_points(from_x, to_x, .2, 14)
		for index: int in range(7):
			var anchor: Vector3 = flags[index * 2 + 1] - Vector3(0, .004, 0)
			if index % 2 == 0:
				_pennant(root, "TintPennant_%d_%d" % [side, index], anchor, .13, .18, colour)
			else:
				_pennant(root, "Pennant_%d_%d" % [side, index], anchor, .13, .18, accent[(index / 2) % 2])


static func _crepe_swags(root: Node3D, colour: String) -> void:
	var accent: Array[String] = accents(colour)
	for side: int in range(2):
		var from_x: float = -1.13 if side == 0 else .03
		var to_x: float = -.03 if side == 0 else 1.13
		var line: Array[Vector3] = _swag_points(from_x, to_x, .2, 12)
		for index: int in range(12):
			var a: Vector3 = line[index]
			var b: Vector3 = line[index + 1]
			var strip := _box(root, "TintCrepe_%d_%d" % [side, index] if index % 2 == 0 else "Crepe_%d_%d" % [side, index], (a + b) * .5, Vector3(a.distance_to(b) + .012, .05, .004), colour if index % 2 == 0 else accent[(index / 2) % 2], .9)
			var slope: float = atan2(b.y - a.y, b.x - a.x)
			strip.basis = Basis(Vector3.BACK, slope) * Basis(Vector3.RIGHT, deg_to_rad(52.0 if index % 4 < 2 else -52.0))
	var tails: Array = [[-1.13, 4.0, colour, true], [0.0, -5.0, accent[0], false], [1.13, 6.0, colour, true]]
	for index: int in range(tails.size()):
		var tail: Array = tails[index]
		var length: float = .5 - float(index % 2) * .08
		var node := _box(root, ("TintTail_%d" if bool(tail[3]) else "Tail_%d") % index, Vector3(float(tail[0]), -length * .5, .004), Vector3(.055, length, .004), str(tail[2]), .9)
		node.rotation.z = deg_to_rad(float(tail[1]))


static func _tassel_fringe(root: Node3D, colour: String) -> void:
	var accent: Array[String] = accents(colour)
	_box(root, "Cord", Vector3(0, 0, 0), Vector3(2.3, .012, .012), "d9d1c0", .8)
	for index: int in range(11):
		var x: float = -1.0 + float(index) * .2
		var length: float = .42 if index % 2 == 0 else .30
		_ball(root, "Bead_%d" % index, Vector3(x, -.02, 0), Vector3(.04, .04, .04), "e0b15a", .3)
		if index % 2 == 0:
			_box(root, "TintStrand_%d" % index, Vector3(x, -.04 - length * .5, 0), Vector3(.05, length, .008), colour, .9)
		else:
			_box(root, "Strand_%d" % index, Vector3(x, -.04 - length * .5, 0), Vector3(.05, length, .008), accent[(index / 2) % 2], .9)


# ------------------------------------------------------------------------ food

## The tray every platter stands on, with its doily.
static func _tray(root: Node3D) -> void:
	_box(root, "Tray", Vector3(0, .006, 0), Vector3(.5, .012, .34), "f4f1ea", .55)
	_box(root, "Doily", Vector3(0, .013, 0), Vector3(.44, .002, .28), "e6d8c5", .9)


## The centre of each of the eight places: four across and two deep.
static func _slot(index: int) -> Vector3:
	return Vector3(-.165 + float(index % 4) * .11, .014, -.06 if index < 4 else .06)


static func _serving(root: Node3D, index: int) -> Node3D:
	var serving := Node3D.new()
	serving.name = "Serving_%d" % index
	serving.position = _slot(index)
	root.add_child(serving)
	return serving


static func _cupcakes(root: Node3D) -> void:
	_tray(root)
	var cases: Array[String] = ["e8c3d6", "c9e0d8", "f2dca0", "d6c8e8"]
	var icing: Array[String] = ["ef8fb0", "f4f1ea", "8fd3c1", "f7c873"]
	for index: int in range(SERVING_SLOTS):
		var serving: Node3D = _serving(root, index)
		_tube(serving, "Case", Vector3(0, .016, 0), .033, .024, .032, cases[index % 4], .7)
		_ball(serving, "Icing", Vector3(0, .045, 0), Vector3(.075, .05, .075), icing[(index + index / 4) % 4], .5)
		_ball(serving, "Cherry", Vector3(0, .072, 0), Vector3(.02, .02, .02), "c9302c", .3)


static func _sandwiches(root: Node3D) -> void:
	_tray(root)
	var fillings: Array[String] = ["7fb069", "e07a5f", "f2c14e", "d9a066"]
	for index: int in range(SERVING_SLOTS):
		var serving: Node3D = _serving(root, index)
		var turn: float = 0.0 if index % 2 == 0 else PI
		for layer: int in range(3):
			var mesh := PrismMesh.new()
			mesh.size = Vector3(.095, .095, .014 if layer != 1 else .007)
			var colour: String = "ecd9a8" if layer != 1 else fillings[index % 4]
			var at := Vector3(0, [.007, .0165, .027][layer], 0)
			var piece: MeshInstance3D = _mesh(serving, ["BreadBottom", "Filling", "BreadTop"][layer], mesh, at, colour, .9)
			piece.rotation = Vector3(PI * .5, turn, 0)


static func _snacks(root: Node3D) -> void:
	_tray(root)
	for index: int in range(SERVING_SLOTS):
		var serving: Node3D = _serving(root, index)
		_tube(serving, "Cracker", Vector3(0, .004, 0), .036, .036, .008, "d9a45b", .9)
		if index % 2 == 0:
			_box(serving, "Cheese", Vector3(0, .023, 0), Vector3(.034, .03, .034), "f2c14e", .6)
		else:
			_ball(serving, "Tomato", Vector3(0, .026, 0), Vector3(.04, .036, .04), "d1432f", .35)


# ------------------------------------------------------------------- tablecloth

## The drape for a gathering table, in the table's own coordinates: a thin sheet over the
## top with a short skirt hanging from each edge, a contrasting runner down the middle
## and a trim at each hem. The sheet is no more than 1.6 mm above the table, so food and
## dishes keep the heights they always had.
static func build_cloth(colour: String) -> Node3D:
	var accent: String = accents(colour)[0]
	var root := Node3D.new()
	root.name = "TableCloth"
	var top: float = CLOTH_TABLE_TOP
	var half := CLOTH_SIZE * .5
	_box(root, "TintClothTop", Vector3(0, top + CLOTH_THICKNESS * .5, 0), Vector3(CLOTH_SIZE.x, CLOTH_THICKNESS, CLOTH_SIZE.y), colour, .95)
	var skirt_y: float = top - CLOTH_DROP * .5
	var hem_y: float = top - CLOTH_DROP + .0125
	for side: int in range(4):
		var along_x: bool = side < 2
		var sign: float = 1.0 if side % 2 == 0 else -1.0
		var label: String = ["N", "S", "E", "W"][side]
		if along_x:
			_box(root, "TintClothSkirt_" + label, Vector3(0, skirt_y, sign * (half.y - .003)), Vector3(CLOTH_SIZE.x + .012, CLOTH_DROP, .006), colour, .95)
			_box(root, "ClothHem_" + label, Vector3(0, hem_y, sign * (half.y - .002)), Vector3(CLOTH_SIZE.x + .012, .025, .008), accent, .85)
		else:
			_box(root, "TintClothSkirt_" + label, Vector3(sign * (half.x - .003), skirt_y, 0), Vector3(.006, CLOTH_DROP, CLOTH_SIZE.y), colour, .95)
			_box(root, "ClothHem_" + label, Vector3(sign * (half.x - .002), hem_y, 0), Vector3(.008, .025, CLOTH_SIZE.y), accent, .85)
	_box(root, "ClothRunner", Vector3(0, top + CLOTH_THICKNESS + .0004, 0), Vector3(CLOTH_SIZE.x, .0008, .22), accent, .85)
	return root
