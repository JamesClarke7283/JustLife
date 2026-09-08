extends RefCounted
class_name LifeSanitation
## Persistent floor messes; visual nodes and transient ownership live in the controller.
var serial:int=0
var puddles:Array=[]
static func fresh()->Dictionary:return {"version":1,"serial":0,"puddles":[]}
func clear()->void:serial=0;puddles.clear()
func get_state()->Dictionary:return {"version":1,"serial":serial,"puddles":puddles.duplicate(true)}
func restore(value:Dictionary)->void:serial=int(value.serial);puddles=value.puddles.duplicate(true)
func find(id:String)->Dictionary:
	for puddle:Dictionary in puddles:
		if str(puddle.id)==id:return puddle
	return {}
func add(member:String,venue:String,at:Vector3,level:int,now:float)->String:
	serial+=1
	var id:String="puddle_%d" % serial
	puddles.append({"id":id,"member":member,"venue":venue,"position":[at.x,at.y,at.z],"floor_y":at.y,"level":level,"created":now})
	return id
func remove(id:String)->bool:
	for index:int in puddles.size():
		if str(puddles[index].id)==id:puddles.remove_at(index);return true
	return false
static func number(value:Variant,minimum:float,maximum:float)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum
static func integer(value:Variant,minimum:int,maximum:int)->bool:
	return number(value,minimum,maximum) and float(value)==floorf(float(value))
static func validate(value:Variant,members:Array,states:Array,now:float)->String:
	if not value is Dictionary or not integer(value.get("version"),1,1) or not integer(value.get("serial"),0,1000000000) or not value.get("puddles") is Array:return "Save contains invalid floor messes."
	var ids:Dictionary={}
	for entry:Variant in value.puddles:
		if not entry is Dictionary or not entry.get("id") is String or not entry.get("member") is String or not entry.get("venue") is String:return "Save contains an invalid puddle."
		var id:String=entry.id
		var digits:String=id.trim_prefix("puddle_")
		if not id.begins_with("puddle_") or not digits.is_valid_int() or digits!=str(int(digits)) or int(digits)<1 or int(digits)>int(value.serial) or ids.has(id):return "Save contains invalid puddle identity."
		if not members.has(entry.member) or not LifeNeighborhood.PLACES.has(entry.venue):return "Save contains a puddle with an unknown Lifelet or place."
		if not entry.get("position") is Array or entry.position.size()!=3:return "Save contains an invalid puddle position."
		for component:Variant in entry.position:
			if not number(component,-1000.0,1000.0):return "Save contains an invalid puddle position."
		if not integer(entry.get("level"),0,1) or not number(entry.get("floor_y"),-1.0,4.0) or absf(float(entry.position[1])-float(entry.floor_y))>.000001 or absf(float(entry.floor_y)-(.16+3.0*int(entry.level)))>.000001 or not number(entry.get("created"),0.0,now):return "Save contains invalid puddle floor or time."
		ids[id]=true
	var active:Dictionary={}
	for member:Dictionary in states:
		for action:Dictionary in member.state.get("action_queue",[]):
			if str(action.id)!="mop_puddle":continue
			if not ids.has(str(action.target_id)):return "Save contains cleanup for a missing puddle."
			if str(action.phase)=="active":
				if active.has(str(action.target_id)):return "Save contains two cleaners using the same puddle."
				active[str(action.target_id)]=str(member.id)
	return ""
