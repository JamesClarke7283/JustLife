extends SceneTree
var app:Node
var assertions:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(value:bool,message:String) -> void:
	assertions+=1
	if not value:failures+=1;push_error(message)
func press(text:String) -> void:
	for b:Node in app.find_children("*","Button",true,false):
		if b.text==text and b.is_visible_in_tree() and not b.disabled:b.pressed.emit();return
	check(false,"Missing button "+text)
func finish_trip() -> void:
	for i:int in range(1200):
		if app.mode!="travel":break
		app._process(.05)
		if i%10==0:await process_frame
	check(app.mode=="live","Car trip completes before destination assertions.")
func run() -> void:
	if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():push_error("Set JUSTLIFE_DATA_DIR to an isolated test folder.");quit(2);return
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
	press("New game")
	app.add_creator_member();app.start_household();app.set_sound(false)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	await process_frame
	app.set_build_mode(true)
	app.change_floor("896953")
	app.world.construction.add_wall({"x":-1.0,"z":5.6,"w":2.0,"d":.14,"cut":true})
	app.world.add_item({"id":"travel_test_plant","kind":"plant","x":-2,"z":4.4,"rotation":0})
	var home:Array=app.world.serialize_items()
	app.set_build_mode(false);app.set_game_speed(3)
	press("Explore");await process_frame
	check(app.sim.speed==0 and app.overlay_pauses_sim,"Explore pauses the whole household.")
	app.show_neighborhood("park");press("Travel here  →");await finish_trip();await process_frame
	check(app.current_venue=="park" and app.sim.speed==3,"Public map travels to the garden and restores original speed.")
	check(is_equal_approx(app.sim.minutes,495.0),"Travel advances exactly15minutes.")
	check(app.world.items.any(func(i:Dictionary):return i.kind=="bench"),"Garden contains usable original benches.")
	for venue:String in ["park","library","studio"]:
		if app.current_venue!=venue:app.travel_to(venue)
		await finish_trip();await process_frame
		check(app.current_venue==venue and app.world.items.size()>5,"Distinct populated destination: "+venue)
		check(app.household.members.size()==2 and app.world.actors.size()==4,"Household stays together at "+venue)
		for target:Dictionary in app.world.simulation_targets():
			check(not app.world.path_to(app.player.position,target.position).is_empty(),"Accessible "+str(target.id))
		app.set_build_mode(true)
		check(app.mode=="live","Public buildings cannot be sold/edited as owned homes.")
	app.save_game();app.load_game();await process_frame
	check(app.current_venue=="studio","Save/resume retains the current public venue.")
	check(app.home_layout.size()==home.size(),"Away save retains the remodeled home snapshot.")
	app.travel_to("home");await finish_trip();await process_frame
	check(JSON.parse_string(JSON.stringify(app.world.serialize_items(),"",true,true))==JSON.parse_string(JSON.stringify(home,"",true,true)),"Returning home restores furnishings and custom walls.")
	check(app.floor_color=="896953","Returning home retains the chosen flooring.")
	app.household.day=1;app.household.minutes=1439
	app.household.set_speed(1);app.household.tick(3.0/LifeSim.GAME_MINUTES_PER_SECOND)
	check(not app.sim.get_story_events().is_empty(),"A new day creates a readable choice event.")
	app.show_stories();await process_frame
	var event:Dictionary=app.sim.get_story_events()[0]
	var choice:Dictionary={}
	for option:Dictionary in event.choices:
		if option.available:choice=option;break
	press(str(choice.label));await process_frame
	check(app.sim.story_history.size()==1,"Story button applies and records its chosen outcome.")
	check(not app.sim.choose_story_event(event.id,choice.id),"A story choice cannot be redeemed twice.")
	app.close_overlay();app.save_game();app.load_game();await process_frame
	check(app.sim.story_history.size()==1,"Story history survives save and resume.")
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	print("Neighborhood: %d assertions, %d failures." % [assertions,failures]);quit(0 if failures==0 else 1)
