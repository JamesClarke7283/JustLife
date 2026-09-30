extends Node3D
## One clock for the moving seat and everyone sitting on it. The authored frame
## stays planted; the cushions move about their suspension point and the four
## hangers keep their upper ends attached to the frame.

const PERIOD: float = 3.6
const AMPLITUDE: float = .18
var model: Node3D
var pivot: Node3D
var seat_rest := Vector3.ZERO
var hangers: Array[Dictionary] = []
var clock: float = 0.0
var weight: float = 0.0
var angle: float = 0.0
var occupied: bool = false
var style: String = "a"

func configure(item: Dictionary) -> void:
	style = str((item.get("variant", {}) as Dictionary).get("style", "a"))
	model = item.node.get_child(0)
	var pieces: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	var cushion: MeshInstance3D
	for piece: MeshInstance3D in pieces:
		if str(piece.name).begins_with("Tint") and style != "c": cushion = piece
		elif str(piece.name).begins_with("Basket body") and style == "c": cushion = piece
	# Read the actual imported mesh surface, including the exporter grounding
	# offset. The three models do not share an identical seat height.
	var support: AABB = cushion.transform * cushion.get_aabb()
	seat_rest = Vector3(0, support.end.y, .04 if style != "c" else .08)
	pivot = Node3D.new()
	pivot.name = "MovingSwingSeat"
	model.add_child(pivot)
	pivot.position = Vector3(0, 1.03 if style == "a" else 1.96, -.10 if style == "a" else 0.0)
	if style == "a": pivot.position.y += support.end.y - .53
	if style == "c": pivot.position.y += support.end.y - .67
	for piece: MeshInstance3D in pieces:
		var label := str(piece.name)
		if style == "c" and label.begins_with("Chain link"):
			# The old decorative centre chain intersects a seated adult's head.
			# Two continuous side suspensions carry the basket from the beam.
			piece.visible = false
		elif label.begins_with("Glider arm") or label.begins_with("Swing chain"):
			var rest: Transform3D = piece.transform
			var bounds := piece.get_aabb()
			var first: Vector3 = rest * Vector3(0, bounds.position.y, 0)
			var last: Vector3 = rest * Vector3(0, bounds.end.y, 0)
			var upper: Vector3 = first if first.y > last.y else last
			var lower: Vector3 = last if first.y > last.y else first
			hangers.append({"node": piece, "rest": rest, "upper": upper, "lower": lower})
		elif label.begins_with("Seat") or label.begins_with("Tint") or label.begins_with("Back") or label.begins_with("Armrest") or label.begins_with("Swing armrest") or label.begins_with("Swing headboard") or label.begins_with("Basket"):
			piece.reparent(pivot, true)
	if style == "c":
		for side: float in [-1.0, 1.0]:
			var top := Vector3(side * .34, 0, 0)
			var bottom := Vector3(side * .34, .70 + seat_rest.y - .67 - pivot.position.y, -.20)
			var cable := MeshInstance3D.new()
			cable.name = "BasketSuspensionLeft" if side < 0 else "BasketSuspensionRight"
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .012; cylinder.bottom_radius = .012
			cylinder.height = top.distance_to(bottom); cylinder.radial_segments = 8
			cable.mesh = cylinder
			var metal := StandardMaterial3D.new()
			metal.albedo_color = Color("b9bec2"); metal.metallic = .45; metal.roughness = .35
			cable.material_override = metal
			pivot.add_child(cable)
			cable.layers = cushion.layers
			cable.position = (top + bottom) * .5
			cable.quaternion = Quaternion(Vector3.UP, (top-bottom).normalized())

func advance(delta: float) -> void:
	if delta <= 0.0: return
	clock += delta
	weight = move_toward(weight, 1.0 if occupied else 0.0, delta * .7)
	occupied = false
	angle = sin(clock * TAU / PERIOD) * AMPLITUDE * smoothstep(0.0, 1.0, weight)
	pivot.rotation.x = angle
	for hanger: Dictionary in hangers:
		var lower: Vector3 = pivot.transform * (Vector3(hanger.lower) - pivot.position)
		var upper: Vector3 = hanger.upper
		var original: Vector3 = Vector3(hanger.upper) - Vector3(hanger.lower)
		var direction: Vector3 = upper - lower
		var turn := Basis(Quaternion(original.normalized(), direction.normalized()))
		var rest_basis: Basis = hanger.rest.basis
		var stretched := Basis(rest_basis.x, rest_basis.y * (direction.length() / original.length()), rest_basis.z)
		hanger.node.transform = Transform3D(turn * stretched, (upper + lower) * .5)

func anchor(offset: Vector3) -> Dictionary:
	occupied = true
	var scale: float = model.scale.x
	var at: Vector3 = seat_rest + offset / maxf(.01, scale)
	return {"position": pivot.to_global(at - pivot.position), "yaw": model.global_rotation.y,
		"kind": "seat", "outdoor_kind": "outdoor_swing", "swing_angle": angle,
		"swing_phase": clock * TAU / PERIOD, "swing_motion": self}
