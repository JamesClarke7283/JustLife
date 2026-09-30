extends RefCounted
class_name LifeRelationshipProgress
## Pair progress is credited by completed social actions, never menu clicks.
const DATE:String="go_on_date"
const FLIRTS_REQUIRED:int=3
const DATES_REQUIRED:int=2
const MAX_COUNT:int=1000000

static func normalize(relationship:Dictionary)->void:
	for key:String in ["successful_flirts","completed_dates"]:
		relationship[key]=int(relationship.get(key,0))
	relationship["married"]=bool(relationship.get("married",false))

static func validate(relationship:Dictionary)->String:
	for key:String in ["successful_flirts","completed_dates"]:
		var count:Variant=relationship.get(key,0)
		if not (count is int or count is float) or not is_finite(float(count)) or float(count)!=floorf(float(count)) or float(count)<0 or float(count)>MAX_COUNT:return "Save contains invalid relationship progress."
	if not relationship.get("married",false) is bool:return "Save contains an invalid marriage."
	if bool(relationship.get("married",false)) and (str(relationship.get("bond","none"))!="committed" or int(relationship.get("completed_dates",0))<DATES_REQUIRED):return "Save contains an inconsistent marriage."
	if LifeFamilyGraph.is_family(str(relationship.get("family_role","none"))) and (int(relationship.get("successful_flirts",0))>0 or int(relationship.get("completed_dates",0))>0 or bool(relationship.get("married",false))):return "Family members cannot have romantic progress."
	return ""

static func partner_reason(relationship:Dictionary)->String:
	if int(relationship.get("successful_flirts",0))<FLIRTS_REQUIRED:return "Share three successful flirts before asking to become partners."
	if float(relationship.get("friendship",0))<35.0:return "Build your friendship before asking to become partners."
	return ""

static func date_reason(sim:Node,target:String)->String:
	var relationship:Dictionary=sim.relationships.get(target,{})
	if str(sim.romantic_partner)!=target or str(relationship.get("bond","none")) not in ["partners","committed"]:return "Become partners before planning a date."
	return ""

static func proposal_reason(sim:Node,target:String)->String:
	var reason:String=date_reason(sim,target)
	if not reason.is_empty():return reason
	var relationship:Dictionary=sim.relationships[target]
	if bool(relationship.get("married",false)):return "You are already married."
	if int(relationship.get("completed_dates",0))<DATES_REQUIRED:return "Complete two dates together before proposing marriage and moving in."
	return ""

static func successful_flirt(relationship:Dictionary)->void:
	normalize(relationship)
	relationship.successful_flirts=mini(MAX_COUNT,int(relationship.successful_flirts)+1)

static func complete_date(relationship:Dictionary)->void:
	normalize(relationship)
	relationship.completed_dates=mini(MAX_COUNT,int(relationship.completed_dates)+1)

static func separate(relationship:Dictionary)->void:
	relationship.successful_flirts=0
	relationship.completed_dates=0
	relationship.married=false
