extends SceneTree
## Throwaway: visit Tom's house, cache the layout via the journey path, save, reload.
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0;app.start_household();await process_frame
	app.set_process(false)
	# Establish the two-floor build that forces the journey/cached-layout save path.
	app.set_build_mode(true);app.set_build_level(0);await process_frame
	app.household.funds=99999
	app.set_build_level(1);await process_frame
	var c=app.world.construction
	c.anchored=true;c.anchor=Vector3(-7.6,0,-6.4)
	app.on_construction(c.make_proposal(Vector3(6.9,3.16,6.1)));await process_frame
	app.begin_construction("stairs")
	app.on_construction(c.make_proposal(Vector3(-1.5,.16,-2.5)));await process_frame
	app.set_build_mode(false);await process_frame
	# Visit each resident home so its layout is cached, exactly as play does.
	for place:String in LifeNeighborhood.RESIDENT_HOMES:
		app.travel_to(place);await process_frame
		app.travel_to("home");await process_frame
	var saved:bool=app.save_game("Tom Cached Layout")
	await process_frame
	var slot:String=app.active_save_id
	print("SAVED=",saved," slot=",slot)
	var read:Dictionary=LifeSaveLibrary.read_slot(slot)
	print("READ ok=",read.ok," err=",read.get("error",""))
	app.load_game(slot);await process_frame
	print("LOAD mode=",app.mode," notice=",app.notice.text if app.get("notice")!=null else "")
	print("journey_error=",app.household.journeys.size()>0)
	app.queue_free();await process_frame
	quit(0 if read.ok else 1)
