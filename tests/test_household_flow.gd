extends SceneTree
## Stateful household controller checks; public signals exercise safe UI teardown.
var app:Node
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func item(kind:String) -> Dictionary:
	for furnishing:Dictionary in app.world.items:
		if furnishing.kind==kind:return furnishing
	return {}
func press(text:String) -> void:
	for button:Node in app.find_children("*","Button",true,false):
		if button.text==text and button.is_visible_in_tree():button.pressed.emit();return
	check(false,"Missing public button: "+text)
func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
	press("New game")
	press("+ Add Lifelet")
	await process_frame
	check(app.household_profiles.size()==2,"Add a second Lifelet using the creator button.")
	app.profile.name="Ellis Test";app.profile.hair=2;app.profile.frame=1
	press("Find my home  →")
	await process_frame
	press("Start living  →")
	await process_frame
	check(app.household.members.size()==2 and app.world.actors.size()==2+LifeResidentCatalogue.IDS.size(),
		"Two playable Lifelets and the lane's residents move into the world.")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.set_sound(false)
	# Cooking draws a meal out of the kitchen, so the fixture stocks it through
	# the household's own order before queueing a recipe.
	var ordered:Dictionary=app.household.order_groceries("weekly")
	var collected:Dictionary=app.household.collect_groceries()
	check(bool(ordered.ok) and bool(collected.ok),"The fixture stocks its own kitchen through the household's order.")
	var shop_funds:int=app.household.funds
	app.set_game_speed(8)
	app.queue_interaction(item("fridge"),"cook")
	var first_path:PackedVector3Array=app.path.duplicate()
	var first=app.sim
	app.select_household_member(1)
	check(app.sim!=first and app.sim.character.name=="Ellis Test","Portrait selection switches the controlled Lifelet.")
	app.queue_interaction(item("shower"),"shower")
	check(first.action_queue.size()==1 and app.sim.action_queue.size()==1,"Each Lifelet has its own queue.")
	app.select_household_member(0)
	check(app.path==first_path,"Switching selection preserves the earlier Lifelet's route.")
	var completed:Array=[]
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):completed.append(id+":"+action.id))
	for frame in range(140):app._process(.1)
	check(completed.has("player:cook") and completed.has("housemate_1:shower"),"Both household members arrive and finish their own activities.")
	var earned:int=0
	for member:Dictionary in app.household.members:
		for wish:Dictionary in member.sim.wants:
			if wish.complete:earned+=int(wish.reward)
	check(app.household.funds==shop_funds+earned and app.sim.funds==app.household.member_sim("housemate_1").funds,"One wallet draws the meal from the kitchen once and receives fulfilled-wish rewards once.")
	check(float(first.skills.cooking.xp)>0 and app.household.member_sim("housemate_1").skills.cooking.xp==0,"Skill gains stay with the Lifelet who practiced.")
	app.queue_interaction(item("bed"),"sleep")
	app.select_household_member(1)
	app.queue_interaction(item("bed"),"sleep")
	for frame in range(40):app._process(.1)
	var active_count:int=0
	for member:Dictionary in app.household.members:
		if member.sim.get_current_action().get("phase")=="active":active_count+=1
	check(active_count==1,"A furnishing cannot be occupied by two Lifelets at once.")
	app.select_household_member(0);app.cancel_current_action()
	for frame in range(10):app._process(.1)
	check(app.household.member_sim("housemate_1").get_current_action().get("phase")=="active","Waiting housemate takes a furnishing when its occupant leaves.")
	app.select_household_member(1)
	var before:Dictionary=app.household.get_state()
	var position:Vector3=app.player.position
	app.save_game()
	app.load_game()
	await process_frame
	check(app.household.members.size()==2 and app.household.selected_index==1,"Saving and loading restores household and selection.")
	check(app.sim.character.name=="Ellis Test" and app.player.position.distance_to(position)<.3,"Resume restores the selected Lifelet's name and location.")
	check(app.sim.action_queue.size()==1 and app.sim.action_queue[0].paid,"Resume retains the paid in-progress activity.")
	check(app.household.funds==int(before.funds),"Household funds survive resume.")
	# Exercise signal-driven deletion from a live overlay and queue.
	app.show_interactions(item("fridge"),Vector2(700,400));press("Grab a snack   ℒ4")
	await process_frame
	check(app.overlay.get_child_count()==0,"An interaction button closes its overlay safely.")
	app.cancel_current_action()
	app.refresh_hud()
	if app.queue_box.get_child_count()>0:app.queue_box.get_child(0).pressed.emit()
	await process_frame
	check(app.sim.action_queue.is_empty(),"A queued action cancels itself through its own button.")
	app.queue_free();await process_frame;await process_frame
	await create_timer(.2).timeout
	print("Household flow: %d assertions, %d failures." % [checks,failures]);quit(0 if failures==0 else 1)
