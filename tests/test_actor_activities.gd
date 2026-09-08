extends SceneTree
## Run in an isolated project with imported standard GLBs and no MCP autoload.
const Actor = preload("res://scripts/actor.gd")
var checks: int = 0
var failures: int = 0
var largest_spoon_radius: float = 0.0
var largest_mouth_gap: float = 0.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	for frame: int in range(2):
		var actor: LifeActor = Actor.new()
		root.add_child(actor)
		actor.configure({"name":"Contact test", "frame":frame, "low_detail":true,
			"body_scale":1.15 if frame == 1 else .85,"height_scale":1.08 if frame == 1 else .93})
		actor.voice_enabled = false
		actor.position = Vector3(2,.17,3)
		actor.rotation.y = .8
		var root_transform: Transform3D = actor.transform
		check(actor._cooking_bowl.get_parent() == actor._joints.Forearm_L,"The bowl must attach to the left forearm, not the world.")
		check(actor._cooking_spoon.get_parent() == actor._joints.Forearm_R,"The spoon must attach to the right forearm.")
		for i: int in range(360):
			actor.animate(1.0/60.0,1,false,"cook")
			if i > 90 and i % 15 == 0:
				var tip: Vector3 = actor._bowl_center.to_local(actor._spoon_tip.global_position)
				var radius: float = Vector2(tip.x,tip.z).length()
				largest_spoon_radius = maxf(largest_spoon_radius,radius)
				check(radius < .12,"The stirring spoon must stay inside the bowl rim throughout its cycle.")
				check(tip.y > -.015 and tip.y < .080,"The spoon end must stay within the bowl's food depth.")
				var bowl_basis: Basis = actor._model.global_basis.inverse()*actor._cooking_bowl.global_basis
				check(bowl_basis.y.normalized().dot(Vector3.UP) > .999,"The carried bowl must remain level.")
		check(actor.transform.is_equal_approx(root_transform),"Cooking must not move or rotate the navigation root.")
		var bowl_before: Transform3D = actor._cooking_bowl.global_transform
		var spoon_before: Transform3D = actor._cooking_spoon.global_transform
		var head_before: Transform3D = actor._joints.Head.transform
		var action_time: float = actor._action_time
		actor.animate(.5,0,true,"")
		check(actor._cooking_bowl.visible and actor._cooking_spoon.visible,"Pause must preserve visible props even when world supplies a different action.")
		check(actor._cooking_bowl.global_transform.is_equal_approx(bowl_before) and actor._cooking_spoon.global_transform.is_equal_approx(spoon_before),"Pause must freeze held object transforms.")
		check(actor._joints.Head.transform.is_equal_approx(head_before) and actor._action_time == action_time,"Pause must freeze the head and the activity clock.")
		actor.configure(actor.profile)
		for i: int in range(324):
			actor.animate(1.0/60.0,1,false,"snack")
			if i in [94,100,106,112]:
				var head: Node3D = actor._joints.Head
				var mouth: Vector3 = actor._model.to_local(head.to_global(Vector3(0,.054,.114)))
				var food_contact: Vector3 = actor._model.to_local(actor._snack.to_global(Vector3(0,.029,-.011)))
				var gap: float = mouth.distance_to(food_contact)
				largest_mouth_gap = maxf(largest_mouth_gap,gap)
				check(gap < .030,"During the bite hold, the food edge must meet the mouth within three centimeters.")
		check(actor._snack.visible,"Eating must show the vegetable roll.")
		var previous_hand: Vector3 = actor._snack.global_position
		for i: int in range(60):
			actor.animate(1.0/60.0,1,true,"")
			var step: float = previous_hand.distance_to(actor._snack.global_position)
			check(step < .085,"Returning to walking must move the hand continuously.")
			previous_hand = actor._snack.global_position
		check(not actor._snack.visible and not actor._cooking_bowl.visible,"Held activity props must clear after returning to walking.")
		var anchor: Vector3 = Vector3(1,.69,2)
		actor.set_activity_anchor(anchor,-.4,"seat","relax")
		for i: int in range(180): actor.animate(1.0/60.0,1,false,"relax")
		check(actor.visual.to_global(Vector3(0,actor._hip_height,0)).distance_to(anchor) < .015,"New hand motions must preserve scaled furniture support.")
		check(actor.transform.is_equal_approx(root_transform),"All activity transitions must preserve navigation ownership.")
		actor.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("ACTIVITY TESTS: %d checks, %d failures; maximum spoon radius %.4fm, mouth gap %.4fm" % [checks,failures,largest_spoon_radius,largest_mouth_gap])
	quit(1 if failures > 0 else 0)
