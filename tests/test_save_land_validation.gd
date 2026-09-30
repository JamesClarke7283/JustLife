extends SceneTree
## Detached save operations must not replace the running world's land. No
## main scene, actors, renderer, clock ticks or user save directory are used.
const Building=preload("res://scripts/building_state.gd")
const Land=preload("res://scripts/land.gd")
const Household=preload("res://scripts/household.gd")
const Library=preload("res://scripts/save_library.gd")
var checks:int=0
var failures:int=0

func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path() or not OS.get_environment("XDG_DATA_HOME").is_absolute_path():
		push_error("Land validation tests require isolated absolute save and user directories.");quit(2);return
	_run.call_deferred()

func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1

func fixture(people:int=1)->Dictionary:
	var home:=Household.new()
	var profiles:Array=[]
	for i:int in people:profiles.append({"name":"Land fixture "+str(i),"age_stage":"adult","traits":[]})
	home.new_household(profiles);home.set_speed(0)
	var building:Dictionary=Building.fresh()
	building.floors=[{"id":"saved_ground","level":0,"x":-22.0,"z":0.0,"w":4.0,"d":4.0,"material":"bb9a73"}]
	var state:Dictionary=home.get_state([building]);home.free()
	var saved_land:Dictionary=Land.fresh();saved_land.west=1
	state.household_version=2
	state["journeys"]={"version":2,"next_identity":1,"next_ticket":1,"members":{}}
	for i:int in state.members.size():
		var member:Dictionary=state.members[i]
		var position:Array=[-22.0,.16,float(i-1)]
		member.state.character["world_state"]={"player":position,"player_rotation":0.0,"resource_wait_started":-1.0,"resource_action_active":false,"waiting_action_id":"","waiting_target_id":""}
		if i==0:member.state.character.world_state.merge({"venue":"home","land":saved_land,"home_layout":[],"venue_layouts":{}})
		state.journeys.members[str(member.id)]={"position":position,"yaw":0.0,"motion":{}}
	return state

func land_unchanged(before:Dictionary,label:String)->void:
	check(is_same(Building.land,before) and Building.land.east==2 and Building.land.west==0,label+" preserves the live land values and object identity")

func _run()->void:
	var original:Dictionary=Building.land
	var current:Dictionary=Land.fresh();current.east=2;Building.set_land(current)
	var live:Dictionary=Building.land
	var state:Dictionary=fixture()
	var saved:Dictionary=Library.save_slot("test_validation_land_valid","Canonical west plot",state)
	check(bool(saved.get("ok",false)),"A canonical house on its saved west plot validates and saves")
	land_unchanged(live,"Successful save_slot")
	if not bool(saved.get("ok",false)):
		print("SAVE_ERROR ",saved);Building.land=original;quit(1);return
	var read:Dictionary=Library.read_slot("test_validation_land_valid")
	check(bool(read.get("ok",false)),"read_slot accepts the expanded saved layout while the live lot extends east")
	land_unchanged(live,"Successful read_slot")
	var before_bytes:PackedByteArray=FileAccess.get_file_as_bytes(Library._slot_path("test_validation_land_valid"))
	var bad:Dictionary=state.duplicate(true);bad.world[0].floors[0].x=-99.0
	var refused:Dictionary=Library.save_slot("test_validation_land_valid","Must not replace",bad)
	check(not bool(refused.get("ok",false)),"save_slot rejects construction outside even the saved land")
	land_unchanged(live,"Rejected save_slot")
	check(FileAccess.get_file_as_bytes(Library._slot_path("test_validation_land_valid"))==before_bytes,"Rejected save preserves the previous valid slot bytes")
	var written:Dictionary=Library._atomic_json(Library._slot_path("test_validation_land_invalid"),{"save_library_version":1,"metadata":{"name":"Invalid west plot"},"data":bad})
	check(bool(written.ok),"A controlled malformed disk fixture is available for read validation")
	read=Library.read_slot("test_validation_land_invalid")
	check(not bool(read.get("ok",false)),"read_slot rejects the malformed saved layout")
	land_unchanged(live,"Rejected read_slot")
	var entries:Array=Library.list_saves()
	check(entries.any(func(entry:Dictionary)->bool:return str(entry.id)=="test_validation_land_valid" and bool(entry.valid)),"Save listing retains the valid canonical household")
	check(entries.any(func(entry:Dictionary)->bool:return str(entry.id)=="test_validation_land_invalid" and not bool(entry.valid)),"Save listing reports the malformed household as invalid")
	land_unchanged(live,"Listing valid and invalid slots")
	# Actual household adoption still applies its saved lot; only detached
	# library validation rolls back. Staged canonical loaders rely on this.
	var loaded:=Household.new()
	var adopted:Dictionary=loaded.restore_state(state)
	check(bool(adopted.ok) and Building.land.west==1 and Building.land.east==0,"Actual canonical household restoration still adopts its saved land")
	loaded.free();Building.land=original
	print("SAVE_LAND_VALIDATION checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
