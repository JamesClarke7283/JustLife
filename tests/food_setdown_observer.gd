extends Node
## Read-only callback observer. Never changes food, actors, clocks or queues.
var app:Node
var data:Dictionary={"releases":[],"maximum_horizontal_metres":0.0}
var previous:Dictionary={}
var watched:Dictionary={}
func _ready()->void:
	app.household.member_action_finished.connect(func(_id:String,action:Dictionary):inspect("finished:"+str(action.id)))
	app.household.member_action_started.connect(func(_id:String,_action:Dictionary):inspect("action_started"))
func _process(_delta:float)->void:
	for member:Dictionary in app.household.members:
		var key:int=member.sim.get_instance_id()
		if not watched.has(key):
			watched[key]=true;member.sim.changed.connect(func():inspect("sim_changed"))
	inspect("frame")
func inspect(source:String)->void:
	if app.mode not in ["live","build"]:return
	var current:Dictionary={}
	for food:Dictionary in app.household.meals.batches+app.household.meals.portions:
		var id:String=str(food.id);current[id]={"owner":str(food.owner),"food":food.duplicate(true)}
		var before:Dictionary=previous.get(id,{})
		if before.is_empty() or str(before.owner).is_empty() or not str(food.owner).is_empty() or str(food.storage) not in ["dirty","surface"]:continue
		var owner:Node3D=app.world.actors.get(str(before.owner))
		if not is_instance_valid(owner):continue
		var at:=Vector3(float(food.position[0]),float(food.position[1]),float(food.position[2]))
		var distance:float=Vector2(at.x-owner.position.x,at.z-owner.position.z).length()
		data.maximum_horizontal_metres=maxf(float(data.maximum_horizontal_metres),distance)
		data.releases.append({"at":(app.household.day-1)*1440.0+app.household.minutes,"food_id":id,"former_owner":before.owner,"actor_position":[owner.position.x,owner.position.y,owner.position.z],"setdown_position":[at.x,at.y,at.z],"horizontal_metres":distance,"source":source,"food":food.duplicate(true)})
	previous=current
