extends SceneTree
## Public furnishing lifecycle with an occupied worktop, including real save/load.
var app:Node
var checks:int=0
var failures:int=0
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1;push_error(message)
func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Run with an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
	run.call_deferred()
func frames(count:int=2)->void:
	for i:int in count:await process_frame
func item(id:String)->Dictionary:return app._find_item(id)
func run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await frames(3);app.set_sound(false);app.selected_lot=0;app.start_household();await frames(3)
	app.set_process(false);app.household.set_speed(0);app.set_build_mode(true);app.world.set_process(false)
	app.household.set_funds(20000)
	var counter:Dictionary=app.world.closest_item("counter",Vector3(-4,.16,-4))
	var counter_id:String=str(counter.id)
	var home_position:Vector3=counter.node.position
	app.begin_purchase("coffee_machine");app.on_placement("coffee_machine",home_position,0)
	var coffee:Dictionary={}
	for entry:Dictionary in app.world.items:
		if str(entry.kind)=="coffee_machine":coffee=entry;break
	check(not coffee.is_empty(),"Coffee bought on an existing starter counter")
	if coffee.is_empty():quit(1);return
	var coffee_id:String=str(coffee.id)
	var coffee_position:Vector3=coffee.node.position
	app.move_item(counter);await frames();app.cancel_placement();await frames()
	check(item(counter_id).node.position.is_equal_approx(home_position),"Cancel returns the moved counter to its original location")
	check(item(coffee_id).node.position.is_equal_approx(coffee_position),"Cancel keeps the supported coffee at its original height and position")
	app.store_item(item(counter_id));await frames()
	check(item(counter_id).is_empty() and app.household_flow.storage_count()==1,"Store removes the occupied counter into storage")
	check(is_equal_approx(item(coffee_id).node.position.y,.16) and not item(coffee_id).has("support_id"),"Storing the counter safely grounds its coffee")
	app.withdraw_stored(counter_id);await frames();app.cancel_placement();await frames()
	check(item(counter_id).is_empty() and app.household_flow.storage_count()==1,"Canceling withdrawal returns the counter once to storage")
	app.withdraw_stored(counter_id);await frames()
	var at:Vector3=Vector3.INF
	for candidate:Vector3 in [Vector3(-3,.16,7),Vector3(3,.16,7),Vector3(3,.16,8)]:
		if app.world.can_place("counter",candidate,0):at=candidate;break
	check(at.is_finite(),"A supported destination exists for the stored counter")
	if not at.is_finite():quit(1);return
	app.on_placement("counter",at,0)
	check(not item(counter_id).is_empty() and app.household_flow.storage_count()==0,"Withdrawing and placing preserves counter identity")
	app.move_item(item(coffee_id));await frames();app.on_placement("coffee_machine",item(counter_id).node.position,0)
	check(str(item(coffee_id).get("support_id",""))==counter_id,"Grounded coffee can be moved onto its restored counter")
	app.store_item(item(coffee_id));await frames()
	check(item(coffee_id).is_empty() and app.household_flow.storage_count()==1,"Supported coffee itself can be stored")
	app.withdraw_stored(coffee_id);await frames();app.cancel_placement();await frames()
	check(item(coffee_id).is_empty() and app.household_flow.storage_count()==1,"Canceling coffee withdrawal does not duplicate or lose it")
	app.withdraw_stored(coffee_id);await frames();app.on_placement("coffee_machine",item(counter_id).node.position,0)
	check(str(item(coffee_id).get("support_id",""))==counter_id,"Coffee withdrawn from storage reacquires its surface support")
	var saved_position:Vector3=item(coffee_id).node.position
	var saved:bool=app.save_game("kitchen_lifecycle","Kitchen support lifecycle")
	check(saved,"The occupied-counter household saves through the public save path")
	if saved:
		app.load_game("kitchen_lifecycle");await frames(5);app.set_process(false);app.world.set_process(false)
		check(not item(coffee_id).is_empty() and item(coffee_id).node.position.is_equal_approx(saved_position),"Loading the save restores supported coffee position")
		check(str(item(coffee_id).get("support_id",""))==counter_id,"Loading preserves the coffee/counter attachment")
		app.set_build_mode(true);app.sell_item(item(counter_id));await frames()
		check(item(counter_id).is_empty() and is_equal_approx(item(coffee_id).node.position.y,.16),"Selling a reloaded support leaves coffee safely on the floor")
	app.queue_free();await frames(3)
	print("KITCHEN_SUPPORT_LIFECYCLE %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
