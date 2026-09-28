extends SceneTree
## Verify the actual bus meshes, materials, stop lamps, and route sockets.
## Add -- --render to save front/rear screenshots from the rendering viewport.

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)

func run() -> void:
	var bus: Node3D = LifeSchoolBusVisual.build()
	root.add_child(bus)
	var route := LifeSchoolBus.new()
	route.visual = bus
	for child: String in ["BusBody_Mesh", "Grille_Mesh", "FrontWindshield_Mesh", "SideWindows_Group", "BrakeLights_Mesh", "DoorSocket", "ExitSpawnPoint"]:
		check(bus.has_node(child), "Bus exposes named component: "+child)
	check(bus.get_node("SideWindows_Group").get_child_count() == 10, "Five passenger windows line each side.")
	var pane: MeshInstance3D = bus.get_node("SideWindows_Group/NearPassengerWindow1/Glass")
	var glass: StandardMaterial3D = pane.material_override
	check(glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and glass.albedo_color.a >= 0.15 and glass.albedo_color.a <= 0.30, "Passenger glass transmits light at 15–30 percent opacity.")
	check(glass.albedo_texture != null and glass.roughness < 0.25, "Glass has a subtle reflection map and polished response.")
	var paint: StandardMaterial3D = bus.get_node("BusBody_Mesh/Hood").material_override
	check(paint.albedo_color.r > 0.9 and paint.albedo_color.g > 0.9 and paint.albedo_color.b > 0.9, "Bus body uses clean white paint.")
	for side: String in ["Near", "Far"]:
		var logo: Node3D = bus.get_node("BusBody_Mesh/"+side+"Trefoil")
		check(logo.find_children("Leaf*", "MeshInstance3D", false, false).size() == 3, side+" logo has exactly three leaves.")
	var lamps: Array[Node] = bus.get_node("BrakeLights_Mesh").find_children("BrakeLamp*", "MeshInstance3D", false, false)
	check(lamps.size() == 4, "Paired upper and lower rear brake lamps are present.")
	var brakes: StandardMaterial3D = lamps[0].material_override
	var other_bus: Node3D = LifeSchoolBusVisual.build()
	var other_brakes: StandardMaterial3D = other_bus.get_node("BrakeLights_Mesh").get_meta("brake_material")
	for phase: String in ["approaching", "waiting", "departing", "returning", "dropping", "leaving"]:
		route.phase = phase
		route.position = LifeSchoolBus.CURB
		bus.position = route.position
		bus.rotation.y = PI if phase in ["returning", "dropping", "leaving"] else 0.0
		LifeSchoolBusVisual.sync(bus, phase)
		var stopped: bool = phase in ["waiting", "dropping"]
		check(brakes.emission_enabled and (brakes.emission_energy_multiplier > 3.0) == stopped, "Brake glow follows actual travel phase: "+phase)
		check(route.door_position().is_equal_approx(bus.get_node("DoorSocket").global_position), "Boarding uses live DoorSocket in "+phase)
		check(route.exit_position().is_equal_approx(bus.get_node("ExitSpawnPoint").global_position), "Drop-off uses live ExitSpawnPoint in "+phase)
		check(route.door_position().z < LifeSchoolBus.CURB.z-1.4 and route.exit_position().z < route.door_position().z, "Door and exit stay clear of the bus on the house side: "+phase)
	check(other_brakes.emission_energy_multiplier < 0.1, "Bus instances never share mutable brake state.")
	other_bus.free()
	if OS.get_cmdline_user_args().has("--render"):
		check(DisplayServer.get_name() != "headless", "Actual renderer is required for bus captures.")
		if DisplayServer.get_name() != "headless":
			await render_bus(bus)
	bus.free()
	print("SCHOOL_BUS_VISUAL %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func render_bus(bus: Node3D) -> void:
	root.size = Vector2i(1440, 900)
	bus.position = Vector3.ZERO
	bus.rotation = Vector3.ZERO
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("d6dedc")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e5eff0")
	environment.environment.ambient_light_energy = 0.25
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -26, 0)
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.position.y = -0.01
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b5c3bd")
	ground.material_override = material
	root.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.9
	camera.current = true
	root.add_child(camera)
	var directory: String = "/tmp/justlife-goal-bus"
	DirAccess.make_dir_recursive_absolute(directory)
	for view: String in ["front", "rear_driving", "rear_braking"]:
		camera.position = Vector3(-8, 4.4, -9) if view == "front" else Vector3(8, 4.1, -9)
		camera.look_at(Vector3(-0.1, 1.3, 0))
		LifeSchoolBusVisual.sync(bus, "waiting" if view == "rear_braking" else "approaching")
		for frame: int in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = directory+"/"+view+".png"
		check(root.get_texture().get_image().save_png(path) == OK, "Saved actual bus viewport: "+view)
	print("BUS_RENDER_PATH "+ProjectSettings.globalize_path(directory))
