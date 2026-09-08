extends SceneTree
var app:Node
var assertions:int=0
var failures:int=0
var id_a:String
var id_b:String
func _initialize() -> void:run.call_deferred()
func check(value:bool,message:String) -> void:
	assertions+=1
	if not value:failures+=1;push_error(message)
func press(value:String) -> void:
	for b:Node in app.find_children("*","Button",true,false):
		if b.text==value and b.is_visible_in_tree() and not b.disabled:b.pressed.emit();return
	check(false,"Missing enabled button "+value)
func select_save(id:String) -> void:
	for b:Node in app.find_children("*","Button",true,false):
		if str(b.get_meta("save_id",""))==id and b.is_visible_in_tree():b.pressed.emit();return
	check(false,"Missing visible save row "+id)
func snap(which:String) -> void:
	for i in range(3):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png("res://art/screenshots/menus/"+which+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://art/screenshots/menus")
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	await process_frame
	check(app.mode=="menu","Game starts at its main menu.")
	if "--resume-only" in OS.get_cmdline_user_args():
		check(LifeSaveLibrary.list_saves().size()==1,"Only undeleted save survives fresh process.")
		press("Saved lives");await process_frame;await snap("09_fresh_save_picker")
		press("Load selected life  →");await process_frame
		check(app.mode=="live" and app.has_active_game,"Fresh picker loads a household.")
		check(app.household.members.size()==2,"Both saved Lifelets return.")
		check(is_equal_approx(app.household.members[1].sim.needs.hunger,43.0),"The chosen save retains its independent state.")
		await finish();return
	check(LifeSaveLibrary.list_saves().is_empty(),"Test begins with an isolated empty save library.")
	await snap("01_main_menu")
	press("Saved lives");await process_frame
	check(app.overlay_open,"Empty save picker opens.")
	await snap("02_empty_picker")
	press("Create a household");await process_frame
	check(app.mode=="creator","Empty save picker leads to character creation.")
	app.add_creator_member();app.start_household();await process_frame
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.household.members[1].sim.needs.hunger=77.0
	app.set_game_speed(3)
	await snap("03_household")
	app.show_menu();press("Save this life");await process_frame
	check(app.sim.speed==0 and app.overlay_pauses_sim,"Save picker pauses the household.")
	app.menus.name_input.text="The Vale family"
	press("Save as new");await process_frame
	id_a=app.active_save_id
	check(not id_a.is_empty() and LifeSaveLibrary.read_slot(id_a).ok,"Save as new writes a named household.")
	check(app.sim.speed==3 and not app.overlay_open,"Saving returns to the original play speed.")
	check(LifeSaveLibrary.list_saves().size()==1,"First save creates exactly one picker entry.")
	var first:Dictionary=LifeSaveLibrary.list_saves()[0]
	check(first.name=="The Vale family" and first.members.size()==2,"Picker shows the named household and both members.")
	if DisplayServer.get_name()!="headless":check(FileAccess.file_exists(first.preview_path),"A rendered scene preview accompanies the save.")
	app.household.members[1].sim.needs.hunger=43.0
	app.show_menu();press("Save this life");await process_frame
	app.menus.name_input.text="A second chapter"
	press("Save as new");await process_frame;id_b=app.active_save_id
	check(id_a!=id_b and LifeSaveLibrary.list_saves().size()==2,"Save as new preserves the first life as a separate file.")
	app.show_menu();press("Load a saved life");await process_frame
	select_save(id_a);await process_frame;await snap("04_named_picker")
	press("Load selected life  →");await process_frame
	check(app.overlay_open and app.active_save_id==id_b,"Loading asks how to handle the open household.")
	press("Cancel");await process_frame
	check(app.active_save_id==id_b and app.household.members[1].sim.needs.hunger==43.0,"Cancelling load preserves the open household.")
	app.menus.show_picker("load",id_a);press("Load selected life  →");press("Continue without saving");await process_frame
	check(app.active_save_id==id_a and app.household.members[1].sim.needs.hunger==77.0,"Picker loads precisely the selected save.")
	app.household.members[1].sim.needs.hunger=61.0
	app.show_menu();press("Save this life");select_save(id_a);await process_frame
	app.menus.name_input.text="The Vale family, settled in"
	press("Overwrite…");await process_frame;await snap("05_overwrite_confirmation")
	press("Cancel");await process_frame
	check(LifeSaveLibrary.read_slot(id_a).data.members[1].state.needs.hunger==77.0,"Cancelling overwrite keeps the prior snapshot.")
	press("Overwrite…");press("Replace save");await process_frame
	check(LifeSaveLibrary.read_slot(id_a).data.members[1].state.needs.hunger==61.0,"Confirmed overwrite stores the latest household.")
	check(LifeSaveLibrary.list_saves().size()==2,"Overwrite does not create a duplicate save.")
	app.show_menu();press("Load a saved life");select_save(id_a);press("Delete save…");await process_frame
	check(LifeSaveLibrary.read_slot(id_a).ok,"Opening delete confirmation has no file side effect.")
	await snap("06_delete_confirmation")
	press("Keep save");await process_frame
	check(LifeSaveLibrary.read_slot(id_a).ok,"Keep save cancels deletion.")
	press("Delete save…");press("Delete permanently");await process_frame
	check(not LifeSaveLibrary.read_slot(id_a).ok,"Confirmed deletion removes the selected file.")
	check(LifeSaveLibrary.read_slot(id_b).ok and LifeSaveLibrary.list_saves().size()==1,"Deletion preserves the other saved life.")
	check(app.active_save_id.is_empty() and app.household.members[1].sim.needs.hunger==61.0,"Deleting a current save keeps the live household and clears its deleted slot reference.")
	await snap("07_after_deletion")
	app.close_overlay();app.set_game_speed(3)
	var before:float=app.sim.minutes
	app.show_main_menu();app._process(5)
	check(app.mode=="menu" and app.sim.minutes==before,"Main menu preserves the open life without advancing time.")
	await snap("08_menu_with_open_life")
	press("Continue your life  →");await process_frame
	check(app.mode=="live" and app.sim.speed==3 and app.sim.minutes==before,"Continue returns to the exact open life and speed.")
	await finish()
func finish() -> void:
	app.queue_free();await process_frame;await process_frame
	print("Menus: %d assertions, %d failures." % [assertions,failures]);quit(0 if failures==0 else 1)
