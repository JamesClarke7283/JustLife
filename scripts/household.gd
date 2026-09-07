extends Node
class_name LifeHousehold
## A shared home and wallet, with independent needs, careers and action queues.

signal member_action_started(member_id: String, action: Dictionary)
signal member_action_finished(member_id: String, action: Dictionary)
signal notice(message: String)
signal selection_changed(member_id: String)

const SAVE_PATH = "user://justlife_save.json"
const MAX_MEMBERS = 8
var members: Array = []
var selected_index: int = 0
var funds: int = 2500
var speed: int = 1
var day: int = 1
var minutes: float = 480
var targets: Array = []
var restoring: bool = false

func new_household(profiles: Array) -> void:
	for member in members:member.sim.queue_free()
	members.clear()
	selected_index=0;funds=2500;speed=1;day=1;minutes=480
	for profile in profiles.slice(0,MAX_MEMBERS):add_member(profile)
	if members.is_empty():add_member({})
	_sync_wallet()

func add_member(profile: Dictionary) -> String:
	if members.size()>=MAX_MEMBERS:return ""
	var id:String="player" if members.is_empty() else "housemate_%d" % members.size()
	var sim=LifeSim.new()
	sim.name="Life_"+id
	add_child(sim)
	sim.new_household(profile)
	sim.day=day;sim.minutes=minutes;sim.funds=funds;sim.speed=speed
	sim.household_bills_enabled=members.is_empty()
	sim.register_targets(targets)
	members.append({"id":id,"sim":sim})
	connect_member(id,sim)
	return id

func connect_member(id: String, sim: LifeSim) -> void:
	sim.action_started.connect(func(action:Dictionary):
		if not restoring:member_action_started.emit(id,action))
	sim.action_finished.connect(func(action:Dictionary):
		if not restoring:member_action_finished.emit(id,action))
	sim.notice.connect(func(message:String):
		if not restoring:notice.emit(message))

func selected() -> LifeSim:
	return null if members.is_empty() else members[selected_index].sim

func selected_id() -> String:
	return "" if members.is_empty() else members[selected_index].id

func select(index: int) -> void:
	if index<0 or index>=members.size() or index==selected_index:return
	adopt_selected_changes()
	selected_index=index
	selection_changed.emit(selected_id())

func member_sim(id: String) -> LifeSim:
	for member in members:
		if member.id==id:return member.sim
	return null

func adopt_selected_changes() -> void:
	if selected():
		funds=selected().funds
		speed=selected().speed
	_sync_wallet()

func _sync_wallet() -> void:
	for member in members:
		member.sim.funds=funds
		member.sim.speed=speed

func set_funds(value: int) -> void:
	funds=maxi(value,0)
	_sync_wallet()

func set_speed(value: int) -> void:
	speed=value if value in [0,1,3,8] else 1
	_sync_wallet()

func register_targets(new_targets: Array) -> void:
	targets=new_targets.duplicate(true)
	for member in members:member.sim.register_targets(targets)

func tick(delta: float) -> void:
	if members.is_empty():return
	adopt_selected_changes()
	var start_day:int=day
	var start_minutes:float=minutes
	for member in members:
		var sim:LifeSim=member.sim
		sim.day=start_day;sim.minutes=start_minutes;sim.speed=speed;sim.funds=funds
		sim.tick(delta)
		funds=sim.funds
	day=members[0].sim.day
	minutes=members[0].sim.minutes
	_sync_wallet()

func begin_action(id: String) -> void:
	adopt_selected_changes()
	var sim=member_sim(id)
	if not sim:return
	sim.funds=funds
	sim.begin_current_action()
	funds=sim.funds
	_sync_wallet()

func get_state(world_data: Array = []) -> Dictionary:
	adopt_selected_changes()
	var states:Array=[]
	for member in members:states.append({"id":member.id,"state":member.sim.get_state()})
	return {"household_version":1,"selected_index":selected_index,"funds":funds,"day":day,"minutes":minutes,"speed":speed,"members":states,"world":world_data.duplicate(true)}

func save_game(world_data: Array = []) -> bool:
	var data=get_state(world_data)
	var temp_path=SAVE_PATH+".tmp"
	var file=FileAccess.open(temp_path,FileAccess.WRITE)
	if not file:return false
	file.store_string(JSON.stringify(json_safe(data),"  "))
	file.flush();file.close()
	var error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path),ProjectSettings.globalize_path(SAVE_PATH))
	return error==OK

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):return {"ok":false,"error":"No saved household yet."}
	var file=FileAccess.open(SAVE_PATH,FileAccess.READ)
	if not file or file.get_length()>8*1024*1024:return {"ok":false,"error":"The household save could not be read."}
	var parser=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return {"ok":false,"error":"The household save is damaged."}
	return restore_state(parser.data)

func restore_state(data: Dictionary) -> Dictionary:
	# Single-Lifelet saves from the first playable version are accepted.
	if data.has("version") and not data.has("household_version"):
		data={"household_version":1,"selected_index":0,"funds":data.get("funds",2500),"members":[{"id":"player","state":data}],"world":data.get("world",[])}
	if data.get("household_version")!=1 or not data.get("members") is Array:return {"ok":false,"error":"This household save uses an unsupported format."}
	if data.members.is_empty() or data.members.size()>MAX_MEMBERS or not data.get("world",[]) is Array:return {"ok":false,"error":"The saved household has invalid members."}
	var candidates:Array=[]
	var ids:Array=[]
	for entry in data.members:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("state") is Dictionary or ids.has(entry.id):
			for c in candidates:c.sim.free()
			return {"ok":false,"error":"The saved household has an invalid Lifelet."}
		var sim=LifeSim.new()
		var result=sim.restore_state(entry.state)
		if not result.ok:
			sim.free()
			for c in candidates:c.sim.free()
			return result
		ids.append(entry.id);candidates.append({"id":entry.id,"sim":sim})
	var selected_value:Variant=data.get("selected_index",0)
	if not (selected_value is int or selected_value is float) or int(selected_value)<0 or int(selected_value)>=candidates.size():
		for c in candidates:c.sim.free()
		return {"ok":false,"error":"The selected Lifelet is invalid."}
	restoring=true
	for old in members:old.sim.queue_free()
	members=candidates
	selected_index=int(selected_value)
	funds=members[selected_index].sim.funds
	day=members[selected_index].sim.day;minutes=members[selected_index].sim.minutes;speed=members[selected_index].sim.speed
	for i in range(members.size()):
		var member:Dictionary=members[i]
		add_child(member.sim)
		member.sim.name="Life_"+member.id
		member.sim.household_bills_enabled=i==0
		connect_member(member.id,member.sim)
		member.sim.register_targets(targets)
	_sync_wallet()
	restoring=false
	return {"ok":true,"world":data.get("world",[]).duplicate(true)}

func json_safe(value: Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is Color:return value.to_html()
	if value is Array:
		var result:Array=[]
		for item in value:result.append(json_safe(item))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[str(key)]=json_safe(value[key])
		return result
	return value
