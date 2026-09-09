extends SceneTree
const MainScene=preload("res://scenes/main.tscn")
const MORGAN="housemate_2"
var app:Node
var input_guard:LineEdit
var phase:String="load"
var inside_step:bool=false
var checks:int=0
var failures:Array=[]
var report:Dictionary={"samples":[],"events":[],"speed_observations":[],"morgan_changed_signals":[]}

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("WALK_DIAG_FAIL ",label)
func exclude_input(n:Node)->void:
	n.set_process_input(false);n.set_process_unhandled_input(false);n.set_process_unhandled_key_input(false);n.set_process_shortcut_input(false)
func freeze(n:Node)->void:
	exclude_input(n);n.set_process(false);n.set_physics_process(false)
	for child:Node in n.get_children():freeze(child)
func excluded(n:Node)->bool:
	if n.is_processing_input() or n.is_processing_unhandled_input() or n.is_processing_unhandled_key_input() or n.is_processing_shortcut_input():return false
	for child:Node in n.get_children():
		if not excluded(child):return false
	return true
func frames(count:int=1)->void:
	for i:int in count:await process_frame
func wire(value:Variant)->Variant:
	if value is float and not is_finite(value):return {"__diagnostic_nonfinite__":"nan" if is_nan(value) else ("positive_infinity" if value>0 else "negative_infinity")}
	if value is Vector3:return [wire(value.x),wire(value.y),wire(value.z)]
	if value is Vector2:return [wire(value.x),wire(value.y)]
	if value is Transform3D:return {"basis":[wire(value.basis.x),wire(value.basis.y),wire(value.basis.z)],"origin":wire(value.origin)}
	if value is Color:return value.to_html(true)
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[str(key)]=wire(value[key])
		return result
	if value is Array or value is PackedVector3Array or value is PackedStringArray:
		var result:Array=[]
		for item:Variant in value:result.append(wire(item))
		return result
	return value
func write_json(name:String,value:Variant)->void:
	var f:=FileAccess.open("res://evidence/"+name,FileAccess.WRITE);f.store_string(JSON.stringify(wire(value),"  ",true,true));f.close()
func speeds()->Dictionary:
	var members:Dictionary={}
	for m:Dictionary in app.household.members:members[m.id]={"speed":m.sim.speed,"autonomy":m.sim.autonomy,"minutes":m.sim.minutes,"day":m.sim.day}
	return {"phase":phase,"household":app.household.speed,"selected":app.household.selected().speed,"bound":app.sim.speed,"members":members,"day":app.household.day,"minutes":app.household.minutes}
func semantic()->Dictionary:
	# Deliberately does not call Household.get_state: that adopts selected speed.
	var members:Dictionary={};var actors:Dictionary={}
	for m:Dictionary in app.household.members:members[m.id]=m.sim.get_state()
	for id:String in app.world.actors:
		var a:LifeActor=app.world.actors[id];actors[id]={"position":a.position,"yaw":a.rotation.y,"visible":a.visible}
	return {"speeds":speeds(),"members":members,"actors":actors,"funds":app.household.funds,"day":app.household.day,"minutes":app.household.minutes,"motions":app.motion_states.duplicate(true),"routes":app.traversal.routes.duplicate(true),"stairs":app.traversal.stairs.duplicate(true),"physical":app._physical_snapshot_context(),"food":app.household.meals.get_state(),"sanitation":app.household.sanitation.get_state(),"guest":app.residents.home_visit.state.duplicate(true),"courtesy":{"blocked":app.traversal.courtesy.blocked.duplicate(true),"queries":app.traversal.courtesy.queries,"trace":app.traversal.courtesy.trace.duplicate(true)}}
func changed_signal(id:String)->void:
	if id!=MORGAN:return
	var sim:LifeSim=app.household.member_sim(id)
	report.morgan_changed_signals.append({"phase":phase,"inside_ordinary_process":inside_step,"autonomy":sim.autonomy,"queue_count":sim.action_queue.size(),"speed":sim.speed,"day":sim.day,"minutes":sim.minutes})
func action_event(action:Dictionary,id:String,kind:String)->void:
	report.events.append(wire({"phase":phase,"id":id,"kind":kind,"day":app.household.day,"minutes":app.household.minutes,"action":action.duplicate(true)}))
func body_facts()->Dictionary:
	var pairs:Array=[];var support:Array=[]
	var ids:Array=app.world.actors.keys();ids.sort()
	for i:int in ids.size():
		var a:LifeActor=app.world.actors[ids[i]]
		if not a.visible:continue
		for j:int in range(i+1,ids.size()):
			var b:LifeActor=app.world.actors[ids[j]]
			if not b.visible or not app.traversal._same_floor(a.position,b.position):continue
			var distance:float=a.position.distance_to(b.position)
			if distance<1.6:pairs.append({"a":ids[i],"b":ids[j],"distance":distance,"below_gap":distance<LifeTraversal.BODY_GAP-.000001})
	for m:Dictionary in app.household.members:
		var a:LifeActor=app.world.actors[m.id];var level:int=app.world.point_level(a.position)
		support.append({"id":m.id,"level":level,"static_point_clear":level>=0 and app.world.lot_navigation.point_clear(level,a.position),"visible":a.visible,"stair_safe":app.traversal.safety(m.id),"stair_busy":app.traversal.busy(m.id)})
	return {"nearby_pairs":pairs,"member_support":support}
func ordinary_step()->void:
	freeze(app);input_guard.grab_focus()
	check(root.gui_disable_input and excluded(app) and root.gui_get_focus_owner()==input_guard,"All native event modes and polled camera keys excluded")
	inside_step=true;app._process(.05);inside_step=false;freeze(app);await frames()
func finish()->void:
	report.checks=checks;report.failures=failures;write_json("diagnostic.json",report)
	var stream:WeakRef=weakref(app.ambience_player.stream);var playback:WeakRef=weakref(app.ambience_player.get_stream_playback()) if app.ambience_player.has_stream_playback() else null
	app.queue_free();app=null;input_guard.queue_free();await frames(4)
	var start:int=Time.get_ticks_msec()
	while (stream.get_ref()!=null or (playback!=null and playback.get_ref()!=null)) and Time.get_ticks_msec()-start<1000:await create_timer(.01).timeout
	var drained:bool=stream.get_ref()==null and (playback==null or playback.get_ref()==null)
	write_json("teardown.json",{"drained":drained,"stream_released":stream.get_ref()==null,"playback_released":playback==null or playback.get_ref()==null})
	check(drained,"Observed audio resources drained")
	report.checks=checks;report.failures=failures;write_json("diagnostic.json",report)
	print("WALK_DIAG ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
