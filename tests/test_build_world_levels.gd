extends SceneTree
## Actual LifeWorld geometry/route/view integration. No main controller, actor
## stair gait, household save UI, money mutation or public building claim.
const World=preload("res://scripts/world.gd")
const Building=preload("res://scripts/building_state.gd")
var checks:int=0
var failures:Array[String]=[]
var observations:Dictionary={"scope":"Actual scene geometry, serialized layout, explicit route metadata and camera/picking masks; no actor traversal or public feature."}
var picked:String=""

func _initialize()->void:_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func fixture(with_stair:bool=true)->Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	for level:int in [0,1]:
		for side:int in [-1,1]:
			state.walls.append({"id":("upper_" if level else "")+("north" if side<0 else "south"),"level":level,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	if with_stair:
		var quote:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
		check(bool(quote.ok),"Actual-scene fixture uses a validated supported staircase purchase proposal.")
		if bool(quote.ok):state=quote.after
	return state

func _layout(state:Dictionary)->Array:
	# Marker intentionally last, matching the real serializer.
	return [{"id":"ground_plant","kind":"plant","x":-2.0,"z":2.0,"rotation":0.0},{"id":"upper_plant","kind":"plant","x":-2.0,"z":2.0,"rotation":0.0,"level":1},{"id":"ground_stove","kind":"stove","x":2.5,"z":-3.0,"rotation":90.0},{"id":"upper_stove","kind":"stove","x":2.5,"z":-3.0,"rotation":90.0,"level":1},{"id":"upper_chair","kind":"chair","x":-2.5,"z":-.5,"rotation":0.0,"level":1},state]

func _item(world:Node3D,id:String)->Dictionary:
	for item:Dictionary in world.items:
		if item.id==id:return item
	return {}

func _floor_boxes(world:Node3D,level:int)->Array:
	var result:Array=[]
	for node:Node3D in world.construction.floor_nodes:
		if int(node.get_meta("building_level",-1))==level and node is MeshInstance3D and node.mesh is BoxMesh:result.append(node)
	return result

func _covered_by_scene(world:Node3D,level:int,at:Vector2)->bool:
	for node:MeshInstance3D in _floor_boxes(world,level):
		var local:Vector3=node.to_local(Vector3(at.x,Building.level_y(level),at.y))
		var half:Vector3=node.mesh.size*.5
		if absf(local.x)<=half.x+.00001 and absf(local.z)<=half.z+.00001 and absf(local.y-half.y)<.00001:return true
	return false

func _run()->void:
	root.size=Vector2i(1280,800)
	var world:Node3D=World.new();root.add_child(world)
	await process_frame
	var state:Dictionary=fixture()
	var loaded:Dictionary=world.load_home(_layout(state))
	check(bool(loaded.ok),"Canonical two-storey structure loads before its marker-last upper furniture.")
	if not bool(loaded.ok):print(loaded);world.queue_free();_finish();return
	await process_frame
	check(world.items.size()==5 and world.construction.stair_nodes.size()==1,"Actual world contains five furnishings and one imported stair instance.")
	check(world.starter_floor_nodes.all(func(node:Node3D)->bool:return not node.visible),"A replacement footprint hides the old starter boards and bathroom tiles.")
	_geometry(world,state)
	_contacts(world)
	_routes(world,state)
	_construction_preview(world,state)
	await _views(world)
	await _serialization(world,state)
	await _legacy()
	world.queue_free();await process_frame
	_finish()

func _geometry(world:Node3D,state:Dictionary)->void:
	var upper:Array=_floor_boxes(world,1)
	check(not upper.is_empty(),"Upper support is actual rendered slab meshes.")
	var area:float=0.0
	var hole:Rect2=Building.rect(state.openings[0])
	var all_supported:bool=true;var no_cover:bool=true;var correct_height:bool=true
	for node:MeshInstance3D in upper:
		var size:Vector3=node.mesh.size
		var bounds:=Rect2(Vector2(node.global_position.x,node.global_position.z)-Vector2(size.x,size.z)*.5,Vector2(size.x,size.z))
		area+=size.x*size.z
		no_cover=no_cover and not bounds.intersects(hole)
		correct_height=correct_height and is_equal_approx(node.global_position.y+size.y*.5,3.16) and is_equal_approx(node.global_position.y-size.y*.5,3.0)
		all_supported=all_supported and Building.footprint_supported(state,1,bounds)
	check(no_cover,"No actual upper slab rectangle covers any part of the internal stair opening.")
	check(correct_height,"Upper slabs have a real 3.16m top and 3.0m underside.")
	check(all_supported,"Every generated upper tile corresponds to supported geometry.")
	check(is_equal_approx(area,80.0-hole.get_area()+8.0*.14),"Rendered slab union conserves area including both 7cm perimeter bearing extensions.")
	check(_covered_by_scene(world,0,Vector2(0,0)) and not _covered_by_scene(world,1,Vector2(0,0)),"Actual scene keeps the lower floor while removing only the upper stairwell surface.")
	for z:float in [-5.069,-5.035,5.035,5.069]:check(_covered_by_scene(world,1,Vector2(0,z)),"Actual bearing slab supports the outside half of the perimeter wall at z="+str(z))
	var stair:Dictionary=state.stairs[0]
	var node:Node3D=world.construction.stair_nodes[str(stair.id)]
	for pair:Array in [["LowerLanding",Vector3(0,.16,-2.5)],["RunBegin",Vector3(0,.16,-2)],["RunEnd",Vector3(0,3.16,1.75)],["UpperLanding",Vector3(0,3.16,2.25)]]:
		var marker:Node3D=node.find_child(str(pair[0]),true,false)
		check(is_instance_valid(marker) and marker.global_position.distance_to(pair[1])<.0001,"Imported physical stair marker agrees with navigation coordinates: "+str(pair[0]))
	for step:int in range(1,16):
		var marker:Node3D=node.find_child("Tread_%02d"%step,true,false)
		check(is_instance_valid(marker) and marker.global_position.distance_to(Vector3(0,.16+step*.2,-2+(step-.5)*.25))<.0001,"Actual tread contact marker "+str(step)+" is on its ascending step.")
	observations["upper_slab_area"]=area
	observations["opening_area"]=hole.get_area()
	var guard:Node3D=world.construction.guard_nodes[str(stair.id)]
	var posts:int=0;var spans:int=0
	for child:Node3D in guard.get_children():
		if child.has_meta("guard_post"):
			posts+=1
			for dx:float in [-.043,.043]:
				for dz:float in [-.043,.043]:check(_covered_by_scene(world,1,Vector2(child.position.x+dx,child.position.z+dz)),"Actual generated guard post full footprint rests on rendered slab.")
		if child.has_meta("guard_span"):spans+=1
	check(posts==11 and spans==10,"Opening kit has one shared post per junction and ten bounded spans.")
	check(world.lot_navigation.point_clear(1,Vector3(0,3.16,2.25)),"Supported upper landing exit stays open through the generated guard kit.")
	check(not world.lot_navigation.point_clear(1,Vector3(.68,3.16,0)),"Actual guard strips also block upper floor navigation.")
	check(not world.can_place("plant",Vector3(.8,3.16,0),0),"A furnishing cannot cover the actual guard strip beside the opening.")
	observations["guard_limitation"]="Derived supported upper perimeter guards and flush fascia; no actor, feet, clothing or roof headroom proof."

func _contacts(world:Node3D)->void:
	var ground:Dictionary=_item(world,"ground_stove");var upper:Dictionary=_item(world,"upper_stove")
	check(upper.node.position-ground.node.position==Vector3(0,3,0),"Identical appliance placements on different levels differ by exactly 3m.")
	check(world.oven_approach(upper)-world.oven_approach(ground)==Vector3(0,3,0),"Paid bake approach preserves local facing and the selected floor height.")
	var ground_anchor:Dictionary=world.activity_anchor(ground,"cook",{"recipe":"harvest_bake"})
	var upper_anchor:Dictionary=world.activity_anchor(upper,"cook",{"recipe":"harvest_bake"})
	check(upper_anchor.position-ground_anchor.position==Vector3(0,3,0),"Oven activity anchor remains host-local on the upper storey.")
	check(is_equal_approx(world.activity_anchor(_item(world,"upper_chair"),"sit").position.y,3.68),"A real upper chair preserves its cushion contact offset.")
	check(is_equal_approx(world.approach(upper).y,3.16) and is_equal_approx(world.approach(ground).y,.16),"Simulation interaction approaches remain on each furnishing's own floor.")
	var targets:Array=world.simulation_targets();var found:Dictionary={}
	for target:Dictionary in targets:
		if str(target.id) in ["ground_stove","upper_stove"]:found[target.id]=target
	check(found.size()==2 and int(found.upper_stove.level)==1 and is_equal_approx(found.upper_stove.position.y,3.16),"Simulation target payload retains explicit level metadata and world height.")
	world.update_oven_presentations({"upper_stove":{"inside":true,"progress":.5}})
	var view:Node3D=world.oven_food_views.get("upper_stove")
	var rack:Node3D=upper.node.find_child("OvenRack",true,false)
	check(is_instance_valid(view) and view.get_parent()==upper.node and view.global_position.distance_to(rack.global_position)<.00001,"World interior food remains parented to its actual upper oven rack.")
	check(view.find_children("*","MeshInstance3D",true,false).all(func(node:MeshInstance3D)->bool:return node.layers==World.VIEW_UPPER),"Late-created oven dish inherits the upper floor visibility layer.")
	world._show_desk_booster(_item(world,"upper_chair").node)
	var booster:Node3D=_item(world,"upper_chair").node.find_child("LifeletDeskBooster",true,false)
	check(is_instance_valid(booster) and booster.find_children("*","MeshInstance3D",true,false).all(func(node:MeshInstance3D)->bool:return node.layers==World.VIEW_UPPER),"Late-created child booster inherits its real chair's floor visibility layer.")
	check(world.items.size()==5,"Interior oven presentation creates no independent food or furnishing identity.")
	world.update_oven_presentations({})
	check(world.oven_food_views.is_empty(),"Removing current presentation clears the upper oven dish.")
	check(world.can_place("plant",Vector3(2.5,.16,2.0),0) and world.can_place("plant",Vector3(2.5,3.16,2.0),0),"A supported free footprint can be placed independently on both floors.")
	check(not world.can_place("plant",Vector3(0,3.16,0),0),"Placement rejects the actual internal stair hole, despite surrounding slab.")
	check(not world.can_place("plant",Vector3(-2,3.16,2),0),"Placement detects same-level upper furnishing overlap.")
	check(not world.navigation.is_point_solid(Vector2i(-10,-2)),"An upper chair does not block the legacy ground compatibility grid.")

func _routes(world:Node3D,state:Dictionary)->void:
	var route:Dictionary=world.route_to(Vector3(-2,.16,-2),Vector3(2,3.16,2))
	check(bool(route.ok),"Actual world's explicit navigation graph reaches the upper floor.")
	if bool(route.ok):
		var changing:int=0;var tagged:bool=true
		for segment:Dictionary in route.segments:
			if absf(segment.to.y-segment.from.y)>.00001:changing+=1;tagged=tagged and segment.kind=="stair" and str(segment.stair_id)==str(state.stairs[0].id)
		check(changing==15 and tagged,"Every vertical route segment belongs to the one real stair, with 15 ascent edges.")
		check(route.points[0]==Vector3(-2,.16,-2) and route.points[-1]==Vector3(2,3.16,2),"Route preserves exact supported start and destination instead of floor snapping.")
		check(world.path_to(Vector3(-2,.16,-2),Vector3(2,3.16,2))==route.points,"Compatibility path API exposes the same real 3D route in a canonical building.")
		observations["route"]=route
	check(not bool(world.route_to(Vector3(-2,.16,-2),Vector3(0,3.16,0)).ok),"An endpoint inside the upper hole does not receive a partial route.")
	check(not bool(world.route_to(Vector3(-2,1.66,-2),Vector3(2,3.16,2)).ok),"Mid-stair state cannot be silently treated as a floor endpoint.")
	var disconnected:Dictionary=fixture(false)
	world.construction.restore(disconnected);world.rebuild_navigation()
	check(not bool(world.route_to(Vector3(-2,.16,-2),Vector3(2,3.16,2)).ok),"Removing the actual staircase disconnects upper and lower floor graphs.")
	world.construction.restore(state);world.rebuild_navigation()
	check(bool(world.route_to(Vector3(-2,.16,-2),Vector3(2,3.16,2)).ok),"Restoring the staircase restores only its explicit cross-floor connection.")

func _construction_preview(world:Node3D,state:Dictionary)->void:
	var ground:Dictionary=fixture(false)
	ground.floors=ground.floors.filter(func(record:Dictionary)->bool:return int(record.level)==0)
	ground.walls=ground.walls.filter(func(record:Dictionary)->bool:return int(record.level)==0)
	world.construction.restore(ground);world.construction.build_level=1
	var before:Dictionary=world.construction.snapshot()
	world.construction.begin("wall");world.construction.click(Vector3(-2,3.16,3))
	var rejected:Dictionary=world.construction.click(Vector3(0,3.16,3))
	var explanation:String=str(rejected.get("error","")).to_lower()
	check(explanation.contains("upper wall") and explanation.contains("floor"),"Unsupported upper-wall preview returns the actual floor-support explanation.")
	check(world.construction.snapshot()==before,"Rejected structure preview changes no geometry or identities.")
	world.construction.restore(state);world.construction.build_level=1
	world.construction.begin("wall");world.construction.click(Vector3(-4,3.16,-2))
	var accepted:Dictionary=world.construction.click(Vector3(-4,3.16,0))
	check(bool(accepted.get("valid",false)) and int(accepted.get("cost",0))==110,"A normal new upper perimeter wall produces a valid original per-metre quote.")
	check(world.construction.snapshot()==state,"A valid upper-wall preview remains detached from live geometry.")
	if bool(accepted.get("valid",false)):
		world.construction.commit(accepted)
		check(world.construction.records.size()==state.walls.size()+1 and _covered_by_scene(world,1,Vector2(-4.069,-1)),"Committing the preview builds its full physical bearing slab and upper wall.")
	world.construction.restore(state);world.construction.cancel();world.rebuild_navigation()

func _views(world:Node3D)->void:
	var actor:=Node3D.new();actor.position=Vector3(3,.16,3);world.add_child(actor);world.actors["view_probe"]=actor
	var mesh:MeshInstance3D=world.box(actor,Vector3(0,.6,0),Vector3(.4,1.2,.4),"397e70")
	actor.visible=false
	world.set_view_level(1)
	check(not actor.visible,"Floor view changes never turn an away/hidden actor visible.")
	actor.visible=true;world.refresh_actor_layers()
	check(mesh.layers==World.VIEW_ACTOR_GROUND and (mesh.layers&world.camera.cull_mask)==0,"An at-home ground actor is filtered through layers rather than visible state.")
	actor.position.y=3.16;world.refresh_actor_layers()
	check(mesh.layers==World.VIEW_ACTOR_UPPER and (mesh.layers&world.camera.cull_mask)!=0,"Upper actor rendering uses the correct camera layer.")
	actor.position.y=1.6;world.refresh_actor_layers()
	check(mesh.layers==(World.VIEW_ACTOR_GROUND|World.VIEW_ACTOR_UPPER),"A future stair-traversing actor remains renderable from either level.")
	world.actors.erase("view_probe");actor.queue_free()
	world.object_clicked.connect(func(item:Dictionary,_at:Vector2)->void:picked=str(item.id))
	world.live_enabled=true
	for level:int in [0,1]:
		check(world.set_view_level(level),"View selection accepts explicit floor "+str(level))
		world.camera.position=Vector3(-2,12,2);world.camera.look_at(Vector3(-2,0,2),Vector3.FORWARD)
		await physics_frame
		var screen:Vector2=world.camera.unproject_position(Vector3(-2,Building.level_y(level)+.2,2))
		picked="";world.pick(screen)
		check(picked==("ground_plant" if level==0 else "upper_plant"),"Actual physics ray picks only the selected floor despite vertically aligned furnishings.")
		check(absf(world.floor_point(screen).y-Building.level_y(level))<.00001,"Build ground ray intersects the selected level plane.")
	var before:Dictionary=world.construction.snapshot();world.set_cutaway(false)
	check(world.construction.snapshot()==before,"Wall visibility does not modify canonical structure or support identity.")
	for id:String in ["north","south"]:
		var support:Node3D=world.construction.wall_nodes[id];var rim:MeshInstance3D=null
		for child:Node3D in support.get_children():
			if child.has_meta("floor_support_rim"):rim=child
		check(is_instance_valid(rim) and is_equal_approx(rim.global_position.y-rim.mesh.size.y*.5,2.76) and is_equal_approx(rim.global_position.y+rim.mesh.size.y*.5,3.0),"Actual full-wall rim bridges the bearing wall to the upper slab underside: "+id)
	world.set_cutaway(true);world.live_enabled=false

func _serialization(world:Node3D,state:Dictionary)->void:
	var saved:Array=world.serialize_items()
	check(str(saved[-1].kind)=="__construction" and int(saved[-1].version)==2,"Serializer retains a versioned structural record after its furnishings.")
	var fresh:Node3D=World.new();root.add_child(fresh);await process_frame
	var result:Dictionary=fresh.load_home(JSON.parse_string(JSON.stringify(saved)))
	check(bool(result.ok),"Actual JSON layout restores into a fresh world scene.")
	await process_frame
	check(fresh.items.size()==world.items.size() and fresh.construction.building_state==JSON.parse_string(JSON.stringify(state)),"World reconstruction preserves furnishings and validated structural identities.")
	check(_item(fresh,"upper_stove").node.position==_item(world,"upper_stove").node.position and _item(fresh,"upper_stove").node.rotation.is_equal_approx(_item(world,"upper_stove").node.rotation),"Upper furnishing placement and rotation survive marker-last JSON reload.")
	var snapshot:Array=fresh.serialize_items();var old_house:Node3D=fresh.house
	for alteration:String in ["hole","unsupported","duplicate","bad_level"]:
		var invalid:Array=saved.duplicate(true)
		match alteration:
			"hole":invalid[1].x=0;invalid[1].z=0
			"unsupported":invalid[1].x=8
			"duplicate":invalid[1].id="ground_plant"
			"bad_level":invalid[1].level={}
		var rejected:Dictionary=fresh.load_home(invalid)
		check(not bool(rejected.ok) and not str(rejected.error).is_empty(),"Malformed or unsupported actual world load rejects: "+alteration)
		check(fresh.house==old_house and fresh.serialize_items()==snapshot,"Rejected load leaves previous world and serialized layout untouched: "+alteration)
	var excessive:Array=[]
	for index:int in range(513):excessive.append({"id":"plant_"+str(index),"kind":"plant","x":-2.0,"z":2.0,"rotation":0.0})
	excessive.append(state)
	check(not bool(fresh.load_home(excessive).ok) and fresh.house==old_house,"Obstacle-cap ingress rejects before replacing the actual world scene.")
	var outside:Array=[{"id":"outside","kind":"plant","x":100.0,"z":0.0,"rotation":0.0}]
	check(not bool(fresh.load_home(outside).ok) and fresh.house==old_house,"Legacy-shaped out-of-lot furnishing rejects before scene mutation or graph failure.")
	check(fresh.validate_home_layout([{"id":"default","kind":"plant"}]).is_empty(),"Optional legacy transform defaults are validated without unsafe missing-key access.")
	fresh.queue_free();await process_frame

func _legacy()->void:
	var old:Node3D=World.new();root.add_child(old);await process_frame
	old.create_home([])
	var snapshot:Array=old.serialize_items()
	check(old.construction.building_state.is_empty() and old.starter_floor_nodes.all(func(node:Node3D)->bool:return node.visible),"Unversioned starter world preserves its original ground rendering mode.")
	check(not old.path_to(Vector3(-.7,.16,2.8),Vector3(-7,.16,5.4)).is_empty(),"Legacy ground routing still reaches the public sidewalk.")
	snapshot[-1]["version"]=1
	var migrated:Dictionary=old.load_home(snapshot)
	check(bool(migrated.ok) and int(old.construction.building_state.get("version",0))==2,"Explicit version-1 construction migrates through actual world loading.")
	check(old.starter_floor_nodes.all(func(node:Node3D)->bool:return node.visible),"Migration retains original authored starter boards and bathroom tiles.")
	check(bool(old.route_to(Vector3(-.7,.16,2.8),Vector3(-7,.16,5.4)).ok),"Migrated ground graph retains an actual exterior route.")
	old.create_home(LifeCatalog.starter_layout())
	var furnished:Array=old.serialize_items();furnished[-1]["version"]=1
	var furnished_result:Dictionary=old.load_home(furnished)
	check(bool(furnished_result.ok),"A real furnished starter layout also passes explicit version-1 migration.")
	if not bool(furnished_result.ok):print("MIGRATION_DIAGNOSTIC ",furnished_result)
	old.load_home(_layout(fixture()));old.set_view_level(1)
	old.create_public_venue("library",[])
	check(old.view_level==0 and old.camera_target.y==0 and (old.camera.cull_mask&World.VIEW_ACTOR_GROUND)!=0,"Entering a legacy public venue resets upper-floor view and ground actor visibility.")
	old.queue_free();await process_frame

func _safe(value:Variant)->Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is PackedVector3Array:
		var out:Array=[]
		for point:Vector3 in value:out.append(_safe(point))
		return out
	if value is Dictionary:
		var out:Dictionary={}
		for key:Variant in value:out[key]=_safe(value[key])
		return out
	if value is Array:
		var out:Array=[]
		for item:Variant in value:out.append(_safe(item))
		return out
	return value

func _finish()->void:
	observations["checks"]=checks;observations["failures"]=failures
	var file:=FileAccess.open("user://build_world_levels.json",FileAccess.WRITE);file.store_string(JSON.stringify(_safe(observations),"  "));file.close()
	print("BUILD_WORLD_LEVELS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
