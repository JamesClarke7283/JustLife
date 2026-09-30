extends "res://tests/test_playthrough.gd"
## Continuous play through engine frames. No direct clock, needs, positions,
## action phases or completion changes. See run_sustained_play.py.
var journal:Dictionary={"start":0.0,"target":0.0,"samples":[],"actions":{},"notices":[],"issues":[],"checkpoints":[],"sessions":0,"pet_requests":[],"pet_attempts":0}
const OBSERVATION_KEYS:Array[String]=["actions","samples","notices","issues","pet_requests","pet_attempts","pet_rotation","library_excursion"]
const OPEN_PET_REQUESTS:Array[String]=["requested","pending","queued"]
const PET_REQUEST_GRACE:float=360.0
var last_sample:float=0.0
var positions:Dictionary={}
var signatures:Dictionary={}
var stationary:Dictionary={}
var critical:Dictionary={}
var pet_low_social_since:Dictionary={}
var pet_low_hygiene_since:Dictionary={}
var resident_tracks:Dictionary={}
var resident_last_observed:float=-1.0
var last_day:int=0
var next_command:float=0.0
var last_ui_notice:String=""
var stop_reason:String=""
var journal_path:String="user://sustained_journal.json"
var segment_days:int=maxi(1,int(OS.get_environment("JUSTLIFE_SEGMENT_DAYS")))
var total_days:int=maxi(1,int(OS.get_environment("JUSTLIFE_TOTAL_DAYS")))

class EngineErrors:
	extends Logger
	var pending:Array[Dictionary]=[]
	var guard:=Mutex.new()
	func _log_error(function:String,file:String,line:int,code:String,message:String,_notify:bool,_type:int,backtrace:Array[ScriptBacktrace])->void:
		var record:Dictionary={"function":function,"file":file,"line":line,"code":code,"message":message,"backtrace":str(backtrace)}
		guard.lock();pending.append(record);guard.unlock()
	func drain()->Array[Dictionary]:
		guard.lock();var records:Array[Dictionary]=pending;pending=[];guard.unlock()
		return records

var engine_errors:EngineErrors
var excursion_active:bool=false
var excursion_failed:bool=false
var excursion_interrupted:bool=false
var excursion_car_entry:RefCounted
var next_excursion_check:float=0.0

func _run()->void:
	engine_errors=EngineErrors.new();OS.add_logger(engine_errors)
	screenshot_dir="res://art/sustained_play"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	if OS.get_environment("JUSTLIFE_SUSTAINED_RESUME")=="1":
		var stored_journal:Variant=JSON.parse_string(FileAccess.get_file_as_string(journal_path)) if FileAccess.file_exists(journal_path) else null
		if not stored_journal is Dictionary or not stored_journal.get("checkpoints") is Array or stored_journal.checkpoints.is_empty():
			push_error("No committed playthrough checkpoint; existing files preserved.")
			app.queue_free();await frames(3);quit(1);return
		journal=stored_journal
		var saved:Dictionary=journal.checkpoints.back()
		if not _restore_checkpoint_bytes(saved):
			app.queue_free();await frames(3);quit(1);return
		var saved_document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LifeSaveLibrary._slot_path(str(saved.slot))))
		var saved_layout:Dictionary=_layout_by_id(saved_document.data.world)
		app.load_game(str(saved.slot));await frames(8)
		var restored_layout:Dictionary=_layout_by_id(app.world.serialize_items())
		if not equivalent(restored_layout,saved_layout):
			print("SUSTAINED_RESTORE_LAYOUT_MISMATCH ",JSON.stringify({"expected":saved_layout,"actual":restored_layout,"layout_error":str(app.world.last_layout_error)}))
		check(equivalent(restored_layout,saved_layout),"Restart retains every furnishing, placement and construction record")
		check(absf(_now()-float(saved.at))<.01,"Restart retains the exact saved game clock")
		check(app.household.funds==int(saved.funds),"Restart retains household funds")
		check(app.household.members.size()==saved.members.size(),"Restart retains every Lifelet")
		for member:Dictionary in saved.members:
			var restored:LifeSim=app.household.member_sim(str(member.id))
			for field:String in ["needs","skills","career","lifecycle"]:
				check(equivalent(restored.get_state()[field],member.state[field]),"Restart retains "+str(member.id)+" "+field)
			if restored.action_queue.size()!=member.state.action_queue.size():
				print("SUSTAINED_RESTORE_QUEUE_MISMATCH ",JSON.stringify({"member":member.id,"expected":member.state.action_queue,"actual":restored.action_queue,"notice":str(app.notice_text),"notice_queue":app.notice_queue}))
			check(restored.action_queue.size()==member.state.action_queue.size(),"Restart retains queued activity count for "+str(member.id))
			if restored.action_queue.size()==member.state.action_queue.size():
				for i:int in restored.action_queue.size():
					var actual:Dictionary=restored.action_queue[i];var expected:Dictionary=member.state.action_queue[i]
					check(actual.id==expected.id and actual.target_id==expected.target_id and actual.paid==expected.paid and absf(float(actual.elapsed)-float(expected.elapsed))<.001,"Restart retains queued activity identity, payment and progress")
		if saved.has("services"):
			check(equivalent(app.household.pets,saved.services.pets),"Restart retains pets and their care")
			check(equivalent(app.household.meals.get_state(),saved.services.meals),"Restart retains prepared food and servings")
			check(equivalent(app.household.groceries,saved.services.groceries),"Restart retains groceries and delivery state")
			check(equivalent(app.household.journeys,saved.services.journeys),"Restart retains saved journeys")
			if saved.services.has("street"):
				check(equivalent(app.street_life.snapshot(),saved.services.street),"Restart retains street positions, directions and presence")
			if saved.services.has("residents"):
				check(equivalent(app.residents.snapshot(),saved.services.residents),"Restart retains resident positions, directions, routines and visits")
		if failures.is_empty() and not _restore_observations(saved):
			app.queue_free();await frames(3);quit(1);return
	else:
		await _new_household()
		journal.start=_now();journal.target=_now()+total_days*1440.0
		last_sample=_now();next_command=_now()+60.0
	journal.sessions=int(journal.sessions)+1
	if not failures.is_empty():
		print("SUSTAINED_RESULT saved-state verification failed; checkpoint preserved")
		app.queue_free();await frames(3);quit(1);return
	_connect_observers()
	_poll_engine_errors()
	if not stop_reason.is_empty():
		_flush();app.queue_free();await frames(3);quit(1);return
	if app.current_venue!="home":
		_issue("A sustained checkpoint must resume at home.",{"venue":app.current_venue});_flush();app.queue_free();await frames(3);quit(1);return
	await _ensure_pet_supplies()
	last_day=app.household.day
	var segment_target:float=minf(float(journal.target),_now()+segment_days*1440.0)
	await _checkpoint("session_start")
	# A ready paused home checkpoint is already a natural admission window;
	# do not start another autonomous activity before offering the planned trip.
	var startup_excursion:bool=false
	if _library_excursion_due() and _library_excursion_blocker(segment_target).is_empty():
		startup_excursion=true;await _library_excursion()
	if _now()<segment_target and stop_reason.is_empty() and not startup_excursion:await press("▶▶▶")
	var heartbeat:int=Time.get_ticks_msec()
	var progress_time:int=heartbeat
	var progress_clock:float=_now()
	var control_check:int=heartbeat
	while _now()<segment_target and stop_reason.is_empty():
		await process_frame
		_poll_engine_errors()
		if not stop_reason.is_empty():break
		_observe_ui_notice()
		_poll_pet_requests()
		_observe_residents()
		if _library_excursion_due() and _now()>=next_excursion_check:
			next_excursion_check=_now()+15.0
			var reason:String=_library_excursion_blocker(segment_target)
			if reason.is_empty():
				await _library_excursion()
				progress_clock=_now();progress_time=Time.get_ticks_msec()
				if not stop_reason.is_empty():break
			else:print("SUSTAINED_EXCURSION_WAIT at=",_now()," reason=",reason)
		if Time.get_ticks_msec()-control_check>1000:
			control_check=Time.get_ticks_msec()
			if FileAccess.file_exists("res://checkpoint.request"):
				DirAccess.remove_absolute(ProjectSettings.globalize_path("res://checkpoint.request"))
				segment_target=_now()
		if _now()>progress_clock:
			progress_clock=_now();progress_time=Time.get_ticks_msec()
		if Time.get_ticks_msec()-heartbeat>60000:
			heartbeat=Time.get_ticks_msec()
			print("SUSTAINED_HEARTBEAT day=%d minute=%.2f mode=%s"%[app.household.day,app.household.minutes,app.mode])
		if Time.get_ticks_msec()-progress_time>120000:stop_reason="Game clock stopped for two minutes: "+str(app.mode)
		if _now()-last_sample>=15.0:_sample()
		if app.household.day!=last_day:
			last_day=app.household.day
			await _daily()
		if _now()>=next_command:
			next_command=_now()+360.0
			await _play_command()
		if app.household.speed==0 and not app.overlay_open and app.mode=="live":
			stop_reason="The household paused unexpectedly."
	_sample()
	_poll_pet_requests()
	_poll_engine_errors()
	if _now()>=float(journal.target):
		for request:Dictionary in journal.pet_requests:
			if bool(request.accepted) and str(request.status) in OPEN_PET_REQUESTS:
				_issue("Play target reached before accepted pet care completed: "+str(request.action),{"pet_request":request.duplicate(true),"current":_pet_request_evidence(request)})
	await _checkpoint("segment_end" if stop_reason.is_empty() else "issue")
	var finished:bool=_now()>=float(journal.target)
	journal["clock_complete"]=finished
	journal["complete"]=finished and failures.is_empty() and stop_reason.is_empty()
	journal["last_stop"]=stop_reason
	journal["pet_coverage"]=_pet_coverage()
	_flush()
	print("SUSTAINED_PET_COVERAGE ",JSON.stringify(journal.pet_coverage))
	print("SUSTAINED_RESULT complete=%s day=%d elapsed_days=%.5f sessions=%d issues=%d checks=%d failures=%d stop=%s"%[str(journal.complete),app.household.day,(_now()-float(journal.start))/1440.0,journal.sessions,journal.issues.size(),assertions,failures.size(),stop_reason])
	app.queue_free();await frames(3)
	quit(0 if stop_reason.is_empty() and failures.is_empty() else 1)

func _poll_engine_errors()->void:
	for error:Dictionary in engine_errors.drain():
		print("SUSTAINED_ENGINE_ERROR ",JSON.stringify(error))
		_issue("Engine error: "+str(error.message if not str(error.message).is_empty() else error.code),{"engine_error":error})

func _new_household()->void:
	await _enter_new_game()
	for person:String in ["Alex Vale","Jamie Vale"]:
		if person=="Jamie Vale":await press("+ Add Lifelet")
		var edit:LineEdit=app.find_children("*","LineEdit",true,false)[0]
		edit.text=person;edit.text_changed.emit(person)
	await press("Find my home",true);await press("Willow Cottage");await press("Start living",true);await press("Ⅱ")
	check(app.household.members.size()==2,"Two Lifelets enter the furnished cottage")
	# Long is an ordinary player setting and keeps the same living household
	# playable for all 180 days while still exercising automatic birthdays.
	await press("PauseMenu");await press("Life settings")
	var pace:OptionButton=app.find_child("LifespanSetting",true,false)
	pace.select(2);pace.item_selected.emit(2);await press("Apply")
	for member:Dictionary in app.household.members:
		check(member.sim.lifecycle.lifespan=="long" and member.sim.lifecycle.auto_age,"Long lifespan with automatic birthdays is applied")
	app.pet_shop.show_shop();await frames(2);app.pet_shop.show_species();await frames(2)
	await press("Dog",true);await press("Take ",true)
	check(app.household.pets.pets.size()==1,"A dog is purchased through the pet picker")
	if app.overlay_open:app.close_overlay()
	await frames(3)
	await _public_save("Vale household — continuous 180-day play")
	if app.overlay_open:app.close_overlay()

func _connect_observers()->void:
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):
		var key:String=id+":"+str(action.id)
		journal.actions[key]=int(journal.actions.get(key,0))+1
		for request:Dictionary in journal.pet_requests:
			if str(request.status) not in OPEN_PET_REQUESTS or str(request.member)!=id or str(request.action)!=str(action.id) or str(request.pet)!=str(action.get("target_id","")):continue
			request["status"]="completed";request["accepted"]=true;request["completed_at"]=_now()
			request["completion"]={"elapsed":action.get("elapsed",0),"duration":action.get("duration",0),"paid":action.get("paid",false)}
			print("SUSTAINED_PET_COMPLETED ",JSON.stringify(request))
			break)
	app.household.notice.connect(func(message:String):
		journal.notices.append({"at":_now(),"message":message})
		if journal.notices.size()>500:journal.notices.pop_front())

func _ensure_pet_supplies()->void:
	# Buy ordinary care objects with the household's existing funds, giving the
	# dog real places to eat, rest and play throughout the observation.
	for kind:String in ["pet_bowl","pet_bed_dog","dog_toy_box"]:
		if not first_item(kind).is_empty():continue
		app.set_build_mode(true);await frames(2)
		app.begin_purchase_variant(kind,{"style":"","size":"","color":""})
		var placed:bool=false
		for z:float in [-1.0,1.0,3.0,-3.0]:
			var at:=Vector3(-8.0,.16,z)
			if not app.world.can_place(kind,at,0.0):continue
			app.world.update_ghost(at)
			app.on_placement(kind,app.world.ghost_position,app.world.placement_angle)
			placed=not first_item(kind).is_empty()
			if placed:break
		check(placed,"Bought and placed "+kind+" from existing household funds")
		app.cancel_placement();app.set_build_mode(false);await frames(2)
	if first_item("coffee_machine").is_empty():
		app.set_build_mode(true);await frames(2)
		app.begin_purchase_variant("coffee_machine",{})
		for item:Dictionary in app.world.items:
			if str(item.kind)!="counter":continue
			var at:Vector3=item.node.position
			if not app.world.can_place("coffee_machine",at,0):continue
			app.world.update_ghost(at)
			app.on_placement("coffee_machine",app.world.ghost_position,0)
			break
		check(not first_item("coffee_machine").is_empty(),"Bought a countertop coffee machine for everyday use")
		app.cancel_placement();app.set_build_mode(false);await frames(2)

func _now()->float:return (app.household.day-1)*1440.0+app.household.minutes

func _layout_by_id(layout:Array)->Dictionary:
	var records:Dictionary={}
	for entry:Dictionary in layout:
		var key:String="__construction" if str(entry.get("kind",""))=="__construction" else str(entry.id)
		var record:Dictionary=entry.duplicate(true)
		if record.has("rotation"):record.rotation=fposmod(float(record.rotation),360.0)
		records[key]=record
	return records

func _observe_residents()->void:
	# Check actual frame-to-frame movement so a daily save cannot miss a
	# neighbour trapped in a walking phase. Conversations and visits can
	# intentionally hold a resident still and are not walking failures.
	var now:float=_now()
	var elapsed:float=maxf(0.0,now-resident_last_observed) if resident_last_observed>=0.0 else 0.0
	resident_last_observed=now
	var service:LifeResidents=app.residents
	for id:String in service.PEOPLE:
		var state:Dictionary=service.locations.get(service.active_place,{}).get(id,{})
		var walking:bool=app.household.speed>0 and str(state.get("phase",""))=="walking" and service.present(id) and not service.home_visit.owns(id) and not service.home_visit.owns_bell(id) and service._speaker(id).is_empty()
		if not walking:
			resident_tracks.erase(id);continue
		var point:Vector3=app.world.actors[id].position
		var previous:Dictionary=resident_tracks.get(id,{})
		var still:bool=false
		if str(previous.get("place",""))==service.active_place and previous.has("position"):
			var anchor:Array=previous.position
			still=point.distance_to(Vector3(float(anchor[0]),float(anchor[1]),float(anchor[2])))<.02
		if still:
			previous.stationary=float(previous.stationary)+elapsed
		else:
			resident_tracks[id]={"place":service.active_place,"position":vec(point),"stationary":0.0}
		if float(resident_tracks[id].stationary)>180.0:
			_issue("Walking neighbour unmoving for three hours: "+id,{"resident":id,"state":state.duplicate(true),"position":vec(point),"tracker":resident_tracks[id].duplicate(true)})

func _sample()->void:
	var at:float=_now();var elapsed:float=at-last_sample;last_sample=at
	var row:Dictionary={"at":at,"day":app.household.day,"funds":app.household.funds,"stock":app.household.groceries.get("stock",0),"members":[],"doors":app.world.construction.doors.passages.size()}
	for member:Dictionary in app.household.members:
		var id:String=str(member.id);var sim:LifeSim=member.sim
		var actor:Node3D=app.world.actors[id];var action:Dictionary=sim.get_current_action()
		var signature:String=str(action.get("id",""))+":"+str(action.get("target_id",""))+":"+str(action.get("phase",""))
		var motion:Dictionary=app.motion_states.get(id,{})
		var stalled:bool=str(action.get("phase",""))=="approach" and not bool(motion.get("waiting",false)) and signatures.get(id,"")==signature and positions.has(id) and actor.position.distance_to(positions[id])<.02
		stationary[id]=float(stationary.get(id,0))+elapsed if stalled else 0.0
		critical[id]=float(critical.get(id,0))+elapsed if float(sim.needs.hunger)<5.0 else 0.0
		positions[id]=actor.position;signatures[id]=signature
		row.members.append({"id":id,"age":sim.character.age_stage,"needs":sim.needs.duplicate(),"action":action.duplicate(true),"position":vec(actor.position),"stationary":stationary[id],"hunger_critical":critical[id],"career":sim.career.duplicate(true),"away":sim.is_away()})
		if float(stationary[id])>180.0:_issue("Unmoving approach for three hours: "+id+" "+signature,row)
		if float(critical[id])>360.0:_issue("Hunger below five for six hours: "+id,row)
		if sim.is_spirit():_issue("Unexpected death on long lifespan: "+id,row)
	row["residents"]=[]
	for id:String in app.residents.PEOPLE:
		var state:Dictionary=app.residents.locations.get(app.residents.active_place,{}).get(id,{})
		var actor:Node3D=app.world.actors.get(id)
		if not is_instance_valid(actor):continue
		row.residents.append({"id":id,"phase":state.get("phase",""),"direction":state.get("direction",0),"position":vec(actor.position),"present":app.residents.present(id),"stationary":float(resident_tracks.get(id,{}).get("stationary",0.0))})
	row["pets"]=_pet_snapshot()
	for pet:Dictionary in row.pets:
		var id:String=str(pet.id);var social:float=float(pet.needs.social)
		for need:String in pet.needs:
			var value:float=float(pet.needs[need])
			if not is_finite(value) or value<0.0 or value>100.0:_issue("Invalid observed pet "+need+" need: "+id,row)
		if social>=15.0:pet_low_social_since.erase(id)
		elif not pet_low_social_since.has(id):pet_low_social_since[id]=at
		elif at-float(pet_low_social_since[id])>=1440.0:_issue("Pet social stayed below fifteen for a full observed day: "+id,row)
		if float(pet.needs.hygiene)>=10.0:pet_low_hygiene_since.erase(id)
		elif not pet_low_hygiene_since.has(id):pet_low_hygiene_since[id]=at
		elif at-float(pet_low_hygiene_since[id])>=1440.0:_issue("Pet hygiene stayed below ten for a full observed day: "+id,row)
	journal.samples.append(row)
	# Keep every daily checkpoint separately; the rolling samples diagnose the
	# preceding three days without a growing multi-megabyte write every hour.
	if journal.samples.size()>288:journal.samples.pop_front()

func _pet_snapshot()->Array:
	var result:Array=[]
	for pet:Dictionary in app.household.pets.pets:
		var care:Dictionary=app.household.pet_care(str(pet.id))
		result.append({"id":pet.id,"name":pet.name,"needs":care.needs.duplicate(true),"mood":LifePetCare.mood_label(care),"skills":care.skills.duplicate(true)})
	return result

func _pet_daily_trend()->Dictionary:
	var result:Dictionary={}
	for sample:Dictionary in journal.samples:
		if float(sample.at)<_now()-1440.0:continue
		for pet:Dictionary in sample.get("pets",[]):
			var id:String=str(pet.id);var social:float=float(pet.needs.social)
			if not result.has(id):result[id]={"samples":0,"from":sample.at,"to":sample.at,"first":social,"last":social,"min":social,"max":social,"sum":0.0,"moods":{},"needs":{}}
			var row:Dictionary=result[id]
			row.samples+=1;row.to=sample.at;row.last=social;row.min=minf(float(row.min),social);row.max=maxf(float(row.max),social);row.sum=float(row.sum)+social
			row.moods[str(pet.mood)]=int(row.moods.get(str(pet.mood),0))+1
			for need:String in pet.needs:
				var value:float=float(pet.needs[need])
				if not row.needs.has(need):row.needs[need]={"first":value,"last":value,"min":value,"max":value,"sum":0.0,"samples":0}
				var observed:Dictionary=row.needs[need]
				observed.last=value;observed.min=minf(float(observed.min),value);observed.max=maxf(float(observed.max),value)
				observed.sum=float(observed.sum)+value;observed.samples+=1
	for id:String in result:
		var row:Dictionary=result[id]
		row["mean"]=float(row.sum)/float(row.samples);row.erase("sum")
		row["low_social_minutes"]=_now()-float(pet_low_social_since[id]) if pet_low_social_since.has(id) else 0.0
		row["low_hygiene_minutes"]=_now()-float(pet_low_hygiene_since[id]) if pet_low_hygiene_since.has(id) else 0.0
		for need:String in row.needs:
			var observed:Dictionary=row.needs[need]
			observed["mean"]=float(observed.sum)/float(observed.samples);observed.erase("sum")
	return result

func _issue(detail:String,row:Dictionary)->void:
	if not stop_reason.is_empty():return
	stop_reason=detail;journal.issues.append({"at":_now(),"detail":detail,"sample":row.duplicate(true)})
	print("SUSTAINED_ISSUE ",detail)

func _daily()->void:
	# Paying a posted bill is a player responsibility, not a reason to let an
	# unattended test silently lose utilities and report the resulting hunger.
	if app.household.bill_total_due()>0:
		app.adoption_flow.show_bills();await frames(2)
		var pay:Button=button_matching("PhonePayBill")
		if pay!=null:pay.pressed.emit();await frames(2)
		print("SUSTAINED_BILL day=%d remaining=%d"%[app.household.day,app.household.bill_total_due()])
		app.close_overlay()
	await _checkpoint("day_%03d"%app.household.day)
	if stop_reason.is_empty():await press("▶▶▶")

func _play_command()->void:
	if app.mode!="live" or app.overlay_open:return
	# Give a due daytime outing a quiet admission window. Existing accepted
	# care still runs to completion, and ordinary need autonomy remains active.
	if _library_excursion_due() and app.current_venue=="home" and app.household.minutes>=480.0 and app.household.minutes<=960.0:
		var day_off:bool=true
		for member:Dictionary in app.household.members:
			day_off=day_off and not LifeCareerSchedule.workday(member.sim.day,member.sim.career)
		if day_off:return
	# Request real care when a Lifelet has time. Urgent hygiene precedes social
	# training; neither override consumes the next ordinary care turn.
	for index:int in range(app.household.members.size()):
		var sim:LifeSim=app.household.members[index].sim
		if sim.is_away() or sim.action_queue.size()>1 or float(sim.needs.hunger)<35.0 or float(sim.needs.energy)<25.0:continue
		var member_id:String=str(app.household.members[index].id)
		if app.household.pets.pets.is_empty():return
		var pet_id:String=str(app.household.pets.pets[0].id)
		if _pet_request_open(member_id,pet_id):continue
		app.select_household_member(index)
		app.show_pet_card(pet_id,true);await frames(2)
		var attempt:int=int(journal.pet_attempts)
		var rotation:int=int(journal.get("pet_rotation",attempt))
		var needs:Dictionary=app.household.pet_care(pet_id).needs
		var dog:bool=str(app.household.pets.pets[0].species)=="dog"
		var hygiene_care:bool=dog and float(needs.hygiene)<35.0
		var social_care:bool=dog and not hygiene_care and float(needs.social)<45.0
		var priority:bool=hygiene_care or social_care
		var action_id:String="bathe_pet" if hygiene_care else ("pet_train_social" if social_care else ["pet_play","pet_feed","pet_teach_trick","bathe_pet"][rotation%4])
		var choice:String="Train Social Skills" if social_care else ("Train Clever Tricks" if action_id=="pet_teach_trick" else "PetCare_"+action_id)
		journal.pet_attempts=attempt+1
		journal.pet_rotation=rotation if priority else rotation+1
		var request:Dictionary={"attempt":attempt+1,"at":_now(),"member":member_id,"pet":pet_id,"action":action_id,"choice":choice,"selection":"low_hygiene" if hygiene_care else ("low_social" if social_care else "rotation"),"rotation":rotation,"pet_social":float(needs.social),"pet_hygiene":float(needs.hygiene),"status":"requested","accepted":false}
		journal.pet_requests.append(request)
		request["before"]=_pet_request_evidence(request)
		var command:Button=_pet_care_button(choice)
		if command==null or command.disabled:
			request["status"]="unavailable" if command!=null or not bool(request.before.availability.available) else "missing_button"
			request["reason"]=command.tooltip_text if command!=null else str(request.before.availability.get("reason",""))
			if str(request.status)=="missing_button":_issue("Available pet care is missing from the card: "+choice,{"pet_request":request.duplicate(true)})
		elif _matching_pet_queue(sim,request) or _matching_pending_care(request):
			# Never attribute the completion of a pre-existing action to this press.
			request["status"]="already_requested"
		else:
			var ahead:float=0.0
			for queued:Dictionary in sim.action_queue:ahead+=maxf(0.0,float(queued.get("duration",0))-float(queued.get("elapsed",0)))
			request["deadline"]=_now()+ahead+PET_REQUEST_GRACE
			if float(request.deadline)>float(journal.target):
				request["status"]="skipped_end" # Leave time to observe every accepted completion.
			else:
				command.pressed.emit()
				# Capture admission before another engine frame can cancel it.
				_poll_pet_requests()
				await frames(2)
				_observe_ui_notice();_poll_pet_requests()
				if str(request.status)=="requested":
					var evidence:Dictionary=_pet_request_evidence(request)
					var refused:bool=not bool(evidence.availability.available) or _new_pet_notice(request.before.notice,evidence.notice)
					request["status"]="rejected" if refused else "ignored"
					request["result"]=evidence
					if not refused:_issue("Pet care button neither queued nor deferred the interaction: "+choice,{"pet_request":request.duplicate(true)})
		print("SUSTAINED_COMMAND ",JSON.stringify(request))
		if app.overlay_open:app.close_overlay()
		if priority and str(request.status) in ["unavailable","rejected"]:_retry_priority_care()
		return
	# A working/sleeping household can miss a six-hour slot. Recheck urgent
	# care in an hour without interrupting any existing or accepted action.
	_retry_priority_care()

func _retry_priority_care()->void:
	if app.household.pets.pets.is_empty():return
	var pet:Dictionary=app.household.pets.pets[0]
	if str(pet.species)!="dog":return
	var needs:Dictionary=app.household.pet_care(str(pet.id)).needs
	if float(needs.hygiene)<35.0 or float(needs.social)<45.0:next_command=minf(next_command,_now()+60.0)

func _pet_care_button(choice:String)->Button:
	# Unlike button_matching, retain disabled controls and their player-facing
	# reason. An unavailable option is an observed skip, not an attempted action.
	for node:Node in app.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and (str(node.name)==choice or str(node.text)==choice):return node as Button
	return null

func _pet_request_open(member_id:String,pet_id:String)->bool:
	for request:Dictionary in journal.pet_requests:
		if str(request.status) in OPEN_PET_REQUESTS and (str(request.member)==member_id or str(request.pet)==pet_id):return true
	return false

func _pet_coverage()->Dictionary:
	# Missing historical keys explicitly remain zero. Coverage is evidence,
	# never proof that a disabled option should have been forced to run.
	var result:Dictionary={}
	for action_id:String in ["pet_play","pet_feed","pet_teach_trick","bathe_pet","pet_train_social"]:
		var row:Dictionary={"observed_completions":0,"tracked_accepted":0,"tracked_completed":0,"outcomes":{}}
		for key:String in journal.actions:
			if key.ends_with(":"+action_id):row.observed_completions+=int(journal.actions[key])
		for request:Dictionary in journal.pet_requests:
			if str(request.action)!=action_id:continue
			var status:String=str(request.status)
			row.outcomes[status]=int(row.outcomes.get(status,0))+1
			if bool(request.accepted):row.tracked_accepted+=1
			if status=="completed":row.tracked_completed+=1
		result[action_id]=row
	return result

func _matching_pet_queue(sim:LifeSim,request:Dictionary)->bool:
	if sim==null:return false
	for action:Dictionary in sim.action_queue:
		if str(action.id)==str(request.action) and str(action.get("target_id",""))==str(request.pet):return true
	return false

func _matching_pending_care(request:Dictionary)->bool:
	var pending:Dictionary=app.pending_pet_care.get(str(request.pet),{})
	return str(pending.get("member",""))==str(request.member) and str(pending.get("action",""))==str(request.action)

func _pet_request_evidence(request:Dictionary)->Dictionary:
	var sim:LifeSim=app.household.member_sim(str(request.member))
	return {"at":_now(),"notice":{"visible":str(app.notice_text),"aside":str(app.notice_aside),"queued":Array(app.notice_queue)},"queue":sim.action_queue.duplicate(true) if sim!=null else [],"pending":app.pending_pet_care.get(str(request.pet),{}).duplicate(true),"errand":app._pet_errand(str(request.pet)).duplicate(true),"availability":sim.get_action_availability(str(request.action),str(request.pet)) if sim!=null else {"available":false,"reason":"Lifelet is no longer present."}}

func _new_pet_notice(before:Dictionary,after:Dictionary)->bool:
	var previous:Array=[str(before.visible),str(before.aside)]
	previous.append_array(before.queued)
	var current:Array=[str(after.visible),str(after.aside)]
	current.append_array(after.queued)
	for message:String in current:
		if not message.is_empty() and not previous.has(message):return true
	return false

func _observe_ui_notice()->void:
	var current:String=JSON.stringify([app.notice_text,app.notice_aside,app.notice_queue])
	if current==last_ui_notice:return
	last_ui_notice=current
	if str(app.notice_text).is_empty() and str(app.notice_aside).is_empty() and app.notice_queue.is_empty():return
	journal.notices.append({"at":_now(),"source":"app","message":str(app.notice_text),"aside":str(app.notice_aside),"queued":Array(app.notice_queue)})
	if journal.notices.size()>500:journal.notices.pop_front()

func _poll_pet_requests()->void:
	for request:Dictionary in journal.pet_requests:
		if str(request.status) not in OPEN_PET_REQUESTS:continue
		var sim:LifeSim=app.household.member_sim(str(request.member))
		var status:String="queued" if _matching_pet_queue(sim,request) else ("pending" if _matching_pending_care(request) else "")
		if not status.is_empty():
			if not bool(request.accepted):request["accepted"]=true;request["accepted_at"]=_now()
			if str(request.status)!=status:request["status"]=status;request["acceptance"]=_pet_request_evidence(request)
			request.erase("missing_since")
		elif bool(request.accepted):
			if not request.has("missing_since"):request["missing_since"]=_now()
			# Allow a frame boundary between removing a deferred request and
			# handing it to the normal action queue, without manufacturing arrival.
			if _now()-float(request.missing_since)>1.0:
				request["status"]="disappeared";request["result"]=_pet_request_evidence(request)
				_issue("Accepted pet care disappeared without completion: "+str(request.action),{"pet_request":request.duplicate(true)})
		if str(request.status) in OPEN_PET_REQUESTS and bool(request.accepted) and _now()>float(request.deadline):
			request["status"]="expired";request["result"]=_pet_request_evidence(request)
			_issue("Accepted pet care did not complete after its queue and six-hour allowance: "+str(request.action),{"pet_request":request.duplicate(true)})

func _checkpoint(label:String)->void:
	if excursion_active or excursion_failed or app.current_venue!="home":
		_issue("Retaining the paired home checkpoint after an incomplete excursion.",{"label":label,"excursion":_excursion_evidence()})
		_flush();return
	if app.mode!="live" or app.overlay_open:
		stop_reason="Checkpoint blocked by game UI: "+str(app.mode)
		var visible:Array[String]=[]
		for node:Node in app.find_children("*","Control",true,false):
			if node.is_visible_in_tree() and (node is Label or node is Button):visible.append(str(node.text))
		journal.issues.append({"at":_now(),"detail":stop_reason,"visible_ui":visible})
		if DisplayServer.get_name()!="headless":await screenshot("blocked_"+label)
		_flush();return
	await press("Ⅱ")
	if DisplayServer.get_name()!="headless":await screenshot(label)
	_observe_ui_notice();_poll_pet_requests()
	var saved:bool=app.save_game()
	check(saved,"Saved checkpoint "+label)
	if not saved:stop_reason="Game refused the checkpoint save.";return
	var checkpoint:Dictionary={"label":label,"at":_now(),"day":app.household.day,"funds":app.household.funds,"slot":app.active_save_id,"actions":journal.actions.duplicate(),"pet_coverage":_pet_coverage(),"pets":_pet_snapshot(),"pet_trend":_pet_daily_trend(),"members":[]}
	if label.begins_with("day_"):
		for id:String in checkpoint.pet_trend:
			check(float(checkpoint.pet_trend[id].low_social_minutes)<1440.0,"Daily pet care avoids a full day of critically low social need: "+id)
			check(float(checkpoint.pet_trend[id].low_hygiene_minutes)<1440.0,"Daily pet care avoids a full day of critically low hygiene: "+id)
		print("SUSTAINED_PET_TREND ",JSON.stringify(checkpoint.pet_trend))
	for member:Dictionary in app.household.members:checkpoint.members.append({"id":member.id,"state":member.sim.get_state()})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://sustained_checkpoints"))
	var archive_index:int=journal.checkpoints.size()
	var backup:String="user://sustained_checkpoints/%06d.json"%archive_index
	while FileAccess.file_exists(backup):
		archive_index+=1
		backup="user://sustained_checkpoints/%06d.json"%archive_index
	var copied:int=DirAccess.copy_absolute(ProjectSettings.globalize_path(LifeSaveLibrary._slot_path(app.active_save_id)),ProjectSettings.globalize_path(backup))
	check(copied==OK,"Archived exact checkpoint bytes "+label)
	if copied!=OK:stop_reason="Checkpoint archive failed.";return
	checkpoint["backup"]=backup;checkpoint["sha256"]=FileAccess.get_sha256(backup)
	var document:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(backup))
	var state:Dictionary=document.data
	checkpoint["services"]={"pets":state.pets,"meals":state.meals,"groceries":state.groceries,"journeys":state.get("journeys",{})}
	for member:Dictionary in state.members:
		var context:Dictionary=member.state.character.get("world_state",{})
		if context.has("street"):checkpoint.services["street"]=context.street
		if context.has("residents"):checkpoint.services["residents"]=context.residents
		if checkpoint.services.has("street") and checkpoint.services.has("residents"):break
	# Keep the rolling evidence out of the journal's growing checkpoint list,
	# but commit its exact state alongside the exact game save.
	var observations_backup:String=backup.trim_suffix(".json")+".observations.json"
	if not _write_observation_archive(observations_backup,_observation_snapshot()):
		stop_reason="Checkpoint observation archive failed.";return
	checkpoint["observations_backup"]=observations_backup
	checkpoint["observations_sha256"]=FileAccess.get_sha256(observations_backup)
	journal.checkpoints.append(checkpoint)
	_flush()
	print("SUSTAINED_CHECKPOINT label=%s day=%d minute=%.2f elapsed_days=%.5f actions=%s"%[label,app.household.day,app.household.minutes,(_now()-float(journal.start))/1440.0,JSON.stringify(journal.actions)])

func _restore_checkpoint_bytes(saved:Dictionary)->bool:
	# The rolling game autosave can be newer than the daily journal after a
	# crash. Resume the exact archived save paired with that journal, retaining
	# the displaced autosave as evidence rather than silently discarding it.
	if not saved.has("backup"):return true # First opening-session format.
	var backup:String=str(saved.backup)
	check(FileAccess.file_exists(backup) and FileAccess.get_sha256(backup)==str(saved.sha256),"Checkpoint archive passes SHA256 verification")
	if not failures.is_empty():return false
	var slot_path:String=LifeSaveLibrary._slot_path(str(saved.slot))
	if FileAccess.get_sha256(slot_path)==str(saved.sha256):return true
	var displaced:String="user://sustained_checkpoints/unpaired_%d.json"%Time.get_unix_time_from_system()
	if FileAccess.file_exists(slot_path):
		check(DirAccess.copy_absolute(ProjectSettings.globalize_path(slot_path),ProjectSettings.globalize_path(displaced))==OK,"Preserved newer unpaired autosave")
		if not failures.is_empty():return false
	check(DirAccess.copy_absolute(ProjectSettings.globalize_path(backup),ProjectSettings.globalize_path(slot_path))==OK,"Restored exact checkpoint archive")
	return failures.is_empty()

func _observational_journal()->Dictionary:
	var result:Dictionary={}
	for key:String in OBSERVATION_KEYS:
		var value:Variant=journal.get(key,int(journal.get("pet_attempts",0)) if key=="pet_rotation" else (0 if key=="pet_attempts" else ({} if key in ["actions","library_excursion"] else [])))
		result[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	return result

func _observation_snapshot()->Dictionary:
	var saved_positions:Dictionary={}
	for id:String in positions:saved_positions[id]=vec(positions[id])
	return {"journal":_observational_journal(),"tracker":{"positions":saved_positions,"signatures":signatures.duplicate(),"stationary":stationary.duplicate(),"critical":critical.duplicate(),"pet_low_social_since":pet_low_social_since.duplicate(),"pet_low_hygiene_since":pet_low_hygiene_since.duplicate(),"resident_tracks":resident_tracks.duplicate(true),"resident_last_observed":resident_last_observed,"last_sample":last_sample,"next_command":next_command,"last_ui_notice":last_ui_notice}}

func _write_observation_archive(path:String,record:Dictionary)->bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"Opened observation archive "+path)
	if file==null:return false
	file.store_string(JSON.stringify(record));file.flush()
	var result:int=file.get_error();file.close()
	check(result==OK,"Wrote observation archive "+path)
	return result==OK

func _restore_observations(saved:Dictionary)->bool:
	var snapshot:Dictionary={}
	if saved.has("observations_backup"):
		var path:String=str(saved.observations_backup)
		check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==str(saved.observations_sha256),"Checkpoint observations pass SHA256 verification")
		if not failures.is_empty():return false
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		check(parsed is Dictionary and parsed.get("journal") is Dictionary and parsed.get("tracker") is Dictionary,"Checkpoint observations contain journal and tracker state")
		if not failures.is_empty():return false
		snapshot=parsed
	else:
		# The opening sessions predate observation sidecars. Their checkpoints
		# still contain exact action counts; only retain timed evidence up to
		# that clock and recover the watchdogs from the last committed sample.
		var committed:Dictionary=_observational_journal()
		committed.actions=saved.get("actions",{}).duplicate(true)
		for key:String in ["samples","notices","issues","pet_requests"]:
			committed[key]=committed[key].filter(func(entry:Dictionary)->bool:return float(entry.get("at",INF))<=float(saved.at))
		snapshot={"journal":committed,"tracker":{"last_sample":float(saved.at),"next_command":float(saved.at)+60.0}}
		if not committed.samples.is_empty():
			var sample:Dictionary=committed.samples.back()
			var tracker:Dictionary=snapshot.tracker
			tracker.merge({"last_sample":float(sample.at),"positions":{},"signatures":{},"stationary":{},"critical":{}},true)
			for member:Dictionary in sample.members:
				var id:String=str(member.id);var action:Dictionary=member.action
				tracker.positions[id]=member.position
				tracker.signatures[id]=str(action.get("id",""))+":"+str(action.get("target_id",""))+":"+str(action.get("phase",""))
				tracker.stationary[id]=float(member.get("stationary",0));tracker.critical[id]=float(member.get("hunger_critical",0))
	# Earlier paired observation files predate the optional one-time outing.
	if not snapshot.journal.has("library_excursion"):snapshot.journal["library_excursion"]={}
	if not snapshot.journal.has("pet_rotation"):snapshot.journal["pet_rotation"]=int(snapshot.journal.pet_attempts)
	if not equivalent(_observational_journal(),snapshot.journal):
		# A failed checkpoint can flush newer observations without a new save.
		# Preserve that whole attempted branch before rewinding its counters.
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://sustained_checkpoints"))
		var displaced:String="user://sustained_checkpoints/observations_attempt_%06d_%d.json"%[int(journal.sessions),int(Time.get_unix_time_from_system()*1000)]
		var copied:int=DirAccess.copy_absolute(ProjectSettings.globalize_path(journal_path),ProjectSettings.globalize_path(displaced))
		check(copied==OK,"Preserved uncommitted playthrough observations")
		if copied!=OK:return false
		if not journal.has("observation_archives"):journal["observation_archives"]=[]
		journal.observation_archives.append({"path":displaced,"sha256":FileAccess.get_sha256(displaced),"resumed_at":saved.at,"checkpoint":saved.backup if saved.has("backup") else "legacy"})
	for key:String in OBSERVATION_KEYS:journal[key]=snapshot.journal[key]
	var tracker:Dictionary=snapshot.tracker
	positions.clear()
	for id:String in tracker.get("positions",{}):
		var point:Array=tracker.positions[id];positions[id]=Vector3(float(point[0]),float(point[1]),float(point[2]))
	signatures=tracker.get("signatures",{});stationary=tracker.get("stationary",{});critical=tracker.get("critical",{})
	pet_low_social_since=tracker.get("pet_low_social_since",{})
	pet_low_hygiene_since=tracker.get("pet_low_hygiene_since",{})
	resident_tracks=tracker.get("resident_tracks",{});resident_last_observed=float(tracker.get("resident_last_observed",-1.0))
	last_sample=float(tracker.get("last_sample",saved.at));next_command=float(tracker.get("next_command",float(saved.at)+60.0))
	last_ui_notice=str(tracker.get("last_ui_notice",""))
	print("SUSTAINED_OBSERVATIONS_RESTORED at=%.2f pet_attempts=%d actions=%s"%[float(saved.at),int(journal.pet_attempts),JSON.stringify(journal.actions)])
	print("SUSTAINED_PET_COVERAGE ",JSON.stringify(_pet_coverage()))
	return true

func _flush()->void:
	var temporary:String=journal_path+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	file.store_string(JSON.stringify(journal));file.close()
	var result:int=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(journal_path))
	if result!=OK:push_error("Could not commit the playthrough journal: %d"%result)

## This optional outing is performed once, after the household has settled into
## long-term play. Every committed checkpoint stays at home. Its only mutations
## are normal UI button presses and observational journal entries.
func _library_excursion_due()->bool:
	return OS.get_environment("JUSTLIFE_LIBRARY_EXCURSION")=="1" and app.household.day>=48 and str(journal.get("library_excursion",{}).get("status",""))!="completed"

func _library_excursion_blocker(segment_target:float)->String:
	if app.mode!="live" or app.current_venue!="home" or app.overlay_open:return "Home play is not ready."
	if FileAccess.file_exists("res://checkpoint.request"):return "A checkpoint was requested."
	if segment_target-_now()<120.0 or float(journal.target)-_now()<120.0:return "The segment is close to its boundary."
	if app.household.minutes<480.0 or app.household.minutes>960.0:return "Wait for daytime."
	if app.household.members.size()!=2:return "The qualified outing requires the original two-person household."
	if not app.residents.trip.is_empty() or app.residents.home_visit.active() or app.residents.home_visit.ringing():return "A trip or home visit is in progress."
	if app.safety.unresolved():return "A home safety incident needs attention."
	for request:Dictionary in journal.pet_requests:
		if bool(request.accepted) and str(request.status)!="completed":return "Accepted pet care must finish first."
		if str(request.status) in OPEN_PET_REQUESTS:return "A pet care request is still being admitted."
	if not app.pending_pet_care.is_empty():return "Deferred pet care must finish first."
	var options:Array=app.residents.party_options()
	for member:Dictionary in app.household.members:
		var id:String=str(member.id);var sim:LifeSim=member.sim
		var available:bool=false
		for entry:Dictionary in options:
			if str(entry.id)==id:available=bool(entry.available)
		if not available or sim.is_away() or app.traversal.busy(id):return id+" cannot join the party yet."
		if LifeCareerSchedule.workday(sim.day,sim.career):return "Wait for a day without a work shift."
		if app.world.construction.doors.passages.has(id):return id+" is finishing a door crossing."
		if not app.household.meals.carried_by(id).is_empty():return id+" is carrying food."
		if float(sim.needs.hunger)<45.0 or float(sim.needs.energy)<35.0 or float(sim.needs.bladder)<35.0 or float(sim.needs.hygiene)<25.0:return id+" needs care before an outing."
		# Travel itself ends an ordinary free autonomous pastime. It must never
		# cancel player instructions, pet care, paid work, school, food or sleep.
		for action:Dictionary in sim.action_queue:
			if not bool(action.get("autonomous",false)) or str(action.id) not in LifeSim.LEISURE_ACTIONS or int(action.get("cost",0))!=0:return id+" is completing a protected activity."
	return ""

func _excursion_identity()->Dictionary:
	var result:Dictionary={"selected":app.household.selected_id(),"members":{},"pets":{}}
	for member:Dictionary in app.household.members:
		var character:Dictionary=member.sim.character.duplicate(true)
		character.erase("world_state") # Travel intentionally replaces scene context.
		result.members[str(member.id)]={"character":character,"career":member.sim.career.duplicate(true)}
	for pet:Dictionary in app.household.pets.pets:
		var identity:Dictionary=pet.duplicate(true);identity.erase("care")
		result.pets[str(pet.id)]=identity
	return result

func _excursion_evidence()->Dictionary:
	var actors:Dictionary={}
	for member:Dictionary in app.household.members:
		var actor:Node3D=app.world.actors.get(str(member.id))
		actors[str(member.id)]={"position":vec(actor.position) if is_instance_valid(actor) else [],"queue":member.sim.action_queue.duplicate(true)}
	var trip:Dictionary=app.residents.trip
	var boarding:Dictionary={}
	for id:String in trip.get("boarding",{}):
		var entry:Dictionary=trip.boarding[id]
		boarding[id]={"index":entry.get("index",0),"boarded":entry.get("boarded",false),"endpoint":vec(entry.endpoint) if entry.get("endpoint") is Vector3 else [],"path":[]}
		for point:Vector3 in entry.get("path",PackedVector3Array()):boarding[id].path.append(vec(point))
	return {"at":_now(),"mode":app.mode,"venue":app.current_venue,"trip_phase":trip.get("phase",""),"trip_seconds":trip.get("time",0.0),"canonical":trip.get("canonical",false),"boarding":boarding,"actors":actors,"notice":app.notice_text,"notice_queue":Array(app.notice_queue),"car":vec(app.residents.car.global_position) if is_instance_valid(app.residents.car) else []}

func _excursion_boarding()->void:
	var trip:Dictionary=app.residents.trip
	if trip.is_empty():return
	if app.residents.car_entry!=null:excursion_car_entry=app.residents.car_entry
	if excursion_car_entry!=null and float(excursion_car_entry.total)>=float(excursion_car_entry.TIMEOUT):
		_issue("Library excursion used the car-entry timeout fallback.",_excursion_evidence());return
	for id:String in trip.get("boarding",{}):
		if journal.library_excursion.boarding_arrivals.has(id):continue
		var entry:Dictionary=trip.boarding[id]
		var endpoint:Vector3=entry.endpoint
		var point:Vector3=app.world.actors[id].position
		var method:String="body"
		if point.distance_to(endpoint)>.02 and excursion_car_entry!=null and excursion_car_entry._from.has(id):
			point=excursion_car_entry._from[id];method="car_entry_start"
		if point.distance_to(endpoint)<=.02:
			journal.library_excursion.boarding_arrivals[id]={"point":vec(point),"endpoint":vec(endpoint),"trip_seconds":trip.time,"method":method}
		elif bool(entry.boarded):
			_issue("Library excursion boarded before physically reaching the car: "+id,_excursion_evidence());return

func _excursion_observe()->void:
	if FileAccess.file_exists("res://checkpoint.request") and stop_reason.is_empty():
		excursion_interrupted=true
		stop_reason="Checkpoint requested during library excursion; retaining the previous paired home save."
		journal.library_excursion["interruption"]=_excursion_evidence()
		_flush()
	_poll_engine_errors();_observe_ui_notice();_poll_pet_requests();_observe_residents()
	_excursion_boarding()
	if _now()-last_sample>=15.0:_sample()
	for id:String in app.world.construction.doors.passages:
		var key:String=app.current_venue+":"+id+":"+str(app.world.construction.doors.passages[id].phase)
		journal.library_excursion.door_phases[key]=true

func _excursion_require(condition:bool,detail:String)->bool:
	check(condition,detail)
	if not condition:_issue(detail,{"excursion":_excursion_evidence()})
	return condition and stop_reason.is_empty()

func _excursion_button(label:String)->bool:
	var button:Button=button_matching(label)
	if not _excursion_require(button!=null,"Excursion has visible enabled UI: "+label):return false
	button.pressed.emit();_excursion_observe()
	if not stop_reason.is_empty():return false
	for frame:int in 3:
		await process_frame;_excursion_observe()
		if not stop_reason.is_empty():return false
	return true

func _excursion_travel(destination:String)->bool:
	var began:float=_now();var funds:int=app.household.funds
	journal.library_excursion.phase="outbound" if destination=="library" else "returning"
	journal.library_excursion["boarding_arrivals"]={};excursion_car_entry=null
	if not await _excursion_button("Explore"):return false
	if not await _excursion_button("The Reading Room" if destination=="library" else "Your home"):return false
	if not await _excursion_button("ChooseTripParty"):return false
	for member:Dictionary in app.household.members:
		var id:String=str(member.id)
		if not _excursion_require(button_matching("TripParty_"+id)!=null and app.party_selection.has(id),"Trip picker includes "+id):return false
	if not _excursion_require(app.party_selection.size()==app.household.members.size() and app.household.speed==0,"Trip picker keeps the whole household paused and selected"):return false
	if not await _excursion_button("TripPartyGo"):return false
	if not _excursion_require(app.mode=="travel" and not app.residents.trip.is_empty(),"The public travel button starts "+destination):return false
	var start:int=Time.get_ticks_msec();var progress:int=start;var previous:Dictionary={};var observed_frames:int=0
	while not (app.mode=="live" and app.current_venue==destination and app.residents.trip.is_empty()):
		await process_frame;observed_frames+=1;_excursion_observe()
		if not stop_reason.is_empty():return false
		var evidence:Dictionary=_excursion_evidence()
		if app.mode=="live" and app.residents.trip.is_empty() and app.current_venue!=destination:
			_issue("Library excursion travel ended before reaching "+destination+".",evidence);return false
		# Queued action clocks and trip.time are not physical progress. Compare
		# phase, boarding cursors, bodies and car positions only.
		var physical:Dictionary={"mode":evidence.mode,"venue":evidence.venue,"phase":evidence.trip_phase,"boarding":{},"car":evidence.car,"positions":{}}
		for id:String in evidence.boarding:
			var entry:Dictionary=evidence.boarding[id]
			physical.boarding[id]={"index":entry.index,"boarded":entry.boarded,"endpoint":entry.endpoint}
		for id:String in evidence.actors:physical.positions[id]=evidence.actors[id].position
		if not equivalent(previous,physical):progress=Time.get_ticks_msec();previous=physical
		if Time.get_ticks_msec()-progress>90000 or Time.get_ticks_msec()-start>180000:
			_issue("Library excursion travel timed out.",evidence);return false
	if not _excursion_require(journal.library_excursion.boarding_arrivals.size()==app.household.members.size(),"Every traveller physically reached the car before boarding"):return false
	if not _excursion_require(observed_frames>0 and app.household.speed==0 and not app.overlay_open,"Arrival at "+destination+" is paused after real engine frames"):return false
	if not _excursion_require(absf(_now()-began-15.0)<.01 and app.household.funds==funds,"Travel to "+destination+" takes fifteen natural game minutes with no charge"):return false
	if not _excursion_require(app.world.last_layout_error.is_empty(),"Arrival reconstructs "+destination+" without layout errors"):return false
	if not _excursion_require(app.world.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(app.world.camera.size,16.0) and is_equal_approx(app.world.camera_angle,.62) and is_equal_approx(app.world.camera_elevation,.82) and app.world.camera_target.distance_to(Vector3(0,0,.25))<.001 and app.world.camera.global_transform.origin.is_finite(),"Arrival uses the documented camera framing"):return false
	journal.library_excursion.legs.append({"destination":destination,"began":began,"arrived":_now(),"frames":observed_frames,"boarding":journal.library_excursion.boarding_arrivals.duplicate(true)})
	_flush();return true

func _library_excursion()->void:
	# The last paired home save is the sole recovery point if either leg fails.
	journal["library_excursion"]={"status":"preparing","phase":"home","started":_now(),"door_phases":{},"legs":[]}
	await _checkpoint("before_library_excursion")
	if not stop_reason.is_empty() or not failures.is_empty():return
	var record:Dictionary=journal.library_excursion
	var paired:Dictionary=journal.checkpoints.back()
	record["home_checkpoint"]={"backup":paired.backup,"sha256":paired.sha256,"at":paired.at}
	var baseline:Dictionary={"at":_now(),"target":journal.target,"layout":_layout_by_id(app.world.serialize_items()),"properties":app.properties.duplicate(true),"land":LifeBuildingState.land.duplicate(true),"identity":_excursion_identity()}
	record["departure_queues"]={}
	for member:Dictionary in app.household.members:record.departure_queues[str(member.id)]=member.sim.action_queue.duplicate(true)
	excursion_active=true;record.status="travelling";_flush()
	if not await _excursion_travel("library") or not await _excursion_travel("home"):
		excursion_failed=true;record.status="interrupted" if excursion_interrupted else "failed";record["failure"]=_excursion_evidence();_flush();return
	var after:Dictionary=_layout_by_id(app.world.serialize_items())
	if not equivalent(after,baseline.layout):print("SUSTAINED_EXCURSION_LAYOUT_MISMATCH ",JSON.stringify({"before":baseline.layout,"after":after}))
	var valid:bool=_excursion_require(equivalent(after,baseline.layout),"Round trip preserves every home furnishing and construction record")
	valid=_excursion_require(equivalent(app.properties,baseline.properties) and equivalent(LifeBuildingState.land,baseline.land),"Round trip preserves exact owned properties and home land") and valid
	valid=_excursion_require(equivalent(_excursion_identity(),baseline.identity),"Round trip preserves household, careers, selected member and pet identities") and valid
	valid=_excursion_require(absf(_now()-float(baseline.at)-30.0)<.01 and float(journal.target)==float(baseline.target),"Round trip adds thirty natural minutes and retains the original 180-day target") and valid
	_poll_engine_errors()
	if not valid or not stop_reason.is_empty():
		excursion_failed=true;record.status="interrupted" if excursion_interrupted else "failed";record["failure"]=_excursion_evidence();_flush();return
	# A scene transition legitimately replaces body positions. Start fresh
	# motion anchors; keep need-critical history and all completion evidence.
	positions.clear();signatures.clear();stationary.clear();resident_tracks.clear();resident_last_observed=_now()
	excursion_active=false;record.status="completed";record.phase="home";record["completed_at"]=_now()
	_sample();await _checkpoint("after_library_excursion")
	if stop_reason.is_empty():await press("▶▶▶")
	print("SUSTAINED_LIBRARY_EXCURSION ",JSON.stringify(record))
