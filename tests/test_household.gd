extends SceneTree

var checks:int=0
var failures:int=0

func check(condition:bool,description:String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(description)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var home=LifeHousehold.new()
	root.add_child(home)
	home.new_household([{"name":"Mara Vale","traits":["Creative"]},{"name":"Alex Rowan","traits":["Bookworm"]}])
	check(home.members.size()==2,"Two Lifelets belong to the same household")
	var a:LifeSim=home.member_sim("player")
	var b:LifeSim=home.member_sim("housemate_1")
	a.autonomy=false;b.autonomy=false
	a.wants.clear();b.wants.clear()
	a.needs.hunger=12;b.needs.hunger=80
	a.queue_action("snack","fridge",Vector3.ZERO)
	b.queue_action("read","shelf",Vector3.ZERO)
	home.begin_action("player")
	home.begin_action("housemate_1")
	check(a.funds==2492 and b.funds==2492 and home.funds==2492,"One ingredient expense updates the shared wallet")
	home.tick(3)
	check(a.needs.hunger>40 and b.needs.hunger<80,"Eating changes only the acting Lifelet's need")
	check(a.action_queue.is_empty() and b.action_queue.size()==1,"Action queues progress independently")
	check(a.day==b.day and is_equal_approx(a.minutes,b.minutes),"The household clock is shared")
	check(b.skills.logic.xp>0 and a.skills.logic.xp==0,"Skills remain individual")
	home.select(1)
	check(home.selected()==b and home.selected_id()=="housemate_1","Selection changes the active Lifelet")
	b.funds+=145
	home.tick(.1)
	check(a.funds==2637 and home.funds==2637,"Selected-member UI income synchronizes to household")
	home.day=1;home.minutes=1439
	home.tick(.5)
	check(home.day==2,"Household advances across midnight")
	check(home.funds==2602,"Bills are charged once for the entire household")
	check(a.bills_paid==35 and b.bills_paid==0,"Bill accounting belongs to one household owner")
	var snapshot=home.get_state([{"kind":"plant","x":2,"z":3}])
	var restored=LifeHousehold.new();root.add_child(restored)
	var result=restored.restore_state(home.json_safe(snapshot))
	check(result.ok and result.world.size()==1,"Whole household snapshot restores world data")
	check(restored.selected_id()=="housemate_1","Save retains household selection")
	check(restored.members.size()==2 and restored.funds==2602,"Save retains all Lifelets and shared money")
	check(restored.member_sim("housemate_1").action_queue.size()==1,"Background actions survive save")
	var malformed=home.json_safe(snapshot)
	malformed.members[1].state.needs.hunger="broken"
	check(not restored.restore_state(malformed).ok,"Malformed member rejected before replacing household")
	check(restored.members.size()==2 and restored.funds==2602,"Failed restore leaves household untouched")
	var oldsave=a.get_state();oldsave.world=[]
	check(restored.restore_state(home.json_safe(oldsave)).ok,"Earlier single-Lifelet save migrates")
	check(restored.members.size()==1,"Single-Lifelet migration has exactly one member")
	home.set_speed(0)
	var before:float=a.needs.energy
	home.tick(10)
	check(a.needs.energy==before,"Pause freezes every Lifelet")
	home.queue_free();restored.queue_free()
	await process_frame
	print("HOUSEHOLD_TESTS ",checks," assertions; ",failures," failures")
	quit(1 if failures else 0)
