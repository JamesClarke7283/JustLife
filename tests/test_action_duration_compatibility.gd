extends SceneTree
## Controlled real action construction, not actor routing or public UI.
var checks:int=0
var failures:int=0
var records:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;if not ok:failures+=1
	records.append({"case":label,"passed":ok});print("CHECK ","PASS " if ok else "FAIL ",label)
func json(value:Variant)->Variant:return JSON.parse_string(JSON.stringify(LifeSaveLibrary._json_safe(value),"",false,true))
func make(stage:String="adult",traits:Array=[])->LifeSim:
	var sim:=LifeSim.new();root.add_child(sim);sim.new_household({"name":"Duration control","age_stage":stage,"traits":traits});sim.autonomy=false
	sim.register_targets([{"id":"lot_exit","kind":"lot_exit","position":Vector3(0,.16,8)},{"id":"stove","kind":"stove","position":Vector3(2,.16,2)},{"id":"desk","kind":"desk","position":Vector3.ZERO},{"id":"sofa","kind":"sofa","position":Vector3.ZERO}],false)
	return sim
func roundtrip(sim:LifeSim,label:String)->void:
	var before:Dictionary=json(sim.get_state());var clone:=LifeSim.new();root.add_child(clone)
	var result:Dictionary=clone.restore_state(before)
	check(bool(result.ok),label+" restores")
	if bool(result.ok):
		var a:Dictionary=before.action_queue[0];var b:Dictionary=clone.get_current_action()
		check(float(a.duration)==float(b.duration) and absf(float(a.elapsed)-float(b.elapsed))<1e-10 and bool(a.paid)==bool(b.paid),label+" exact duration/progress/payment")
	clone.free()
func run()->void:
	for recipe:String in ["garden_skillet","herb_pasta","harvest_bake"]:
		var sim:LifeSim=make();sim.skills.cooking.level=4
		check(sim.queue_action("cook","stove",Vector3(2,.16,2),recipe),recipe+" actual queue")
		sim.begin_current_action();sim._step(7.125);sim._start_front()
		roundtrip(sim,recipe+" paid partial approach");sim.free()
	for active:bool in [false,true]:
		var sim:LifeSim=make("adult",["Active"] if active else [])
		check(sim.queue_action("nap","sofa",Vector3.ZERO),"nap actual queue "+str(active))
		check(float(sim.get_current_action().duration)==(60.0 if active else 75.0),"nap authored duration "+str(active))
		sim.begin_current_action();sim._step(4.25);sim._start_front();roundtrip(sim,"nap "+str(active));sim.free()
	for schooling:bool in [true,false]:
		var sim:LifeSim=make("child" if schooling else "adult");sim.minutes=575.123456789
		var id:String="school_day" if schooling else "career_day"
		check(sim.queue_action(id,"lot_exit",Vector3(0,.16,8)),id+" actual queue")
		sim.begin_current_action();check(sim.is_away(),id+" actual departure")
		if sim.is_away():
			sim._step(5.125);roundtrip(sim,id+" fractional paid absence")
			sim.request_return_home();roundtrip(sim,id+" early return")
		sim.free()
	# Existing cooperative metadata remains governed by its household/session
	# validator; both paid helper and learner have the fixed 45-minute duration.
	var home:=LifeHousehold.new();root.add_child(home)
	home.new_household([{"name":"Parent","age_stage":"adult","traits":[]},{"name":"Child","age_stage":"child","traits":[]}])
	check(bool(home.configure_family([{"a":"player","b":"housemate_1","role":"parent"}]).ok),"paired setup actual family")
	home.register_targets([{"id":"player","kind":"neighbor","position":Vector3(.75,.16,0)},{"id":"housemate_1","kind":"neighbor","position":Vector3(0,.16,0)},{"id":"desk","kind":"desk","position":Vector3(0,.16,0)}],false)
	for m:Dictionary in home.members:m.sim.autonomy=false
	var queued:Dictionary=home.queue_supported_homework("housemate_1","player","desk",Vector3(0,.16,0),Vector3(.75,.16,0))
	check(bool(queued.ok),"actual paired homework queue")
	if bool(queued.ok):
		home.begin_action("player");home.begin_action("housemate_1");home.tick(.75)
		var clone:=LifeHousehold.new();root.add_child(clone)
		var before:Dictionary=json(home.get_state());var result:Dictionary=clone.restore_state(before)
		check(bool(result.ok),"paired partial household restores")
		if bool(result.ok):
			check(clone.members.all(func(m:Dictionary)->bool:return float(m.sim.get_current_action().duration)==45 and float(m.sim.get_current_action().elapsed)>0 and bool(m.sim.get_current_action().paid)),"paired helper/learner durations and paid progress preserved")
		clone.free()
	home.free()
	# Arrival is intentionally unpaid/zero-time and its separate validator is
	# kept. Produce it through the real household transaction.
	home=LifeHousehold.new();root.add_child(home);home.new_household([{"name":"Parent","age_stage":"adult","traits":[]}]);home.set_speed(0)
	var prepared:Dictionary=home.prepare_adoption(["player"],0);check(bool(prepared.ok),"actual adoption proposal")
	if bool(prepared.ok):
		var adopted:Dictionary=home.commit_adoption(prepared.request,Vector3(0,.16,8.5),Vector3(0,.16,6.5),[]);check(bool(adopted.ok),"actual adoption transaction")
		if bool(adopted.ok):
			var clone:=LifeHousehold.new();root.add_child(clone);var result:Dictionary=clone.restore_state(json(home.get_state()))
			check(bool(result.ok),"unpaid zero-time arrival restores")
			if bool(result.ok):
				var a:Dictionary=clone.members[-1].sim.get_current_action();check(a.id=="arrive_home" and a.duration==1 and a.elapsed==0 and not a.paid,"arrival special duration remains exact")
			clone.free()
	home.free()
	var sim:LifeSim=make();sim.queue_action("read","desk",Vector3.ZERO)
	var old:Dictionary=json(sim.get_state());old.action_queue[0].erase("duration");old.action_queue[0].erase("elapsed");old.action_queue[0].erase("paid")
	var clone:=LifeSim.new();root.add_child(clone);var restored:Dictionary=clone.restore_state(old)
	check(bool(restored.ok) and clone.get_current_action().duration==60 and clone.get_current_action().elapsed==0 and not clone.get_current_action().paid,"legacy omitted generic defaults remain valid")
	clone.free();sim.free();await process_frame
	# The report's own folder is a precondition of writing it, so the suite
	# creates it rather than failing on a null file handle when run directly.
	DirAccess.make_dir_recursive_absolute("user://regression/evidence")
	FileAccess.open("user://regression/evidence/duration_compatibility.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":records},"  ",false,true))
	print("DURATION_COMPATIBILITY ",checks," checks / ",failures," failures");quit(1 if failures else 0)
