extends RefCounted
class_name LifeSanitation
## Persistent floor messes; visual nodes and transient ownership live in the controller.
const Building=preload("res://scripts/building_state.gd")
const PATCH_HALF:Vector2=Vector2(.52,.33)
const MIN_SCALE:float=.28
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
func add(member:String,venue:String,at:Vector3,level:int,now:float,scale:float=1.0)->String:
	serial+=1
	var id:String="puddle_%d" % serial
	puddles.append({"id":id,"member":member,"venue":venue,"position":[at.x,at.y,at.z],"floor_y":at.y,"level":level,"created":now,"scale":scale})
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
		if not number(entry.get("scale",1.0),MIN_SCALE,1.0):return "Save contains an invalid wet-patch footprint."
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

static func bounds(value:Dictionary)->Rect2:
	var half:Vector2=PATCH_HALF*float(value.get("scale",1.0))
	return Rect2(Vector2(float(value.position[0]),float(value.position[2]))-half,half*2.0)

static func support_error(value:Dictionary,layout:Array)->String:
	var state:Dictionary={}
	for item:Variant in layout:
		if not item is Dictionary or item.get("kind")!="__construction":continue
		if not state.is_empty():return "A saved puddle has ambiguous building support."
		var result:Dictionary=Building.migrate(item)
		if not bool(result.ok):return "A saved puddle has invalid building support."
		state=result.state
	if state.is_empty():return "A saved puddle is missing its physical building layout."
	var area:Rect2=bounds(value);var level:int=int(value.level)
	if not Building.footprint_supported(state,level,area,level==0):return "A saved puddle extends beyond its supporting floor."
	if Building.blocked_rect(state,level,area):return "A saved puddle intersects a wall or stair opening."
	return ""

static func validate_layout(value:Dictionary,household:Dictionary)->String:
	# Detached legacy component saves have no complete world. V2 physical
	# snapshots must prove support in every location containing a floor mess.
	if int(household.get("household_version",1))<2:return ""
	var selected:Dictionary=household.members[int(household.get("selected_index",0))].state.character
	var context:Dictionary=selected.get("world_state",{})
	var venue:String=str(context.get("venue","home"))
	var layouts:Dictionary={venue:household.get("world",[])}
	if venue!="home" and context.get("home_layout") is Array:layouts.home=context.home_layout
	if context.get("venue_layouts") is Dictionary:
		for place:Variant in context.venue_layouts:
			if place is String and not layouts.has(place) and context.venue_layouts[place] is Array:layouts[place]=context.venue_layouts[place]
	for puddle:Dictionary in value.puddles:
		var layout:Variant=layouts.get(str(puddle.venue),[])
		if not layout is Array or layout.is_empty():return "A saved puddle is missing its venue layout."
		var error:String=support_error(puddle,layout)
		if not error.is_empty():return error
	return ""
