extends SceneTree
## Uses cottage furniture measurements and full padded limb segments, not hand endpoints alone.
const Actor = preload("res://scripts/actor.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)
func run() -> void:
	for body: float in [.85,1.0,1.15]:
		for height: float in [.93,1.0,1.08]:
			for frame: int in range(2):
				var actor: LifeActor = Actor.new();root.add_child(actor)
				actor.configure({"age_stage":"child","frame":frame,"low_detail":true,"body_scale":body,"height_scale":height,"outfit":frame})
				actor.voice_enabled = false
				for yaw: float in [0.0,PI*.5,PI,PI*1.5]:
					var facing: Basis = Basis(Vector3.UP,yaw)
					var base: Vector3 = Vector3(3.4,0,3.5)
					var anchor: Vector3 = base+facing*Vector3(0,.86,.23)
					var keyboard: Vector3 = base+facing*Vector3(0,1.075,.695)
					var edge: Vector3 = base+facing*Vector3(0,1.03,.415)
					actor.set_activity_anchor(anchor,yaw,"seat","school",{"hand_center":keyboard,"hand_spread":.105,"desk_surface_y":1.03,"desk_front_edge":edge,"desk_forward":facing*Vector3(0,0,1)})
					for i: int in range(180): actor.animate(1.0/60.0,1.0,false,"school")
					var worst: float = INF
					var farthest: float = 0.0
					for sample: int in range(24):
						actor.animate(1.0/30.0,1.0,false,"school")
						for side: String in ["L","R"]:
							var shoulder: Vector3 = actor._joints["Arm_"+side].global_position
							var elbow: Vector3 = actor._joints["Forearm_"+side].global_position
							var palm: Vector3 = actor._joints["Forearm_"+side].to_global(actor._palm_offset(side))
							var target: Vector3 = keyboard+facing*Vector3(-.105 if side == "L" else .105,0,0)
							var limb_scale: float = maxf(body,height)*actor._proportion
							worst = minf(worst,actor._desk_segment_clearance(shoulder,elbow,.047*limb_scale))
							worst = minf(worst,actor._desk_segment_clearance(elbow,palm,.032*limb_scale))
							farthest = maxf(farthest,palm.distance_to(target))
					var label_text: String = "body%.2f height%.2f frame%d yaw%.2f" % [body,height,frame,yaw]
					check(worst >= -.001,label_text+": the padded upper arm and forearm clear the real desktop; gap="+str(worst))
					check(farthest < .015,label_text+": both palms remain on the keyboard; error="+str(farthest))
					check(actor.visual.to_global(Vector3(0,actor._hip_height,0)).distance_to(anchor)<.002,label_text+": hips remain supported by the supplied visible cushion.")
					var before: Transform3D = actor.visual.transform
					var elbow_before: Transform3D = actor._joints.Forearm_R.global_transform
					actor.animate(.5,0,true,"")
					check(actor.visual.transform.is_equal_approx(before) and actor._joints.Forearm_R.global_transform.is_equal_approx(elbow_before),label_text+": pause freezes the clearance pose.")
				actor.queue_free();await process_frame
	print("DESK ACTOR TESTS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
