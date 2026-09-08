extends SceneTree
const Actor = preload("res://scripts/actor.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	for stage: String in ["child","teen","young_adult","elder"]:
		for frame: int in range(2):
			var actor: LifeActor = Actor.new();root.add_child(actor)
			actor.configure({"name":"Age QA","age_stage":stage,"frame":frame,"low_detail":true,"outfit":frame,"height_scale":1.05,"body_scale":1.1})
			actor.voice_enabled = false
			var expected: float = {"child":1.18,"teen":1.55,"young_adult":1.76,"elder":1.72}[stage]
			check(absf(actor.get_display_height()-expected*1.05) < .002,"Display height must come from the distinct authored age model.")
			check(actor._rig_bones.size() == 9,"Every age and frame must retain nine usable skeletal joints.")
			if stage != "young_adult": check(actor._model.scene_file_path.contains("character_"+stage),"Age selection must use its distinct mesh file, not a scaled adult.")
			var landmarks: Dictionary = actor.get_body_landmarks()
			check(landmarks.age_stage == stage or (stage == "young_adult" and landmarks.age_stage == "adult"),"Reported landmarks must identify the actual age model; young adults share the adult mesh.")
			check(actor.get_portrait_center().y < actor.get_display_height() and actor.get_portrait_center().y > actor.get_display_height()*.7,"Portrait center must follow the actual head height.")
			actor.position = Vector3(2,.16,3);actor.rotation.y = .5
			var nav: Transform3D = actor.transform
			var anchor: Vector3 = Vector3(1,.68,2)
			actor.set_activity_anchor(anchor,-.3,"seat","school")
			for i: int in range(180):actor.animate(1.0/60.0,1,false,"school")
			check(actor.visual.to_global(Vector3(0,actor._hip_height,0)).distance_to(anchor) < .015,"Age-specific hips must settle on the shared chair top.")
			check(actor._sit_amount > .999,"Online classes must use the seated clothing corrective when a chair exists.")
			actor.set_activity_anchor(Vector3(1,.16,2),-.3,"standing","homework")
			for i: int in range(180):actor.animate(1.0/60.0,1,false,"homework")
			check(actor._book.visible and actor._sit_amount < .001,"Bookshelf homework must use a standing reading pose at every age.")
			check(absf(actor._joints.Leg_L.rotation.x) < .01,"Standing homework must not leave folded legs.")
			actor.set_activity_anchor(anchor,-.3,"bed","sleep")
			for i: int in range(180):actor.animate(1.0/60.0,1,false,"sleep")
			check(actor.visual.to_global(Vector3(0,actor._hip_height,-.10*actor._proportion)).distance_to(anchor) < .015,"Age-specific body support must meet the bed surface.")
			actor.clear_activity_anchor();actor._motion_action="";actor._action_time=0
			for i: int in range(115):actor.animate(1.0/60.0,1,false,"snack")
			var head: Node3D = actor._joints.Head
			var mouth: Vector3 = actor._model.to_local(head.to_global(actor._mouth_anchor))
			var contact: Vector3 = actor._model.to_local(actor._snack.to_global(Vector3(0,.029,-.011)))
			check(mouth.distance_to(contact) < .035,"Age-specific snack hand targeting must still bring the food edge to the lips.")
			var pose: Transform3D = actor.visual.transform;var snack: Transform3D = actor._snack.global_transform
			actor.animate(.5,0,true,"")
			check(actor.visual.transform.is_equal_approx(pose) and actor._snack.global_transform.is_equal_approx(snack),"Age-specific posing must freeze in pause.")
			check(actor.transform.is_equal_approx(nav),"Age-specific support must preserve navigation ownership.")
			for feature: String in Actor.IDENTITY_KEYS:
				actor.set_face_feature(feature,.8)
				check(not actor._identity_shapes.get(feature,[]).is_empty(),"Every age must preserve real coupled facial controls.")
			actor.queue_free()
	await process_frame;await create_timer(.2).timeout
	print("AGE ACTOR TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
