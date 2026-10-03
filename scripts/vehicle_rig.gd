extends RefCounted
class_name LifeVehicleRig
## Wheels that turn. Every car model has its tyres and hubs as separate meshes
## and nothing moved them; the rig finds them by name, remembers where each
## rests, and then poses them from two numbers a path gives for any moment: the
## steering angle and how far the car has rolled.
##
## The front pair is steered about a vertical line through each tyre's centre,
## every wheel spins about the axle (the car's own X axis), and a hub shares the
## pivot of the tyre it sits on. A car rolling backwards spins its wheels
## backwards. Reverse and brake lights are a flag on the tail-light surfaces.
##
## Which models: the saloons, hatchback, estate, coupe, van, minibus, SUV,
## off-roader, pickup, the Juniper (shared and police) car, the electric_car
## and the delivery van are all authored nose +Z with the axle along X. The
## older car_electric.glb is authored lying on its side (its length runs along
## the model's Y axis), so its wheels have no front or rear along Z: attach()
## reports it as not rigged and it is driven without wheel animation.

const AXLE_TOLERANCE: float = .97
const BRAKE_COLOUR: Color = Color(1.0, .08, .05)


static func _is_tyre(name: String) -> bool:
	var low: String = name.to_lower()
	if low.contains("spare") or low.contains("hub"): return false
	return low.contains("tyre") or low.contains("tire") or low.contains("rubber") or low.begins_with("wheel")


static func _is_hub(name: String) -> bool:
	var low: String = name.to_lower()
	return low.contains("hub") and not low.contains("spare")


## The transform from a node's parent space up to the car's own space.
static func _to_car(car: Node3D, node: Node) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var parent: Node = node.get_parent()
	while parent != null and parent != car:
		if parent is Node3D: chain = (parent as Node3D).transform * chain
		parent = parent.get_parent()
	return chain


## Find the wheels of a car node. Returns {ok, wheels, wheelbase, radius, front, tail_lights}.
## `wheels` entries hold the node, its rest transform, the pivot in car space,
## whether it is on the steered axle, and whether it is a hub.
static func attach(car: Node3D) -> Dictionary:
	if car.has_meta("vehicle_rig"):
		var kept: Variant = car.get_meta("vehicle_rig")
		if kept is Dictionary and (kept as Dictionary).get("car") == car: return kept
	var tyres: Array[Dictionary] = []
	var hubs: Array[Dictionary] = []
	for found: Node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = found as MeshInstance3D
		if mesh_node.mesh == null: continue
		var tyre: bool = _is_tyre(str(mesh_node.name))
		var hub: bool = not tyre and _is_hub(str(mesh_node.name))
		if not tyre and not hub: continue
		var parent_to_car: Transform3D = _to_car(car, mesh_node)
		var in_car: Transform3D = parent_to_car * mesh_node.transform
		var box: AABB = mesh_node.mesh.get_aabb()
		var thin: int = 0
		for axis: int in range(1, 3):
			if box.size[axis] < box.size[thin]: thin = axis
		var axle_local := Vector3.ZERO
		axle_local[thin] = 1.0
		var axle: Vector3 = (in_car.basis * axle_local).normalized()
		var scale_factor: float = in_car.basis.get_scale().x
		var round_size: float = 0.0
		for axis: int in range(3):
			if axis != thin: round_size = maxf(round_size, box.size[axis])
		var entry: Dictionary = {"node": mesh_node, "rest": mesh_node.transform, "to_car": parent_to_car, "centre": in_car * box.get_center(),
			"axle_x": absf(axle.x), "radius": round_size * .5 * scale_factor, "front": false, "hub": hub}
		if hub: hubs.append(entry)
		else: tyres.append(entry)
	var rig: Dictionary = {"ok": false, "car": car, "wheels": [], "wheelbase": 0.0, "radius": 0.0, "tail_lights": []}
	if tyres.size() < 4: return rig
	var mean_z: float = 0.0
	for tyre: Dictionary in tyres:
		if float(tyre.axle_x) < AXLE_TOLERANCE: return rig
		mean_z += float(tyre.centre.z)
	mean_z /= float(tyres.size())
	var front_sum: float = 0.0
	var rear_sum: float = 0.0
	var front_count: int = 0
	var rear_count: int = 0
	var radius: float = 0.0
	for tyre: Dictionary in tyres:
		tyre["front"] = float(tyre.centre.z) > mean_z + .05
		if bool(tyre.front): front_sum += float(tyre.centre.z); front_count += 1
		elif float(tyre.centre.z) < mean_z - .05: rear_sum += float(tyre.centre.z); rear_count += 1
		radius = maxf(radius, float(tyre.radius))
	if front_count < 2 or rear_count < 2: return rig
	# A hub turns about the tyre it sits on: the nearest tyre on its side.
	for hub: Dictionary in hubs:
		var best: Dictionary = {}
		var best_distance: float = INF
		for tyre: Dictionary in tyres:
			var distance: float = (hub.centre as Vector3).distance_to(tyre.centre)
			if distance < best_distance: best_distance = distance; best = tyre
		if best.is_empty() or best_distance > .5: continue
		hub["centre"] = best.centre
		hub["front"] = best.front
		hub["radius"] = best.radius
	var wheels: Array = []
	wheels.append_array(tyres)
	for hub: Dictionary in hubs:
		if hub.centre is Vector3 and absf(float(hub.axle_x)) >= AXLE_TOLERANCE: wheels.append(hub)
	rig["wheels"] = wheels
	rig["wheelbase"] = front_sum / float(front_count) - rear_sum / float(rear_count)
	rig["radius"] = radius
	rig["ok"] = true
	var lights: Array = []
	for found: Node in car.find_children("*", "MeshInstance3D", true, false):
		if str(found.name).to_lower().contains("tail light") or str(found.name).to_lower().contains("tail lamp"): lights.append(found)
	rig["tail_lights"] = lights
	car.set_meta("vehicle_rig", rig)
	return rig


## Pose every wheel: `steer` is the front wheels' angle (radians, left positive as
## the path's own curvature), `rolled` the signed distance the car has covered.
static func apply(rig: Dictionary, steer: float, rolled: float) -> void:
	if not bool(rig.get("ok", false)): return
	var car: Node3D = rig.car
	if not is_instance_valid(car): return
	var car_scale: float = maxf(.01, car.scale.x)
	for wheel: Dictionary in rig.wheels:
		var node: Node3D = wheel.node
		if not is_instance_valid(node): continue
		var spin: float = rolled / maxf(.05, float(wheel.radius) * car_scale)
		var turn := Basis(Vector3.UP, steer if bool(wheel.front) else 0.0) * Basis(Vector3.RIGHT, spin)
		var centre: Vector3 = wheel.centre
		var about := Transform3D(turn, centre - turn * centre)
		var to_car: Transform3D = wheel.to_car
		node.transform = to_car.affine_inverse() * about * to_car * (wheel.rest as Transform3D)


## Put the wheels back as the model was authored.
static func reset(rig: Dictionary) -> void:
	apply(rig, 0.0, 0.0)


## Brake and reverse lights glow on the tail-light surfaces while the flag is set.
static func lights(rig: Dictionary, on: bool) -> void:
	if not bool(rig.get("ok", false)): return
	for node: Variant in rig.tail_lights:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if not is_instance_valid(mesh_node): continue
		if on:
			if mesh_node.has_meta("rig_lit"): continue
			var glow := StandardMaterial3D.new()
			glow.albedo_color = BRAKE_COLOUR
			glow.emission_enabled = true
			glow.emission = BRAKE_COLOUR
			glow.emission_energy_multiplier = 1.8
			mesh_node.material_override = glow
			mesh_node.set_meta("rig_lit", true)
		elif mesh_node.has_meta("rig_lit"):
			mesh_node.material_override = null
			mesh_node.remove_meta("rig_lit")
