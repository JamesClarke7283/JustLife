extends "res://tests/test_public_twofloor.gd"
## Shared headless public-control and exact-state helpers for courtesy beneficiaries.
## Diagnostic serialization never changes production named-save bytes.
const LANDING_SLOT="life_1788959163926_31350169"
var audit:Dictionary={}
var phase_tag:String=""
var mode_tag:String=OS.get_environment("CLEAR_MODE")

func frames(count:int=2)->void:
	for i:int in range(count):
		root.gui_disable_input=true
		if is_instance_valid(app):_exclude_input(app)
		await process_frame
		root.gui_disable_input=true
		if is_instance_valid(app):_exclude_input(app)

func _exclude_input(node:Node)->void:
	node.set_process_input(false);node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false);node.set_process_shortcut_input(false)
	for child:Node in node.get_children():_exclude_input(child)

func _now()->float:
	return float(app.household.day-1)*1440.0+app.household.minutes

func _decoded_integer_fields(decoded:Dictionary,fields:Array,scope:String)->Dictionary:
	var result:Dictionary=decoded.duplicate(true)
	var invalid:Array[String]=[]
	for key:String in fields:
		var value:Variant=decoded.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)):
			invalid.append(scope+"."+key)
	check(invalid.is_empty(),"Specified decoded identity fields are finite integral values: "+scope+str(invalid))
	if not invalid.is_empty():return result
	for key:String in fields:result[key]=int(decoded[key])
	return result

func _finite_diagnostic(value:Variant)->Variant:
	if value is float and not is_finite(value):
		return {"__diagnostic_nonfinite__":"nan" if is_nan(value) else ("positive_infinity" if value>0.0 else "negative_infinity")}
	if value is Array:
		var result:Array=[]
		for entry:Variant in value:result.append(_finite_diagnostic(entry))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[key]=_finite_diagnostic(value[key])
		return result
	return value

func _same(disk:Variant,current:Variant)->bool:
	if current is Vector3:return disk is Array and disk.size()==3 and current==LifeJourneyState.vector(disk)
	if disk is Dictionary:
		if not current is Dictionary or disk.size()!=current.size():return false
		for key:Variant in disk:
			if not current.has(key) or not _same(disk[key],current[key]):return false
		return true
	if disk is Array:
		if not current is Array or disk.size()!=current.size():return false
		for i:int in disk.size():
			if not _same(disk[i],current[i]):return false
		return true
	return disk==current

func _project_journeys(data:Dictionary)->Dictionary:
	var projected:Dictionary=data.duplicate(true)
	for record:Dictionary in projected.members.values():
		record.position=LifeJourneyState.packed(LifeJourneyState.vector(record.position))
		record.yaw=float(PackedFloat32Array([record.yaw])[0])
		var motion:Dictionary=record.motion
		if motion.is_empty():continue
		for key:String in ["destination","wait","clear"]:
			if not motion[key].is_empty():motion[key]=LifeJourneyState.packed(LifeJourneyState.vector(motion[key]))
		if motion.has("courtesy"):motion.courtesy.anchor=LifeJourneyState.packed(LifeJourneyState.vector(motion.courtesy.anchor))
	return projected

func _project_queue(queue:Array)->Array:
	# The loader rebuilds each stored action from the live definition table (with
	# the recipe's own definition for a cook) and then adopts the saved progress,
	# so a definition-derived field (`label`, `changes`, `cost`, `description`,
	# `skill`, `xp`) reflects today's code rather than the text that was saved —
	# which is what lets a retuned activity load. The saved duration, elapsed,
	# identity and ownership are what a fresh load must preserve.
	var result:Array=queue.duplicate(true)
	for action:Dictionary in result:
		action.progress=clampf(float(action.elapsed)/float(action.duration),0.0,1.0)
		var definition:Dictionary=app.sim._actions.get(str(action.get("id","")),{})
		if definition.is_empty():continue
		var rebuilt:Dictionary=definition.duplicate(true)
		if str(action.get("id",""))=="cook":rebuilt=LifeMeals.cooking_definition(rebuilt,str(action.get("recipe","garden_skillet")))
		for key:String in ["label","changes","cost","description","skill","xp"]:
			if rebuilt.has(key):action[key]=rebuilt[key]
	return result

func _physical_facts()->Dictionary:
	var facts:Dictionary={"clock":[app.household.day,app.household.minutes,app.household.speed],"funds":app.household.funds,"people":app.household.members.map(func(m:Dictionary):return {"id":m.id,"position":app.world.actors[m.id].position,"yaw":app.world.actors[m.id].rotation.y,"queue":m.sim.action_queue.duplicate(true),"needs":m.sim.needs.duplicate(true),"career":m.sim.career.duplicate(true),"education":m.sim.education.duplicate(true)}),"journeys":app.traversal.snapshot(),"food":app.household.meals.get_state(),"visitor":app.residents.home_visit.state.duplicate(true)}
	facts["speeds"]={"selected_id":app.household.selected_id(),"bound_id":app.bound_member_id,"selected":app.sim.speed,"aggregate":app.household.speed,"members":app.household.members.map(func(m:Dictionary):return {"id":m.id,"speed":m.sim.speed})}
	facts["stair_locks"]=app.traversal.stairs.duplicate(true)
	return facts

func _record_clear()->Dictionary:
	var bodies:Dictionary={}
	for id:String in app.world.actors:
		if app.world.actors[id].visible:bodies[id]=app.world.actors[id].position
	return {"at":_now(),"bodies":bodies,"journeys":app.traversal.snapshot(),"locks":app.traversal.stairs.duplicate(true),"motion":app.motion_states.duplicate(true),"queues":app.household.members.map(func(m:Dictionary):return {"id":m.id,"queue":m.sim.action_queue.duplicate(true)}),"courtesy_trace":app.traversal.courtesy.trace.duplicate(true)}

func _load_exact(slot:String)->void:
	if app.mode=="menu":await press("Saved lives")
	else:await press("PauseMenu");await press("Load a saved life")
	var selected:bool=false
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and str(node.get_meta("save_id",""))==slot:
			node.pressed.emit();await frames(2);selected=true;break
	check(selected,"Public picker locates exact actual slot: "+slot)
	await press("Load selected life",true)
	if is_instance_valid(button_matching("Continue without saving")):await press("Continue without saving")
	check(app.mode=="live" and app.active_save_id==slot,"Public picker adopts chosen actual slot.")

func _finish()->void:
	audit["assertions"]=assertions;audit["failures"]=failures;audit["receipts"]=receipts
	audit["at"]=_now();audit["phase"]=phase_tag
	var ambience:WeakRef=weakref(app.ambience_player.stream)
	var playback:WeakRef=weakref(app.ambience_player.get_stream_playback())
	app.queue_free();await frames(2)
	var deadline:int=Time.get_ticks_msec()+1000
	while (ambience.get_ref()!=null or playback.get_ref()!=null) and Time.get_ticks_msec()<deadline:await create_timer(.01).timeout
	check(ambience.get_ref()==null and playback.get_ref()==null,"Private app ambience releases before process exit.")
	audit["assertions"]=assertions;audit["failures"]=failures
	var f:=FileAccess.open(screenshot_dir.path_join(phase_tag+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(_finite_diagnostic(LifeSaveLibrary._json_safe(audit)),"  ",true,true));f.close()
	print("COMPOSED_RESULT assertions=%d failures=%d phase=%s"%[assertions,failures.size(),phase_tag])
	quit(0 if failures.is_empty() else 1)
