extends SceneTree
## Blocked autonomy must recover needs without replacing directed work.
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,detail:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(detail)
func run() -> void:
	var sim:=LifeSim.new()
	sim.register_targets([
		{"id":"bed","kind":"bed","position":Vector3(0,.16,0)},
		{"id":"sofa","kind":"sofa","position":Vector3(2,.16,0)},
		{"id":"fridge","kind":"fridge","position":Vector3(4,.16,0)},
		{"id":"books","kind":"bookshelf","position":Vector3(6,.16,0)},
		{"id":"easel","kind":"easel","position":Vector3(8,.16,0)}])
	for need:String in LifeSim.NEED_NAMES:sim.needs[need]=90.0
	# Daytime weekday recovery intentionally prefers a nap. This first control
	# needs a night-time bed preference before testing a blocked-bed fallback.
	sim.minutes=1320.0
	sim.needs.energy=5.0
	sim._choose_autonomous_action()
	check(sim.get_current_action().id=="sleep","Energy first chooses sleep when all recovery objects are available.")
	sim.queue_action("read","books",Vector3(6,.16,0))
	var directed:Dictionary=sim.action_queue[1].duplicate(true)
	check(not sim.reconsider_waiting_autonomy(["bed"],29.9),"Brief contention preserves the original queue position.")
	check(sim.reconsider_waiting_autonomy(["bed"],30.0),"A prolonged unavailable bed permits another recovery object.")
	check(sim.get_current_action().id=="nap" and sim.get_current_action().target_id=="sofa","A free sofa supplies an autonomous nap instead of indefinite bed waiting.")
	check(sim.action_queue[1]==directed,"Replanning preserves the exact later player-directed activity.")
	sim.needs.hunger=1.0
	check(sim.reconsider_waiting_autonomy(["bed","sofa"],60.0),"A second blocked energy object permits critically depleted hunger recovery.")
	check(sim.get_current_action().id=="snack","The more critical recoverable hunger need takes priority.")
	sim.cancel_action()
	check(not sim.reconsider_waiting_autonomy(["books"],500.0),"An explicit player-directed activity is never discarded by waiting autonomy.")
	sim.cancel_action()
	sim.needs.energy=90.0;sim.needs.hunger=90.0;sim.needs.fun=5.0
	sim._choose_autonomous_action()
	check(sim.get_current_action().id=="paint","Creative fun selection executes without a typed conditional-array runtime error.")
	sim.cancel_action();sim.character.traits=["Bookworm"]
	sim._choose_autonomous_action()
	check(sim.get_current_action().id=="read","Bookworm fun selection executes and prefers reading.")
	sim.get_current_action()["cooperation_id"]="preserved_pair"
	check(not sim.reconsider_waiting_autonomy(["books"],500.0),"A coordinated session is preserved by waiting autonomy.")
	sim.free()
	print("WAITING_AUTONOMY %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
