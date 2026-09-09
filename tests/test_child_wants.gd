extends SceneTree
var checks:int=0
var failures:int=0

func check(value:bool,detail:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(detail)

func setup(stage:String="child") -> LifeSim:
	var sim:LifeSim=LifeSim.new()
	sim.new_household({"name":"Curious Lifelet","age_stage":stage,"aspiration":"Balanced","traits":[]})
	sim.autonomy=false;sim.household_bills_enabled=false
	sim.set_aging("normal",false)
	return sim

func complete_snack(sim:LifeSim) -> void:
	check(sim.queue_action("snack","fridge"),"The first snack can use an ordinary queued fridge activity.")
	sim.begin_current_action()
	sim.tick(float(sim.get_action_definition("snack").duration)/LifeSim.GAME_MINUTES_PER_SECOND)

func _initialize() -> void:
	var child:LifeSim=setup()
	check(child.wants[0].id=="first_snack" and child.wants[0].actions==["snack"],"New children receive an attainable snack goal.")
	check(not child.queue_action("cook","stove"),"The attainable goal must not weaken the child stove restriction.")
	var money:int=child.funds
	complete_snack(child)
	check(child.wants[0].complete and child.wants[0].progress==1.0,"An actual completed snack fulfills the child's first want.")
	check(child.satisfaction==60 and child.funds==money-int(child.get_action_definition("snack").cost)+60,"The snack want grants its specified reward once.")
	complete_snack(child)
	check(child.satisfaction==60,"Repeated snacks cannot duplicate the first-want reward.")
	var copy:LifeSim=setup()
	check(copy.restore_state(JSON.parse_string(JSON.stringify(child._json_safe(child.get_state())))).ok and copy.wants[0].complete,"The completed action-based want survives JSON save and load.")
	var legacy:LifeSim=setup()
	legacy.wants[0]={"id":"first_meal","label":"A taste of home","description":"Cook your first fresh meal.","progress":0.0,"target":1.0,"reward":60,"complete":false}
	var state:Dictionary=JSON.parse_string(JSON.stringify(legacy._json_safe(legacy.get_state())))
	check(copy.restore_state(state).ok and copy.wants[0].id=="first_snack" and copy.satisfaction==0,"Old uncompleted child cooking wants migrate without awarding satisfaction.")
	check(copy.funds==legacy.funds and copy.wants[0].reward==60,"Migration preserves funds and the originally promised reward.")
	check(copy.celebrate_birthday() and copy.character.age_stage=="teen" and copy.wants[0].id=="first_snack","Growing to teen retains the unfinished goal, which is still attainable.")
	complete_snack(copy)
	check(copy.wants[0].complete and copy.satisfaction==60,"A retained childhood goal can finish after a birthday.")
	legacy.wants[0].progress=1.0;legacy.wants[0].complete=true;legacy.satisfaction=60
	check(copy.restore_state(legacy.get_state()).ok and copy.wants[0].id=="first_meal" and copy.wants[0].complete,"Previously fulfilled goals are preserved as history, without replacement.")
	for stage:String in ["teen","young_adult","adult","elder"]:
		var other:LifeSim=setup(stage)
		check(other.wants[0].id=="first_meal" and other.get_action_availability("cook","stove").available,stage+" keeps its attainable cooking goal.")
		other.free()
	child.free();copy.free();legacy.free()
	print("CHILD_WANTS %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
