extends SceneTree
## Contact suite: use the production age assets in an isolated import.
const Actor = preload("res://scripts/actor.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)
func run() -> void:
	for stage: String in ["child","teen","young_adult","elder"]:
		for frame: int in range(2):
			for detail: bool in [true,false]:
				var actor: LifeActor = Actor.new();root.add_child(actor)
				actor.configure({"age_stage":stage,"frame":frame,"low_detail":detail,"body_scale":.93,"height_scale":1.04})
				actor.voice_enabled = false
				var name_text: String = "%s frame%d lod%s" % [stage,frame,detail]
				check(not actor._grip_shapes.L.is_empty() and not actor._grip_shapes.R.is_empty(),name_text+": both authored independent grips import.")
				if stage != "child":
					var largest_angle: float = 0.0
					for i: int in range(360):
						actor.animate(1.0/60.0,1,false,"cook")
						if i > 90:
							var grip_axis: Vector3 = actor._joints.Forearm_R.global_basis.x.normalized()
							var handle_axis: Vector3 = (actor._spoon_tip.global_position-actor._cooking_spoon.global_position).normalized()
							largest_angle = maxf(largest_angle,rad_to_deg(acos(clampf(absf(grip_axis.dot(handle_axis)),0.0,1.0))))
					check(largest_angle < 8.0,name_text+": full stirring cycle keeps the spoon inside the finger channel; max angle="+str(largest_angle))
					check(actor._grip_amounts.R>.94 and actor._grip_amounts.L>.24,name_text+": handle uses full grip, bowl partial support.")
					var bowl_body: MeshInstance3D = actor._bowl_center.get_child(0) as MeshInstance3D
					var support: Vector3 = actor._joints.Forearm_L.to_global(actor._grip_offset("L"))
					var sphere_point: Vector3 = bowl_body.to_local(support)
					var radial_squared: float = sphere_point.x*sphere_point.x+sphere_point.z*sphere_point.z
					var base_y: float = -sqrt(maxf(0.0,1.0-radial_squared))
					var support_gap: float = (base_y-sphere_point.y)*bowl_body.global_basis.y.length()
					check(radial_squared<.5 and support_gap>=-.002 and support_gap<.022,name_text+": palm support lies beneath the real bowl base, not inside its side wall.")
					check(actor._joints.Forearm_L.global_basis.z.normalized().dot(Vector3.UP)>.88,name_text+": the supporting palm faces upward.")
					var hand_before: Transform3D = actor._joints.Forearm_R.global_transform
					var spoon_before: Transform3D = actor._cooking_spoon.global_transform
					actor.animate(.5,0,false,"cook")
					check(actor._joints.Forearm_R.global_transform.is_equal_approx(hand_before) and actor._cooking_spoon.global_transform.is_equal_approx(spoon_before),name_text+": pause freezes aligned fingers and utensil together.")
				actor._motion_action="";actor._action_time=0
				for i: int in range(115):actor.animate(1.0/60.0,1,false,"snack")
				var mouth: Vector3 = actor._joints.Head.to_global(actor._mouth_anchor)
				var food: Vector3 = actor._snack.to_global(Vector3(0,.029,-.011))
				check(mouth.distance_to(food)<.035,name_text+": partial eating grip preserves actual food/lip contact.")
				check(actor._grip_amounts.R>.44 and actor._grip_amounts.R<.46,name_text+": snack keeps a partial grip around its edge.")
				for i: int in range(90):actor.animate(1.0/60.0,1,true,"")
				check(actor._grip_amounts.R<.001 and actor._grip_amounts.L<.001,name_text+": walking releases both hands.")
				actor.queue_free();await process_frame
	print("ALIGNED GRIP TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
