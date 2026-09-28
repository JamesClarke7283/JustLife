extends SceneTree
## Assign through the bed menu, then walk both unrelated adults to opposite
## sides, save/reload and reject duplicate/blocked assignments.
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message);push_error(message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	print("BED_ASSIGNMENTS loading main scene")
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	print("BED_ASSIGNMENTS starting home")
	app.selected_lot=0;app.start_household();await process_frame
	print("BED_ASSIGNMENTS home ready")
	app.set_process(false);app.set_sound(false)
	while app.household.members.size()<2:app.household.add_member({"name":"Rowan","age_stage":"adult"})
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false;member.sim.needs.energy=20.0
		if not app.world.actors.has(str(member.id)):app.spawn_actor(str(member.id),member.sim.character.duplicate(true),Vector3(1,.16,2))
	app._refresh_sim_targets(false)
	var bed:Dictionary=app.world.closest_item("bed",Vector3.ZERO)
	var left:String=str(app.household.members[0].id)
	var right:String=str(app.household.members[1].id)
	app.show_interactions(bed,Vector2(700,400))
	var go:bool=false
	for node:Node in app.overlay.find_children("*","Button",true,false):
		if node.text=="Go to Bed":go=true
	check(go,"Double bed offers Go to Bed.")
	app.show_bed_assignments(str(bed.id))
	var first:Button=app.overlay.find_child("AssignBed_"+left+"_left",true,false)
	check(first!=null,"Bed menu lists adults with left/right assignment buttons.")
	if first!=null:first.pressed.emit()
	check(app.household.assigned_bed_side(left,str(bed.id))=="left","First adult is assigned left from the menu.")
	var second:Button=app.overlay.find_child("AssignBed_"+right+"_right",true,false)
	if second!=null:second.pressed.emit()
	check(app.household.assigned_bed_side(right,str(bed.id))=="right","Second adult is assigned right from the same bed menu.")
	if "--render" in OS.get_cmdline_user_args():
		await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/justlife-bed-assignments-ui.png")==OK,"Rendered bed assignment menu saved.")
	check(not bool(app.household.assign_bed_side(right,str(bed.id),"left").ok),"An occupied assignment cannot be stolen.")
	app.close_overlay()
	# The right-side sleeper goes first: order must not decide their half.
	app.select_household_member(1);app.queue_interaction(bed,"sleep")
	app.select_household_member(0);app.queue_interaction(bed,"sleep")
	for i:int in 1000:
		app._process(.1)
		if i%30==0:await process_frame
		if app.household.members.all(func(m:Dictionary):return str(m.sim.get_current_action().get("phase",""))=="active"):break
	# Let both settled sleep animations reach the mattress, including the
	# Lifelet whose arrival was the final event in the previous tick.
	for i:int in 30:app._process(.1)
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		check(str(action.get("id",""))=="sleep" and str(action.get("phase",""))=="active","Assigned adult reaches bed and sleeps: "+str(member.id)+" "+str(action.get("phase","")))
		check(str(action.get("seat_slot",""))==("left" if member.id==left else "right"),"Assigned side survives reversed arrival order: "+str(member.id))
		check(str(app.world.actors[str(member.id)]._activity_anchor.get("kind",""))=="bed","Each sleeper receives the mattress pose.")
		var at:Vector3=bed.node.to_local(action.get("target_position",Vector3.ZERO))
		check((at.x< -float(bed.size.x)*.5 if member.id==left else at.x>float(bed.size.x)*.5),"Sleeper reaches their actual bedside instead of the foot.")
	var a:Dictionary=app.world.activity_anchor(bed,"sleep",{"seat_slot":"left"})
	var b:Dictionary=app.world.activity_anchor(bed,"sleep",{"seat_slot":"right"})
	check(a.position.distance_to(b.position)>.8,"Sleep poses occupy separate mattress halves.")
	if "--render" in OS.get_cmdline_user_args():
		app.world.camera_target=bed.node.position;app.world.camera.size=6.0;app.world.update_camera()
		await process_frame;await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("/tmp/justlife-bed-assigned-sleepers.png")==OK,"Rendered assigned sleepers saved.")
	var saved:Dictionary=app.household.json_safe(app.household.get_state(app.world.serialize_items()))
	var restored:=LifeHousehold.new();root.add_child(restored)
	var result:Dictionary=restored.restore_state(saved)
	check(bool(result.ok),"Assigned sleeping household reloads: "+str(result.get("error","")))
	check(restored.bed_assignments==app.household.bed_assignments,"Assignments survive a save/restore.")
	var invalid:Dictionary=saved.duplicate(true);invalid.bed_assignments[right].slot="left"
	check(not bool(restored.restore_state(invalid).ok),"Duplicate side in save is rejected without replacing live state.")
	check(restored.bed_assignments==app.household.bed_assignments,"Invalid save leaves current assignments intact.")
	invalid=saved.duplicate(true);invalid.bed_assignments[left].bed_id="missing_bed"
	check(not bool(restored.restore_state(invalid).ok),"Save cannot assign an adult to a missing furnishing.")
	var without_bed:Array=app.world.serialize_items().filter(func(entry:Dictionary):return str(entry.get("id",""))!=str(bed.id))
	check(app.household.get_state(without_bed).bed_assignments.is_empty(),"Saving after a bed is sold drops its stale assignments.")
	for member:Dictionary in app.household.members:member.sim.cancel_action(0)
	var third:String=app.household.add_member({"name":"Unassigned adult","age_stage":"adult"})
	check(not app._activity_available_for_member({"id":"sleep","target_id":str(bed.id),"target_position":app.world.approach(bed)},third),"Autonomy rejects an empty bed whose halves both belong to other adults.")
	check(app._activity_available_for_member({"id":"sleep","target_id":str(bed.id),"target_position":app.world.approach(bed)},left),"An assigned adult can still choose the empty bed before their half is resolved.")
	var original:Vector3=bed.node.position
	bed.node.position=Vector3(17,.16,10)
	check(not app.world.bed_side_approach(bed,"right").is_finite(),"Blocked/out-of-lot bedside cannot silently snap somewhere else.")
	bed.node.position=original
	restored.queue_free();app.queue_free();await process_frame
	print("BED_ASSIGNMENTS %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
