extends SceneTree
## Fresh production-only character portraits, identity and creator-to-home QA.
## Run in the isolated character runner with a display. Output stays in user://.

const Identity = preload("res://scripts/character_identity.gd")
const OUT := "user://character62"
# Name the styles so a lineup cannot accidentally review a buzz cut as a bob.
const FACE_COMPARISON_STYLE := "Hair_Buzz"
const SURFACE_REVIEW_STYLE := "Hair_Bob"
var failures: Array[String] = []
var checks: int = 0
var app: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, explanation: String) -> void:
	checks += 1
	if not ok:
		failures.append(explanation)
		push_error(explanation)

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var file: String = OUT.path_join(label + ".png")
	var result: Error = root.get_texture().get_image().save_png(file)
	check(result == OK, "Captured " + label)
	print("CHARACTER62_SHOT ", ProjectSettings.globalize_path(file))

func present(person: Dictionary, tab: String, yaw: float = -.16) -> void:
	app.profile = person.duplicate(true)
	app.profile.erase("rig_preview")
	app.profile.erase("low_detail")
	app.creator_tab = tab
	app.creator_spin = yaw
	app.refresh_preview()
	app.preview.rotation.y = yaw
	app.preview.voice_enabled = false
	await frames()
	check(app.preview._model.scene_file_path.begins_with("res://assets/models/character"), "Production character selected")
	var hair_index: int = int(app.preview.profile.get("hair", 0))
	for index: int in LifeActor.HAIR_NAMES.size():
		var hair_root: Node3D = app.preview._model.find_child(LifeActor.HAIR_NAMES[index], true, false)
		if hair_root != null: check(hair_root.visible == (index == hair_index), "Only the selected hairstyle is visible: " + LifeActor.HAIR_NAMES[index])
	for feature: String in LifeActor.IDENTITY_KEYS:
		var entries: Array = app.preview._identity_shapes.get(feature, [])
		check(not entries.is_empty(), "Actual geometry supports " + feature)
		for entry: Dictionary in entries:
			check(is_equal_approx(entry.mesh.get_blend_shape_value(entry.index), float(person.get(feature, 0.0))), "Applied " + feature)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(5)
	var world_msaa: int = root.msaa_3d
	var world_scale: float = root.scaling_3d_scale
	app.show_creator()
	check(root.msaa_3d >= Viewport.MSAA_4X and root.scaling_3d_scale >= 1.0, "Portrait uses clean native-resolution edges")
	# Fixed neutral poses: elapsed test time cannot change the comparison.
	app.set_process(false)
	var people: Array = []
	for index: int in 6:
		var person: Dictionary = Identity.generate(61100 + index, {"gender":"female","age_stage":"young_adult"}, people)
		people.append(person)
		var neutral: Dictionary = person.duplicate(true)
		neutral.merge({"hair":LifeActor.HAIR_NAMES.find(FACE_COMPARISON_STYLE),"outfit":3,"skin_color":"d9a17d","hair_color":"473027","eye_color":"547365","top_color":"c5c5bd","body_scale":1.0,"height_scale":1.0},true)
		await present(neutral,"Face",0.0)
		await shot("identity_%02d_front" % index)
		await present(neutral,"Face",.68)
		await shot("identity_%02d_three_quarter" % index)
		await present(person,"Face",-.16)
		await shot("styled_%02d" % index)
	# Independently review the continuous bob, including recolours. The neutral
	# buzz-cut face comparison above deliberately keeps the jawline unobscured.
	var bob: Dictionary = people[0].duplicate(true)
	bob.merge({"hair":LifeActor.HAIR_NAMES.find(SURFACE_REVIEW_STYLE),"outfit":3,"skin_color":"d9a17d","hair_color":"473027","eye_color":"547365","body_scale":1.0,"height_scale":1.0},true)
	for angle: Dictionary in [{"name":"front","yaw":0.0},{"name":"three_quarter","yaw":.68},{"name":"back","yaw":PI}]:
		await present(bob,"Face",float(angle.yaw))
		await shot("bob_" + str(angle.name))
	for colour: Dictionary in [{"name":"blonde","hex":"ccb178"},{"name":"red","hex":"ad5636"},{"name":"grey","hex":"c9c7be"}]:
		bob.hair_color = colour.hex
		await present(bob,"Face",.68)
		await shot("bob_" + str(colour.name))
	# Profile ranges together, including negative signed features and Blink.
	for sign_value: float in [-1.0,1.0]:
		var extreme: Dictionary = people[0].duplicate(true)
		extreme.hair = LifeActor.HAIR_NAMES.find(FACE_COMPARISON_STYLE)
		for feature: String in LifeActor.IDENTITY_KEYS:
			extreme[feature] = sign_value if feature in LifeActor.SIGNED_IDENTITY_KEYS else maxf(0,sign_value)
		await present(extreme,"Face",.68)
		await shot("combined_%s" % ("minimum" if sign_value < 0 else "maximum"))
		for entry: Dictionary in app.preview._blink_shapes: entry.mesh.set_blend_shape_value(entry.index,1.0)
		await frames()
		await shot("combined_%s_blink" % ("minimum" if sign_value < 0 else "maximum"))
	for age: String in ["baby","child","teen","young_adult","adult","elder"]:
		var person: Dictionary = Identity.generate(2026 + age.hash(), {"age_stage":age,"gender":"male"})
		await present(person,"Face",.25)
		await shot("age_%s_face" % age)
		await present(person,"Look",.25)
		await shot("age_%s_body" % age)
	# The supported creator path still opens a home with the authored profile.
	app.household_profiles = [people[0].duplicate(true)]
	app.profile = app.household_profiles[0]
	app.creator_index = 0
	app.show_lot_selection()
	await frames()
	check(app.mode == "lots", "Creator leads to choosing a home")
	check(app.world.sun.light_energy > 0, "Outdoor daylight restored after portrait lighting")
	check(root.msaa_3d == world_msaa and is_equal_approx(root.scaling_3d_scale,world_scale), "Portrait quality restores the player's world rendering settings")
	app.start_household()
	await frames(8)
	check(app.mode == "live", "Household starts living")
	app.household.set_speed(0)
	await frames()
	await shot("live_home")
	var receipt: Dictionary = {"checks":checks,"failures":failures,"profiles":people,"method":"Actual production models rendered in Godot; fixed neutral pose comparisons plus creator-to-home path."}
	var file := FileAccess.open(OUT.path_join("receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"  "))
	file.close()
	print("CHARACTER62_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
