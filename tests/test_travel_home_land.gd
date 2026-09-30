extends "res://tests/test_load_land_rollback.gd"
## Land belongs to the household's home throughout ordinary physical trips,
## including when the only durable save was written at a public venue.

func start_home(name:String)->void:
	app.household_profiles=[{"name":name,"age_stage":"adult","traits":[],"hair":0},
		{"name":"Other plot keeper","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household()
	app.set_process(false);app.set_sound(false);app.household.set_speed(0)
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false
		while not member.sim.action_queue.is_empty():member.sim.cancel_action()
	app.household.set_funds(100000)

func travel(destination:String)->bool:
	app.travel_to(destination)
	if app.mode!="travel":return false
	for step:int in 1800:
		app._process(.05)
		if step%20==0:await process_frame
		if app.mode=="live":return app.current_venue==destination
	return false

func expanded_home_intact(label:String)->void:
	check(Building.land.west==1 and Building.land.east==0,label+" restores the purchased home land")
	var item:Dictionary={}
	for entry:Dictionary in app.world.items:
		if str(entry.get("id",""))=="west_easel":item=entry;break
	check(not item.is_empty() and is_equal_approx(float(item.get("x",0)),-22.0) and is_equal_approx(item.node.position.x,-22.0),label+" restores the actual furnishing at its original purchased-plot position")
	check(app.world.last_layout_error.is_empty() and app.world.navigation.region.has_point(Vector2i(-88,8)),label+" reconstructs a valid home and navigation over the purchased plot")

func _run()->void:
	var original:Dictionary=Building.land
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	start_home("Travel plot keeper")
	check(bool(app.build_transactions.buy_land("west").get("ok",false)),"The household buys an actual west plot")
	app.world.add_item({"id":"west_easel","kind":"easel","x":-22.0,"z":0.0,"rotation":37.0})
	if "--canonical-fixture" in OS.get_cmdline_user_args():
		app.home_layout=app.world.serialize_items();app.properties=app._properties_for_save()
		var layout:Array=app.home_layout.duplicate(true)
		for index:int in layout.size():
			if str(layout[index].get("kind",""))=="__construction":layout[index]=Building.migrate(layout[index]).state
		app.loading_game=true;app.setup_live(layout);app.loading_game=false
		check(not app.world.construction.building_state.is_empty(),"The home fixture uses real canonical construction")
	expanded_home_intact("Before travel")
	check(await travel("park"),"The Lifelet boards, drives and arrives at the park through the public travel path")
	check(Building.land==Land.fresh(),"The public park keeps its own unexpanded lot")
	var property:Dictionary=LifeProperties.house(app.properties,LifeProperties.active(app.properties))
	check(property.get("land",{}).get("west",0)==1,"Departure retains bought land in the existing active home property")
	check(await travel("home"),"The Lifelet physically travels home without reloading")
	expanded_home_intact("Ordinary return")
	if failures>0 or "--reproduce-only" in OS.get_cmdline_user_args():await finish(original);return
	check(await travel("park"),"A second outing reaches the park")
	app.overlay_open=true
	var saved:bool=app.save_game("travel_expanded_away","Expanded home while at the park")
	check(saved,"The public save succeeds away from the expanded home")
	if not saved:print("SAVE_ERROR ",app.notice_text);await finish(original);return
	var data:Dictionary=Library.read_slot("travel_expanded_away").data
	var context:Dictionary=data.members[int(data.selected_index)].state.character.world_state
	check(int(context.land.west)==1 and str(context.venue)=="park","The away save retains home-owned land alongside its current venue")
	# Older away saves wrote the venue's fresh lot into world_state.land. Their
	# existing owned-home property still carries the useful home boundary.
	var older:Dictionary=data.duplicate(true)
	older.members[int(older.selected_index)].state.character.world_state.land=Land.fresh()
	check(bool(Library.save_slot("travel_expanded_old_away","Older away snapshot",older).get("ok",false)),"An older away-save fixture keeps the purchased property despite its venue land field")
	# Destroy the previous controller so no live properties or cached world
	# context can conceal a missing field in the actual disk save.
	app.queue_free();await frames(3)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	app.load_game("travel_expanded_old_away")
	check(str(app.current_venue)=="park" and str(app.active_save_id)=="travel_expanded_old_away" and str(app.notice_text).begins_with("Welcome back"),"A fresh controller loads the saved outing including the older land field")
	check(Building.land==Land.fresh(),"Loading the outing leaves the park's own lot unexpanded")
	var malformed:Dictionary=data.duplicate(true)
	for item:Dictionary in malformed.members[int(malformed.selected_index)].state.character.world_state.home_layout:
		if str(item.get("id",""))=="west_easel":item.x=-99.0
	check(bool(Library.save_slot("travel_expanded_bad_cache","Malformed cached home",malformed).get("ok",false)),"The legacy fixture carries a cached furnishing beyond even the purchased home lot")
	var previous_world:Node=app.world;var previous_sim:Node=app.sim;var previous_land:Dictionary=Building.land
	var previous_state:Dictionary=app.household.get_state(app.world.serialize_items()).duplicate(true)
	app.load_game("travel_expanded_bad_cache")
	check(str(app.notice_text).begins_with("Invalid cached home layout:"),"A malformed cached home is refused before replacing the live outing")
	check(is_same(app.world,previous_world) and is_same(app.sim,previous_sim) and is_same(Building.land,previous_land) and app.household.get_state(app.world.serialize_items())==previous_state,"Cached-home refusal preserves live world, sim, land object and complete household state")
	check(await travel("home"),"The freshly loaded household physically travels home")
	expanded_home_intact("Return after away save and fresh load")
	if failures==0 and not "--canonical-fixture" in OS.get_cmdline_user_args():
		# Homes that predate owned-property records still use their existing
		# saved land field, including across the traveller-context reset.
		app.properties=LifeProperties.fresh()
		check(await travel("park"),"A pre-property household can travel away")
		app.overlay_open=true
		check(app.save_game("travel_expanded_legacy","Legacy home while away"),"A pre-property household saves its existing home land while away")
		app.select_household_member(1)
		check(not app.sim.character.world_state.has("land") and int(app._home_land().west)==1,"Selecting the other member recovers the old household's shared home land")
		app.overlay_open=true
		check(app.save_game("travel_expanded_legacy","Legacy home with changed selection"),"Saving after changing selected members retains the old home land")
		app.load_game("travel_expanded_legacy")
		check(await travel("home"),"The pre-property household returns after loading its away save")
		expanded_home_intact("Pre-property return")
	await finish(original)

func finish(original:Dictionary)->void:
	app.queue_free();await frames(3);Building.land=original
	print("TRAVEL_HOME_LAND checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
