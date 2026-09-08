extends Node
class_name LifeSanitationFlow
## Floor-level accident presentation and cleanup are independent of food custody.
var app:Node
var views:Dictionary={}
func member_id(sim:LifeSim)->String:
	for member:Dictionary in app.household.members:
		if member.sim==sim:return str(member.id)
	return ""
func accident(sim:LifeSim)->bool:
	if app.mode!="live" or app.loading_game or sim.is_away():return false
	var id:String=member_id(sim)
	var actor:LifeActor=app.world.actors.get(id)
	if not is_instance_valid(actor) or not actor.visible or bool(actor.get_meta("away",false)):return false
	# Store the actual root's X/Z and its supported floor, not a chair/bed visual
	# offset. Both supported levels retain a datum for future physical restores.
	var at:Vector3=actor.position
	var level:int=clampi(floori((at.y-.16+.15)/3.0),0,1)
	at.y=.16+3.0*level
	app.household.sanitation.add(id,app.current_venue,at,level,(sim.day-1)*1440.0+sim.minutes)
	actor.speech("Oh no… I couldn't hold on.")
	actor.react_to_accident()
	return true
func action_availability(sim:LifeSim,id:String,target:String)->String:
	if not app.household.meals.carried_by(member_id(sim)).is_empty():return "Put down the food you are carrying first."
	var item:Dictionary=app._find_item(target)
	if id=="plant_wee":
		if item.is_empty() or str(item.kind)!="plant":return "That plant pot is no longer here."
		return ""
	var puddle:Dictionary=app.household.sanitation.find(target)
	if puddle.is_empty() or str(puddle.venue)!=app.current_venue or item.is_empty():return "That puddle has already been cleaned or is in another place."
	for member:Dictionary in app.household.members:
		if member.sim==sim:continue
		var action:Dictionary=member.sim.get_current_action()
		if str(action.get("id",""))=="mop_puddle" and str(action.get("target_id",""))==target and str(action.get("phase",""))=="active":return "Another Lifelet is already mopping this puddle."
	return ""
func finished(_sim:LifeSim,action:Dictionary)->void:
	if str(action.id)=="mop_puddle":app.household.sanitation.remove(str(action.target_id))
func sync_world()->void:
	if not is_instance_valid(app.world.house):return
	var present:Dictionary={}
	var changed:bool=false
	for puddle:Dictionary in app.household.sanitation.puddles:
		if str(puddle.venue)!=app.current_venue:continue
		var id:String=puddle.id;present[id]=true
		if not views.has(id) or not is_instance_valid(views[id]) or views[id].get_parent()!=app.world.house or views[id].is_queued_for_deletion():
			if views.has(id) and is_instance_valid(views[id]):views[id].queue_free()
			var node:Node3D=make_view(id);node.name=id;app.world.house.add_child(node);views[id]=node
			# The picking volume is broad enough to click but never participates in navigation.
			app.world.items.append({"id":id,"kind":"puddle","label":"Accident puddle","node":node,"size":Vector2(.9,.5),"transient_puddle":true,"level":int(puddle.level)})
			changed=true
		views[id].position=Vector3(float(puddle.position[0]),_display_height(puddle),float(puddle.position[2]))
	var removed:bool=false
	for id:String in views.keys():
		if not present.has(id) or not is_instance_valid(views[id]):
			if is_instance_valid(views[id]):views[id].queue_free()
			views.erase(id)
			app.world.items=app.world.items.filter(func(item:Dictionary)->bool:return str(item.id)!=id)
			changed=true;removed=true
	if changed:app.household.register_targets(app.world.simulation_targets())
	if removed:
		# A second queued cleaner loses only this obsolete instruction, keeping
		# later activities. Clearing the old route before cancel matches the main controller.
		for member:Dictionary in app.household.members:
			for i:int in range(member.sim.action_queue.size()-1,-1,-1):
				var action:Dictionary=member.sim.action_queue[i]
				if str(action.id)=="mop_puddle" and app.household.sanitation.find(str(action.target_id)).is_empty():
					var previous:String=app.bound_member_id
					app._store_motion();app._bind_member(member.id);app.cancel_current_action(i);app._store_motion();app._bind_member(previous)
func _display_height(puddle:Dictionary)->float:
	var height:float=float(puddle.floor_y)
	var at:Vector3=Vector3(float(puddle.position[0]),height,float(puddle.position[2]))
	if int(puddle.level)==0:height=app.meal_flow._floor_height(at)-.002
	for item:Dictionary in app.world.items:
		if str(item.kind)!="rug" or absf(item.node.position.y-float(puddle.floor_y))>.05:continue
		var local:Vector3=item.node.to_local(at)
		if absf(local.x)<=float(item.size.x)*.5 and absf(local.z)<=float(item.size.y)*.5:
			# Authored woven rug top: .014 centre + .025/2 thickness.
			height=maxf(height,item.node.position.y+.0265)
	return height+.006
static func make_view(id:String)->Node3D:
	var node:Node3D=Node3D.new()
	var vertices:PackedVector3Array=PackedVector3Array([Vector3.ZERO])
	var normals:PackedVector3Array=PackedVector3Array([Vector3.UP])
	var colors:PackedColorArray=PackedColorArray([Color(.22,.20,.10,.48)])
	var indices:PackedInt32Array=PackedInt32Array()
	# A low-saturation wet centre fades across an irregular perimeter. It
	# preserves the visible weave/wood beneath it rather than painting a disc.
	for ring:int in 2:
		for i:int in 48:
			var angle:float=TAU*i/48.0
			var radius:float=(.72 if ring==0 else 1.0)*(1.0+.09*sin(angle*3.0)+.04*cos(angle*5.0))
			vertices.append(Vector3(cos(angle)*.46*radius,0,sin(angle)*.29*radius));normals.append(Vector3.UP)
			colors.append(Color(.22,.20,.10,.42 if ring==0 else 0.0))
	for i:int in 48:
		var next:int=(i+1)%48
		indices.append_array(PackedInt32Array([0,i+1,next+1,i+1,i+49,next+49,i+1,next+49,next+1]))
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh:ArrayMesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:StandardMaterial3D=StandardMaterial3D.new()
	material.albedo_color=Color.WHITE;material.vertex_color_use_as_albedo=true;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.roughness=.08;material.metallic_specular=.8
	var view:MeshInstance3D=MeshInstance3D.new();view.mesh=mesh;view.material_override=material;view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.add_child(view)
	var body:StaticBody3D=StaticBody3D.new();body.name="PuddlePicking";body.collision_layer=2;body.collision_mask=0;body.set_meta("item_id",id);node.add_child(body)
	var shape:CollisionShape3D=CollisionShape3D.new();var box:BoxShape3D=BoxShape3D.new();box.size=Vector3(.94,.025,.62);shape.shape=box;body.add_child(shape)
	return node
