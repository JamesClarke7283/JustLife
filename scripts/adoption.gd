extends RefCounted
class_name LifeAdoption
## Original school-age adoption policy. Confirmation is the only paid operation.
const FEE:int=1000
const CANDIDATE_COUNT:int=3
const NAMES:Array[String]=["Wren Avery","Finley Brook","Kit Solis","Rowan Finch","Sage Ellis","Remy Vale","Jules Moss","Noa Linden","Alex Reed"]

static func fresh() -> Dictionary:return {"version":1,"next_serial":1,"events":[]}
static func integer(value:Variant,low:int,high:int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=low and float(value)<=high
static func point(value:Variant) -> bool:
	if value is Vector3:return value.is_finite() and absf(value.x)<=30 and absf(value.z)<=30 and absf(value.y-.16)<.001
	if not value is Array or value.size()!=3:return false
	for component:Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)):return false
	return absf(float(value[0]))<=30 and absf(float(value[2]))<=30 and absf(float(value[1])-.16)<.001

static func candidate(serial:int,choice:int) -> Dictionary:
	# Appearance and personality use independent fixed cycles, without any
	# demographic inference or mutation of the game's random generator.
	var index:int=(serial-1)*CANDIDATE_COUNT+choice
	return {"name":NAMES[index%NAMES.size()],"age_stage":"child","life_stage":"minor","frame":index%2,"hair":(index+1)%3,"skin_color":["d9a17d","925c40","f2d1b1","b77e58","e7b98f","613e30"][index%6],"hair_color":["54382a","2a2420","89563a","c2a16b"][index%4],"top_color":["7195b3","417a71","c97c66"][index%3],"bottom_color":"eadfc9","eye_color":"547365","outfit":index%3,"body_scale":1.0,"height_scale":1.0,"traits":[["Creative","Bookworm"],["Outgoing","Active"],["Neat","Foodie"]][choice].duplicate(),"aspiration":["Maker","Connected","Balanced"][choice]}

static func request_error(value:Variant) -> String:
	if not value is Dictionary or value.size()!=5 or not integer(value.get("serial"),1,7) or not integer(value.get("choice"),0,CANDIDATE_COUNT-1) or not integer(value.get("member_count"),1,7) or not integer(value.get("fee"),FEE,FEE) or not value.get("guardians") is Array:
		return "This adoption review is no longer valid. Open a new review."
	if value.guardians.is_empty() or value.guardians.size()>2:return "Choose one or two adult guardians."
	var ids:Array=[]
	for id:Variant in value.guardians:
		if not id is String or id.is_empty() or ids.has(id):return "Choose different adult guardians."
		ids.append(id)
	return ""

static func validate(value:Variant,data:Dictionary) -> String:
	if not value is Dictionary or value.size()!=3 or not integer(value.get("version"),1,1) or not integer(value.get("next_serial"),1,8) or not value.get("events") is Array or value.events.size()>7:return "Save contains invalid adoption history."
	if int(value.next_serial)!=value.events.size()+1:return "Save contains an invalid adoption serial."
	if not value.events.is_empty() and not data.get("family_graph") is Dictionary:return "Save adoption history requires its explicit family graph."
	var by_id:Dictionary={}
	for entry:Dictionary in data.members:by_id[str(entry.id)]=entry.state
	var adopted:Array=[]
	for index:int in range(value.events.size()):
		var event:Variant=value.events[index]
		if not event is Dictionary or event.size()!=7 or not integer(event.get("serial"),index+1,index+1) or not integer(event.get("choice"),0,CANDIDATE_COUNT-1) or not event.get("child") is String or not by_id.has(event.child) or adopted.has(event.child) or not integer(event.get("fee"),FEE,FEE) or not integer(event.get("day"),1,int(data.get("day",1))) or not (event.get("minutes") is int or event.get("minutes") is float):return "Save contains an invalid adoption event."
		if not is_finite(float(event.minutes)) or float(event.minutes)<0 or float(event.minutes)>=1440 or (int(event.day)==int(data.get("day",1)) and float(event.minutes)>float(data.get("minutes",0))):return "Save contains a future adoption event."
		if not event.get("guardians") is Array or event.guardians.is_empty() or event.guardians.size()>2:return "Save contains invalid adoptive guardians."
		var seen:Array=[]
		for guardian:Variant in event.guardians:
			if not guardian is String or guardian==event.child or not by_id.has(guardian) or seen.has(guardian) or LifeLifecycle.eligibility(LifeLifecycle.stage_for(by_id[guardian].character))!="adult":return "Save contains an invalid adoptive guardian."
			if not data.family_graph.parents.any(func(edge:Dictionary)->bool:return str(edge.a)==guardian and str(edge.b)==event.child):return "Save adoption history does not match its parent links."
			seen.append(guardian)
		adopted.append(event.child)
	for entry:Dictionary in data.members:
		var arrivals:int=0
		var queue:Array=entry.state.get("action_queue",[])
		for index:int in range(queue.size()):
			var action:Dictionary=queue[index]
			if str(action.get("id",""))!="arrive_home":continue
			arrivals+=1
			if index!=0 or arrivals>1 or not integer(action.get("adoption_serial"),1,value.events.size()):return "Save contains an invalid adoption arrival."
			var event:Dictionary=value.events[int(action.adoption_serial)-1]
			if str(event.child)!=str(entry.id):return "Save adoption arrival belongs to another Lifelet."
	return ""
