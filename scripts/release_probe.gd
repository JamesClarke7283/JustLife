extends RefCounted
## Opt-in packaged-runtime verification. Refuses normal user data directories.
var app:Node
var failures:int=0
var checks:int=0
var native_focus_guard:LineEdit
func disable_node_input(node:Node) -> void:
	node.set_process_input(false);node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false);node.set_process_shortcut_input(false)
func exclude_native_input() -> void:
	if not is_instance_valid(app):return
	app.get_viewport().gui_disable_input=true
	app.set_process(false);app.world.set_process(false)
	for node:Node in [app]+app.find_children("*","Node",true,false):disable_node_input(node)
	if is_instance_valid(native_focus_guard):native_focus_guard.grab_focus()
func native_input_excluded() -> bool:
	if not app.get_viewport().gui_disable_input or app.get_viewport().gui_get_focus_owner()!=native_focus_guard:return false
	for node:Node in [app]+app.find_children("*","Node",true,false):
		if node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input() or node.is_processing_shortcut_input():return false
	return not app.is_processing() and not app.world.is_processing()
func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("RELEASE_CHECK "+message)
func press(value:String) -> void:
	for b:Node in app.find_children("*","Button",true,false):
		if b.text==value and b.is_visible_in_tree() and not b.disabled:b.pressed.emit();return
	check(false,"Missing public control "+value)
func capture(name:String) -> void:
	for i in range(3):await app.get_tree().process_frame
	exclude_native_input()
	check(native_input_excluded(),"Capture "+name+" excludes native input and direct camera polling.")
	# Private verification windows may have automatic redraw suspended when hidden.
	RenderingServer.force_draw(false,0.0)
	var directory:String="user://release_check"
	DirAccess.make_dir_recursive_absolute(directory)
	check(app.get_viewport().get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func finish_trip() -> void:
	for frame:int in range(1500):
		if app.mode!="travel":return
		app._process(.05)
		if frame%20==0:await app.get_tree().process_frame
	check(false,"Packaged car journey exceeded its bounded travel window.")

func choose_age(label:String) -> void:
	var selector:OptionButton=app.find_child("CreatorAge",true,false) as OptionButton
	if selector!=null:
		for index:int in range(selector.item_count):
			if selector.get_item_text(index)==label:
				selector.select(index);selector.item_selected.emit(index);return
	check(false,"Missing packaged age choice "+label)
static func isolated_environment() -> bool:
	var data: String = OS.get_environment("XDG_DATA_HOME")
	var saves: String = OS.get_environment("JUSTLIFE_DATA_DIR")
	return OS.get_name() == "Linux" and data.is_absolute_path() and data == data.simplify_path() and data.get_file().begins_with("justlife-release-check-") and saves == data.path_join("save_data") and preload("res://scripts/save_storage.gd").safe_directory(data)

func run(owner_app:Node) -> void:
	app=owner_app
	if not isolated_environment():
		printerr("Release check requires an isolated justlife-release-check-* XDG_DATA_HOME and JUSTLIFE_DATA_DIR set to its save_data folder.")
		app.get_tree().quit(2);return
	app.get_viewport().gui_disable_input=true
	app.get_tree().node_added.connect(disable_node_input)
	app.get_tree().process_frame.connect(exclude_native_input)
	native_focus_guard=LineEdit.new();native_focus_guard.position=Vector2(-9000,-9000)
	app.get_tree().root.add_child(native_focus_guard)
	exclude_native_input()
	app.set_process(false);app.set_sound(false)
	check(app.mode=="menu","Packaged main menu starts.")
	check(is_instance_valid(app.ambience_player.stream) and is_instance_valid(app.audio_player.stream),"Imported ambience and click audio load from the PCK.")
	check(is_instance_valid(app.music_player) and is_instance_valid(app.music_player.stream) and not app.music_player.stream_paused,"The packaged theme loads from the PCK and loops at startup.")
	await capture("01_main_menu")
	press("New game");await app.get_tree().process_frame
	check(app.mode=="creator" and is_instance_valid(app.preview.visual),"Packaged creator and model load.")
	check(app.preview._voice_streams.size()==5,"All five wordless voice categories load from the PCK.")
	for stage:String in ["child","teen","young_adult","adult","elder"]:
		choose_age(str(LifeLifecycle.LABELS[stage]));await app.get_tree().process_frame
		check(app.profile.age_stage==stage and is_instance_valid(app.preview.visual) and app.preview.supports_age(stage),"Packaged creator loads the authored "+stage+" model.")
	choose_age("Child");await app.get_tree().process_frame
	check(app.preview._cake_flames.size()==3,"The original birthday cake and three candles load from the PCK.")
	check(ResourceLoader.load("res://assets/models/desk_booster.glb") is PackedScene,"The authored child desk booster loads from the PCK.")
	for prop:String in ["meal_serving","meal_plate","meal_fork","meal_herb_pasta_serving","meal_herb_pasta_plate","meal_harvest_bake_serving","meal_harvest_bake_plate"]:
		check(ResourceLoader.load("res://assets/models/"+prop+".glb") is PackedScene,"The original "+prop+" loads from the PCK.")
	for prop:String in ["juniper_car","juniper_mop","juniper_stair","juniper_guard_post","juniper_guard_span","roof_gable_modules"]:
		check(ResourceLoader.load("res://assets/models/"+prop+".glb") is PackedScene,"The original "+prop+" loads from the PCK.")
	for prop:String in ["pet_cat","pet_dog","pet_bowl","cat_tree","kennel"]:
		check(ResourceLoader.load("res://assets/models/"+prop+".glb") is PackedScene,"The original "+prop+" loads from the PCK.")
	check(ResourceLoader.load("res://assets/shaders/pet_coat.gdshader") is Shader,"The pet coat shader loads from the PCK.")
	check(bool(app.household.pets.get("pets") is Array),"The packaged household exposes its pet record.")
	press("Face");await app.get_tree().process_frame
	app.preview.set_face_feature("face_round",.5);app.profile.face_round=.5
	await capture("02_face_editor")
	press("+ Add Lifelet");await app.get_tree().process_frame
	choose_age("Adult");await app.get_tree().process_frame
	press("Connections");await app.get_tree().process_frame
	var parent_choice:OptionButton
	for option:Node in app.find_children("*","OptionButton",true,false):
		if option.is_visible_in_tree() and int(option.get_meta("connection_member",-1))==0:parent_choice=option
	check(is_instance_valid(parent_choice),"Packaged creator exposes a child connection choice.")
	if is_instance_valid(parent_choice):parent_choice.select(4);parent_choice.item_selected.emit(4)
	press("Back to creating")
	press("Find my home  →");press("Start living  →");await app.get_tree().process_frame
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.household.members[1].sim.needs.hunger=43.0
	app.set_game_speed(0)
	check(app.household.members.size()==2 and app.world.actors.size()==4,"Two Lifelets enter their home.")
	var oven:Dictionary=app.world.closest_item("stove",Vector3.ZERO)
	var rack:Node3D=oven.node.find_child("OvenRack",true,false) if not oven.is_empty() else null
	var handle:Node3D=oven.node.find_child("OvenHandleGrip",true,false) if not oven.is_empty() else null
	check(is_instance_valid(rack) and str(rack.get_parent().name)=="OvenRackCarrier" and is_instance_valid(handle) and str(handle.get_parent().name)=="OvenDoor","The packaged stove retains its sliding rack and hinged handle anchors.")
	check(LifeOvenSequence.phase(.5)=="bake" and LifeOvenSequence.inside(.5),"The packaged oven sequence includes closed interior baking.")
	check(app.household.members[0].sim.character.age_stage=="child" and app.household.members[0].sim.wants[0].id=="first_snack","A child enters the packaged home with an attainable first want.")
	check(app.household.members[0].sim.education.stage=="child" and app.household.members[1].sim.education.stage=="adult","Packed schooling enrolls the child and leaves the adult unenrolled.")
	check(app.household.family_relationship("player","housemate_1")=="parent","The packaged creator starts a directed parent-child family.")
	app.household.set_aging("long",false)
	await capture("03_live_household")
	press("My Lifelet");press("Family tree");await app.get_tree().process_frame
	check(is_instance_valid(app.find_child("FamilyCard_player",true,false)) and is_instance_valid(app.find_child("FamilyCard_housemate_1",true,false)),"The packaged family tree displays both household members.")
	await capture("03b_family_tree")
	press("Back to life")
	app.select_household_member(1)
	var before_adoption:Dictionary=app.household.get_state(app.world.serialize_items())
	press("Phone");press("Household calendar");await app.get_tree().process_frame
	check(is_instance_valid(app.find_child("CalendarAgenda",true,false)) and app.find_children("CalendarEntry_*","Control",true,false).size()==2,"Packaged calendar shows the child's school and the adult's work.")
	check(app.overlay_open and app.overlay_pauses_sim and app.sim.speed==0,"The packaged calendar preserves the household pause.")
	await capture("03bb_household_calendar")
	var work_filter:Button=app.find_child("CalendarFilter_work",true,false)
	if is_instance_valid(work_filter):work_filter.pressed.emit()
	check(app.find_children("CalendarEntry_*","Control",true,false).size()==1,"The packaged work filter leaves the pupil's school plan visible.")
	press("Back to phone")
	check(app.household.get_state(app.world.serialize_items())==before_adoption,"Packaged calendar browsing preserves the complete household state.")
	press("Adopt a child");await app.get_tree().process_frame
	var candidates:int=0
	for index:int in range(3):
		var candidate:Button=app.find_child("AdoptionCandidate_%d" % index,true,false)
		if is_instance_valid(candidate) and candidate.is_visible_in_tree() and not candidate.disabled:candidates+=1
	check(candidates==3,"Packaged phone opens three original adoption candidates.")
	press("Meet Wren");await app.get_tree().process_frame
	var confirmation:Button=app.find_child("AdoptionConfirm",true,false)
	check(is_instance_valid(confirmation) and not confirmation.disabled,"Packaged adoption review prepares an eligible guardian and displayed fee.")
	await capture("03c_adoption_review")
	press("Cancel adoption")
	check(app.household.get_state(app.world.serialize_items())==before_adoption,"Packaged adoption cancellation preserves household and funds.")
	var before_pet:Dictionary=app.household.get_state(app.world.serialize_items())
	press("Back to phone");press("Juniper Pet Shop");await app.get_tree().process_frame
	check(is_instance_valid(app.find_child("PetShopAdopt",true,false)),"The packaged phone opens the pet shop.")
	press("Adopt a cat or dog");await app.get_tree().process_frame
	check(is_instance_valid(app.find_child("PetSpecies_cat",true,false)) and is_instance_valid(app.find_child("PetSpecies_dog",true,false)),"The packaged pet picker offers both species.")
	check(is_instance_valid(app.find_child("PetSex_female",true,false)) and is_instance_valid(app.find_child("PetSex_male",true,false)),"The packaged pet picker offers both sexes.")
	check(is_instance_valid(app.find_child("PetGradient",true,false)),"The packaged pet picker offers the mixed-gradient control.")
	var pet_confirm:Button=app.find_child("PetShopConfirm",true,false)
	check(is_instance_valid(pet_confirm) and not pet_confirm.disabled,"The packaged pet review prepares an eligible, priced purchase.")
	await capture("03d_pet_picker")
	app.pet_shop.show_shop()
	check(app.household.get_state(app.world.serialize_items())==before_pet,"Packaged pet browsing preserves household and funds.")
	press("Back to life");app.show_menu();press("Save this life");await app.get_tree().process_frame
	app.menus.name_input.text="Packaged release verification"
	press("Save as new");await app.get_tree().process_frame
	var id:String=app.active_save_id
	check(not id.is_empty() and LifeSaveLibrary.read_slot(id).ok,"The packaged save picker writes a named save.")
	app.household.members[1].sim.needs.hunger=7.0
	app.show_menu();press("Load a saved life");await app.get_tree().process_frame
	await capture("04_save_picker")
	press("Load selected life  →");press("Continue without saving");await app.get_tree().process_frame
	check(app.active_save_id==id and is_equal_approx(app.household.members[1].sim.needs.hunger,43.0),"The selected named save restores both Lifelets.")
	check(app.household.members[0].sim.character.age_stage=="child" and app.household.members[0].sim.education.first_class_day==1,"Named save restores the child's authored age and school calendar.")
	check(app.household.family_relationship("player","housemate_1")=="parent" and app.household.family_parent_links().size()==1,"The named save restores the directed family graph.")
	check(app.household.members[1].sim.lifecycle.lifespan=="long" and not app.household.members[0].sim.lifecycle.auto_age,"Named save restores lifespan and automatic-birthday settings.")
	app.show_menu();press("Load a saved life");press("Delete save…");await app.get_tree().process_frame
	await capture("05_delete_confirmation")
	press("Keep save");await app.get_tree().process_frame
	check(LifeSaveLibrary.read_slot(id).ok,"Keep save leaves the file intact.")
	press("Delete save…");press("Delete permanently");await app.get_tree().process_frame
	check(not LifeSaveLibrary.read_slot(id).ok and app.household.members.size()==2,"Confirmed deletion removes only the selected file and preserves the open life.")
	app.close_overlay()
	var before_trip:float=(app.household.day-1)*1440.0+app.household.minutes
	app.travel_to("library")
	check(app.mode=="travel" and is_instance_valid(app.residents.car),"The packaged household starts its real shared-car journey.")
	await finish_trip();await app.get_tree().process_frame
	check((app.household.day-1)*1440.0+app.household.minutes==before_trip+15.0,"The packaged car trip advances exactly fifteen game minutes.")
	check(app.current_venue=="library" and app.world.items.size()>5,"Packed neighborhood models and travel work.")
	await capture("06_library")
	var tree:SceneTree=app.get_tree()
	print("JUSTLIFE_RELEASE_CHECK ",checks," checks, ",failures," failures")
	tree.process_frame.disconnect(exclude_native_input)
	tree.node_added.disconnect(disable_node_input)
	native_focus_guard.queue_free()
	# Schedule through SceneTree: freeing app also releases this RefCounted probe.
	app.queue_free()
	tree.create_timer(.2).timeout.connect(tree.quit.bind(0 if failures==0 else 1), CONNECT_ONE_SHOT)
