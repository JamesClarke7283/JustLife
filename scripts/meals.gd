extends RefCounted
class_name LifeMeals
const Building=preload("res://scripts/building_state.gd")
## Persistent food ownership. World nodes are views of this state.
const VERSION := 2
const MAX_BATCHES := 64
const MAX_PORTIONS := 128
const EATING_MINUTES := 32.0
# Authored support dimensions in tools/create_furniture.py. Keep the entire
# ceramic footprint on the surface, with a 1 cm inset from its outer edge.
const SURFACE_HEIGHTS := {"dining":.847,"counter":.952,"stove":.997,"coffee_table":.46}
const SURFACE_HALF_SIZE := {"dining":Vector2(.8,.56),"counter":Vector2(.525,.39),"stove":Vector2(.51,.385),"coffee_table":Vector2(.5,.24)}
const PLATE_HALF_SIZE := Vector2(.15,.15)
const PLATTER_HALF_SIZE := Vector2(.25,.168)
const SURFACE_INSET := .01
const RECIPES := {
	"garden_skillet":{"label":"Garden skillet", "servings":4, "cost":12, "skill":1, "nutrition":70.0, "duration":45.0, "xp":34.0, "description":"Toasted grains, roasted vegetables and fresh basil.", "model":"meal"},
	"herb_pasta":{"label":"Herb garden pasta", "servings":4, "cost":16, "skill":2, "nutrition":76.0, "duration":50.0, "xp":40.0, "description":"Curled pasta folded with garden herbs and tomato.", "model":"meal_herb_pasta"},
	"harvest_bake":{"label":"Harvest vegetable bake", "servings":8, "cost":24, "skill":4, "nutrition":82.0, "duration":70.0, "xp":55.0, "description":"A generous dish of vegetables under a golden baked topping.", "model":"meal_harvest_bake"},
	"mushroom_soup":{"label":"Mushroom soup", "servings":4, "cost":20, "skill":3, "nutrition":74.0, "duration":60.0, "xp":46.0, "description":"Sliced mushrooms simmered in a herbed cream broth.", "model":"meal_mushroom_soup"},
	"berry_crumble":{"label":"Berry crumble", "servings":6, "cost":28, "skill":5, "nutrition":78.0, "duration":80.0, "xp":62.0, "description":"Baked berries under an uneven golden crumble.", "model":"meal_berry_crumble"}
}
const QUALITY_LABELS := ["", "Homestyle", "Delicious", "Excellent"]

static func recipe_error(recipe: String, level: int, age: String, money: int, paid: bool=false) -> String:
	if not RECIPES.has(recipe):return "Choose a recipe from the cookbook."
	if age=="child":return "Children can grab a snack. An older Lifelet can use the stove."
	var definition:Dictionary=RECIPES[recipe]
	if level<int(definition.skill):return "Cooking level %d unlocks this recipe." % int(definition.skill)
	if not paid and money<int(definition.cost):return "Requires §%d for ingredients." % int(definition.cost)
	return ""

static func cooking_definition(base: Dictionary, recipe: String) -> Dictionary:
	if not RECIPES.has(recipe):return {}
	var result:Dictionary=base.duplicate(true)
	var definition:Dictionary=RECIPES[recipe]
	result.merge({"recipe":recipe,"label":"Cook "+str(definition.label).to_lower(),"duration":float(definition.duration),"cost":int(definition.cost),"xp":float(definition.xp),"description":str(definition.description)},true)
	return result

static func model_path(recipe: String, plate: bool=false) -> String:
	return "res://assets/models/"+str(RECIPES.get(recipe,RECIPES.garden_skillet).model)+("_plate.glb" if plate else "_serving.glb")

var serial: int = 0
var batches: Array = []
var portions: Array = []

func clear() -> void:
	serial=0; batches.clear(); portions.clear()

func get_state() -> Dictionary:
	return {"version":VERSION,"serial":serial,"batches":batches.duplicate(true),"portions":portions.duplicate(true)}

func restore(data: Dictionary) -> void:
	serial=int(data.get("serial",0))
	batches=data.get("batches",[]).duplicate(true)
	portions=data.get("portions",[]).duplicate(true)

func _id(prefix: String) -> String:
	serial+=1
	return prefix+str(serial)

func batch(id: String) -> Dictionary:
	for value: Dictionary in batches:
		if str(value.id)==id:return value
	return {}

func portion(id: String) -> Dictionary:
	for value: Dictionary in portions:
		if str(value.id)==id:return value
	return {}

func carried_by(member_id: String) -> Dictionary:
	for value: Dictionary in portions:
		if str(value.owner)==member_id:return value
	for value: Dictionary in batches:
		if str(value.owner)==member_id:return value
	return {}

func create_batch(recipe: String, chef: String, quality: int, venue: String, now: float) -> Dictionary:
	if not RECIPES.has(recipe) or batches.size()>=MAX_BATCHES or not carried_by(chef).is_empty():return {}
	var definition: Dictionary=RECIPES[recipe]
	var result: Dictionary={"id":_id("meal_"),"recipe":recipe,"chef":chef,"quality":clampi(quality,1,3),"initial":int(definition.servings),"remaining":int(definition.servings),"served":0,"discarded":0,"created":now,"expires":now+360.0,"venue":venue,"storage":"carried","owner":chef,"host":"","position":[0.0,0.0,0.0],"offset":[0.0,0.0,0.0]}
	batches.append(result)
	return result

func set_batch_location(id: String, storage: String, host: String, position: Vector3, now: float, owner: String="") -> bool:
	var value: Dictionary=batch(id)
	if value.is_empty() or storage not in ["surface","fridge","carried"] or not position.is_finite():return false
	if storage=="carried" and owner.is_empty():return false
	if storage!="carried" and not owner.is_empty():return false
	if storage=="carried":
		if not str(value.owner).is_empty() and str(value.owner)!=owner:return false
		var carried: Dictionary=carried_by(owner)
		if not carried.is_empty() and str(carried.id)!=id:return false
	var freshness: float=maxf(0.0,float(value.expires)-now)
	if str(value.storage)=="fridge" and storage!="fridge":freshness/=12.0
	elif str(value.storage)!="fridge" and storage=="fridge":freshness*=12.0
	value.expires=now+freshness
	value.merge({"storage":storage,"host":host,"position":[position.x,position.y,position.z],"owner":owner},true)
	return true

func claim(id: String, member_id: String, now: float) -> Dictionary:
	# Claim on physical pickup, not invitation or queue insertion. A second
	# arrival cannot obtain the last serving, and cannot claim while carrying.
	var value: Dictionary=batch(id)
	if value.is_empty() or int(value.remaining)<=0 or now>=float(value.expires) or str(value.storage)=="carried" or not carried_by(member_id).is_empty() or portions.size()>=MAX_PORTIONS:return {}
	var freshness: float=maxf(0.0,float(value.expires)-now)
	if str(value.storage)=="fridge":freshness/=12.0
	var result: Dictionary={"id":_id("plate_"),"batch":id,"owner":member_id,"venue":str(value.venue),"storage":"carried","host":"","seat":"","position":value.position.duplicate(),"offset":[0.0,0.0,0.0],"progress":0.0,"expires":now+freshness,"shared_minutes":0.0,"company":[]}
	value.remaining=int(value.remaining)-1
	value.served=int(value.served)+1
	portions.append(result)
	return result

func take_portion(id: String, member_id: String, now: float) -> bool:
	var value: Dictionary=portion(id)
	if value.is_empty() or not str(value.owner).is_empty() or not carried_by(member_id).is_empty() or float(value.progress)>=1.0 or now>=float(value.expires):return false
	value.owner=member_id;value.storage="carried";value.seat=""
	return true

func put_portion(id: String, host: String, seat: String, position: Vector3, eating: bool=false, local_position: Vector3=Vector3.ZERO) -> bool:
	var value: Dictionary=portion(id)
	if value.is_empty() or not position.is_finite():return false
	value.merge({"storage":"table" if eating else "surface","host":host,"seat":seat,"position":[position.x,position.y,position.z],"offset":[local_position.x,local_position.y,local_position.z]},true)
	if not eating:value.owner=""
	return true

func eat(id: String, member_id: String, game_minutes: float, now: float) -> float:
	var value: Dictionary=portion(id)
	if value.is_empty() or str(value.owner)!=member_id or game_minutes<=0 or not is_finite(game_minutes) or now>=float(value.expires):return 0.0
	var amount: float=minf(game_minutes/EATING_MINUTES,1.0-float(value.progress))
	value.progress=minf(1.0,float(value.progress)+amount)
	var recipe: Dictionary=RECIPES[str(batch(str(value.batch)).recipe)]
	return amount*float(recipe.nutrition)

func finish_portion(id: String) -> void:
	var value: Dictionary=portion(id)
	if value.is_empty():return
	value.progress=1.0
	value.storage="dirty"
	value.owner=""
	value.seat=""

func release_member(member_id: String, position: Vector3) -> void:
	var value: Dictionary=carried_by(member_id)
	if value.is_empty():return
	if value.has("batch"):
		if str(value.storage)=="carried":value.position=[position.x,position.y,position.z];value.host=""
		value.owner="";value.seat="";value.storage="dirty" if float(value.progress)>=1.0 else "surface"
	else:
		value.owner="";value.storage="surface";value.host="";value.position=[position.x,position.y,position.z]

func discard_batch(id: String) -> bool:
	var value: Dictionary=batch(id)
	if value.is_empty() or not str(value.owner).is_empty():return false
	value.discarded=int(value.discarded)+int(value.remaining);value.remaining=0
	_prune_empty()
	return true

func clean_portion(id: String, member_id: String) -> bool:
	var value: Dictionary=portion(id)
	if value.is_empty() or str(value.owner) not in ["",member_id]:return false
	portions.erase(value);_prune_empty();return true

func restore_portion(id: String, fridge_id: String, position: Vector3, now: float, carrier: String="") -> bool:
	# A serving that was plated but never finished goes back to its dish and into
	# the fridge, rather than being washed away. The owning batch still exists:
	# _prune_empty keeps any batch a live portion still refers to, so the serving
	# simply returns to its remaining count and the fresh fridge timer.
	var value: Dictionary=portion(id)
	if value.is_empty() or float(value.progress)>=1.0:return false
	# The carrier may still hold it when the walk to the fridge completes.
	if not str(value.owner).is_empty() and str(value.owner)!=carrier:return false
	if str(value.storage) not in ["carried","surface","table"] or now>=float(value.expires):return false
	var dish: Dictionary=batch(str(value.batch))
	if dish.is_empty() or int(dish.served)<=0 or int(dish.remaining)+1>int(dish.initial):return false
	value.owner="";value.storage="surface";value.seat=""
	var placed: Vector3=position
	if not set_batch_location(str(dish.id),"fridge",fridge_id,placed,now):return false
	dish.remaining=int(dish.remaining)+1
	dish.served=int(dish.served)-1
	dish.offset=[0.0,0.0,0.0]
	portions.erase(value);_prune_empty()
	return true

func _prune_empty() -> void:
	for value: Dictionary in batches.duplicate():
		if int(value.remaining)>0:continue
		if portions.any(func(p:Dictionary)->bool:return str(p.batch)==str(value.id)):continue
		batches.erase(value)

static func _number(value: Variant, low: float, high: float, whole: bool=false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high and (not whole or floorf(float(value))==float(value))

static func _position(value: Variant) -> bool:
	return value is Array and value.size()==3 and value.all(func(v:Variant)->bool:return _number(v,-100000.0,100000.0))

static func _offset(value:Variant) -> bool:
	return value is Array and value.size()==3 and _number(value[0],-2,2) and _number(value[1],0,1.1) and _number(value[2],-2,2)

static func validate(data: Variant, member_ids: Array, now: float,guest:Dictionary={}) -> String:
	if not data is Dictionary or not _number(data.get("version"),1,VERSION,true) or not _number(data.get("serial"),0,1e9,true):return "The saved food format is invalid."
	if not data.get("batches") is Array or data.batches.size()>MAX_BATCHES or not data.get("portions") is Array or data.portions.size()>MAX_PORTIONS:return "The saved food collection is invalid."
	var company_ids:Array=member_ids.duplicate()
	if int(data.version)>=2:company_ids.append_array(LifeResidentCatalogue.PEOPLE.keys())
	var ids: Dictionary={};var owners: Dictionary={};var batch_ids: Dictionary={};var claimed: Dictionary={};var seats: Dictionary={}
	for value: Variant in data.batches:
		if not value is Dictionary:return "The save contains an invalid meal."
		if not value.get("id") is String or not str(value.id).begins_with("meal_") or not str(value.id).trim_prefix("meal_").is_valid_int() or int(str(value.id).trim_prefix("meal_"))>int(data.serial) or ids.has(value.id):return "The save contains duplicate or invalid food identities."
		ids[value.id]=true;batch_ids[value.id]=value;claimed[value.id]=0
		if not RECIPES.has(str(value.get("recipe",""))) or str(value.get("chef","")) not in member_ids or not _number(value.get("quality"),1,3,true):return "The saved meal recipe or cook is invalid."
		var total: int=int(RECIPES[str(value.recipe)].servings)
		if value.get("initial")!=total or not _number(value.get("remaining"),0,total,true) or not _number(value.get("served"),0,total,true) or not _number(value.get("discarded"),0,total,true) or int(value.remaining)+int(value.served)+int(value.discarded)!=total:return "The meal's serving counts do not add up."
		if not _number(value.get("created"),0,now) or not _number(value.get("expires"),float(value.created),now+4320.0) or not _position(value.get("position")) or not _offset(value.get("offset",[0,0,0])):return "The saved meal freshness or position is invalid."
		if str(value.get("storage","")) not in ["surface","fridge","carried"] or not value.get("venue") is String or not value.get("host") is String or not value.get("owner") is String:return "The saved meal location is invalid."
		if str(value.storage)=="carried":
			if str(value.owner) not in member_ids or owners.has(value.owner):return "Two foods have the same carrier."
			owners[value.owner]=value.id
		elif not str(value.owner).is_empty():return "A placed meal cannot have a carrier."
	for value: Variant in data.portions:
		if not value is Dictionary:return "The save contains an invalid plate."
		if not value.get("id") is String or not str(value.id).begins_with("plate_") or not str(value.id).trim_prefix("plate_").is_valid_int() or int(str(value.id).trim_prefix("plate_"))>int(data.serial) or ids.has(value.id) or not batch_ids.has(str(value.get("batch",""))):return "The save contains an invalid plate identity or meal reference."
		ids[value.id]=true;claimed[value.batch]+=1
		if int(claimed[value.batch])>int(batch_ids[value.batch].served):return "More plates exist than servings were taken."
		if not _number(value.get("progress"),0,1) or not _number(value.get("expires"),0,now+4320) or not _number(value.get("shared_minutes"),0,EATING_MINUTES) or not _position(value.get("position")) or not _offset(value.get("offset",[0,0,0])):return "The saved plate progress is invalid."
		if not value.get("company") is Array or value.company.size()>8 or not value.company.all(func(id:Variant)->bool:return id is String and id in company_ids):return "The saved meal company is invalid."
		var unique_company:Dictionary={}
		for companion:String in value.company:
			if unique_company.has(companion):return "The saved meal repeats a dining companion."
			unique_company[companion]=true
		if not value.get("owner") is String or not value.get("host") is String or not value.get("seat") is String or not value.get("venue") is String or str(value.get("storage","")) not in ["carried","table","surface","dirty"]:return "The saved plate location is invalid."
		if not str(value.owner).is_empty():
			if (str(value.owner) not in member_ids and (int(data.version)<2 or str(value.owner)!=str(guest.get("guest","")))) or owners.has(value.owner) or str(value.storage) not in ["carried","table"]:return "A plate has conflicting ownership."
			owners[value.owner]=value.id
		elif str(value.storage) in ["carried","table"]:return "An active plate is missing its owner."
		var guest_owner:bool=not str(value.owner).is_empty() and str(value.owner) not in member_ids
		if guest_owner:
			if value.get("guest_visit")!=guest.get("serial") or value.get("guest_meal")!=guest.get("meal",{}).get("token"):return "The guest plate belongs to a different visit or meal."
		elif value.has("guest_visit") or value.has("guest_meal"):return "A released or household plate contains guest custody."
		if str(value.storage)=="dirty" and float(value.progress)!=1.0:return "An unfinished plate is marked empty."
		if str(value.storage)=="table" and not str(value.seat).is_empty():
			var seat_key: String=str(value.venue)+":"+str(value.seat)
			if seats.has(seat_key):return "Two diners occupy the same chair."
			seats[seat_key]=true
	return ""

static func _saved_floor_error(value:Dictionary,layout:Array) -> String:
	var state:Dictionary={}
	for entry:Variant in layout:
		if entry is Dictionary and entry.get("kind")=="__construction":
			if not state.is_empty():return "A saved floor dish has ambiguous building support."
			var result:Dictionary=Building.migrate(entry)
			if not bool(result.ok):return "A saved floor dish has invalid building support."
			state=result.state
	if state.is_empty():return "A saved floor dish is missing its building layout."
	var at:=Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))
	var level:int=-1;var terrain:bool=absf(at.y-(-.148))<.012 or absf(at.y-(-.093))<.012
	if terrain:level=0
	for candidate:int in [0,1]:
		if absf(at.y-(Building.level_y(candidate)+.002))<.025:level=candidate
	# Migrated starter boards retain their authored top instead of a new slab.
	if level<0 and absf(at.y-.1295)<.012:
		for floor:Dictionary in state.floors:
			if str(floor.id)=="legacy_starter_floor" and Building.rect(floor).has_point(Vector2(at.x,at.z)):level=0;break
	if level<0:return "A saved floor dish is not on a supported floor height."
	var half:Vector2=PLATE_HALF_SIZE if value.has("batch") else PLATTER_HALF_SIZE
	var bounds:=Rect2(Vector2(at.x,at.z)-half,half*2)
	if terrain:
		if not Building.LOT.encloses(bounds):return "A saved floor dish is outside the lot."
		for tile:Dictionary in Building.surface_tiles(state,0):
			if tile.rect.intersects(bounds):return "A saved floor dish is below its visible floor."
	elif not Building.footprint_supported(state,level,bounds):return "A saved floor dish extends beyond its supporting floor."
	if Building.blocked_rect(state,level,bounds.grow(.002)):return "A saved floor dish overlaps the building."
	for entry:Variant in layout:
		if not entry is Dictionary or not LifeCatalog.ITEMS.has(str(entry.get("kind",""))) or LifeCatalog.passable(str(entry.kind)):continue
		if not _number(entry.get("level",0),0,1,true):return "A saved floor dish has an invalid furniture level."
		if int(entry.get("level",0))!=level:continue
		for axis:String in ["x","z","rotation"]:
			if not _number(entry.get(axis,0),-100000,100000):return "A saved floor dish has an invalid furniture transform."
		var inverse:=Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0)))).inverse()
		var local:Vector3=inverse*(at-Vector3(float(entry.get("x",0)),Building.level_y(level),float(entry.get("z",0))))
		var across:Vector3=inverse*Vector3(half.x,0,0);var along:Vector3=inverse*Vector3(0,0,half.y)
		var extent:=Vector2(absf(across.x)+absf(along.x),absf(across.z)+absf(along.z))
		var body:Vector2=LifeCatalog.ITEMS[str(entry.kind)].size*.5
		if absf(local.x)<body.x+extent.x+.002 and absf(local.z)<body.y+extent.y+.002:return "A saved floor dish overlaps furniture on its floor."
	return ""

static func validate_layout(data:Dictionary,household:Dictionary) -> String:
	# V1 detached component saves may omit layouts. A journey-aware public V2
	# must supply the actual venue layout even for held or floor-only food.
	var strict:bool=_number(household.get("household_version"),2,2,true)
	var selected:Dictionary=household.members[int(household.get("selected_index",0))].state.character
	var context:Variant=selected.get("world_state",{})
	if not context is Dictionary:context={}
	var layouts:Dictionary={str(context.get("venue","home")):household.get("world",[])}
	if context.get("home_layout") is Array and str(context.get("venue","home"))!="home":layouts.home=context.home_layout
	if context.get("venue_layouts") is Dictionary:
		for venue:Variant in context.venue_layouts:
			if venue is String and not layouts.has(venue) and context.venue_layouts[venue] is Array:layouts[venue]=context.venue_layouts[venue]
	for value:Dictionary in data.batches+data.portions:
		var layout:Variant=layouts.get(str(value.venue),[])
		if not layout is Array or layout.is_empty():
			if strict:return "A saved meal is missing its venue layout."
			continue
		if str(value.storage)=="carried" or (str(value.storage)=="table" and str(value.host).is_empty()):continue
		if str(value.host).is_empty():
			if strict:
				var error:String=_saved_floor_error(value,layout)
				if not error.is_empty():return error
			continue
		if not value.has("offset"):
			if strict:return "A saved meal is missing its supporting offset."
			continue
		var host:Dictionary={}
		for entry:Variant in layout:
			if entry is Dictionary and entry.get("id")==value.host:
				if not host.is_empty():return "A saved meal refers to ambiguous furniture."
				host=entry
		if host.is_empty():return "A saved meal refers to missing furniture."
		for axis:String in ["x","z","rotation"]:
			if not _number(host.get(axis,0),-100000,100000):return "A saved meal has an invalid furniture transform."
		if not _number(host.get("level",0),0,1,true):return "A saved meal has an invalid furniture level."
		var level:int=int(host.get("level",0))
		var local:=Vector3(float(value.offset[0]),float(value.offset[1]),float(value.offset[2]))
		var placed:=Vector3(float(host.get("x",0)),Building.level_y(level),float(host.get("z",0)))+Basis(Vector3.UP,deg_to_rad(float(host.get("rotation",0))))*local
		var saved:=Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))
		if placed.distance_to(saved)>.02:return "A saved meal position does not match its furniture."
		var kind:String=str(host.get("kind",""))
		if str(value.storage)=="fridge":
			if kind!="fridge" or local.length()>.002:return "The saved leftovers are not inside their fridge."
		else:
			if not SURFACE_HEIGHTS.has(kind) or absf(local.y-float(SURFACE_HEIGHTS[kind]))>.003:return "A saved plate is not supported by its furniture."
			var extent:Vector2=SURFACE_HALF_SIZE[kind]
			var footprint:Vector2=PLATE_HALF_SIZE if value.has("batch") else PLATTER_HALF_SIZE
			if absf(local.x)+footprint.x+SURFACE_INSET>extent.x+.00001 or absf(local.z)+footprint.y+SURFACE_INSET>extent.y+.00001:return "A saved dish extends beyond its supporting surface."
		if str(value.get("storage",""))=="table" and not str(value.get("seat","")).is_empty():
			var chair:Dictionary={}
			for entry:Variant in layout:
				if entry is Dictionary and entry.get("id")==value.seat:chair=entry;break
			if chair.is_empty() or chair.get("kind")!="chair" or not _number(chair.get("level",0),level,level,true):return "A saved diner’s chair is not on the table’s floor."
	return ""

static func _validate_guest_food(data:Dictionary,guest:Dictionary,owners:Dictionary)->String:
	var meal:Dictionary=guest.get("meal",{})
	if meal.is_empty():return ""
	if int(data.version)<2:return "A guest meal requires the supported food version."
	var serving:Dictionary={};var source:Dictionary={}
	for batch:Dictionary in data.batches:
		if str(batch.id)==str(meal.source):source=batch
	for value:Dictionary in data.portions:
		if str(value.id)==str(meal.plate):serving=value
	var phase:String=str(meal.phase)
	if phase in ["pickup","to_place","eating"] and (source.is_empty() or str(source.venue)!="home"):return "The guest meal source is missing from home."
	if not str(meal.plate).is_empty():
		if serving.is_empty() or str(serving.batch)!=str(meal.source) or str(serving.owner)!=str(guest.guest) or str(serving.venue)!="home" or owners.has(str(serving.id)):return "Guest meal custody does not match one unique portion."
		if phase=="to_place" and str(serving.storage)!="carried":return "A walking guest must carry their portion."
		if phase=="eating":
			if str(serving.storage)!="table" or str(serving.seat)!=str(meal.seat) or (bool(meal.standing)!=str(serving.host).is_empty()):return "The guest's eating place does not match their plate."
		owners[str(serving.id)]=str(guest.guest)
	elif phase in ["to_place","eating"]:return "The guest's current meal has no owned portion."
	return ""

static func validate_actions(data:Dictionary,members:Array,custody:Dictionary={},venue:String="",guest:Dictionary={}) -> String:
	var foods:Dictionary={};var active_owners:Dictionary={}
	for value:Dictionary in data.batches+data.portions:foods[value.id]=value
	for member:Dictionary in members:
		var queue:Array=member.state.get("action_queue",[])
		for index:int in range(queue.size()):
			var action:Dictionary=queue[index]
			var action_id:String=str(action.id)
			var meal_action:bool=action_id in ["serve_meal","eat_meal","store_meal","clean_plate","discard_meal"]
			if not meal_action:
				for key:String in ["meal_source","meal_stage","meal_plate","meal_seat","meal_standing"]:
					if action.has(key):return "A non-meal action contains food ownership."
				continue
			if action_id!="eat_meal" and (action.has("meal_plate") or action.has("meal_seat") or action.has("meal_standing")):return "A meal transport action contains a diner’s plate or chair."
			if action.has("meal_standing") and not action.meal_standing is bool:return "A standing diner’s reservation is invalid."
			var source:Variant=action.get("meal_source",action.get("target_id",""))
			var stage:Variant=action.get("meal_stage","pickup")
			if not source is String or not foods.has(source) or not stage is String:return "A meal action refers to missing food."
			var value:Dictionary=foods[source]
			var owner_id:String=""
			match action_id:
				"serve_meal":
					if value.has("batch") or stage not in ["pickup","serve"]:return "The serving action is invalid."
					owner_id=str(source)
				"store_meal","discard_meal":
					if value.has("batch") or stage not in ["pickup","store" if action_id=="store_meal" else "discard"]:return "The leftovers action is invalid."
					if stage in ["store","discard"]:owner_id=str(source)
				"clean_plate":
					if not value.has("batch") or stage not in ["pickup","wash"]:return "The dish-washing action is invalid."
					if stage=="wash":owner_id=str(source)
				"eat_meal":
					if stage not in ["pickup","eat"]:return "The dining action has an invalid stage."
					if action.has("meal_standing") and (stage!="eat" or not bool(action.meal_standing) or not str(action.get("meal_seat","")).is_empty() or str(action.get("target_id",""))!=str(action.get("meal_plate",""))):return "The standing diner’s place does not match their serving."
					if stage=="eat":
						var plate_id:Variant=action.get("meal_plate")
						if not plate_id is String or not foods.has(plate_id) or not foods[plate_id].has("batch"):return "The diner’s plate is missing."
						var plate:Dictionary=foods[plate_id]
						if (str(source)!=str(plate.batch) and str(source)!=plate_id) or absf(float(action.get("duration",0))-EATING_MINUTES)>.00002 or absf(float(action.get("elapsed",0))-float(plate.progress)*EATING_MINUTES)>.00002:return "The diner’s progress does not match their serving."
						if str(action.get("meal_seat",""))!=str(plate.seat) and str(plate.storage)=="table":return "The diner’s chair does not match their plate."
						owner_id=plate_id
					elif action.has("meal_plate") or float(action.get("elapsed",0))>0:return "A diner has eating progress before collecting food."
			if not owner_id.is_empty():
				if index!=0 or str(foods[owner_id].owner)!=str(member.id) or active_owners.has(owner_id):return "Food ownership does not match the active Lifelet."
				active_owners[owner_id]=str(member.id)
	var guest_error:String=_validate_guest_food(data,guest,active_owners)
	if not guest_error.is_empty():return guest_error
	# Custody is derived by the journey validator from one owned safe-exit
	# crossing. It is distinct from a later action and expires at the landing.
	for id:Variant in custody:
		if not id is String or not foods.has(id) or not custody[id] is String:return "Saved stair custody refers to missing food or Lifelet."
		var held:Dictionary=foods[id]
		if str(held.owner)!=str(custody[id]) or str(held.storage)!="carried" or str(held.venue)!=venue:return "Saved stair custody does not match its carried food and venue."
		if active_owners.has(id):return "Food has both current-action ownership and canceled stair custody."
		active_owners[id]=str(custody[id])
	for id:String in foods:
		if not str(foods[id].owner).is_empty() and not active_owners.has(id):return "A carried or active food has no matching action."
	return ""
