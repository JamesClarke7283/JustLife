extends RefCounted
class_name LifeSchoolBusVisual
## Original procedural bus, facing local -X. Kept in one reusable component so
## the curb controller and a visual inspection scene use the same model.

const DOOR_LOCAL := Vector3(-1.82, 0.0, -1.48)
const EXIT_LOCAL := Vector3(-1.82, 0.0, -1.85)
const GLASS_OPACITY := 0.24

static func build() -> Node3D:
	var bus := Node3D.new()
	bus.name = "BusRoot"
	bus.set_meta("livery", true)
	var paint := _material("CleanWhitePaint", "f4f7f2", 0.3)
	var green := _material("GreenStripe", "287644", 0.35)
	var rubber := _material("RubberTrim", "20282a", 0.82)
	var metal := _material("BrushedMetal", "98a5a8", 0.3, 0.7)
	var glass := _glass()
	var body := _group(bus, "BusBody_Mesh")
	_box(body, "Chassis", Vector3(0, 0.48, 0), Vector3(6.15, 0.26, 1.95), rubber)
	_box(body, "PassengerFloor", Vector3(0.45, 0.73, 0), Vector3(5.3, 0.16, 2.05), rubber)
	_box(body, "RearPanel", Vector3(3.1, 1.65, 0), Vector3(0.12, 1.9, 2.15), paint)
	_box(body, "Hood", Vector3(-2.76, 1.07, 0), Vector3(1.14, 0.82, 2.04), paint)
	_box(body, "HoodTop", Vector3(-2.73, 1.5, 0), Vector3(1.16, 0.12, 2.08), paint)
	_box(body, "Roof", Vector3(0.4, 2.61, 0), Vector3(5.6, 0.18, 2.18), paint)
	_box(body, "RoofCrown", Vector3(0.4, 2.72, 0), Vector3(5.32, 0.1, 1.94), paint)
	var side_windows := _group(bus, "SideWindows_Group")
	var doors := _group(bus, "PassengerDoors")
	for side: float in [-1.0, 1.0]:
		var label: String = "Near" if side < 0.0 else "Far"
		_box(body, label+"LowerPanel", Vector3(0.9, 1.1, side*1.03), Vector3(4.5, 0.76, 0.12), paint)
		_box(body, label+"GreenStripe", Vector3(0.9, 1.19, side*1.097), Vector3(4.49, 0.37, 0.012), green)
		_box(body, label+"LowerRail", Vector3(0.9, 0.84, side*1.104), Vector3(4.49, 0.065, 0.028), rubber)
		_box(body, label+"WindowSill", Vector3(0.9, 1.51, side*1.04), Vector3(4.5, 0.1, 0.13), paint)
		_box(body, label+"RoofRail", Vector3(0.4, 2.48, side*1.055), Vector3(5.54, 0.11, 0.13), paint)
		for index: int in 5:
			var x: float = -0.9+index*0.87
			_window(side_windows, label+"PassengerWindow"+str(index+1), Vector3(x, 2.0, side*1.106), Vector2(0.76, 0.83), side, glass, rubber)
			_box(body, label+"Pillar"+str(index), Vector3(x+0.415, 1.98, side*1.047), Vector3(0.09, 0.93, 0.13), paint)
		_box(body, label+"FrontPillar", Vector3(-2.32, 1.98, side*1.036), Vector3(0.13, 0.98, 0.13), paint)
		_box(body, label+"DoorPillar", Vector3(-1.36, 1.84, side*1.046), Vector3(0.14, 1.28, 0.13), paint)
		_trefoil(body, label+"Trefoil", Vector3(0.6, 1.2, side*1.113), side, paint)
		# A curb door on each side keeps the same safe sidewalk access when the
		# afternoon route faces the opposite direction.
		var door := _group(doors, label+"Door")
		door.position = Vector3(-1.82, 1.5, side*1.105)
		for edge: float in [-0.393, 0.0, 0.393]:
			_box(door, "Upright"+str(edge), Vector3(edge, 0, 0), Vector3(0.035, 1.84, 0.06), rubber)
		for height: float in [-0.92, -0.065, 0.92]:
			_box(door, "Rail"+str(height), Vector3(0, height, 0), Vector3(0.82, 0.035, 0.06), rubber)
		for panel: int in 2:
			var dx: float = -0.194+panel*0.388
			_box(door, "WhitePanel"+str(panel), Vector3(dx, -0.48, side*0.041), Vector3(0.35, 0.72, 0.025), paint)
			_pane(door, "DoorGlass"+str(panel), Vector3(dx, 0.35, side*0.044), Vector2(0.32, 0.8), 0.0 if side > 0 else PI, glass)
		_box(body, label+"EntryStep", Vector3(-1.82, 0.43, side*1.13), Vector3(0.89, 0.13, 0.38), metal)
		_box(body, label+"MirrorArm", Vector3(-2.45, 2.02, side*1.16), Vector3(0.16, 0.065, 0.35), rubber)
		_box(body, label+"Mirror", Vector3(-2.46, 2.06, side*1.35), Vector3(0.14, 0.32, 0.2), rubber)
		_box(body, label+"MirrorFace", Vector3(-2.378, 2.06, side*1.35), Vector3(0.015, 0.27, 0.15), metal)
	_front(bus, rubber, metal, glass)
	_interior(bus, rubber)
	_wheels(bus, rubber, metal)
	_rear(bus, rubber)
	var door_socket := Marker3D.new()
	door_socket.name = "DoorSocket"
	door_socket.position = DOOR_LOCAL
	bus.add_child(door_socket)
	var exit_socket := Marker3D.new()
	exit_socket.name = "ExitSpawnPoint"
	exit_socket.position = EXIT_LOCAL
	bus.add_child(exit_socket)
	sync(bus, "approaching")
	return bus

static func sync(bus: Node3D, phase: String) -> void:
	var stopped: bool = phase in ["waiting", "dropping"]
	var returning: bool = phase in ["returning", "dropping", "leaving"]
	var lights: Node3D = bus.get_node("BrakeLights_Mesh")
	var material: StandardMaterial3D = lights.get_meta("brake_material")
	material.emission_energy_multiplier = 3.2 if stopped else 0.08
	bus.set_meta("braking", stopped)
	# Model-space curb side changes when the vehicle turns, but the actual
	# interaction markers and exit remain on the house side of the road.
	var side: float = 1.0 if returning else -1.0
	bus.get_node("DoorSocket").position = Vector3(DOOR_LOCAL.x, 0, absf(DOOR_LOCAL.z)*side)
	bus.get_node("ExitSpawnPoint").position = Vector3(EXIT_LOCAL.x, 0, absf(EXIT_LOCAL.z)*side)
	for door: Node3D in bus.get_node("PassengerDoors").get_children():
		var curb_door: bool = (door.name == "NearDoor") == (side < 0.0)
		door.visible = not (stopped and curb_door)

static func _front(bus: Node3D, rubber: Material, metal: Material, glass: Material) -> void:
	var windshield := _group(bus, "FrontWindshield_Mesh")
	# Two panes span almost the whole cabin width, with a rubber gasket and
	# center divider. The cabin remains open behind the translucent glass.
	for side: float in [-1.0, 1.0]:
		_pane(windshield, "WindshieldLeft" if side < 0 else "WindshieldRight", Vector3(-2.391, 2.0, side*0.497), Vector2(0.918, 0.87), -PI/2.0, glass)
		_box(windshield, "OuterTrim"+str(side), Vector3(-2.399, 2.0, side*0.986), Vector3(0.062, 0.95, 0.062), rubber)
		var wiper := _box(windshield, "Wiper"+str(side), Vector3(-2.429, 1.735, side*0.48), Vector3(0.03, 0.033, 0.63), rubber)
		wiper.rotation.x = side*0.13
	_box(windshield, "CenterRubberTrim", Vector3(-2.399, 2.0, 0), Vector3(0.062, 0.95, 0.062), rubber)
	for height: float in [1.535, 2.465]:
		_box(windshield, "HorizontalTrim"+str(height), Vector3(-2.399, height, 0), Vector3(0.062, 0.065, 2.03), rubber)
	_box(bus, "DestinationPanel", Vector3(-2.399, 2.64, 0), Vector3(0.045, 0.22, 1.5), green_material())
	_text(bus, "SchoolBusFront", "SCHOOL BUS", Vector3(-2.43, 2.64, 0), -PI/2.0, 0.0025)
	var grille := _group(bus, "Grille_Mesh")
	_box(grille, "IntakeRecess", Vector3(-3.341, 1.025, 0), Vector3(0.05, 0.57, 1.42), rubber)
	for slat: int in 6:
		_box(grille, "HorizontalSlat"+str(slat), Vector3(-3.375, 0.795+slat*0.089, 0), Vector3(0.033, 0.028, 1.33), metal)
	_box(grille, "FrontBumperBar", Vector3(-3.44, 0.59, 0), Vector3(0.22, 0.25, 2.19), rubber)
	for side: float in [-1.0, 1.0]:
		_box(grille, "BumperMount"+str(side), Vector3(-3.36, 0.59, side*0.64), Vector3(0.3, 0.13, 0.12), metal)
		var lamp := _material("Headlamp", "fff7d7", 0.15)
		lamp.emission_enabled = true
		lamp.emission = Color("fff0be")
		lamp.emission_energy_multiplier = 0.25
		_box(bus, "HeadlightHousing"+str(side), Vector3(-3.355, 1.09, side*0.874), Vector3(0.06, 0.35, 0.3), rubber)
		_box(bus, "Headlight"+str(side), Vector3(-3.393, 1.09, side*0.874), Vector3(0.035, 0.25, 0.22), lamp)

static func _rear(bus: Node3D, rubber: Material) -> void:
	var lights := _group(bus, "BrakeLights_Mesh")
	var brake := _material("EmissiveRedBrakeLights", "ac1022", 0.22)
	brake.emission_enabled = true
	brake.emission = Color("ff0401")
	lights.set_meta("brake_material", brake)
	_box(bus, "RearBumper", Vector3(3.2, 0.61, 0), Vector3(0.24, 0.24, 2.2), rubber)
	_box(bus, "RearGreenStripe", Vector3(3.168, 1.19, 0), Vector3(0.012, 0.37, 2.14), green_material())
	for side: float in [-1.0, 1.0]:
		for height: float in [0.87, 2.34]:
			_box(lights, "Housing"+str(side)+str(height), Vector3(3.184, height, side*0.85), Vector3(0.1, 0.27, 0.25), rubber)
			_box(lights, "BrakeLamp"+str(side)+str(height), Vector3(3.245, height, side*0.85), Vector3(0.04, 0.19, 0.18), brake)
	_box(bus, "RearWindowGasket", Vector3(3.176, 1.94, 0), Vector3(0.025, 0.54, 1.41), rubber)
	_box(bus, "RearWindow", Vector3(3.193, 1.94, 0), Vector3(0.012, 0.45, 1.3), _material("RearWindowTint", "637d86", 0.2))
	_text(bus, "SchoolBusRear", "SCHOOL BUS", Vector3(3.2, 1.48, 0), PI/2.0, 0.0026)

static func _interior(bus: Node3D, rubber: Material) -> void:
	var interior := _group(bus, "Interior")
	var seat := _material("GreenUpholstery", "335e50", 0.9)
	for row: int in 5:
		for side: float in [-1.0, 1.0]:
			var x: float = -0.74+row*0.78
			_box(interior, "Seat"+str(row)+str(side), Vector3(x, 1.07, side*0.64), Vector3(0.54, 0.16, 0.63), seat)
			_box(interior, "SeatBack"+str(row)+str(side), Vector3(x+0.25, 1.41, side*0.64), Vector3(0.1, 0.7, 0.63), seat)
	_box(interior, "Dashboard", Vector3(-2.21, 1.55, 0), Vector3(0.29, 0.19, 1.9), rubber)

static func _wheels(bus: Node3D, rubber: Material, metal: Material) -> void:
	var group := _group(bus, "Wheels")
	for axle: float in [-2.78, 2.03]:
		for side: float in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			wheel.name = "Tyre"+str(axle)+str(side)
			var tyre := CylinderMesh.new()
			tyre.top_radius = 0.45
			tyre.bottom_radius = 0.45
			tyre.height = 0.25
			tyre.radial_segments = 24
			wheel.mesh = tyre
			wheel.material_override = rubber
			wheel.position = Vector3(axle, 0.45, side*1.09)
			wheel.rotation.x = PI/2.0
			group.add_child(wheel)
			var hub := MeshInstance3D.new()
			var hub_mesh := CylinderMesh.new()
			hub_mesh.top_radius = 0.25
			hub_mesh.bottom_radius = 0.25
			hub_mesh.height = 0.028
			hub_mesh.radial_segments = 16
			hub.mesh = hub_mesh
			hub.material_override = metal
			hub.position = Vector3(axle, 0.45, side*1.226)
			hub.rotation.x = PI/2.0
			group.add_child(hub)

static func _trefoil(parent: Node3D, name: String, at: Vector3, side: float, material: Material) -> void:
	var logo := _group(parent, name)
	logo.position = at
	logo.rotation.y = 0.0 if side > 0.0 else PI
	# Exactly three heart-shaped leaves, each tapering into a shared center.
	for leaf: int in 3:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points := PackedVector3Array()
		var angle: float = leaf*TAU/3.0
		for index: int in 33:
			var t: float = float(index)*TAU/32.0
			var x: float = 0.072*pow(sin(t), 3)
			var y: float = 0.075+(13*cos(t)-5*cos(2*t)-2*cos(3*t)-cos(4*t))*0.0048
			points.append(Vector3(x*cos(angle)-y*sin(angle), x*sin(angle)+y*cos(angle)+0.015, 0))
		for index: int in 32:
			for point: Vector3 in [Vector3(-sin(angle)*0.068, cos(angle)*0.068+0.015, 0), points[index], points[index+1]]:
				surface.set_normal(Vector3.FORWARD)
				surface.add_vertex(point)
		var mesh := MeshInstance3D.new()
		mesh.name = "Leaf"+str(leaf+1)
		mesh.mesh = surface.commit()
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		logo.add_child(mesh)
	var stem := _box(logo, "Stem", Vector3(0.018, -0.098, 0), Vector3(0.022, 0.112, 0.005), material)
	stem.rotation.z = -0.25

static func _glass() -> StandardMaterial3D:
	var glass := _material("TintedReflectiveGlass24Percent", "86b5c2", 0.18, 0.12)
	glass.albedo_color.a = GLASS_OPACITY
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.metallic_specular = 0.7
	# A subtle original reflection map gives a readable sky sheen even in the
	# compatibility renderer, while environment reflections supply live light.
	var map := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.68, 0.8, 0.87), Color(0.96, 1, 1), Color(0.75, 0.86, 0.92)])
	gradient.offsets = PackedFloat32Array([0.0, 0.36, 1.0])
	map.gradient = gradient
	map.fill_from = Vector2(0, 0)
	map.fill_to = Vector2(0.55, 1)
	glass.albedo_texture = map
	return glass

static func green_material() -> StandardMaterial3D:
	return _material("GreenStripe", "287644", 0.35)

static func _window(parent: Node3D, name: String, at: Vector3, size: Vector2, side: float, glass: Material, rubber: Material) -> void:
	var window := _group(parent, name)
	window.position = at
	for x: float in [-size.x/2, size.x/2]:
		_box(window, "VerticalTrim"+str(x), Vector3(x, 0, 0), Vector3(0.034, size.y+0.04, 0.035), rubber)
	for y: float in [-size.y/2, size.y/2]:
		_box(window, "HorizontalTrim"+str(y), Vector3(0, y, 0), Vector3(size.x+0.03, 0.034, 0.035), rubber)
	_pane(window, "Glass", Vector3.ZERO, size, 0.0 if side > 0 else PI, glass)

static func _pane(parent: Node3D, name: String, at: Vector3, size: Vector2, yaw: float, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = name
	var mesh := QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.rotation.y = yaw
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

static func _group(parent: Node3D, name: String) -> Node3D:
	var node := Node3D.new()
	node.name = name
	parent.add_child(node)
	return node

static func _material(name: String, hex: String, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_color = Color(hex)
	material.roughness = roughness
	material.metallic = metallic
	return material

static func _box(parent: Node3D, name: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

static func _text(parent: Node3D, name: String, text: String, at: Vector3, yaw: float, pixels: float) -> void:
	var label := Label3D.new()
	label.name = name
	label.text = text
	label.font_size = 54
	label.pixel_size = pixels
	label.modulate = Color("f4f7f2")
	label.outline_size = 0
	label.position = at
	label.rotation.y = yaw
	parent.add_child(label)
