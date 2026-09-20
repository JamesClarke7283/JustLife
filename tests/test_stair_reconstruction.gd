extends SceneTree
## Directed fresh-actor presentation tests. Not household persistence or admission.
var checks:int=0
var failures:Array[String]=[]
var max_grip_error:float=0
var max_pose_error:float=0
var samples:Array=[]
const OUT="user://regression/stair_integration/"
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func run()->void:
	var flow:=LifeMealFlow.new();root.add_child(flow)
	for spec:Dictionary in [{"age":"young_adult","frame":0,"body":1.0,"height":1.0},{"age":"child","frame":0,"body":1.0,"height":1.0},{"age":"elder","frame":1,"body":1.15,"height":1.08},{"age":"teen","frame":0,"body":.85,"height":.93}]:
		var live:LifeActor=make_actor(spec);var fresh:LifeActor=make_actor(spec)
		# Directed prior presentation history, so a same-actor-only test cannot pass by accident.
		for frame:int in range(30):live.animate(.1,1,false,"paint")
		for platter:bool in [false,true]:
			live.meal_presentation={"carrying":true,"platter":platter,"grips":flow.carry_grips_for_recipe("harvest_bake") if platter else {}};fresh.meal_presentation=live.meal_presentation.duplicate(true)
			var dish:Node3D=load("res://assets/models/meal_harvest_bake_serving.glb" if platter else "res://assets/models/meal_plate.glb").instantiate();root.add_child(dish)
			for direction:int in [1,-1]:
				var plan:Dictionary=LifeStairGait.plan(Transform3D(Basis(Vector3.UP,PI/2),Vector3(1,.16,-2)),direction,live.stair_rear_extent(direction))
				for fraction:float in [0,.12,.33,.53,.77,.98,1]:
					var state:Dictionary=LifeStairGait.sample(plan,float(plan.length)*fraction)
					live.position=state.root;live.rotation.y=state.yaw;live.present_stair(state);live.animate(1.0/60,1,true,"")
					fresh.position=state.root;fresh.rotation.y=state.yaw
					var live_clocks:Dictionary=clocks(live);var fresh_clocks:Dictionary=clocks(fresh)
					var before:Dictionary=pose(live)
					live.present_stair(state,true);fresh.present_stair(state,true)
					check(live.stair_pose_valid and fresh.stair_pose_valid,"Both actual leg reach envelopes accept "+str(spec.age))
					check(clocks(live)==live_clocks and clocks(fresh)==fresh_clocks,"Zero-time reconstruction preserves clocks, voice and RNG.")
					compare(before,pose(live),"Same-actor zero-time pose")
					compare(before,pose(fresh),"Fresh-actor pose with different prior clocks")
					dish.global_transform=live.meal_carry_transform()
					for side:String in ["L","R"]:
						var palm:Vector3=live._joints["Forearm_"+side].to_global(live._grip_offset(side))
						var contact:Vector3
						if platter:contact=dish.find_child("GripLeft" if side=="L" else "GripRight",true,false).global_position
						else:contact=dish.to_global(Vector3(-.12 if side=="L" else .12,.005,0))
						var error:float=palm.distance_to(contact);max_grip_error=maxf(max_grip_error,error)
						check(error<.008,"Final pelvis palm matches actual dish contact within8mm: "+str(spec.age))
						samples.append({"age":spec.age,"platter":platter,"direction":direction,"fraction":fraction,"side":side,"grip_error":error})
				# Exiting while paused must clear the leg pose, independent of previous time.
				var before_clock:Dictionary=clocks(live)
				live.present_stair({},true);fresh.present_stair({},true)
				check(live.stair_presentation.is_empty() and live.visual.position==Vector3.ZERO,"Paused exit removes stair/pelvis pose.")
				check(clocks(live)==before_clock,"Paused exit does not advance clocks or voice.")
				compare(pose(live),pose(fresh),"Fresh paused exit including carried dish")
				for side:String in ["L","R"]:
					check(live._joints["Leg_"+side].rotation.is_equal_approx(live._rest_rotations["Leg_"+side]) and live._joints["Shin_"+side].rotation.is_equal_approx(live._rest_rotations["Shin_"+side]),"Exit restores neutral leg joints.")
			dish.queue_free();await process_frame
		# Impossible contact must be explicit, not accepted through IK clamping.
		var bad_plan:Dictionary=LifeStairGait.plan(Transform3D.IDENTITY,1,live.stair_rear_extent(1))
		var bad:Dictionary=LifeStairGait.sample(bad_plan,.5);bad.feet.L+=Vector3(0,10,0)
		live.position=bad.root;live.rotation.y=bad.yaw;live.present_stair(bad,true)
		check(not live.stair_pose_valid and not live.stair_pose_error.is_empty(),"Impossible foot contact reports invalid pose explicitly.")
		live.queue_free();fresh.queue_free();await process_frame
	flow.queue_free();await process_frame
	DirAccess.make_dir_recursive_absolute("user://regression/stair_integration")
	var file:=FileAccess.open(OUT+"reconstruction.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"max_grip_error":max_grip_error,"max_transform_error":max_pose_error,"samples":samples,"scope":"Directed old/fresh actors with plate/platter; four profiles, seven distances, both directions; zero-time joint/bone/grip/dish/clock equality and paused exit. No controller, ledger custody, fresh-process save or geometry clearance."},"  "));file.close()
	print("STAIR_RECONSTRUCTION checks=%d failures=%d max_grip=%.6f pose_error=%.8f"%[checks,failures.size(),max_grip_error,max_pose_error])
	quit(0 if failures.is_empty() else 1)

func make_actor(spec:Dictionary)->LifeActor:
	var actor:=LifeActor.new();root.add_child(actor)
	actor.configure({"name":"Pose reconstruction "+str(spec.age),"age_stage":spec.age,"frame":spec.frame,"body_scale":spec.body,"height_scale":spec.height,"hair":0,"outfit":0})
	actor.voice_enabled=false;return actor

func clocks(actor:LifeActor)->Dictionary:
	return {"time":actor._time,"action":actor._action_time,"voice_rng":actor._voice_rng.state,"voice_wait":actor._voice_cooldown,"blink_wait":actor._blink_wait,"blink_elapsed":actor._blink_elapsed,"speech_remaining":actor._speech_remaining,"pending_voice":actor._pending_voice}

func pose(actor:LifeActor)->Dictionary:
	var result:Dictionary={"visual":actor.visual.global_transform,"dish":actor.meal_carry_transform(),"grips":actor._grip_amounts.duplicate(),"bones":[]}
	for name:String in LifeActor.JOINT_NAMES:result[name]=actor._joints[name].global_transform
	for side:String in actor._leg_rest:result["shoe_"+side]=actor._leg_rest[side].shoe.global_transform
	for entry:Dictionary in actor._rig_bones:result.bones.append(entry.skeleton.get_bone_pose_rotation(int(entry.index)))
	return result

func compare(first:Dictionary,second:Dictionary,label:String)->void:
	for key:String in first:
		if first[key] is Transform3D:
			var a:Transform3D=first[key];var b:Transform3D=second[key]
			var error:float=maxf(a.origin.distance_to(b.origin),maxf(a.basis.x.distance_to(b.basis.x),maxf(a.basis.y.distance_to(b.basis.y),a.basis.z.distance_to(b.basis.z))))
			max_pose_error=maxf(max_pose_error,error);check(error<.00001,label+": "+key)
		elif key=="grips":check(first[key]==second[key],label+": grip shapes")
		elif key=="bones":
			for i:int in first.bones.size():check(Quaternion(first.bones[i]).is_equal_approx(second.bones[i]),label+": skinned bone")
