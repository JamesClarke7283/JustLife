extends SceneTree
## A household that is only living — nobody shopping, nobody ordering — keeps
## its purse until physical theft or an explicit payment. The midnight crime
## roll and an issued bill cannot silently take money.

var checks: int = 0
var failures: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL ", message)
	else:
		print("PASS ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var home := LifeHousehold.new()
	root.add_child(home)
	home.new_household([
		{"name": "Ada", "age_stage": "adult"},
		{"name": "Ben", "age_stage": "adult"},
		{"name": "Cara", "age_stage": "child"},
	])
	home.set_home_value_provider(func() -> int: return 20000)
	for member: Dictionary in home.members:
		member.sim.set_home_value_provider(func() -> int: return 20000)
		member.sim.autonomy = false
		member.sim.wants.clear()
	var start: int = home.funds
	var nights:Array=[]
	home.burglary_due.connect(func(day:int):nights.append(day))
	for step:int in 14*24:
		home.tick(60.0/LifeSim.GAME_MINUTES_PER_SECOND)
		check(home.funds==start,"Clock-only living preserves purse at day %d hour %d."%[home.day,int(home.minutes/60.0)])
	check(not home.bill().is_empty(),"The weekly bill is still waiting for the player.")
	check(home.funds==start,"Neither bills nor a burglary roll silently drain the purse.")
	check(nights.size()==14,"Fourteen midnights request fourteen household burglary rolls.")
	for index:int in nights.size():check(int(nights[index])==index+2,"Nightly roll dates are consecutive and never duplicated.")
	print("PURSE_LEAK ", checks, " assertions; ", failures, " failures")
	quit(1 if failures else 0)
