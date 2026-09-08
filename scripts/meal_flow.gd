extends Node
class_name LifeMealFlow
## Routes preparation, carrying, independent diners, leftovers and washing.
const ACTIONS := ["serve_meal","eat_meal","store_meal","clean_plate","discard_meal"]
# Top faces in tools/create_furniture.py, measured from each furniture root.
# Meal meshes have their underside at local Y=0; 2 mm avoids contact flicker.
const SURFACE_HEIGHTS := LifeMeals.SURFACE_HEIGHTS
var app: Node
var views: Dictionary = {}
var revision: String = ""
var sync_due: bool = true

func food() -> LifeMeals:return app.household.meals
func now() -> float:return (app.household.day-1)*1440.0+app.household.minutes
func member_id(sim:LifeSim) -> String:
	for member: Dictionary in app.household.members:
		if member.sim==sim:return str(member.id)
	return ""
func item(id:String) -> Dictionary:return app._find_item(id)
func actor(id:String) -> LifeActor:return app.world.actors.get(id)

func _pending_furniture(id:String) -> bool:
	var pending:Variant=app.get("pending_move")
	return not id.is_empty() and pending is Dictionary and not pending.is_empty() and str(pending.get("entry",{}).get("id",""))==id

func action_availability(sim:LifeSim,id:String,target:String) -> String:
	var person:String=member_id(sim)
	if id=="cook":
		if food().batches.size()>=LifeMeals.MAX_BATCHES:return "Clear old meals before making more food."
		if not food().carried_by(person).is_empty():return "Put down the food you are carrying first."
		if app.world.closest_item("stove",Vector3.ZERO).is_empty():return "Place a stove to cook a hot meal."
		return ""
	if id=="eat_meal":
		var held:Dictionary=food().carried_by(person)
		if not held.is_empty() and held.has("batch") and float(held.progress)<1:return ""
		var batch:Dictionary=food().batch(target)
		if not batch.is_empty():
			if int(batch.remaining)<=0:return "That dish has no servings left."
			if now()>=float(batch.expires):return "This meal has spoiled. Clear it away."
			if str(batch.storage)=="carried":return "Wait until the cook puts the serving dish down."
			return ""
		var plate:Dictionary=food().portion(target)
		if not plate.is_empty() and str(plate.owner).is_empty() and float(plate.progress)<1 and now()<float(plate.expires):return ""
		return "Choose an available serving or a plate with food."
	if id=="store_meal":
		var batch:Dictionary=food().batch(target)
		if batch.is_empty() or int(batch.remaining)<=0 or now()>=float(batch.expires):return "Only fresh remaining servings can be stored."
		if str(batch.storage)!="surface" or not str(batch.owner).is_empty():return "That dish is already stored or being carried."
		if app.world.closest_item("fridge",Vector3.ZERO).is_empty():return "Place a fridge for leftovers."
	if id=="discard_meal":
		var batch:Dictionary=food().batch(target)
		if batch.is_empty() or int(batch.remaining)<=0 or not str(batch.owner).is_empty():return "That serving dish is empty or being carried."
		if app.world.closest_item("sink",Vector3.ZERO).is_empty():return "Place a sink to clear the dish."
	if id=="clean_plate":
		var plate:Dictionary=food().portion(target)
		if plate.is_empty() or not str(plate.owner).is_empty():return "That plate is being used."
		if app.world.closest_item("sink",Vector3.ZERO).is_empty():return "Place a sink to wash dishes."
	return ""

func actions_for(sim:LifeSim,kind:String,target:String) -> Array:
	var ids:Array=[]
	if kind=="meal":ids=["eat_meal","store_meal","discard_meal"]
	if kind=="plate":ids=["eat_meal","clean_plate"]
	var result:Array=[]
	for id:String in ids:
		var definition:Dictionary=sim.get_action_definition(id)
		var reason:String=action_availability(sim,id,target)
		definition.merge({"available":reason.is_empty(),"unavailable_reason":reason},true)
		result.append(definition)
	return result

func resolve(sim:LifeSim,action:Dictionary) -> void:
	if str(action.id) not in ACTIONS:return
	var person:String=member_id(sim)
	if not action.has("meal_source"):action.meal_source=str(action.target_id)
	if not action.has("meal_stage"):action.meal_stage="pickup"
	if action.id=="serve_meal":
		var surface:Dictionary=_serving_surface(actor(person).position)
		if not surface.is_empty():action.target_id=surface.id
	elif action.id=="eat_meal" and action.get("meal_stage")=="eat":
		var chair:Dictionary=item(str(action.get("meal_seat","")))
		if chair.is_empty() or _chair_table(chair).is_empty():
			_choose_seat(person,action)
			var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
			if not plate.is_empty():plate.storage="carried";plate.seat=""
	elif action.get("meal_stage")=="store":
		var fridge:Dictionary=app.world.closest_item("fridge",actor(person).position)
		if not fridge.is_empty():action.target_id=fridge.id
	elif action.get("meal_stage") in ["wash","discard"]:
		var sink:Dictionary=app.world.closest_item("sink",actor(person).position)
		if not sink.is_empty():action.target_id=sink.id
	var target:Dictionary=item(str(action.target_id))
	if not target.is_empty():action.target_position=app.world.approach(target)

func before_begin(sim:LifeSim,action:Dictionary) -> bool:
	if str(action.id)=="cook":
		var problem:String=action_availability(sim,"cook",str(action.target_id))
		if not problem.is_empty():_stop(sim,problem);return false
	if str(action.id) not in ACTIONS:return true
	var person:String=member_id(sim)
	if action.id=="eat_meal" and action.get("meal_stage")=="pickup":
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		if plate.is_empty():
			if not food().batch(str(action.meal_source)).is_empty():plate=food().claim(str(action.meal_source),person,now())
			elif food().take_portion(str(action.meal_source),person,now()):plate=food().portion(str(action.meal_source))
		if plate.is_empty():_stop(sim,"There is no fresh serving available.");return false
		action.meal_plate=plate.id;action.meal_stage="eat"
		action.elapsed=float(plate.progress)*LifeMeals.EATING_MINUTES
		action.progress=float(plate.progress)
		_choose_seat(person,action)
		sync_due=true;sim._emit_action_started(action);return false
	if action.id=="eat_meal":
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		if plate.is_empty() or str(plate.owner)!=person or now()>=float(plate.expires):_stop(sim,"This serving is no longer available.");return false
		var place:Dictionary=eating_anchor(person,action)
		var host:Dictionary=item(str(place.get("table_id","")))
		var offset:Vector3=host.node.to_local(place.plate_position) if not host.is_empty() else Vector3.ZERO
		food().put_portion(str(plate.id),str(place.get("table_id","")),str(action.get("meal_seat","")),place.plate_position,true,offset)
	if action.id in ["store_meal","discard_meal"] and action.get("meal_stage")=="pickup":
		var batch:Dictionary=food().batch(str(action.meal_source))
		if batch.is_empty() or str(batch.storage) not in (["surface"] if action.id=="store_meal" else ["surface","fridge"]) or not str(batch.owner).is_empty() or (action.id=="store_meal" and now()>=float(batch.expires)) or not food().set_batch_location(str(batch.id),"carried","",actor(person).position,now(),person):_stop(sim,"That dish is no longer available.");return false
		action.meal_stage="store" if action.id=="store_meal" else "discard";sim._emit_action_started(action);return false
	if action.id=="clean_plate" and action.get("meal_stage")=="pickup":
		var plate:Dictionary=food().portion(str(action.meal_source))
		if plate.is_empty() or not str(plate.owner).is_empty() or not food().carried_by(person).is_empty():_stop(sim,"That plate is no longer available.");return false
		plate.owner=person;plate.storage="carried";plate.seat=""
		action.meal_stage="wash";sim._emit_action_started(action);return false
	return true

func _stop(sim:LifeSim,message:String) -> void:
	sim._emit_notice(message);sim.cancel_action();sync_due=true

func carry_diner_plate(action:Dictionary) -> void:
	var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
	if not plate.is_empty():
		plate.storage="carried"
		plate.seat=""

func _serving_surface(from:Vector3) -> Dictionary:
	var table:Dictionary=app.world.closest_item("dining",from)
	if not table.is_empty():return table
	var counter:Dictionary=app.world.closest_item("counter",from)
	return counter if not counter.is_empty() else app.world.closest_item("stove",from)

func _chair_table(chair:Dictionary) -> Dictionary:
	var table:Dictionary=app.world.closest_item("dining",chair.node.position,1.6)
	if table.is_empty():return {}
	var direction:Vector3=(table.node.position-chair.node.position).normalized()
	if chair.node.global_basis.z.dot(direction)<.65:return {}
	return table

func _choose_seat(person:String,action:Dictionary) -> void:
	var chairs:Array=[]
	for candidate:Dictionary in app.world.items:
		if str(candidate.kind)!="chair" or _chair_table(candidate).is_empty():continue
		var occupied:bool=false
		for member:Dictionary in app.household.members:
			if member.id==person:continue
			var other:Dictionary=member.sim.get_current_action()
			if str(other.get("meal_seat",""))==str(candidate.id) or str(other.get("target_id",""))==str(candidate.id):occupied=true
		for plate:Dictionary in food().portions:
			if str(plate.seat)==str(candidate.id) and str(plate.owner)!=person:occupied=true
		if not occupied and not app.world.path_to(actor(person).position,app.world.approach(candidate)).is_empty():chairs.append(candidate)
	chairs.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.node.position.distance_squared_to(actor(person).position)<b.node.position.distance_squared_to(actor(person).position))
	if not chairs.is_empty():
		action.meal_seat=str(chairs[0].id);action.target_id=str(chairs[0].id);action.target_position=app.world.approach(chairs[0])
	else:
		# Eating remains possible without enough chairs. Keep the actual carried
		# plate and use a separate reachable standing spot near the meal.
		action.meal_seat="";action.target_id=str(action.meal_source)
		action.target_position=actor(person).position

func eating_anchor(person:String,action:Dictionary) -> Dictionary:
	var chair:Dictionary=item(str(action.get("meal_seat","")))
	if not chair.is_empty():
		var table:Dictionary=_chair_table(chair)
		if not table.is_empty():
			var seated:Dictionary=app.world.activity_anchor(chair,"eat_meal",actor(person).get_body_landmarks())
			var toward:Vector3=(table.node.position-chair.node.position).normalized()
			var local:Vector3=table.node.to_local(chair.node.position+toward*.48)
			local.x=clampf(local.x,-.62,.62);local.z=clampf(local.z,-.39,.39);local.y=SURFACE_HEIGHTS.dining
			if str(actor(person).profile.get("age_stage",""))=="child":
				app.world._show_desk_booster(chair.node)
				seated.position+=Vector3(0,.18,0)+toward*.10
			seated.merge({"plate_position":table.node.to_global(local),"table_id":str(table.id)},true)
			return seated
	var at:Vector3=actor(person).position
	return {"position":at,"yaw":actor(person).rotation.y,"kind":"standing","plate_position":actor(person).meal_carry_transform().origin,"table_id":""}

func consume(sim:LifeSim,action:Dictionary,minutes:float) -> void:
	var person:String=member_id(sim)
	var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
	if plate.is_empty() or now()>=float(plate.expires):_stop(sim,"This meal has spoiled.");return
	var gained:float=food().eat(str(plate.id),person,minutes,(sim.day-1)*1440.0+sim.minutes)
	sim.needs.hunger=minf(100.0,float(sim.needs.hunger)+gained)
	if str(plate.host).is_empty():return
	for other:Dictionary in food().portions:
		if str(other.id)==str(plate.id) or str(other.storage)!="table" or str(other.host)!=str(plate.host) or str(other.owner).is_empty():continue
		var partner:LifeSim=app.household.member_sim(str(other.owner))
		if partner==null or str(partner.get_current_action().get("id",""))!="eat_meal" or str(partner.get_current_action().get("phase",""))!="active":continue
		sim.needs.social=minf(100.0,float(sim.needs.social)+minutes*.35)
		plate.shared_minutes=minf(LifeMeals.EATING_MINUTES,float(plate.shared_minutes)+minutes)
		if not plate.company.has(str(other.owner)):plate.company.append(str(other.owner))
		break

func finished(sim:LifeSim,action:Dictionary) -> void:
	var person:String=member_id(sim)
	if action.id=="cook":
		var batch:Dictionary=food().create_batch(str(action.get("recipe","garden_skillet")),person,clampi(int(sim.skills.cooking.level)/3+1,1,3),app.current_venue,now())
		if not batch.is_empty():_prepend(sim,"serve_meal",str(batch.id),{"meal_source":str(batch.id)})
	elif action.id=="serve_meal":
		var target:Dictionary=item(str(action.target_id))
		var position:Vector3=target.node.to_global(Vector3(0,float(SURFACE_HEIGHTS.get(str(target.kind),.847)),0)) if not target.is_empty() else actor(person).position
		food().set_batch_location(str(action.meal_source),"surface",str(action.target_id),position,now())
		if not target.is_empty():
			var offset:Vector3=target.node.to_local(position)
			food().batch(str(action.meal_source)).offset=[offset.x,offset.y,offset.z]
		var served:Dictionary=food().batch(str(action.meal_source))
		if not served.is_empty():sim._emit_notice("Dinner is ready: %d servings of %s." % [int(served.remaining),str(LifeMeals.RECIPES[str(served.recipe)].label).to_lower()])
		if float(sim.needs.hunger)<75:_prepend(sim,"eat_meal",str(action.meal_source),{})
	elif action.id=="eat_meal":
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		if not plate.is_empty():
			if float(plate.shared_minutes)>=5:
				sim.add_moodlet("Around the table","Happy","Good food and familiar company.",180,2)
				for partner:String in plate.company:
					if sim.relationships.has(partner):sim.relationships[partner].friendship=minf(100,float(sim.relationships[partner].friendship)+4)
			food().finish_portion(str(plate.id))
	elif action.id=="store_meal":
		var fridge:Dictionary=item(str(action.target_id))
		if not fridge.is_empty():
			food().set_batch_location(str(action.meal_source),"fridge",str(fridge.id),fridge.node.position,now())
			food().batch(str(action.meal_source)).offset=[0.0,0.0,0.0]
	elif action.id=="discard_meal":
		food().set_batch_location(str(action.meal_source),"surface","",actor(person).position,now())
		food().discard_batch(str(action.meal_source))
	elif action.id=="clean_plate":food().clean_portion(str(action.meal_source),person)
	sync_due=true

func _prepend(sim:LifeSim,id:String,target:String,metadata:Dictionary) -> void:
	var action:Dictionary=sim.get_action_definition(id)
	action.merge({"target_id":target,"target_position":Vector3.ZERO,"phase":"queued","elapsed":0.0,"progress":0.0,"paid":false,"autonomous":true},true)
	action.merge(metadata,true)
	sim.action_queue.push_front(action)

func canceled(sim:LifeSim,action:Dictionary) -> void:
	if str(action.id) not in ACTIONS:return
	var person:String=member_id(sim)
	var carried:Dictionary=food().carried_by(person)
	var owned_id:String=str(action.get("meal_plate",action.get("meal_source","")))
	if not carried.is_empty() and str(carried.id)==owned_id and is_same(sim.get_current_action(),action) and is_instance_valid(actor(person)):
		food().release_member(person,actor(person).position)
	sync_due=true

func call_to_meal(target:String) -> int:
	var count:int=0
	for member:Dictionary in app.household.members:
		var sim:LifeSim=member.sim
		if not sim.action_queue.is_empty() or float(sim.needs.hunger)>85 or not is_instance_valid(actor(str(member.id))) or not actor(str(member.id)).visible:continue
		if float(sim.needs.energy)<12 or float(sim.needs.bladder)<12:continue
		if sim.queue_action("eat_meal",target,Vector3.ZERO):count+=1
	return count

func _mesh_view(value:Dictionary) -> Node3D:
	var recipe:String=str(food().batch(str(value.batch)).recipe) if value.has("batch") else str(value.recipe)
	var scene:PackedScene=load(LifeMeals.model_path(recipe,value.has("batch")))
	var root:Node3D=scene.instantiate()
	var body:StaticBody3D=StaticBody3D.new();body.name="FoodPicking";body.collision_layer=2;body.set_meta("item_id",str(value.id));root.add_child(body)
	var shape:CollisionShape3D=CollisionShape3D.new();var bounds:BoxShape3D=BoxShape3D.new()
	bounds.size=Vector3(.3,.10,.3) if value.has("batch") else Vector3(.5,.12,.335)
	shape.shape=bounds;shape.position.y=.04;body.add_child(shape)
	return root

func sync_world() -> void:
	if not is_instance_valid(app.world.house):return
	_reconcile_dining_furniture()
	var present:Dictionary={}
	var rebuilt:bool=false
	for value:Dictionary in food().batches+food().portions:
		if str(value.venue)!=app.current_venue:continue
		var key:String=str(value.id);present[key]=true
		if not views.has(key) or not is_instance_valid(views[key]):
			var node:Node3D=_mesh_view(value);node.name=key;app.world.house.add_child(node);views[key]=node;rebuilt=true
			app.world.items.append({"id":key,"kind":"plate" if value.has("batch") else "meal","label":"Plate" if value.has("batch") else str(LifeMeals.RECIPES[str(value.recipe)].label),"node":node,"size":Vector2(.35,.35),"transient_food":true})
		var host:Dictionary=item(str(value.host))
		if not host.is_empty() and str(value.storage) in ["surface","fridge","dirty","table"]:
			var offset:Array=value.get("offset",[0.0,float(SURFACE_HEIGHTS.get(str(host.kind),.847)),0.0])
			var at:Vector3=host.node.to_global(Vector3(float(offset[0]),float(offset[1]),float(offset[2])))
			value.position=[at.x,at.y,at.z]
		elif host.is_empty() and not str(value.host).is_empty() and str(value.storage)!="carried" and not _pending_furniture(str(value.host)):
			var at:Vector3=Vector3(float(value.position[0]),.17,float(value.position[2]))
			if value.has("batch"):
				value.position=[at.x,at.y,at.z];value.host="";value.seat=""
			else:food().set_batch_location(key,"surface","",at,now())
		var view:Node3D=views[key]
		view.visible=str(value.storage)!="fridge" and not _pending_furniture(str(value.host)) and (value.has("batch") or int(value.remaining)>0)
		if not str(value.owner).is_empty() and (str(value.storage)=="carried" or (str(value.storage)=="table" and str(value.host).is_empty())) and is_instance_valid(actor(str(value.owner))):
			view.global_transform=actor(str(value.owner)).meal_carry_transform()
		else:
			view.global_position=Vector3(float(value.position[0]),float(value.position[1]),float(value.position[2]))
			view.global_basis=host.node.global_basis if not host.is_empty() else Basis.IDENTITY
		var body:StaticBody3D=view.get_node("FoodPicking") if view.has_node("FoodPicking") else view.get_child(view.get_child_count()-1)
		body.collision_layer=2 if view.visible and str(value.storage) not in ["carried","table"] else 0
		var food_view:Node3D=view.find_child("Food",true,false)
		food_view.visible=not value.has("batch") or float(value.progress)<1.0
		if value.has("batch"):food_view.scale=Vector3(1.0,maxf(.05,1.0-float(value.progress)*.85),1.0)
	for key:String in views.keys():
		if not present.has(key) or not is_instance_valid(views[key]):
			if is_instance_valid(views[key]):views[key].queue_free()
			views.erase(key)
			app.world.items=app.world.items.filter(func(entry:Dictionary)->bool:return str(entry.id)!=key)
	var signature:String=JSON.stringify(present.keys())
	_sync_table_settings()
	if signature!=revision or rebuilt:
		revision=signature
		app.household.register_targets(app.world.simulation_targets())
	sync_due=false

func _sync_table_settings() -> void:
	# The authored fruit centerpiece belongs on an otherwise unused table.
	# Clear it while persistent food/dishes occupy that same surface.
	var occupied:Dictionary={}
	for value:Dictionary in food().batches+food().portions:
		if str(value.venue)==app.current_venue and str(value.storage) in ["table","surface","dirty"] and (value.has("batch") or int(value.remaining)>0):occupied[str(value.host)]=true
	for table:Dictionary in app.world.items:
		if str(table.kind)!="dining":continue
		for decoration:Node in table.node.find_children("Fruit*","Node3D",true,false):
			decoration.visible=not occupied.has(str(table.id))


func present_actor(person:String) -> void:
	var lifelet:LifeActor=actor(person)
	if not is_instance_valid(lifelet):return
	var held:Dictionary=food().carried_by(person)
	lifelet.meal_presentation={"carrying":not held.is_empty() and str(held.storage)=="carried","platter":not held.is_empty() and not held.has("batch")}
	var current:Dictionary=app.household.member_sim(person).get_current_action()
	lifelet.cooking_presentation={"recipe":str(current.get("recipe","garden_skillet")),"progress":float(current.get("progress",0))} if str(current.get("id",""))=="cook" else {}


func show_leftovers(fridge_id:String) -> void:
	app._begin_pause_overlay()
	app.dismiss_layer()
	app.card(Vector2(410,165),Vector2(620,565),app.P.WHITE,22,app.overlay)
	app.text_label("Something for later",Vector2(442,189),Vector2(544,51),32,app.P.INK,true,app.overlay)
	app.paragraph("Choose a fresh serving from the fridge. Leftovers keep longer, but they still spoil.",Vector2(443,249),Vector2(545,59),16,app.P.MUTED,app.overlay)
	var scroll:ScrollContainer=ScrollContainer.new();app.rect(scroll,Vector2(441,331),Vector2(551,285),app.overlay)
	var column:VBoxContainer=VBoxContainer.new();column.add_theme_constant_override("separation",12);scroll.add_child(column)
	var shown:int=0
	for batch:Dictionary in food().batches:
		if str(batch.storage)!="fridge" or str(batch.host)!=fridge_id or str(batch.venue)!=app.current_venue or int(batch.remaining)<=0:continue
		shown+=1
		var row:Button=Button.new();row.custom_minimum_size=Vector2(529,64)
		var fresh:bool=now()<float(batch.expires)
		row.text="%s · %d servings\n%s" % [str(LifeMeals.RECIPES[str(batch.recipe)].label),int(batch.remaining),("Fresh for about %d hours" % maxi(1,ceili((float(batch.expires)-now())/60.0))) if fresh else "Spoiled"]
		row.disabled=false
		if not fresh:row.text+=" · Clear spoiled food"
		row.pressed.connect(func():
			app.close_overlay()
			var target:Dictionary=item(str(batch.id))
			if not target.is_empty():app.queue_interaction(target,"eat_meal" if fresh else "discard_meal"))
		column.add_child(row)
	if shown==0:app.paragraph("No leftovers yet. Cook a meal and put away the extra servings.",Vector2(452,370),Vector2(518,92),20,app.P.MUTED,app.overlay)
	app.button("Back to life",Vector2(734,657),Vector2(256,43),app.close_overlay,true,app.overlay)


func action_title(action:Dictionary) -> String:
	if str(action.get("id",""))=="cook":return ("Preparing " if str(action.get("phase",""))=="active" else "Getting ready to cook ")+str(LifeMeals.RECIPES[str(action.get("recipe","garden_skillet"))].label).to_lower()
	if str(action.get("id","")) not in ACTIONS:return ""
	var approaching:bool=str(action.get("phase",""))=="approach"
	match str(action.id):
		"serve_meal":return "Bringing dinner to the table" if approaching else "Dinner is ready"
		"eat_meal":
			if str(action.get("meal_stage",""))=="pickup":return "Getting a serving"
			return "Finding a place to eat" if approaching else "Enjoying a meal"
		"store_meal":return "Putting away leftovers"
		"clean_plate":return "Taking a plate to the sink" if approaching else "Washing a plate"
		"discard_meal":return "Clearing away the meal"
	return ""


func company_label(person:String) -> String:
	var plate:Dictionary=food().carried_by(person)
	if plate.is_empty() or str(plate.storage)!="table" or str(plate.host).is_empty():return ""
	var names:Array[String]=[]
	for other:Dictionary in food().portions:
		if str(other.owner).is_empty() or str(other.owner)==person or str(other.storage)!="table" or str(other.host)!=str(plate.host):continue
		var companion:LifeSim=app.household.member_sim(str(other.owner))
		if companion and companion.get_current_action().get("phase")=="active":names.append(str(companion.character.name))
	return "AT THE TABLE WITH "+", ".join(names).to_upper() if not names.is_empty() else ""


func _reconcile_dining_furniture() -> void:
	for member:Dictionary in app.household.members:
		var action:Dictionary=member.sim.get_current_action()
		if action.get("id")!="eat_meal" or action.get("phase")!="active" or str(action.get("meal_seat","")).is_empty():continue
		var plate:Dictionary=food().portion(str(action.get("meal_plate","")))
		# Move temporarily removes furniture from the world. Preserve ownership
		# and progress until placement or cancel restores the same stable ID.
		if _pending_furniture(str(action.meal_seat)) or _pending_furniture(str(plate.get("host",""))):continue
		var chair:Dictionary=item(str(action.meal_seat))
		if not chair.is_empty() and not _chair_table(chair).is_empty():
			var anchor:Dictionary=eating_anchor(str(member.id),action)
			var host:Dictionary=item(str(anchor.table_id))
			food().put_portion(str(action.get("meal_plate","")),str(anchor.table_id),str(action.meal_seat),anchor.plate_position,true,host.node.to_local(anchor.plate_position))
			continue
		if not plate.is_empty():plate.storage="carried";plate.seat=""
		action.phase="approach"
		_choose_seat(str(member.id),action)
		member.sim._emit_action_started(action)


func show_recipes(target_id:String) -> void:
	app._begin_pause_overlay();app.dismiss_layer()
	app.card(Vector2(321,118),Vector2(798,664),app.P.WHITE,22,app.overlay)
	app.text_label("What’s cooking?",Vector2(352,140),Vector2(720,51),34,app.P.INK,true,app.overlay)
	app.paragraph("Cooking level %d · Choose a dish to share. Ingredients are paid for when cooking begins." % int(app.sim.skills.cooking.level),Vector2(355,206),Vector2(721,49),16,app.P.MUTED,app.overlay)
	var index:int=0
	for recipe:String in LifeMeals.RECIPES:
		var definition:Dictionary=LifeMeals.RECIPES[recipe]
		var row:Control=Control.new();row.name="RecipeRow_"+recipe
		app.rect(row,Vector2(349,276+index*135),Vector2(742,122),app.overlay)
		app.card(Vector2.ZERO,Vector2(742,122),Color("f3f4ed"),13,row)
		_recipe_preview(recipe,row)
		app.text_label(str(definition.label),Vector2(179,11),Vector2(533,30),23,app.P.INK,true,row)
		app.paragraph("%d servings  ·  §%d  ·  %d min  ·  Cooking %d" % [int(definition.servings),int(definition.cost),int(definition.duration),int(definition.skill)],Vector2(181,45),Vector2(533,25),13,app.P.INK,row)
		var reason:String=LifeMeals.recipe_error(recipe,int(app.sim.skills.cooking.level),str(app.sim.character.age_stage),app.sim.funds)
		if reason.is_empty():reason=action_availability(app.sim,"cook",target_id)
		app.paragraph(str(definition.description) if reason.is_empty() else reason,Vector2(181,79),Vector2(310,35),12,app.P.MUTED,row)
		var choose:Button=app.button("Cook "+str(definition.label).to_lower(),Vector2(509,78),Vector2(218,34),queue_recipe.bind(target_id,recipe),true,row)
		choose.name="Recipe_"+recipe;choose.disabled=not reason.is_empty();choose.tooltip_text=reason
		index+=1
	app.button("Back to life",Vector2(866,718),Vector2(221,39),app.close_overlay,false,app.overlay)

func queue_recipe(target_id:String,recipe:String) -> void:
	var target:Dictionary=item(target_id)
	if target.is_empty():app.show_notice("This kitchen item is no longer here.");return
	if app.sim.is_away():app.show_notice("This Lifelet will be available after coming home.");return
	if app.sim.queue_action("cook",target_id,app.world.approach(target),recipe):
		app.close_overlay();app.refresh_hud()

func _recipe_preview(recipe:String,parent:Control) -> void:
	var viewport:SubViewport=SubViewport.new();viewport.name="DishPreview";viewport.size=Vector2i(300,204)
	viewport.own_world_3d=true;viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	parent.add_child(viewport)
	var model:Node3D=load(LifeMeals.model_path(recipe)).instantiate();viewport.add_child(model)
	var camera:Camera3D=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.42
	viewport.add_child(camera);camera.position=Vector3(.33,.48,.57);camera.look_at(Vector3(0,.035,0));camera.current=true
	var light:DirectionalLight3D=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-30,0);light.light_energy=.8;viewport.add_child(light)
	var world_environment:WorldEnvironment=WorldEnvironment.new();world_environment.environment=Environment.new()
	world_environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world_environment.environment.ambient_light_color=Color("fff4de");world_environment.environment.ambient_light_energy=.35;world_environment.environment.tonemap_mode=Environment.TONE_MAPPER_REINHARDT
	viewport.add_child(world_environment)
	var picture:TextureRect=TextureRect.new();picture.texture=viewport.get_texture();picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.rect(picture,Vector2(9,9),Vector2(153,104),parent)
