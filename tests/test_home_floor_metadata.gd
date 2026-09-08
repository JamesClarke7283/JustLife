extends SceneTree
## Loads the unedited named slot created by the rejected rendered home run.
## No actor arrival, time advancement, food, or architecture is injected.
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:
	var project:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if OS.get_environment("XDG_DATA_HOME")!=project.path_join("metadata_userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=project.path_join("metadata_userdata/save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		push_error("Run this named-save test only in a sanitized copied project with private metadata_userdata and its save_data override.");quit(2);return
	_run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message);push_error(message)
func same(a:Variant,b:Variant)->bool:
	if a is Vector3:a=[a.x,a.y,a.z]
	if b is Vector3:b=[b.x,b.y,b.z]
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in b:
			if not a.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index:int in a.size():
			if not same(a[index],b[index]):return false
		return true
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	return typeof(a)==typeof(b) and a==b
func _run()->void:
	var fresh:bool="--fresh" in OS.get_cmdline_user_args()
	var original:Dictionary
	var slot_id:String
	if fresh:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://floor_metadata_expected.json"))
		original=expected.original;slot_id=str(expected.slot_id)
	else:
		slot_id=LifeSaveLibrary.latest_id()
		var read:Dictionary=LifeSaveLibrary.read_slot(slot_id)
		check(bool(read.ok),"authentic original named slot is readable")
		if not bool(read.ok):quit(1);return
		original=read.data
	var selected:Dictionary=original.members[int(original.selected_index)].state
	var expected_world:Dictionary=selected.character.world_state
	var app:Node=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	for frame:int in 4:await process_frame
	app.load_game(slot_id)
	for frame:int in 4:await process_frame
	check(app.mode=="live" and app.active_save_id==slot_id,"real named load installs the requested household")
	check(app.floor_color==str(expected_world.floor) and app.selected_lot==int(expected_world.lot),"canonical load restores Walnut choice and selected home metadata")
	var visible_timber:String="missing"
	for node:Node in app.world.house.get_children():
		if node is MeshInstance3D and node.mesh is BoxMesh and node.mesh.size.x==12 and node.mesh.size.z==10:
			visible_timber=node.material_override.albedo_color.to_html(false)
	check(visible_timber==str(LifeBuildingState.find(app.world.construction.building_state,"legacy_starter_floor").material),"actual authored timber displays its saved canonical finish")
	var marker:Dictionary=original.world.filter(func(entry:Dictionary)->bool:return str(entry.kind)=="__construction")[0]
	check(not app.world.construction.building_state.is_empty() and same(app.world.construction.building_state.floors,marker.floors),"canonical per-slab finishes and floor geometry remain exact")
	var furnishings:bool=true
	for entry:Dictionary in original.world:
		if str(entry.kind)=="__construction":continue
		var item:Dictionary=app._find_item(str(entry.id))
		if item.is_empty():furnishings=false;continue
		var level:int=int(entry.get("level",0))
		# Node3D stores these geometric vectors at engine float32 precision.
		# No epsilon: the loaded transform must equal that stored representation.
		furnishings=furnishings and item.kind==entry.kind and app.world.item_level(item)==level and item.node.position==Vector3(entry.x,.16+3.0*level,entry.z) and item.node.rotation_degrees.y==Vector3(0,entry.rotation,0).y
	check(furnishings,"all furnishing IDs, kinds, levels and stored-precision physical transforms restore exactly")
	check(app.household.funds==int(original.funds) and app.household.day==int(original.day) and app.household.minutes==float(original.minutes) and app.household.speed==0,"paused load preserves shared wallet, day, clock and speed")
	check(same(app.household.meals.get_state(),original.meals),"paid-cooking slot retains complete food ledger")
	var actors_queues:bool=true
	for member:Dictionary in original.members:
		var sim:LifeSim=app.household.member_sim(str(member.id))
		var p:Array=member.state.character.world_state.player
		actors_queues=actors_queues and app.world.actors[str(member.id)].position==Vector3(p[0],p[1],p[2]) and same(sim.get_state().action_queue,member.state.action_queue)
	check(actors_queues,"all actual actor positions and paid/later queues remain exact")
	var check_read:Dictionary=LifeSaveLibrary.read_slot(slot_id)
	check(bool(check_read.ok) and same(check_read.data,original),"the loaded slot retains all original household data")
	if not fresh:
		check(app.save_game("","Walnut metadata resave"),"real named save writes a new slot after canonical reload")
		check(app.active_save_id!=slot_id,"new named save retains original rejected-run slot")
		var saved:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
		var normalized:Dictionary=original.duplicate(true)
		# Existing V2 view selection deliberately centers Y on the selected storey.
		# Keep this independently identified camera change explicit; every other
		# original field must survive, including each slab's finish and paid state.
		var camera:Array=normalized.members[int(original.selected_index)].state.character.world_state.camera
		check(app.world.camera_target.y==3.0*app.world.view_level and app.world.camera_target.x==float(camera[0]) and app.world.camera_target.z==float(camera[2]),"existing V2 view normalization changes only camera height to the selected storey")
		camera[1]=app.world.camera_target.y
		check(bool(saved.ok) and same(saved.data,normalized),"save-again preserves all original fields except the declared storey-camera height normalization")
		var expected_file:=FileAccess.open("user://floor_metadata_expected.json",FileAccess.WRITE)
		expected_file.store_string(JSON.stringify({"slot_id":app.active_save_id,"original":saved.data,"authentic_original":original},"  ",true,true));expected_file.close()
	var file:=FileAccess.open("user://floor_metadata_"+("fresh" if fresh else "producer")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"floor":app.floor_color,"lot":app.selected_lot,"original_slot":slot_id,"new_slot":app.active_save_id},"  "));file.close()
	print("FLOOR_METADATA checks=%d failures=%d fresh=%s"%[checks,failures.size(),fresh])
	app.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
