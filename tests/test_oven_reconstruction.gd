extends "res://tests/test_oven_controller.gd"
## Controlled actual paid cooking plus fresh actor/scene reconstruction.
## This is not rendered contact evidence or a fresh-process public test.
var samples:Array=[]
func _phase_progress(wanted:String,part:float=.5)->float:
	for entry:Array in LifeOvenSequence.PHASES:
		if str(entry[0])==wanted:return lerpf(float(entry[1]),float(entry[2]),part)
	return -1.0

func _clocks(a:LifeActor)->Dictionary:
	return {"time":a._time,"action_time":a._action_time,"motion_action":a._motion_action,"blink_wait":a._blink_wait,"blink_elapsed":a._blink_elapsed,"rng":a._voice_rng.state,"cooldown":a._voice_cooldown,"pending":a._pending_voice,"last_voice":a._last_voice_action,"suspended":a._voice_suspended,"speech_remaining":a._speech_remaining,"speech_visible":a._speech.visible,"speech_text":a._speech.text,"voice_playing":a._voice.playing,"smile":a._smile}

func _pose(a:LifeActor)->Dictionary:
	var result:Dictionary={"visual":a.visual.global_transform,"tray":a._baking_tray.global_transform,"tray_visible":a._baking_tray.visible,"bowl_visible":a._cooking_bowl.visible,"spoon_visible":a._cooking_spoon.visible,"jar_visible":a._seasoning_jar.visible,"jar":a._seasoning_jar.global_transform,"grains":a._seasoning_grains.map(func(grain:MeshInstance3D)->Transform3D:return grain.global_transform),"grips":a._grip_amounts.duplicate(true)}
	for key:String in a._joints:result[key]=a._joints[key].global_transform
	return result

func _compare_pose(before:Dictionary,after:Dictionary,label:String)->void:
	check(before.visual.is_equal_approx(after.visual),label+": model root matches the directly evaluated paid phase.")
	check(bool(before.tray_visible)==bool(after.tray_visible) and before.tray.is_equal_approx(after.tray),label+": transfer tray transform and visibility match, including hidden interior cache.")
	check(before.jar_visible==after.jar_visible and (not bool(before.jar_visible) or before.jar.is_equal_approx(after.jar)),label+": visible seasoning jar matches its restored transform.")
	check(not bool(before.jar_visible) or before.grains==after.grains,label+": active seasoning grains reconstruct from authoritative cooking progress.")
	var worst:float=0;var rotation_error:float=0
	for key:String in LifeActor.JOINT_NAMES:
		worst=maxf(worst,before[key].origin.distance_to(after[key].origin))
		rotation_error=maxf(rotation_error,before[key].basis.get_rotation_quaternion().angle_to(after[key].basis.get_rotation_quaternion()))
	check(worst<.0001,label+": all articulated joint origins match within0.1mm.")
	check(rotation_error<.001,label+": joint rotations match within0.001radians.")
	check(before.grips==after.grips,label+": restored finger grip amounts match live cooking.")
	samples.append({"label":label,"maximum_joint_origin_error":worst,"maximum_joint_rotation_error":rotation_error,"model_error":before.visual.origin.distance_to(after.visual.origin),"tray_error":before.tray.origin.distance_to(after.tray.origin)})

func _fresh_phase(wanted:String,part:float=.5)->void:
	var desired:float=_phase_progress(wanted,part)
	var cached:bool=LifeOvenSequence.inside(desired)
	var f:Dictionary=_bake(_phase_progress("load",.7) if cached else desired)
	if cached:
		# Establish real held geometry first, then advance actual paid time into
		# the interior phase. No action/pose progress is fabricated.
		app.household.set_speed(1)
		_advance_oven_minutes(70.0*desired-float(f.action.elapsed))
		app.meal_flow.present_actor("player");app._update_activity_facing(.1,f.action,"cook");app.player.animate(.1,1.0,false,"cook")
		app.household.set_speed(0);app.meal_flow.sync_world()
		f.progress=float(f.action.progress);f.elapsed=float(f.action.elapsed)
	wanted+="@"+str(part)
	check(is_equal_approx(float(f.action.progress),desired),wanted+": actual paid cooking reaches the phase-table sample.")
	var current:LifeActor=app.player
	var before:Dictionary=_pose(current)
	current._blink_wait=0.0;current._blink_elapsed=-1.0;current._speech_remaining=3.0;current._pending_voice="happy";current._voice_cooldown=0.0
	var clocks:Dictionary=_clocks(current)
	current.reconstruct_cooking_pose()
	check(_clocks(current)==clocks,wanted+": reconstruction advances no actor clocks, speech, blink, RNG or voice state.")
	_compare_pose(before,_pose(current),wanted+" existing actor")
	var clone:=LifeActor.new();app.world.add_child(clone);clone.configure(current.profile.duplicate(true));clone.position=current.position;clone.rotation=current.rotation
	clone.cooking_presentation=current.cooking_presentation.duplicate(true)
	var anchor:Dictionary=current._activity_anchor
	clone.set_activity_anchor(anchor.position,float(anchor.yaw),str(anchor.kind),"cook",anchor)
	var fresh_clocks:Dictionary=_clocks(clone)
	clone.reconstruct_cooking_pose()
	check(_clocks(clone)==fresh_clocks,wanted+": a fresh actor reconstructs without animation-time or RNG sampling.")
	_compare_pose(before,_pose(clone),wanted+" fresh actor")
	check(clone._baking_tray.visible!=LifeOvenSequence.inside(float(f.progress)),wanted+": actor and world dish ownership remain exclusive.")
	if LifeOvenSequence.inside(float(f.progress)):
		var interior:Node3D=app.world.oven_food_views.get(str(f.id))
		check(is_instance_valid(interior) and interior.global_transform.is_equal_approx(clone._baking_tray.global_transform),wanted+": world and actor handoff use identical full transforms, including orientation.")
	var paused_before:Dictionary=_pose(clone);var clock_before:Dictionary=_clocks(clone)
	clone.animate(.5,0.0,true,"read")
	check(_pose(clone)==paused_before and clone._time==clock_before.time and clone._action_time==clock_before.action_time and clone._voice_rng.state==clock_before.rng,wanted+": ordinary paused animate still freezes all pose and prop transforms.")
	clone.queue_free()

func _clearing_and_pending_host()->void:
	var f:Dictionary=_bake(_phase_progress("load"));var a:LifeActor=app.player
	var held_before:Dictionary=_pose(a)
	check(bool(held_before.tray_visible),"Controlled active insertion starts with the actual transfer tray visible.")
	a.cooking_presentation={};a.clear_activity_anchor();var clocks:Dictionary=_clocks(a);a.reconstruct_cooking_pose()
	check(not a._baking_tray.visible and not a._seasoning_jar.visible and not a._cooking_bowl.visible and not a._cooking_spoon.visible,"Empty current cooking presentation clears every previous preparation prop immediately.")
	check(_clocks(a)==clocks,"Clearing canceled cooking advances no clocks or RNG.")
	app.meal_flow.present_actor("player");app._update_activity_facing(0.0,f.action,"cook");a.reconstruct_cooking_pose()
	_compare_pose(held_before,_pose(a),"restored after presentation clear")
	app.set_build_mode(true);app.move_item(app._find_item(f.id))
	check(bool(a.cooking_presentation.get("oven_suspended",false)) and not a._baking_tray.visible and not a._seasoning_jar.visible,"Actual detached Build preview clears the cook's transfer props while paused.")
	check(float(f.action.elapsed)==float(f.elapsed) and app.household.funds==976,"Detached pose reconstruction preserves paid cooking progress and money.")
	app.cancel_placement()
	check(not bool(a.cooking_presentation.get("oven_suspended",false)) and a._baking_tray.visible,"Canceling the real oven move reconstructs its paid transfer presentation.")
	_compare_pose(held_before,_pose(a),"canceled Build move")
	app.cancel_current_action()
	check(a.cooking_presentation.is_empty() and not a._baking_tray.visible and app.world.oven_food_views.is_empty(),"Public controller cancellation clears both possible food representations during pause.")

func _named_reconstruction()->void:
	var f:Dictionary=_bake(_phase_progress("load"));var before:Dictionary=_pose(app.player)
	check(app.save_game("","Paused actor reconstruction"),"Actual paid transfer writes a valid named household.")
	var slot:String=app.active_save_id;var at:Vector3=app.player.position
	app.load_game(slot);app.set_process(false)
	check(app.sim.speed==0 and app.player.position.is_equal_approx(at) and float(app.sim.get_current_action().elapsed)==float(f.elapsed),"Scene reconstruction preserves exact paused actor location and paid time.")
	_compare_pose(before,_pose(app.player),"named paused scene reload")

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	for sample:Array in [["season",.2],["season",.8],["season",.999],["reach_load",.001],["pull_load",.25],["pull_load",.75],["load",.7],["push_load",.25],["push_load",.75],["bake",.5],["pull_unload",.25],["pull_unload",.75],["unload",.7],["push_unload",.25],["push_unload",.75]]:
		_fresh_phase(str(sample[0]),float(sample[1]));await process_frame;await process_frame
	_clearing_and_pending_host();_named_reconstruction()
	var report:Dictionary={"checks":checks,"failures":failures,"samples":samples,"scope":"Controlled paid cooking and fresh actors/scenes; not rendered contact or fresh-process public evidence."}
	var file:=FileAccess.open("user://oven_reconstruction.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close();print("OVEN_RECONSTRUCTION ",JSON.stringify(report))
	app.queue_free();await process_frame;await process_frame;await process_frame
	# Audio playback releases are processed on the mixer thread after nodes
	# leave the tree; give shutdown a real engine interval before process exit.
	await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
