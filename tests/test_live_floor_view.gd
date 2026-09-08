extends SceneTree
## Actual main Buttons and input callbacks on a declared two-storey fixture.
## Optional --capture writes real Forward+ views; headless run makes no art claim.
const Building=preload("res://scripts/building_state.gd")
var app:Node
var checks:int=0
var failures:Array[String]=[]
var output:String="user://live_floor_view"
var captures:Array=[]

func _initialize()->void:
	# This harness creates named slots. Refuse the user's ordinary data directory.
	var source:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	var isolated:String=OS.get_environment("XDG_DATA_HOME").simplify_path().trim_suffix("/")
	var allowed:bool=isolated.is_absolute_path() and isolated.get_base_dir()==source and (isolated.get_file()=="userdata" or isolated.get_file().begins_with("userdata-"))
	allowed=allowed and ProjectSettings.globalize_path("user://").begins_with(isolated+"/")
	allowed=allowed and OS.get_environment("JUSTLIFE_DATA_DIR")==isolated.path_join("save_data") and not ProjectSettings.has_setting("autoload/MCPRuntimeServer")
	if not allowed:
		printerr("Live floor tests require a sanitized project, private XDG_DATA_HOME=<project>/userdata[-label], and JUSTLIFE_DATA_DIR=<XDG_DATA_HOME>/save_data. No save was opened.")
		quit(2);return
	if "--guard-only" in OS.get_cmdline_user_args():print("LIVE_FLOOR_ISOLATION_OK");quit(0);return
	_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func _frames(count:int=2)->void:
	for index:int in count:await process_frame
func _button(name:String)->Button:return app.ui.find_child(name,true,false) as Button
func _press(name:String)->void:
	var target:Button=_button(name)
	check(is_instance_valid(target) and not target.disabled,"Production button is available: "+name)
	if is_instance_valid(target) and not target.disabled:target.pressed.emit()
	await _frames()
func _key(code:int,pressed:bool=true,echo:bool=false)->void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;event.echo=echo
	app._unhandled_input(event)
	await _frames()
func _facts()->Dictionary:
	var members:Dictionary={};var actors:Dictionary={}
	for member:Dictionary in app.household.members:
		members[member.id]={"queue":member.sim.action_queue.duplicate(true),"needs":member.sim.needs.duplicate(true),"day":member.sim.day,"minutes":member.sim.minutes,"speed":member.sim.speed,"funds":member.sim.funds}
	for id:String in app.world.actors:actors[id]=app.world.actors[id].transform
	return {"members":members,"actors":actors,"day":app.household.day,"minutes":app.household.minutes,"speed":app.household.speed,"funds":app.household.funds,"routes":app.traversal.routes.duplicate(true),"locks":app.traversal.stairs.duplicate(true),"motions":app.motion_states.duplicate(true),"path":app.path.duplicate(),"path_index":app.path_index,"walk_only":app.walk_only,"pending":app.pending_action.duplicate(true),"generation":app.route_generation,"ledger":app.household.meals.get_state().duplicate(true),"layout":app.world.serialize_items().duplicate(true)}
func _fixture()->Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	for level:int in [0,1]:
		for side:int in [-1,1]:state.walls.append({"id":("upper_" if level else "")+("north" if side<0 else "south"),"level":level,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	var quote:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
	check(bool(quote.ok),"Declared fixture has validated supported slabs and a real staircase.")
	return quote.after if bool(quote.ok) else state
func _setup()->void:
	app.household_profiles=[{"name":"Mara Vale","age_stage":"young_adult","traits":[],"hair":0},{"name":"Rowan Vale","age_stage":"young_adult","traits":[],"hair":1}]
	app.creator_family_links=[];app.start_household();app.set_process(false)
	app.loading_game=true
	app.setup_live([{"id":"upper_shelf","kind":"bookshelf","x":3.25,"z":0.0,"rotation":0.0,"level":1},{"id":"ground_shelf","kind":"bookshelf","x":-3.25,"z":0.0,"rotation":0.0},{"id":"upper_chair","kind":"chair","x":2.5,"z":2.0,"rotation":0.0,"level":1},_fixture()])
	app.loading_game=false
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false;member.sim.set_aging("normal",false);member.sim.household_bills_enabled=false
	app.player.position=Vector3(-2,.16,-3.5)
	app.world.actors.housemate_1.position=Vector3(2,3.16,3.5)
	app._store_motion();app.household.set_speed(0);app.world.refresh_actor_layers();app.draw_live()
func _capture(label:String,dimensions:Vector2i)->void:
	root.size=dimensions
	await _frames(5);await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image.get_size()==dimensions,"Actual rendered size matches "+label)
	var file:String=output.path_join(label+".png")
	check(image.save_png(file)==OK,"Actual viewport image saved: "+label)
	var controls:Dictionary={}
	for name:String in ["LiveGroundView","LiveUpperView","CenterLifelet"]:
		var control:Button=_button(name)
		var bounds:Rect2=control.get_global_rect()
		var screen_bounds:Rect2=Rect2(control.get_global_transform_with_canvas()*Vector2.ZERO,control.size*control.get_global_transform_with_canvas().get_scale())
		check(Rect2(Vector2.ZERO,Vector2(1440,900)).encloses(bounds),"Logical button bounds stay in viewport: "+name)
		controls[name]={"logical_bounds":bounds,"canvas_bounds":screen_bounds,"disabled":control.disabled,"tooltip":control.tooltip_text}
	captures.append({"label":label,"dimensions":dimensions,"controls":controls,"view_level":app.world.view_level,"camera_target":app.world.camera_target})
func _run()->void:
	DirAccess.make_dir_recursive_absolute(output)
	app=load("res://scenes/main.tscn").instantiate()
	root.add_child(app);current_scene=app;app.set_process(false);app.set_sound(false)
	await _frames()
	app.start_household();app.household.set_speed(0);app.set_process(false)
	check(_button("LiveGroundView")!=null and _button("LiveUpperView")!=null,"Home Live exposes semantic Ground and Upper controls.")
	check(_button("LiveUpperView").disabled,"Starter home cannot show an absent upper floor.")
	var unchanged:Dictionary=_facts()
	await _key(KEY_PAGEUP)
	check(app.world.view_level==0 and _facts()==unchanged,"Unavailable Page Up neither selects empty upper space nor mutates gameplay.")
	# Canonical ground-only data also must not masquerade as an existing upper slab.
	var ground:Dictionary=Building.fresh();ground.floors=[{"id":"ground_only","level":0,"x":0.0,"z":0.0,"w":12.0,"d":10.0,"material":"cfa97e"}]
	app.world.construction.restore(ground);app.draw_live()
	check(_button("LiveUpperView").disabled,"Migrated/canonical ground-only architecture still disables Upper.")
	_setup();await _frames()
	check(not _button("LiveUpperView").disabled,"Actual supported upper slab enables Upper.")
	unchanged=_facts();await _press("LiveUpperView")
	check(app.world.view_level==1 and app.world.camera.cull_mask&app.world.VIEW_ACTOR_UPPER,"Upper callback reveals upper actors through actual camera layers.")
	check(_facts()==unchanged,"Upper button changes no actor, clock, wallet, queue, route, lock, ledger or layout fact.")
	await _press("LiveGroundView")
	check(app.world.view_level==0 and _facts()==unchanged,"Ground callback reverses only the view.")
	await _key(KEY_PAGEUP);check(app.world.view_level==1 and _facts()==unchanged,"Page Up uses the production input callback without advancing simulation.")
	await _key(KEY_PAGEDOWN);check(app.world.view_level==0 and _facts()==unchanged,"Page Down uses the production input callback without advancing simulation.")
	await _key(KEY_PAGEUP,false);await _key(KEY_PAGEUP,true,true)
	check(app.world.view_level==0,"Key release and key repeat do not switch floors.")
	app.show_person();var overlay_mode:bool=app.overlay_open
	await _key(KEY_PAGEUP);app.set_live_view_level(1);app.center_lifelet()
	check(overlay_mode and app.overlay_open and app.world.view_level==0,"Modal overlay blocks shortcuts and direct floor/Center callbacks.")
	app.close_overlay()
	var field:=LineEdit.new();app.ui.add_child(field);field.grab_focus();await _frames()
	await _key(KEY_PAGEUP);app.set_live_view_level(1)
	check(app.world.view_level==0 and field.has_focus(),"Text-entry focus blocks floor shortcuts and callbacks.")
	field.release_focus();field.queue_free();await _frames()
	app.select_household_member(1);check(app.world.view_level==0,"Ordinary household selection does not auto-switch floor.")
	unchanged=_facts();await _press("CenterLifelet")
	check(app.world.view_level==1 and app.world.camera_target==app.player.position,"Center reveals and exactly frames the selected supported upper Lifelet.")
	check(_facts()==unchanged,"Center preserves all gameplay and motion facts.")
	# Even a temporarily bound simulation worker must not hijack selected-person Center.
	app._bind_member("player");var bound_before:String=app.bound_member_id;unchanged=_facts()
	app.world.set_view_level(0);await _press("CenterLifelet")
	check(app.world.view_level==1 and app.world.camera_target==app.world.actors.housemate_1.position and app.bound_member_id==bound_before and _facts()==unchanged,"Center reads selected identity without rebinding or storing another member's motion.")
	app._bind_member(app.household.selected_id())
	app.queue_interaction(app._find_item("upper_chair"),"relax");app.household.set_speed(1)
	var seated:bool=false
	for frame:int in 600:
		app._process(.05)
		if str(app.sim.get_current_action().get("phase",""))=="active":seated=true;break
	app.household.set_speed(0);app.world.set_view_level(0);unchanged=_facts()
	await _press("CenterLifelet")
	check(seated and app.world.view_level==1 and _facts()==unchanged,"Center reveals an actually arrived upper-chair activity without mistaking its furnishing for unsupported floor.")
	if "--capture" in OS.get_cmdline_user_args():
		app.world.camera_angle=-.55;app.world.camera_elevation=.85;app.world.camera.size=19;app.world.update_camera()
		await _capture("upper_1440x900",Vector2i(1440,900))
		await _capture("upper_960x600",Vector2i(960,600))
		root.size=Vector2i(1440,900)
	# Save/load is the existing production transaction; no loader fixture overlay.
	app.overlay_open=true
	check(app.save_game("","Live floor view checkpoint"),"Production named save accepts the explicitly chosen upper view.")
	var slot:String=app.active_save_id;var stored:Dictionary=LifeSaveLibrary.read_slot(slot)
	check(bool(stored.ok) and int(stored.data.members[int(stored.data.selected_index)].state.character.world_state.view_level)==1,"Named slot stores view_level through the existing schema.")
	app.overlay_open=false;app.world.set_view_level(0);app.load_game(slot);app.set_process(false)
	check(app.world.view_level==1 and app.household.speed==0,"Existing loader restores the upper view while remaining paused.")
	app.select_household_member(0);unchanged=_facts();await _press("CenterLifelet")
	check(app.world.view_level==0 and _facts()==unchanged,"Center of the ground Lifelet returns to ground without changing restored gameplay.")
	# Real stair progression supplies a genuine in-flight queue and owner.
	app.queue_interaction(app._find_item("upper_shelf"),"read")
	app.queue_interaction(app._find_item("ground_shelf"),"read")
	app.household.set_speed(1)
	var near_floor:bool=false
	for frame:int in 1600:
		app._process(.05)
		var route:Dictionary=app.traversal.routes.get("player",{})
		if str(route.get("phase",""))=="transit":near_floor=app.world.point_level(app.player.position)==0;break
	app.household.set_speed(0);unchanged=_facts()
	await _press("LiveUpperView");await _press("CenterLifelet")
	check(near_floor and app.world.view_level==1 and _facts()==unchanged,"Actual first transit frame retains Upper even while root height is at the ground datum.")
	app.household.set_speed(1)
	var found:bool=false
	for frame:int in 1600:
		app._process(.05)
		var route:Dictionary=app.traversal.routes.get("player",{})
		if str(route.get("phase",""))=="transit" and app.world.point_level(app.player.position)<0:found=true;break
	check(found,"Real queued upstairs activity reaches unsupported-height stair transit.")
	app.household.set_speed(0);unchanged=_facts()
	await _press("LiveUpperView");await _press("CenterLifelet")
	check(app.world.view_level==1 and app.world.camera_target==app.player.position and _facts()==unchanged,"Center mid-stair retains Upper and exact paused route/owner/explicit queue.")
	await _press("LiveGroundView");await _press("CenterLifelet")
	check(app.world.view_level==0 and _facts()==unchanged,"Center mid-stair also retains Ground without snapping the actor.")
	for index:int in 5:app._process(.016)
	check(_facts()==unchanged,"Normal paused main frames do not auto-follow floors or advance the stair journey.")
	app.set_build_mode(true);await _frames()
	check(_button("LiveGroundView")==null and _button("LiveUpperView")==null,"Build retains its own controls rather than duplicating Live selectors.")
	var build_level:int=app.world.view_level;await _key(KEY_PAGEUP);app.set_live_view_level(1)
	check(app.world.view_level==build_level,"Live shortcuts/callbacks do not alter Build's selected level or tool.")
	app.set_build_mode(false);app.current_venue="park";app.draw_live()
	check(_button("LiveGroundView")==null and _button("LiveUpperView")==null,"Single-level venue UI omits home floor selectors.")
	await _key(KEY_PAGEUP);check(app.world.view_level==build_level,"Floor shortcut stays inactive away from home.")
	await _finish("floor_view")
func _finish(label:String)->void:
	var report:Dictionary={"checks":checks,"failures":failures,"captures":captures,"process_id":OS.get_process_id(),"renderer":RenderingServer.get_current_rendering_method(),"scope":"Real production Buttons and input callbacks on an explicit engineering two-floor home. Actual queued stair transit, pause and same-process named save/load. No broad autonomy or all-geometry claim."}
	var file:=FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  ",true,true));file.close()
	print("LIVE_FLOOR_VIEW ",JSON.stringify(report))
	app.queue_free();await _frames(3);await create_timer(.3).timeout
	quit(0 if failures.is_empty() else 1)
