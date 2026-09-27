extends SceneTree
const Properties=preload("res://scripts/properties.gd")
var checks:int=0
var failures:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,detail:String) -> void:
	checks+=1
	if not ok:failures.append(detail);push_error(detail)
func run() -> void:
	var state:Dictionary={"version":1,"active":"willow","houses":{"willow":{"type":"willow","policy":"","land":{},"layout":[]},"rowan":{"type":"rowan","policy":"","land":{},"layout":[]}}}
	check(Properties.validate(state).is_empty(),"Fixture is a valid two-house property record")
	var bought:Dictionary=Properties.buy_policy(state,"willow","home",2000,2)
	check(bought.ok and bought.cost==200 and bought.funds==1800,"Buying home cover costs 200")
	state=bought.state
	bought=Properties.buy_policy(state,"rowan","premium",1800,4)
	check(bought.ok and bought.cost==200 and bought.funds==1600,"Premium home cover also costs 200")
	state=bought.state
	check(state.houses.willow.next_insurance_day==9 and state.houses.rowan.next_insurance_day==11,"Each home has its own explicit weekly renewal date")
	var money:int=1600
	for date:int in range(5,9):
		var ordinary:Dictionary=Properties.collect_premiums(state,date,money)
		check(ordinary.charged==0 and ordinary.funds==money,"No deduction on unscheduled day "+str(date))
		state=ordinary.state
	var scheduled:Dictionary=Properties.collect_premiums(state,9,money)
	check(scheduled.charged==200 and scheduled.funds==1400,"Only first home renews on day 9")
	check(state.houses.willow.next_insurance_day==9,"Premium collection does not mutate caller's snapshot")
	state=scheduled.state;money=scheduled.funds
	var loaded:Dictionary=Properties.from_save(JSON.parse_string(JSON.stringify(state)))
	check(Properties.validate(loaded).is_empty() and int(loaded.houses.willow.next_insurance_day)==16 and int(loaded.houses.willow.last_insurance_day)==9 and int(loaded.houses.rowan.next_insurance_day)==11,"Renewal dates survive JSON save/load")
	var repeat:Dictionary=Properties.collect_premiums(loaded,9,money)
	check(repeat.charged==0 and repeat.funds==money,"Reload and repeat callback cannot charge twice")
	scheduled=Properties.collect_premiums(loaded,11,money)
	check(scheduled.charged==200 and scheduled.funds==1200,"Second home's independent date renews only it")
	state=scheduled.state;money=scheduled.funds
	var skipped:Dictionary=Properties.collect_premiums(state,17,money)
	check(skipped.charged==0 and skipped.funds==money and skipped.state.houses.willow.next_insurance_day==23,"Imported skipped payment date advances without surprise catch-up deduction")
	var poor:Dictionary=Properties.collect_premiums(state,16,100)
	check(poor.charged==0 and poor.funds==100 and poor.unpaid.size()==1,"Insufficient funds never overdraws the purse")
	check(Properties.collect_premiums(poor.state,16,1000).charged==0,"Failed due date cannot charge later the same day")
	var cancelled:Dictionary=Properties.cancel_policy(state,"willow")
	check(cancelled.ok and not cancelled.state.houses.willow.has("next_insurance_day") and Properties.collect_premiums(cancelled.state,16,money).charged==0,"Cancelling removes its scheduled renewal")
	var legacy:Dictionary=state.duplicate(true)
	legacy.houses.willow.erase("next_insurance_day")
	legacy.houses.willow.erase("last_insurance_day")
	legacy.houses.rowan.policy=""
	var migrated:Dictionary=Properties.collect_premiums(legacy,30,money)
	check(migrated.charged==0 and migrated.state.houses.willow.next_insurance_day==37,"Old insurance loads into a fresh weekly term without charging")
	var corrupt:Dictionary=state.duplicate(true)
	corrupt.houses.willow.next_insurance_day=-1
	check(not Properties.validate(corrupt).is_empty(),"Invalid insurance payment dates reject")
	for bad_date:int in [9,10]:
		corrupt=state.duplicate(true)
		corrupt.houses.willow.next_insurance_day=bad_date
		check(not Properties.validate(corrupt).is_empty(),"Renewal dates cannot repeat the paid date or shift off the weekly schedule")
	print("SECURITY_INSURANCE %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
