extends SceneTree
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func run() -> void:
	for stage: String in ["young_adult","adult","elder"]:
		for frame: int in [0,1]:
			var actor: LifeActor=LifeActor.new();root.add_child(actor)
			actor.configure({"age_stage":stage,"frame":frame,"low_detail":true});actor.voice_enabled=false
			actor.position=Vector3(1,.16,0)
			actor.set_activity_anchor(actor.position,-PI/2,"standing","help_homework")
			var original: Transform3D=actor.transform
			for i: int in range(120):actor.animate(1.0/60.0,1,false,"help_homework")
			check(actor.transform==original and actor._sit_amount<.01,"Caregiver stands at the supplied root and does not take the learner's seat.")
			check(actor._joints.Forearm_R.rotation.x<-.6 and actor._joints.Head.rotation.x>.1,"Caregiver explains with a raised hand and attention toward the work.")
			var hand: Transform3D=actor._joints.Forearm_R.transform
			var pose: Transform3D=actor.visual.transform
			actor.animate(2,0,false,"help_homework")
			check(actor._joints.Forearm_R.transform==hand and actor.visual.transform==pose,"Pause freezes the helper's exact gesture.")
			for i: int in range(70):actor.animate(1.0/60.0,1,false,"help_homework")
			check(not actor._joints.Forearm_R.transform.is_equal_approx(hand),"Explanatory motion alternates instead of holding a static greeting.")
			check(not actor._book.visible and not actor._cooking_bowl.visible and not actor._birthday_cake.visible,"Helping introduces no unrelated held props.")
			actor.queue_free()
	for stage: String in ["child","teen"]:
		for frame: int in [0,1]:
			var actor: LifeActor=LifeActor.new();root.add_child(actor)
			actor.configure({"age_stage":stage,"frame":frame,"low_detail":true});actor.voice_enabled=false
			var support: Vector3=Vector3(0,.86,0)
			actor.set_activity_anchor(support,0,"seat","homework_wait")
			for i: int in range(120):actor.animate(1.0/60.0,1,false,"homework_wait")
			check(actor._sit_amount>.99,"Waiting learner uses the real seated corrective.")
			var hip: Vector3=actor.visual.to_global(Vector3(0,actor._hip_height*actor._height,0))
			check(hip.distance_to(support)<.002,"Waiting learner preserves the supplied cushion support.")
			check(actor._joints.Forearm_R.rotation.x<-.8 and not actor._book.visible,"Waiting hands rest without typing or invented homework props.")
			var arm: Transform3D=actor._joints.Forearm_R.transform
			actor.animate(1,0,false,"homework_wait")
			check(actor._joints.Forearm_R.transform==arm,"Paused seated waiting is exact.")
			actor.clear_activity_anchor()
			for i: int in range(60):actor.animate(1.0/60.0,1,true,"")
			check(actor._sit_amount<.01,"Canceled waiting blends back into walking.")
			actor.queue_free()
	await process_frame
	print("CAREGIVING ACTOR: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
