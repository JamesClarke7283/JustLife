extends "res://tests/test_courtesy_beneficiary_base.gd"
## Paused fresh-load rest presentation over the genuine tracked stair checkpoint.
## No action/body/clock edits; the runner generates the nonselected slot through public selection/save.
var variant:String="candidate"
var rest_mode:String=OS.get_environment("REST_MODE")

func actor_timers(actor:LifeActor)->Dictionary:
	var result:Dictionary={}
	for key:String in ["_time","_action_time","_motion_action","_blink_wait","_blink_elapsed","_speech_remaining","_voice_cooldown","_accident_time","_phase_offset"]:result[key]=actor.get(key)
	result.voice_rng_state=str(actor._voice_rng.state)
	result.voice_playing=actor._voice.playing
	return result

func node_pose(node:Node,path:String,result:Dictionary)->void:
	var row:Dictionary={}
	if node is Node3D:row.transform=node.transform;row.visible=node.visible
	if node is MeshInstance3D and node.mesh!=null:
		row.shapes=[]
		for i:int in node.get_blend_shape_count():row.shapes.append(node.get_blend_shape_value(i))
	if node is Skeleton3D:
		row.bones=[]
		for i:int in node.get_bone_count():row.bones.append(node.get_bone_pose(i))
	if not row.is_empty():result[path]=row
	for child:Node in node.get_children():node_pose(child,path+"/"+str(child.name),result)

func presentation(actor:LifeActor)->Dictionary:
	var nodes:Dictionary={};node_pose(actor,"actor",nodes)
	return {"nodes":nodes,"timers":actor_timers(actor),"anchor":actor._activity_anchor.duplicate(true),"sit":actor._sit_amount,"smile":actor._smile}

func all_presentations()->Dictionary:
	var result:Dictionary={}
	for id:String in app.world.actors:result[id]=presentation(app.world.actors[id])
	return result

func binding()->Dictionary:
	return {"selected":app.household.selected_id(),"bound":app.bound_member_id,"sim_same":is_same(app.sim,app.household.selected()),"player_same":app.player==app.world.actors[app.household.selected_id()],"path":app.path.duplicate(),"path_index":app.path_index,"walk":app.walk_only,"destination":app.walk_destination,"pending":app.pending_action.duplicate(true),"generation":app.route_generation,"waiting":app.waiting_for_target,"resume":app.resume_activity}

func contact(actor:LifeActor)->Dictionary:
	var anchor:Dictionary=actor._activity_anchor
	if anchor.is_empty():return {"has_anchor":false}
	var support:Vector3=actor.visual.to_global(Vector3(0,actor._hip_height,-.10*actor._proportion if str(anchor.kind)=="bed" else 0.0))
	return {"has_anchor":true,"kind":anchor.kind,"action":anchor.action,"anchor":anchor.position,"support":support,"gap":support.distance_to(anchor.position),"body_up_dot":actor.visual.global_basis.y.normalized().dot(Vector3.UP),"eyes":actor._blink_shapes.map(func(e:Dictionary):return e.mesh.get_blend_shape_value(int(e.index)))}

func run()->void:
	phase="rest_"+variant+"_"+rest_mode
	input_guard=LineEdit.new();input_guard.name="DiagnosticPolledInputGuard";input_guard.position=Vector2(-10000,-10000);root.add_child(input_guard)
	app=MainScene.instantiate();root.add_child(app);current_scene=app;freeze(app);await frames(3)
	var read:Dictionary=LifeSaveLibrary.read_slot(loaded_slot)
	check(bool(read.get("ok",false)),"Actual input validates through named read")
	if not bool(read.get("ok",false)):await finish();return
	app.load_game(loaded_slot);freeze(app);input_guard.grab_focus();await frames(3)
	check(app.active_save_id==loaded_slot and app.mode=="live" and app.household.speed==0 and app.household.members.all(func(m:Dictionary):return m.sim.speed==0),"Actual named input loads fully paused")
	compare_loaded(read.data);report.loaded=wire(read);report.initial=wire(authoritative_facts());report.initial_presentation=wire(all_presentations());report.initial_binding=wire(binding())
	var sleeper:LifeActor=app.world.actors.housemate_1
	var action:Dictionary=app.household.member_sim("housemate_1").get_current_action()
	check(str(action.get("id",""))=="sleep" and str(action.get("phase",""))=="active","Genuine Ellis active Sleep is preserved")
	report.initial_contact=wire(contact(sleeper))
	if rest_mode=="producer":
		var before:Dictionary=authoritative_facts()
		app.household_chips["player"].pressed.emit();freeze(app);input_guard.grab_focus()
		check(app.household.selected_id()=="player" and app.bound_member_id=="player","Actual household chip makes sleeper nonselected")
		var after:Dictionary=authoritative_facts()
		for key:String in ["clock","funds","people","actors","food","sanitation","visitor","stair_locks","journeys"]:check(before[key]==after[key],"Public selection leaves authoritative "+key+" exact")
		var saved:bool=app.save_game("rest_actual_nonselected","Paused sleep with another Lifelet selected");freeze(app)
		var actual:Dictionary=LifeSaveLibrary.read_slot("rest_actual_nonselected")
		check(saved and bool(actual.get("ok",false)),"Actual named nonselected sleeper save validates")
		check(after==authoritative_facts(),"Named save preserves complete authoritative paused state")
		report.producer={"before":wire(before),"after_selection":wire(after),"after_save":wire(authoritative_facts()),"actual":wire(actual)}
		check(DirAccess.copy_absolute(LifeSaveLibrary._slot_path("rest_actual_nonselected"),OS.get_environment("REST_RUN_ROOT").path_join("evidence/actual_nonselected.json"))==OK,"Copy only actual generated slot bytes")
	else:
		if variant=="candidate":
			var c:Dictionary=contact(sleeper)
			check(bool(c.has_anchor) and str(c.kind)=="bed" and str(c.action)=="sleep" and float(c.gap)<.015 and absf(float(c.body_up_dot))<.05,"Fresh paused Sleep back meets real mattress with lying orientation")
			check(c.eyes.all(func(value:float):return value==1.0),"Fresh sleeping eyelids are closed without a blink sample")
			report.active_rest_contacts={}
			for member:Dictionary in app.household.members:
				var current:Dictionary=member.sim.get_current_action()
				if str(current.get("phase",""))!="active" or str(current.get("id","")) not in ["sleep","nap"]:continue
				var rest:Dictionary=contact(app.world.actors[member.id]);report.active_rest_contacts[member.id]=wire(rest)
				check(rest.has_anchor and rest.gap<.015 and rest.eyes.all(func(value:float):return value==1.0),"Every actual active sleeper has supported contact and closed eyes: "+str(member.id))
			var consequences:Dictionary=semantic();var physical:Dictionary=authoritative_facts();var bound:Dictionary=binding();var visuals:Dictionary=all_presentations()
			app._reconstruct_paused_rest()
			check(semantic()==consequences and authoritative_facts()==physical and binding()==bound,"Repeated rest restore leaves exact consequences and selected binding")
			check(all_presentations()==visuals,"Repeated rest restore is exactly idempotent for all actor pose/timer data")
		var pre:Dictionary=semantic();var expected:Dictionary=pre.duplicate(true);var physical_before:Dictionary=authoritative_facts();var before_visual:Dictionary=all_presentations()
		var cache_ids:Array[String]=[MORGAN]
		if rest_mode=="nonselected":cache_ids.append("housemate_1")
		for id:String in cache_ids:
			check(not app.traversal.routes.has(id) and not expected.motions[id].has("traversal"),"This exact fixture begins with absent derived route cache and no authoritative route: "+id)
			expected.motions[id]["traversal"]={}
		report.expected_empty_cache_insertions=cache_ids
		for i:int in 10:await ordinary_step()
		check(semantic()==expected and authoritative_facts()==physical_before,"Ten paused calls preserve all consequential state with only existing empty route cache fill")
		# The controller sets anchors while paused in the baseline too. Pose nodes
		# and timers remain frozen; anchor dictionary preparation is recorded.
		var after_visual:Dictionary=all_presentations()
		for id:String in before_visual:
			check(before_visual[id].nodes==after_visual[id].nodes and before_visual[id].timers==after_visual[id].timers,"Ordinary pause freezes every actor pose and timer: "+id)
		report.paused={"before":wire(pre),"expected":wire(expected),"after":wire(semantic()),"before_presentations":wire(before_visual),"after_presentations":wire(after_visual),"binding":wire(binding())}
		report.after_contact=wire(contact(sleeper))
		if rest_mode=="selected":await component_checks()
	report.final=wire(authoritative_facts());await finish()

func component_checks()->void:
	var actor:LifeActor=LifeActor.new();root.add_child(actor);freeze(actor)
	actor.configure({"name":"Rest pose component","age_stage":"teen","frame":1,"hair":1,"outfit":1,"height_scale":1.05,"body_scale":1.1,"low_detail":true});actor.voice_enabled=false
	actor.position=Vector3(2,.16,3);actor.rotation.y=.7
	var original_root:Transform3D=actor.transform
	for entry:Dictionary in [{"kind":"bed","action":"sleep"},{"kind":"seat","action":"nap"}]:
		actor.set_activity_anchor(Vector3(1,.68,2),-.3,entry.kind,entry.action)
		var timers:Dictionary=actor_timers(actor)
		actor.call("reconstruct_rest_pose",entry.action)
		var c:Dictionary=contact(actor)
		check(c.gap<.015 and (absf(c.body_up_dot)<.05 if entry.kind=="bed" else c.body_up_dot>.95),"Zero-time rest has appropriate real support/orientation: "+str(entry.kind))
		check(actor.transform==original_root and actor_timers(actor)==timers,"Zero-time rest keeps root and every animation/blink/voice clock")
		check(c.eyes.all(func(value:float):return value==1.0) and actor._sit_amount==(1.0 if entry.kind=="seat" else 0.0),"Rest closes eyelids and applies only matching seated clothing correction")
		var posed:Dictionary=presentation(actor);actor.call("reconstruct_rest_pose",entry.action)
		check(posed==presentation(actor),"Repeated component rest pose is exact")
	var cases:Array=[{"kind":"bed","anchor_action":"sleep","call":"read","position":Vector3.ONE},{"kind":"bed","anchor_action":"nap","call":"sleep","position":Vector3.ONE},{"kind":"standing","anchor_action":"sleep","call":"sleep","position":Vector3.ONE},{"kind":"bed","anchor_action":"sleep","call":"sleep","position":Vector3.INF}]
	for item:Dictionary in cases:
		actor.set_activity_anchor(item.position,0,item.kind,item.anchor_action);var before:Dictionary=presentation(actor);actor.call("reconstruct_rest_pose",item.call)
		check(presentation(actor)==before,"Unsupported/mismatched/nonfinite rest request changes no presentation")
	actor.clear_activity_anchor();var missing:Dictionary=presentation(actor);actor.call("reconstruct_rest_pose","sleep");check(presentation(actor)==missing,"Missing rest anchor does nothing")
	var sleeping:Dictionary=presentation(actor);actor.animate(.5,0,false,"");check(presentation(actor)==sleeping,"Ordinary awake pause remains an exact pose/timer freeze")
	actor.queue_free();await frames()

const MORGAN="housemate_2"
var input_guard:LineEdit
var phase:String=""
var loaded_slot:String=OS.get_environment("REST_SLOT")
var report:Dictionary={}
func _initialize()->void:
	var project:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	var work:String=OS.get_environment("REST_RUN_ROOT")
	if not project.get_file().begins_with("justlife-playthrough-rest") or work.is_empty() or OS.get_environment("JUSTLIFE_DATA_DIR")!=work.path_join("save_data") or OS.get_environment("XDG_DATA_HOME")!=work.path_join("userdata") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Private rest-pose project and all save roots required");quit(2);return
	root.gui_disable_input=true;node_added.connect(exclude_input);run.call_deferred()
func exclude_input(node:Node)->void:
	node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false);node.set_process_shortcut_input(false)
func freeze(node:Node)->void:
	exclude_input(node);node.set_process(false);node.set_physics_process(false)
	for child:Node in node.get_children():freeze(child)
func excluded(node:Node)->bool:
	if node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input() or node.is_processing_shortcut_input():return false
	for child:Node in node.get_children():
		if not excluded(child):return false
	return true
func ordinary_step()->void:
	freeze(app);input_guard.grab_focus()
	check(root.gui_disable_input and excluded(app) and root.gui_get_focus_owner()==input_guard,"Native event modes and polled input excluded")
	app._process(.05);freeze(app);await frames(1)
func finish()->void:
	var stream:WeakRef=weakref(app.ambience_player.stream);var playback:WeakRef=weakref(app.ambience_player.get_stream_playback()) if app.ambience_player.has_stream_playback() else null
	app.queue_free();app=null;input_guard.queue_free();await frames(4)
	var start:int=Time.get_ticks_msec()
	while (stream.get_ref()!=null or (playback!=null and playback.get_ref()!=null)) and Time.get_ticks_msec()-start<1000:await create_timer(.01).timeout
	check(stream.get_ref()==null and (playback==null or playback.get_ref()==null),"Observed audio resources drain")
	report.checks=assertions;report.failures=failures;report.mode=rest_mode
	var file:=FileAccess.open(OS.get_environment("REST_RUN_ROOT").path_join("evidence/rest.json"),FileAccess.WRITE);file.store_string(JSON.stringify(wire(report),"  ",true,true));file.close()
	print("REST_POSE %d checks, %d failures"%[assertions,failures.size()]);quit(0 if failures.is_empty() else 1)

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

func authoritative_facts()->Dictionary:
	# Same named authoritative scope as the accepted stair phase study, plus
	# sanitation/all visible bodies. Full semantic snapshots accompany saves.
	return {"clock":[app.household.day,app.household.minutes,app.household.speed],"speeds":speeds(),"funds":app.household.funds,"people":app.household.members.map(func(m:Dictionary):return {"id":m.id,"position":app.world.actors[m.id].position,"yaw":app.world.actors[m.id].rotation.y,"queue":m.sim.action_queue.duplicate(true),"needs":m.sim.needs.duplicate(true),"career":m.sim.career.duplicate(true),"education":m.sim.education.duplicate(true)}),"actors":semantic().actors,"journeys":app.traversal.snapshot(),"food":app.household.meals.get_state(),"sanitation":app.household.sanitation.get_state(),"visitor":app.residents.home_visit.state.duplicate(true),"stair_locks":app.traversal.stairs.duplicate(true)}


func compare_loaded(disk:Dictionary)->void:
	check(app.household.funds==int(disk.funds) and app.household.day==int(disk.day) and app.household.minutes==float(disk.minutes),"Fresh named load preserves exact decoded wallet and clock")
	check(_same(_project_journeys(disk.journeys),app.traversal.snapshot()),"Fresh complete authoritative journeys match exact decoded scalars and existing typed vector/yaw projection")
	for saved:Dictionary in disk.members:
		var sim:LifeSim=app.household.member_sim(str(saved.id))
		check(_same(_project_queue(saved.state.action_queue),sim.action_queue),"Complete fresh queue/paid/duration/target and elapsed-derived progress: "+str(saved.id))
		check(sim.needs==saved.state.needs and sim.career==saved.state.career,"Exact fresh needs and career: "+str(saved.id))
		check(sim.education==_decoded_integer_fields(saved.state.education,["attended","enrolled_day","first_class_day","homework","last_attendance_day","last_day","last_homework_day","last_prepared_homework_day","missed","prepared","version"],str(saved.id)+".education"),"Exact education with existing nominated integer identities: "+str(saved.id))
	check(app.household.meals.get_state()==_decoded_integer_fields(disk.meals,["version","serial"],"food"),"Exact fresh food with only existing version/serial integer identities")
