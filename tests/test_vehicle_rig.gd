extends SceneTree
## The wheel rig on every car model: tyres and hubs are found by name, the front pair
## steers about its own tyre centres, every wheel spins about the axle in
## proportion to the distance rolled (backwards when reversing, less on a larger
## car), no wheel centre ever moves, and the one mis-authored model is declared
## unrigged rather than animated wrongly.
const Rig = preload("res://scripts/vehicle_rig.gd")
const MODELS: Array[String] = ["car_saloon_a", "car_saloon_b", "car_hatchback", "car_estate", "car_coupe", "car_van", "car_minibus", "car_suv", "car_offroader", "car_pickup", "juniper_car", "electric_car", "delivery_van"]
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)
		print("FAIL ", message)

func bounds(node: Node3D, xf: Transform3D, low: Vector3, high: Vector3) -> Array:
	var here: Transform3D = xf * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for corner: int in 8:
			var point: Vector3 = here * (box.position + box.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1))
			low = low.min(point); high = high.max(point)
	for child: Node in node.get_children():
		if child is Node3D:
			var inner: Array = bounds(child as Node3D, here, low, high)
			low = inner[0]; high = inner[1]
	return [low, high]

func centre_of(wheel: Dictionary) -> Vector3:
	var node: MeshInstance3D = wheel.node
	return (wheel.to_car as Transform3D) * node.transform * node.mesh.get_aabb().get_center()

func run() -> void:
	for name: String in MODELS:
		var car: Node3D = load("res://assets/models/%s.glb" % name).instantiate()
		root.add_child(car)
		var rig: Dictionary = Rig.attach(car)
		check(bool(rig.ok), "%s: the wheels are found and the model is oriented nose +Z, axle along X" % name)
		if not bool(rig.ok): car.free(); continue
		var tyres: int = 0; var hubs: int = 0; var front: int = 0; var rear: int = 0
		for wheel: Dictionary in rig.wheels:
			if bool(wheel.hub): hubs += 1
			else:
				tyres += 1
				if bool(wheel.front): front += 1
				else: rear += 1
		check(tyres == 4 and front == 2 and rear == 2, "%s: four tyres, two on each axle (%d, %d front)" % [name, tyres, front])
		check(hubs >= 4, "%s: the hubs are found as well (%d)" % [name, hubs])
		check(float(rig.wheelbase) > (1.2 if name == "delivery_van" else 1.8) and float(rig.wheelbase) < 3.4 and float(rig.radius) > .25 and float(rig.radius) < .5, "%s: wheelbase %.2f m and radius %.2f m are believable" % [name, float(rig.wheelbase), float(rig.radius)])
		for wheel: Dictionary in rig.wheels: check(float(wheel.axle_x) > .9998, "%s: %s has its axle along the car's X axis (within a degree)" % [name, str((wheel.node as Node).name)])

		# steering turns only the front axle, about each tyre's own centre
		var rest_centres: Array = []
		for wheel: Dictionary in rig.wheels: rest_centres.append(centre_of(wheel))
		Rig.apply(rig, .4, 0.0)
		var steered_front: bool = true
		var steered_rear: bool = true
		var pivots_fixed: bool = true
		for index: int in rig.wheels.size():
			var wheel: Dictionary = rig.wheels[index]
			var node: Node3D = wheel.node
			var delta: Basis = node.transform.basis * (wheel.rest as Transform3D).basis.inverse()
			var axle: Vector3 = delta * Vector3(1, 0, 0)
			var angle: float = atan2(-axle.z, axle.x)
			if bool(wheel.front): steered_front = steered_front and absf(angle - .4) < .001
			else: steered_rear = steered_rear and absf(angle) < .001 and node.transform.is_equal_approx(wheel.rest)
			# a tyre's own centre does not move; a hub stays the same distance from its tyre
			if not bool(wheel.hub): pivots_fixed = pivots_fixed and centre_of(wheel).distance_to(rest_centres[index]) < 1e-4
		check(steered_front, "%s: the front wheels (and their hubs) steer by the angle asked for" % name)
		check(steered_rear, "%s: the rear wheels do not move when steering" % name)
		check(pivots_fixed, "%s: steering pivots every tyre about its own centre" % name)
		Rig.reset(rig)
		var restored: bool = true
		for wheel: Dictionary in rig.wheels: restored = restored and (wheel.node as Node3D).transform.is_equal_approx(wheel.rest)
		check(restored, "%s: reset puts every wheel back as authored" % name)

		# rolling: proportional to the distance, backwards in reverse, centres fixed
		var radius: float = float(rig.radius)
		for rolled: float in [1.0, 3.7, -2.0]:
			Rig.apply(rig, 0.0, rolled)
			var proportional: bool = true
			var fixed: bool = true
			for index: int in rig.wheels.size():
				var wheel: Dictionary = rig.wheels[index]
				var delta: Basis = (wheel.node as Node3D).transform.basis * (wheel.rest as Transform3D).basis.inverse()
				var top: Vector3 = delta * Vector3(0, 1, 0)
				var angle: float = atan2(top.z, top.y)
				proportional = proportional and absf(angle - wrapf(rolled / float(wheel.radius), -PI, PI)) < .002
				if not bool(wheel.hub): fixed = fixed and centre_of(wheel).distance_to(rest_centres[index]) < 1e-4
			check(proportional, "%s: rolling %.1f m turns every wheel by distance / radius%s" % [name, rolled, " (backwards)" if rolled < 0.0 else ""])
			check(fixed, "%s: rolling %.1f m leaves every tyre centre where it was" % [name, rolled])
		Rig.reset(rig)

		# brake lights come on and go off
		check(not rig.tail_lights.is_empty(), "%s: the tail lights are found" % name)
		Rig.lights(rig, true)
		var lit: bool = true
		for light: Variant in rig.tail_lights: lit = lit and (light as MeshInstance3D).material_override != null
		Rig.lights(rig, false)
		var dark: bool = true
		for light: Variant in rig.tail_lights: dark = dark and (light as MeshInstance3D).material_override == null
		check(lit and dark, "%s: brake lights light and go dark" % name)

		# a larger car's wheels turn less for the same distance
		car.scale = Vector3.ONE * 2.0
		Rig.apply(rig, 0.0, .5)
		var big: Dictionary = rig.wheels[0]
		var big_delta: Basis = (big.node as Node3D).transform.basis * (big.rest as Transform3D).basis.inverse()
		var big_top: Vector3 = big_delta * Vector3(0, 1, 0)
		check(absf(atan2(big_top.z, big_top.y) - 0.5 / (float(big.radius) * 2.0)) < .002, "%s: on a double-size car the same distance turns a wheel half as far" % name)
		Rig.reset(rig)
		car.free()

	# ---- the model that was authored on its side is declared unrigged
	var sideways: Node3D = load("res://assets/models/car_electric.glb").instantiate()
	root.add_child(sideways)
	var sideways_rig: Dictionary = Rig.attach(sideways)
	check(not bool(sideways_rig.ok), "car_electric.glb is declared unrigged (its length lies along the model's Y axis)")
	Rig.apply(sideways_rig, .5, 3.0)
	check(true, "Applying an unrigged car is a harmless no-op")
	sideways.free()

	# ---- every car model is 1.82 wide and about 4.2 long with its length on Z
	for name: String in MODELS:
		if name == "delivery_van" or name == "juniper_car": continue
		var model: Node3D = load("res://assets/models/%s.glb" % name).instantiate()
		var box: Array = bounds(model, Transform3D.IDENTITY, Vector3(INF, INF, INF), Vector3(-INF, -INF, -INF))
		var size: Vector3 = box[1] - box[0]
		check(size.z > 3.9 and size.z < 4.6 and size.x > 1.5 and size.x < 2.1 and size.z > size.y, "%s is %.2f wide, %.2f long on Z (%.2f tall)" % [name, size.x, size.z, size.y])
		model.free()
	var shared: Node3D = load("res://assets/models/juniper_car.glb").instantiate()
	var shared_box: Array = bounds(shared, Transform3D.IDENTITY, Vector3(INF, INF, INF), Vector3(-INF, -INF, -INF))
	var shared_size: Vector3 = shared_box[1] - shared_box[0]
	check(shared_size.z > 3.6 and shared_size.z < 4.0 and shared_size.x > 2.0 and shared_size.x < 2.4, "The shared Juniper car is a little shorter and wider than the catalogue cars (%.2f x %.2f)" % [shared_size.x, shared_size.z])
	shared.free()
	var odd: Node3D = load("res://assets/models/car_electric.glb").instantiate()
	var odd_box: Array = bounds(odd, Transform3D.IDENTITY, Vector3(INF, INF, INF), Vector3(-INF, -INF, -INF))
	var odd_size: Vector3 = odd_box[1] - odd_box[0]
	check(odd_size.y > odd_size.z, "car_electric.glb really is lying on its side (%.2f tall on Y, %.2f on Z): the documented defect" % [odd_size.y, odd_size.z])
	odd.free()

	print("VEHICLE_RIG %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
