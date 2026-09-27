extends SceneTree
## Standalone visual check of the exact runtime pet joints and authored props.
var scene: Node3D
func _initialize() -> void:
	run.call_deferred()
func furnishing(kind: String, at: Vector3) -> void:
	var object: Node3D = load("res://assets/models/%s.glb" % kind).instantiate()
	scene.add_child(object)
	object.position = at
func pet(species: String, at: Vector3, pose: String, yaw: float = 0.0) -> void:
	var actor := LifePetActor.new()
	actor.configure("capture_" + str(scene.get_child_count()), species, LifePets.appearance(LifePets.candidate(1, 0 if species == "cat" else 1)), species.capitalize())
	scene.add_child(actor)
	actor.position = at
	actor.rotation.y = yaw
	actor.set_behavior(pose, 16.5)
	for n: int in 60: actor.animate(1.0 / 60.0, false, 1.0)
func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("eadfcb")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff1df")
	environment.environment.ambient_light_energy = .35
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = .65
	light.shadow_enabled = true
	scene.add_child(light)
	var floor := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8, .06, 5)
	floor.mesh = mesh
	floor.position.y = -.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8eac86")
	floor.material_override = material
	scene.add_child(floor)
	var closeup: bool = "--rest-closeup" in OS.get_cmdline_user_args()
	if closeup:
		furnishing("pet_bed_dog", Vector3(-.65, 0, 0))
		pet("dog", Vector3(-.65, .13, 0), "rest")
		furnishing("pet_bed_cat", Vector3(.65, 0, 0))
		pet("cat", Vector3(.65, .10, 0), "rest")
	else:
		furnishing("pet_bed_dog", Vector3(-2.2, 0, -.7))
		pet("dog", Vector3(-2.2, .13, -.7), "rest")
		furnishing("kennel", Vector3(-.4, 0, -.7))
		pet("dog", Vector3(-.4, .10, -.68), "rest")
		furnishing("cat_tree", Vector3(1.5, 0, -.7))
		pet("cat", Vector3(1.5, 1.25, -.81), "tree_play")
		furnishing("cat_toy_box", Vector3(-1.8, 0, 1.3))
		furnishing("pet_toy_cat", Vector3(-.6, 0, 1.63))
		pet("cat", Vector3(-.6, 0, 1.3), "toy_play")
		furnishing("pet_toy_dog", Vector3(1.0, 0, 1.83))
		pet("dog", Vector3(1.0, 0, 1.3), "toy_play")
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(5.2, 4.5, 7.3)
	camera.look_at(Vector3(-.3, .3, .1))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.8
	if closeup:
		camera.position = Vector3(2.3, 1.7, 3.8)
		camera.look_at(Vector3(0, .15, 0))
		camera.size = 2.8
	camera.current = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	var error: Error = screenshot.save_png("/tmp/justlife-pet-rest.png" if closeup else "/tmp/justlife-pet-behaviors.png")
	print("PET_VISUAL_CAPTURE ", error)
	quit(error)
