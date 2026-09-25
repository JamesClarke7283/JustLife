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
	check(a.funds==3746 and b.funds==3746 and home.funds==3746,"One ingredient expense updates the shared wallet")
	home.tick(18.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(a.needs.hunger>40 and b.needs.hunger<80,"Eating changes only the acting Lifelet's need")
	check(a.action_queue.is_empty() and b.action_queue.size()==1,"Action queues progress independently")
	check(a.day==b.day and is_equal_approx(a.minutes,b.minutes),"The household clock is shared")
	check(b.skills.logic.xp>0 and a.skills.logic.xp==0,"Skills remain individual")
	home.select(1)
	check(home.selected()==b and home.selected_id()=="housemate_1","Selection changes the active Lifelet")
	b.funds+=145
	home.tick(.1)
	check(a.funds==3891 and home.funds==3891,"Selected-member UI income synchronizes to household")
	home.day=1;home.minutes=1439
	home.tick(3.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(home.day==2,"Household advances across midnight")
	check(home.funds==3891,"Midnight issues a bill instead of silently charging the household")
	check(int(a.pending_bill.amount)==LifeSim.bill_amount_for(0) and a.pending_bill==b.pending_bill,"One bill is owned by the household and mirrored to every member")
	home.set_funds(5000)
	var paid:Dictionary=home.pay_bill()
	check(bool(paid.ok) and home.funds==5000-LifeSim.bill_amount_for(0) and a.bills_paid_total==LifeSim.bill_amount_for(0) and b.bills_paid_total==a.bills_paid_total,"Paying the shared bill debits the household wallet exactly once")
	check(home.bill().is_empty() and not home.utilities_cut(),"Paying clears the bill for every member")
	var snapshot=home.get_state([{"kind":"plant","x":2,"z":3}])
	var restored=LifeHousehold.new();root.add_child(restored)
	var result=restored.restore_state(home.json_safe(snapshot))
	check(result.ok and result.world.size()==1,"Whole household snapshot restores world data")
	check(restored.selected_id()=="housemate_1","Save retains household selection")
	check(restored.members.size()==2 and restored.funds==4880,"Save retains all Lifelets and shared money")
	check(restored.member_sim("housemate_1").action_queue.size()==1,"Background actions survive save")
	var malformed=home.json_safe(snapshot)
	malformed.members[1].state.needs.hunger="broken"
	check(not restored.restore_state(malformed).ok,"Malformed member rejected before replacing household")
	check(restored.members.size()==2 and restored.funds==4880,"Failed restore leaves household untouched")
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
