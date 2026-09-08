extends Node3D
class_name LifeWorld

signal object_clicked(info: Dictionary, screen_position: Vector2)
signal ground_clicked(world_position: Vector3)
signal placement_requested(kind: String, world_position: Vector3, angle: float)
signal construction_requested(data: Dictionary)

var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var house: Node3D
var furniture: Node3D
var walls: Array[Node3D] = []
var items: Array[Dictionary] = []
var actors: Dictionary = {}
var navigation = AStarGrid2D.new()
var camera_target = Vector3(0,0,0)
var camera_angle: float = .67
var camera_elevation: float = .83
var camera_distance: float = 23.0
var live_enabled: bool = false
var build_enabled: bool = false
var placement_kind: String = ""
var placement_angle: float = 0.0
var ghost: Node3D
var ghost_valid: bool = false
var ghost_position = Vector3.ZERO
var cutaway: bool = true
var grid: Node3D
var elapsed: float = 0.0
var rng = RandomNumberGenerator.new()
var material_cache: Dictionary = {}
var construction: LifeConstruction
var landscape_trees:Array[Node3D]=[]
var ceiling_beams:Array[MeshInstance3D]=[]
var _desk_boosters:Dictionary={}
var oven_presentations:Dictionary={}
var oven_food_views:Dictionary={}

func _ready() -> void:
	rng.seed = 91517
	camera = Camera3D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 17.5
	camera.far = 200
	camera.current = true
	var we = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("cddfd6")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e4ede4")
	environment.ambient_light_energy = .35
	environment.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
	environment.ssao_enabled = true
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 1.2
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-35,0)
	sun.light_color = Color("fff0d7")
	sun.light_energy = .8
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.5
	sun.directional_shadow_max_distance = 60
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	update_camera()

func material(hex: String, roughness: float = .8) -> StandardMaterial3D:
	if material_cache.has(hex): return material_cache[hex]
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = roughness
	material_cache[hex] = m
	return m

func box(parent: Node3D, at: Vector3, dimensions: Vector3, color: String) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	n.mesh = mesh
	n.material_override = material(color)
	n.position = at
	parent.add_child(n)
	return n

func sphere(parent: Node3D, at: Vector3, dimensions: Vector3, color: String) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radial_segments = 16
	mesh.rings = 8
	n.mesh = mesh
	n.material_override = material(color)
	n.position = at
	n.scale = dimensions
	parent.add_child(n)
	return n

func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: String) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	n.mesh = mesh
	n.material_override = material(color)
	n.position = at
	parent.add_child(n)
	return n

func create_home(layout: Array = []) -> void:
	if house: house.queue_free()
	for a in actors.values():
		if is_instance_valid(a): a.queue_free()
	actors.clear()
	landscape_trees.clear();ceiling_beams.clear()
	house = Node3D.new()
	house.name = "JuniperHouse"
	add_child(house)
	construction=LifeConstruction.new()
	house.add_child(construction)
	construction.initialize(self)
	furniture = Node3D.new()
	furniture.name = "Furniture"
	house.add_child(furniture)
	items.clear()
	walls.clear()
	box(house,Vector3(0,-.3,0),Vector3(120,.3,120),"b8cdaa")
	box(house,Vector3(0,-.17,0),Vector3(17,.15,17),"a8c191")
	box(house,Vector3(0,-.025,0),Vector3(12.35,.25,10.35),"d3c9b6")
	box(house,Vector3(0,.105,0),Vector3(12,.045,10),"cfa97e")
	# Individual floor boards, laid with staggered joints.
	for row in range(40):
		for col in range(7):
			var x: float = -5.99 + row*.3
			var z: float = -4.95 + col*1.66 + (row%2)*.83
			if z < 4.95:
				box(house,Vector3(x,.133,minf(z,4.7)),Vector3(.007,.003,minf(1.65,5-z)),"b98f65")
				box(house,Vector3(x+.15,.134,z),Vector3(.29,.003,.008),"b98f65")
	box(house,Vector3(3.5,.14,-3.05),Vector3(4.95,.02,3.87),"b7c7bd")
	for x in range(10):
		for z in range(8):
			box(house,Vector3(1.02+x*.5,.154,-4.97+z*.5),Vector3(.47,.006,.47),"cbd4ca" if (x+z)%2==0 else "becfc4")
	# Back wall, with inset windows on the kitchen and bath.
	wall(Vector3(0,1.4,-5.04),Vector3(12.2,2.6,.16),"eae7d7",false)
	wall(Vector3(-6.04,1.4,0),Vector3(.16,2.6,10.1),"8faf9f",false)
	wall(Vector3(6.04,.4,0),Vector3(.16,.6,10.1),"e6d8c5",true)
	wall(Vector3(-3.55,.4,5.04),Vector3(5.1,.6,.16),"e6d8c5",true)
	wall(Vector3(3.55,.4,5.04),Vector3(5.1,.6,.16),"e6d8c5",true)
	wall(Vector3(1,.47,-3.22),Vector3(.13,.72,3.6),"e4dfce",true)
	wall(Vector3(1,.47,2.7),Vector3(.13,.72,4.6),"e4dfce",true)
	wall(Vector3(1.9,.47,-1.15),Vector3(1.8,.72,.13),"e4dfce",true)
	wall(Vector3(5.0,.47,-1.15),Vector3(2.1,.72,.13),"e4dfce",true)
	for x in [-4.25,-1.25,3.3]: window_panel(Vector3(x,1.78,-4.945),false)
	for z in [-2.3,2.2]: window_panel(Vector3(-5.945,1.75,z),true)
	# Wall accents, skirting, door thresholds and entry.
	box(house,Vector3(0,.24,-4.94),Vector3(12,.18,.04),"fcf5e6").set_meta("wall_decoration",true)
	box(house,Vector3(-5.94,.24,0),Vector3(.04,.18,10),"fcf5e6").set_meta("wall_decoration",true)
	box(house,Vector3(0,.02,5.72),Vector3(2.4,.2,1.35),"c7bea9")
	box(house,Vector3(0,-.025,7.1),Vector3(1.75,.08,1.8),"dcd5be")
	box(house,Vector3(0,-.02,8.5),Vector3(75,.10,1.25),"e0d9c7")
	box(house,Vector3(0,-.07,11.0),Vector3(100,.12,3.7),"798781")
	for x in range(-30,31,5): box(house,Vector3(x,.003,11),Vector3(2,.009,.08),"e6ddbc")
	for x in [-7.55,7.55]:
		for z in [-6.8,-1.2,5.9]: tree(Vector3(x,-.10,z),rng.randf_range(.8,1.1) if z<0 else .55)
	for x in [-10.5,10.6,16,-17]:tree(Vector3(x,-.12,-8),rng.randf_range(1.0,1.6))
	for z in [-7.4,-6.8]:
		for x in range(-7,8):sphere(house,Vector3(x,.25,z),Vector3(1.0,.64,.80),"71945e")
	for x in [-6.85,6.85]:
		for z in range(-5,5):
			if z%2==0:sphere(house,Vector3(x,.16,z),Vector3(.68,.34,.65),"84a366").set_meta("garden_decoration",true)
	for x in [-3.5,3.5]:
		for i in range(12):
			var p=Vector3(x+rng.randf_range(-.9,.9),-.09,6.8+rng.randf_range(-.45,.45))
			flower_clump(p, rng, "d4868e" if i%2 else "f5e5ad")
	for x in [-19,20]: neighbor_home(Vector3(x,0,-1))
	# A simple open mailbox with a brass house number plate.
	box(house,Vector3(2,.52,7.8),Vector3(.10,1.1,.10),"ab7951")
	box(house,Vector3(2,1.06,7.8),Vector3(.45,.35,.33),"397e70")
	box(house,Vector3(2,1.07,7.98),Vector3(.26,.05,.008),"c8a562")
	grid = Node3D.new()
	house.add_child(grid)
	for i in range(-12,13):box(grid,Vector3(i*.5,.17,0),Vector3(.012,.005,10),"a6bca9")
	for i in range(-10,11):box(grid,Vector3(0,.17,i*.5),Vector3(12,.005,.012),"a6bca9")
	grid.visible = false
	for entry in layout:
		if entry.get("kind","")=="__construction":construction.restore(entry)
		else:add_item(entry,false)
	construction.refresh_decorations()
	rebuild_navigation()
	update_camera()

func wall(p: Vector3, dimensions: Vector3, color: String, adjustable: bool) -> void:
	construction.add_wall({"x":p.x,"z":p.z,"w":dimensions.x,"d":dimensions.z,"height":2.6,"color":color,"cut":adjustable})

func window_panel(p: Vector3, side: bool) -> void:
	var root=Node3D.new()
	root.name="Window"
	house.add_child(root)
	root.position=p
	root.set_meta("wall_decoration",true)
	root.set_meta("window_aperture",Rect2(-.878,-.692,1.756,1.384))
	root.set_meta("window_frame_bounds",Rect2(-1.09,-.825,2.18,1.655))
	if side:root.rotation_degrees.y=90
	# A single double-sided pane avoids the stacked alpha faces of a glass box.
	# Give glass its own material so opaque furniture with this tint stays opaque.
	var glass=MeshInstance3D.new()
	glass.name="Glass"
	var pane=QuadMesh.new();pane.size=Vector2(1.756,1.384)
	glass.mesh=pane;glass.position.z=-.095
	var glass_material=StandardMaterial3D.new()
	glass_material.albedo_color=Color(.72,.87,.87,.13)
	glass_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	glass_material.roughness=.14
	glass_material.metallic_specular=.55
	glass.material_override=glass_material
	glass.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	# Deep reveals finish both sides of the real opening through the wall.
	for x in [-.91,.91]:box(root,Vector3(x,0,-.095),Vector3(.065,1.53,.24),"fff8e6")
	for y in [-.72,.72]:box(root,Vector3(0,y,-.095),Vector3(1.9,.055,.24),"fff8e6")
	box(root,Vector3(0,0,-.095),Vector3(.065,1.44,.06),"fff8e6")
	box(root,Vector3(0,0,-.095),Vector3(1.82,.055,.06),"fff8e6")
	box(root,Vector3(0,-.78,.01),Vector3(2,.09,.43),"fff8e6")
	for x in [-1.0,1.0]:box(root,Vector3(x,.03,.12),Vector3(.18,1.6,.09),"d9cbb2")

func tree(p: Vector3, s: float) -> void:
	var tree_root=Node3D.new();house.add_child(tree_root)
	tree_root.position=p
	landscape_trees.append(tree_root)
	cylinder(tree_root,Vector3(0,1.45*s,0),.12*s,2.9*s,"8b7452")
	for i in range(7):
		var a:float=i*2.4
		var offset=Vector3(sin(a)*.64,2.65+(i%3)*.4,cos(a)*.64)*s
		sphere(tree_root,offset,Vector3(1.75,1.8,1.65)*s,"73976a" if i%2 else "8eaa78")

func neighbor_home(p: Vector3) -> void:
	box(house,p+Vector3(0,1.6,0),Vector3(7,3.2,7),"d7dbca")
	box(house,p+Vector3(0,3.28,0),Vector3(7.7,.3,7.7),"6b8578")
	for x in [-2,1.8]:
		box(house,p+Vector3(x,1.8,3.51),Vector3(1.2,1.6,.05),"8aabb0")
	box(house,p+Vector3(0,1.1,3.54),Vector3(1,2.2,.08),"ab8963")

func add_item(entry: Dictionary, rebuild: bool = true) -> void:
	var kind: String=str(entry.get("kind","plant"))
	if not LifeCatalog.ITEMS.has(kind):return
	var data:Dictionary=LifeCatalog.get_item(kind)
	var path="res://assets/models/%s.glb" % kind
	if not ResourceLoader.exists(path):return
	var node=Node3D.new()
	node.name=str(entry.get("id","item_%d" % Time.get_ticks_usec()))
	furniture.add_child(node)
	var model:Node3D=load(path).instantiate()
	node.add_child(model)
	node.position=Vector3(float(entry.get("x",0)),.16,float(entry.get("z",0)))
	node.rotation_degrees.y=float(entry.get("rotation",0))
	var info:Dictionary=entry.duplicate(true)
	info["node"]=node
	info["label"]=data.label
	info["size"]=data.size
	var body=StaticBody3D.new()
	body.collision_layer=2
	node.add_child(body)
	var shape=CollisionShape3D.new()
	var bounds=BoxShape3D.new()
	bounds.size=Vector3(data.size.x,data.height,data.size.y)
	shape.shape=bounds
	shape.position.y=float(data.height)/2
	body.add_child(shape)
	body.set_meta("item_id",info.id)
	items.append(info)
	if rebuild:rebuild_navigation()

func remove_item(id: String) -> Dictionary:
	for i in range(items.size()):
		if items[i].id==id:
			var data=items[i]
			data.node.queue_free()
			items.remove_at(i)
			rebuild_navigation()
			return data
	return {}

func serialize_items() -> Array:
	var out:Array=[]
	for item in items:
		if bool(item.get("transient_food",false)):continue
		out.append({"id":item.id,"kind":item.kind,"x":item.node.position.x,"z":item.node.position.z,"rotation":item.node.rotation_degrees.y})
	if construction:out.append(construction.snapshot())
	return out

func rebuild_navigation() -> void:
	navigation.region=Rect2i(-36,-28,73,65)
	navigation.cell_size=Vector2(.25,.25)
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(-36,37):
		for z in range(-28,37):
			var p=Vector2(x*.25,z*.25)
			var solid:bool = construction.point_blocked(p)
			for item in items:
				if item.kind in ["rug","painting","meal","plate"]:continue
				var local:Vector3=item.node.to_local(Vector3(p.x,.16,p.y))
				var extent:Vector2=item.size*.5+Vector2(.16,.16)
				if absf(local.x)<extent.x and absf(local.z)<extent.y:solid=true;break
			navigation.set_point_solid(Vector2i(x,z),solid)

func nearest_free(p:Vector3) -> Vector2i:
	var cell=Vector2i(roundi(p.x*4),roundi(p.z*4))
	cell.x=clampi(cell.x,-36,36)
	cell.y=clampi(cell.y,-28,36)
	if not navigation.is_point_solid(cell):return cell
	for radius in range(1,14):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				if absi(x)!=radius and absi(z)!=radius:continue
				var c=cell+Vector2i(x,z)
				if navigation.region.has_point(c) and not navigation.is_point_solid(c):return c
	return cell

func path_to(from:Vector3,to:Vector3) -> PackedVector3Array:
	var points:PackedVector3Array=[]
	var cells=navigation.get_id_path(nearest_free(from),nearest_free(to))
	for c in cells:points.append(Vector3(c.x*.25,.16,c.y*.25))
	return points

func approach(item:Dictionary) -> Vector3:
	var n:Node3D=item.node
	var p:Vector3=n.to_global(Vector3(0,0,item.size.y*.5+.55))
	var c=nearest_free(p)
	return Vector3(c.x*.25,.16,c.y*.25)

func lot_exit_position(member_index:int=0) -> Vector3:
	# The front sidewalk belongs to the navigable lot, beyond the front door.
	var cell:Vector2i=nearest_free(Vector3((member_index-3.5)*.75,.16,8.5))
	return Vector3(cell.x*.25,.16,cell.y*.25)

func lot_return_position(member_index:int=0) -> Vector3:
	var cell:Vector2i=nearest_free(Vector3((member_index%4-1.5)*.75,.16,6.5+(member_index/4)*.75))
	return Vector3(cell.x*.25,.16,cell.y*.25)

func set_actor_away(id:String,away:bool,unavailable:bool) -> bool:
	var actor:LifeActor=actors.get(id)
	if not is_instance_valid(actor):return false
	var changed:bool=bool(actor.get_meta("away",false))!=unavailable
	actor.set_meta("away",unavailable)
	actor.visible=not away
	for child:Node in actor.get_children():
		if child is CollisionObject3D:child.collision_layer=0 if away else 2
	if away:actor.clear_speech()
	return changed

func simulation_targets() -> Array:
	var a:Array=[{"id":"lot_exit","kind":"lot_exit","position":lot_exit_position()}]
	for item in items:a.append({"id":item.id,"kind":item.kind,"position":approach(item)})
	for id in actors:
		if bool(actors[id].get_meta("away",false)):continue
		a.append({"id":id,"kind":"neighbor","position":actors[id].position+Vector3(0,0,.8)})
	return a

func set_build(enabled:bool) -> void:
	build_enabled=enabled
	if grid:grid.visible=enabled
	if not enabled:clear_placement()

func begin_placement(kind:String) -> void:
	if construction:construction.cancel()
	clear_placement()
	placement_kind=kind
	placement_angle=0
	ghost=load("res://assets/models/%s.glb" % kind).instantiate()
	add_child(ghost)
	for n in ghost.find_children("*","MeshInstance3D",true,false):
		var m=StandardMaterial3D.new()
		m.albedo_color=Color(.38,.8,.63,.48)
		m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		n.material_override=m

func clear_placement() -> void:
	placement_kind=""
	if is_instance_valid(ghost):ghost.queue_free()
	ghost=null
	if construction:construction.cancel()

func begin_construction(tool:String) -> void:
	clear_placement()
	construction.begin(tool)

func can_place(kind:String,p:Vector3,angle:float) -> bool:
	var size:Vector2=LifeCatalog.ITEMS[kind].size
	if int(roundf(angle/90))%2:size=Vector2(size.y,size.x)
	var rect=Rect2(Vector2(p.x,p.z)-size/2,size)
	for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
		if not construction.floor_contains(corner):return false
	if kind in ["rug","painting"]:return true
	# Interior walls and doorways stay usable.
	if construction.rect_blocked(rect):return false
	for item in items:
		if item.kind in ["rug","painting","meal","plate"]:continue
		var s:Vector2=item.size
		if int(roundf(item.node.rotation_degrees.y/90))%2:s=Vector2(s.y,s.x)
		var other=Rect2(Vector2(item.node.position.x,item.node.position.z)-s/2,s)
		if rect.grow(.05).intersects(other):return false
	return true

func floor_point(screen:Vector2) -> Vector3:
	var origin=camera.project_ray_origin(screen)
	var direction=camera.project_ray_normal(screen)
	var t=(.16-origin.y)/direction.y
	return origin+direction*t

func pick(screen:Vector2) -> void:
	if not live_enabled:return
	if build_enabled and construction and not construction.tool.is_empty():
		var proposal:Dictionary=construction.click(floor_point(screen))
		if not proposal.is_empty():construction_requested.emit(proposal)
		return
	if build_enabled and placement_kind!="":
		if ghost_valid:placement_requested.emit(placement_kind,ghost_position,placement_angle)
		return
	var origin=camera.project_ray_origin(screen)
	var ray=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*150,2)
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var id:String=str(hit.collider.get_meta("item_id",""))
		for item in items:
			if item.id==id:object_clicked.emit(item,screen);return
		if actors.has(id) and not bool(actors[id].get_meta("away",false)):object_clicked.emit({"id":id,"kind":"neighbor","label":actors[id].get_meta("display_name"),"node":actors[id],"size":Vector2(.6,.6)},screen);return
	ground_clicked.emit(floor_point(screen))

func update_camera() -> void:
	if not camera:return
	camera.position=camera_target+Vector3(sin(camera_angle)*cos(camera_elevation),sin(camera_elevation),cos(camera_angle)*cos(camera_elevation))*camera_distance
	camera.look_at(camera_target,Vector3.UP)
	var facing:Vector3=Vector3(sin(camera_angle),0,cos(camera_angle))
	for tree_root:Node3D in landscape_trees:
		if not is_instance_valid(tree_root):continue
		var toward_camera:bool=tree_root.position.dot(facing)>1.0 and absf(tree_root.position.x)<9
		for mesh:GeometryInstance3D in tree_root.get_children():mesh.transparency=.84 if toward_camera and live_enabled else 0.0

func set_cutaway(value:bool) -> void:
	cutaway=value
	if construction:construction.update_cutaway(value)
	for beam:MeshInstance3D in ceiling_beams:
		if is_instance_valid(beam):beam.visible=not value

func _process(delta:float) -> void:
	elapsed+=delta
	if not live_enabled:return
	if build_enabled and construction and not construction.tool.is_empty():construction.update_preview(floor_point(get_viewport().get_mouse_position()))
	if build_enabled and is_instance_valid(ghost):
		var p=floor_point(get_viewport().get_mouse_position())
		p.x=snappedf(p.x,.25);p.z=snappedf(p.z,.25)
		ghost.position=p
		ghost.rotation_degrees.y=placement_angle
		ghost_position=p
		ghost_valid=can_place(placement_kind,p,placement_angle)
		for n in ghost.find_children("*","MeshInstance3D",true,false):n.material_override.albedo_color=Color(.4,.85,.6,.48) if ghost_valid else Color(.9,.3,.25,.48)

func daylight(minutes:float) -> void:
	var brightness:float=clampf(sin((minutes-360)/1440.0*TAU)*.5+.5,.16,1)
	sun.light_energy=.12+brightness*.68
	sun.light_color=Color("b1c5dc").lerp(Color("fff0d7"),brightness)
	environment.ambient_light_energy=.16+brightness*.20

func closest_item(kind:String,from:Vector3,max_distance:float=100.0) -> Dictionary:
	var found:Dictionary={}
	var nearest:float=max_distance
	for item:Dictionary in items:
		if str(item.kind)!=kind:continue
		var distance:float=item.node.position.distance_to(from)
		if distance<nearest:nearest=distance;found=item
	return found

func begin_activity_frame(paused:bool=false) -> void:
	if paused:return
	for id:int in _desk_boosters.keys():
		if not is_instance_valid(_desk_boosters[id]):_desk_boosters.erase(id)
		else:_desk_boosters[id].visible=false

func _show_desk_booster(chair:Node3D) -> void:
	var id:int=chair.get_instance_id()
	if not _desk_boosters.has(id) or not is_instance_valid(_desk_boosters[id]):
		var scene:PackedScene=load("res://assets/models/desk_booster.glb")
		var booster:Node3D=scene.instantiate()
		booster.name="LifeletDeskBooster"
		chair.add_child(booster)
		booster.position=Vector3(0,.52,.02)
		_desk_boosters[id]=booster
	_desk_boosters[id].visible=true

func _desk_surface(node:Node3D) -> Dictionary:
	return {"hand_center":node.to_global(Vector3(0,.915,.105)),"hand_spread":.105,
		"desk_surface_y":node.to_global(Vector3(0,.87,0)).y,
		"desk_front_edge":node.to_global(Vector3(0,.87,.385)),
		"desk_forward":-node.global_basis.z.normalized()}

func activity_resource_ids(item:Dictionary) -> Array[String]:
	var resources:Array[String]=[str(item.id)]
	if str(item.kind)=="desk":
		var chair:Dictionary=closest_item("chair",item.node.to_global(Vector3(0,0,.88)),1.25)
		if not chair.is_empty():resources.append(str(chair.id))
	return resources

func supported_homework_plan(item:Dictionary,learner_from:Vector3,helper_from:Vector3) -> Dictionary:
	if str(item.get("kind","")) not in ["desk","computer"]:
		return {"ok":false,"error":"Choose a desk for homework together."}
	var node:Node3D=item.node
	var learner_destination:Vector3=approach(item)
	if path_to(learner_from,learner_destination).is_empty():
		return {"ok":false,"error":"The learner cannot reach this desk."}
	var seat:Dictionary=closest_item("chair",node.to_global(Vector3(0,0,.88)),1.25)
	if seat.is_empty():return {"ok":false,"error":"Place a chair at the desk before doing homework together."}
	var options:Array[Vector3]=[]
	for side:float in [-1.0,1.0]:
		for forward:float in [.65,.95,1.2]:
			var desired:Vector3=node.to_global(Vector3(side*1.2,0,forward))
			var cell:Vector2i=Vector2i(roundi(desired.x*4),roundi(desired.z*4))
			if not navigation.is_in_boundsv(cell) or navigation.is_point_solid(cell):continue
			var at:Vector3=Vector3(cell.x*.25,.16,cell.y*.25)
			if not _clear_coaching_space(at) or at.distance_to(seat.node.position)<.85:continue
			if path_to(helper_from,at).is_empty():continue
			options.append(at)
	if options.is_empty():
		return {"ok":false,"error":"Leave clear floor space beside the desk for an adult to help."}
	options.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.distance_squared_to(helper_from)<b.distance_squared_to(helper_from))
	return {"ok":true,"learner_position":learner_destination,"helper_position":options[0]}

func _clear_coaching_space(at:Vector3) -> bool:
	# Check the whole standing footprint, not a distant nearest-free fallback.
	for offset:Vector2 in [Vector2.ZERO,Vector2(.29,0),Vector2(-.29,0),Vector2(0,.29),Vector2(0,-.29),Vector2(.21,.21),Vector2(-.21,.21),Vector2(.21,-.21),Vector2(-.21,-.21)]:
		if construction.point_blocked(Vector2(at.x,at.z)+offset):return false
	for other:Dictionary in items:
		if str(other.kind) in ["rug","painting"]:continue
		var local:Vector3=other.node.to_local(at)
		var extent:Vector2=other.size*.5+Vector2(.29,.29)
		if absf(local.x)<extent.x and absf(local.z)<extent.y:return false
	return true

func activity_anchor(item:Dictionary,action_id:String,landmarks:Dictionary={}) -> Dictionary:
	var node:Node3D=item.node
	var local:Vector3=Vector3(0,0,float(item.size.y)*.5+.36)
	var yaw:float=node.rotation.y+PI
	var kind:String="standing"
	if str(item.kind)=="stove" and action_id=="cook" and str(landmarks.get("recipe",""))=="harvest_bake":
		var at:Vector3=landmarks.get("cooking_position",oven_approach(item))
		at.y=node.global_position.y
		return {"position":at,"yaw":yaw,"kind":"standing","oven":node}
	match str(item.kind):
		"fridge":
			# Turn toward the room to present the cake at the reached position.
			# Holding it toward the appliance can push the plate into its door.
			if action_id=="birthday":yaw=node.rotation.y
		"bench":
			local=Vector3(0,.522,.05);yaw=node.rotation.y;kind="seat"
		"sofa":
			local=Vector3(0,.66,.08);yaw=node.rotation.y;kind="seat"
		"chair":
			local=Vector3(0,.52,.02);yaw=node.rotation.y;kind="seat"
		"toilet":
			local=Vector3(0,.615,.12);yaw=node.rotation.y;kind="seat"
		"bed":
			local=Vector3(-.43,.80,.015);yaw=node.rotation.y;kind="bed"
		"shower":
			local=Vector3(0,.166,.01);yaw=node.rotation.y+PI
		"desk":
			var chair:Dictionary=closest_item("chair",node.to_global(Vector3(0,0,.88)),1.25)
			if not chair.is_empty():
				var seat:Vector3=chair.node.to_global(Vector3(0,.52,.02))
				var keyboard:Vector3=node.to_global(Vector3(0,.915,.105))
				if str(landmarks.get("age_stage",""))=="child":
					# A visible booster and a forward seat position put short arms
					# within reach. Keep support inside the actual cushion footprint.
					var forward:Vector3=Vector3(keyboard.x-seat.x,0,keyboard.z-seat.z).normalized()
					var child_seat:Vector3=chair.node.to_local(seat+forward*.23)
					child_seat.x=clampf(child_seat.x,-.24,.24)
					child_seat.z=clampf(child_seat.z,-.25,.26)
					child_seat.y+=.18
					_show_desk_booster(chair.node)
					seat=chair.node.to_global(child_seat)
				var seated:Dictionary={"position":seat,"yaw":node.rotation.y+PI,"kind":"seat"}
				seated.merge(_desk_surface(node))
				return seated
			local=Vector3(0,0,.75)
	var anchor: Dictionary={"position":node.to_global(local),"yaw":yaw,"kind":kind}
	if str(item.kind)=="desk":
		anchor.merge(_desk_surface(node))
	return anchor

func oven_approach(item:Dictionary)->Vector3:
	var at:Vector3=item.node.to_global(Vector3(0,0,1.0))
	return Vector3(roundf(at.x*4)*.25,.16,roundf(at.z*4)*.25)

func update_oven_presentations(states:Dictionary) -> void:
	# These views are presentation only: never world items, servings, pickable
	# food or independent jobs. Their sole owner is a current paid cook action.
	oven_presentations=states.duplicate(true)
	var visible_ids:Dictionary={}
	for appliance:Dictionary in items:
		if str(appliance.kind)!="stove":continue
		var id:String=str(appliance.id)
		var state:Dictionary=states.get(id,{})
		LifeOvenSequence.apply_door(appliance.node,float(state.get("progress",0.0)))
		var rack:Node3D=appliance.node.find_child("OvenRack",true,false)
		if not bool(state.get("inside",false)) or not is_instance_valid(rack):continue
		visible_ids[id]=true
		var view:Node3D=oven_food_views.get(id) if is_instance_valid(oven_food_views.get(id)) else null
		if is_instance_valid(view) and view.get_parent()!=appliance.node:
			view.hide();view.queue_free();view=null
		if not is_instance_valid(view):
			view=load(LifeMeals.model_path("harvest_bake")).instantiate()
			view.name="OvenPreparation";appliance.node.add_child(view);oven_food_views[id]=view
		view.global_transform=Transform3D(appliance.node.global_basis*Basis(Vector3.UP,PI),rack.global_position)
		view.show()
	for id:String in oven_food_views.keys():
		if not visible_ids.has(id):
			var view:Node3D=oven_food_views[id] if is_instance_valid(oven_food_views[id]) else null
			if is_instance_valid(view):view.hide();view.queue_free()
			oven_food_views.erase(id)

func create_public_venue(place:String,layout:Array) -> void:
	if house:house.queue_free()
	actors.clear();items.clear();walls.clear();landscape_trees.clear();ceiling_beams.clear()
	house=Node3D.new();house.name="Community_"+place;add_child(house)
	construction=LifeConstruction.new();house.add_child(construction);construction.initialize(self)
	furniture=Node3D.new();furniture.name="Furniture";house.add_child(furniture)
	box(house,Vector3(0,-.3,0),Vector3(120,.3,120),"b8cdaa")
	box(house,Vector3(0,-.025,0),Vector3(14,.25,12),"d3c9b6")
	if place=="park":
		box(house,Vector3(0,.105,0),Vector3(14,.045,12),"9bb683")
		box(house,Vector3(0,.137,0),Vector3(2.5,.018,12),"ded7c2")
		box(house,Vector3(0,.138,0),Vector3(14,.018,1.5),"ded7c2")
		for x in [-5.8,5.8]:
			for z in [-4.5,3.8]:tree(Vector3(x,.1,z),.75)
		for x in range(-6,7):
			for z in [-5.5,5.5]:
				sphere(house,Vector3(x,.4,z),Vector3(1.1,.65,.8),"74975f")
		for i in range(32):
			var a:float=float(i)*2.399
			var p:Vector3=Vector3(sin(a)*(2.0+float(i%3)*.3),.26,-3.7+cos(a)*.55)
			sphere(house,p,Vector3(.10,.17,.10),["e7c596","d39b87","f1ddaa"][i%3])
		# Open pergola frames the garden; posts stay outside the walkable paths.
		for x in [-1.6,1.6]:
			for z in [-5.1,-3.4]:box(house,Vector3(x,1.6,z),Vector3(.11,3,.11),"b79468")
		for z in [-5.2,-4.8,-4.4,-4.0,-3.3]:box(house,Vector3(0,3.12,z),Vector3(3.7,.12,.10),"b79468")
	else:
		var floor:String="cbb998" if place=="library" else "c4beb0"
		box(house,Vector3(0,.105,0),Vector3(12,.045,10),floor)
		wall(Vector3(0,1.4,-5.04),Vector3(12.2,2.6,.16),"e4e3d3" if place=="library" else "d5b7a1",false)
		wall(Vector3(-6.04,1.4,0),Vector3(.16,2.6,10.1),"8fa6a2" if place=="library" else "ece7d9",false)
		wall(Vector3(6.04,.4,0),Vector3(.16,.6,10.1),"e6d8c5",true)
		for z in [-2.8,.8,3.3]:window_panel(Vector3(-5.945,1.75,z),true)
		for x in [-4.3,-1.4,1.5,4.4]:
			var beam=box(house,Vector3(x,2.65,0),Vector3(.1,.18,10),"ae9169")
			beam.visible=not cutaway
			ceiling_beams.append(beam)
		if place=="library":
			for x in range(-12,13):box(house,Vector3(x*.5,.135,0),Vector3(.007,.004,10),"b39e80")
		else:
			for x in range(-6,7):
				for z in range(-5,6):box(house,Vector3(x,.134,z),Vector3(.98,.004,.98),"c9c3b7" if (x+z)%2 else "d4ccbc")
		for x in [-7.4,7.4]:
			for z in [-4,3.7]:tree(Vector3(x,-.1,z),.75)
	for x in [-11,11,16,-17]:tree(Vector3(x,-.1,-8),1.25)
	box(house,Vector3(0,-.02,7.1),Vector3(3,.1,2.5),"dcd5be")
	box(house,Vector3(0,-.02,8.5),Vector3(75,.1,1.25),"e0d9c7")
	box(house,Vector3(0,-.07,11),Vector3(100,.12,3.7),"798781")
	grid=Node3D.new();house.add_child(grid);grid.visible=false
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))=="__construction":construction.restore(entry)
		else:add_item(entry,false)
	construction.refresh_decorations();rebuild_navigation();update_camera()

func flower_clump(at: Vector3, rng: RandomNumberGenerator, petal_color: String) -> void:
	# A single draw per clump; construction can hide the whole plant under a floor.
	var plant := MultiMeshInstance3D.new()
	plant.position = at
	plant.set_meta("garden_decoration", true)
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8; mesh.rings = 4
	mesh.radius = .5; mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = .85
	mesh.material = mat
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for stalk: int in range(3):
		var center := Vector3((stalk - 1) * .075, 0, rng.randf_range(-.035, .035))
		var height: float = rng.randf_range(.20, .30)
		transforms.append(Transform3D(Basis.from_scale(Vector3(.012, height, .012)), center + Vector3(0, height / 2, 0)))
		colors.append(Color("537942"))
		for side: int in [-1, 1]:
			var basis := (Basis(Vector3.FORWARD, float(side) * .55) * Basis.from_scale(Vector3(.085, .025, .040)))
			transforms.append(Transform3D(basis, center + Vector3(side * .027, height * .44, 0)))
			colors.append(Color("719850"))
		for petal: int in range(5):
			var angle: float = TAU * petal / 5
			var basis := (Basis(Vector3.UP, -angle) * Basis.from_scale(Vector3(.048, .018, .030)))
			transforms.append(Transform3D(basis, center + Vector3(cos(angle) * .027, height, sin(angle) * .027)))
			colors.append(Color(petal_color))
		transforms.append(Transform3D(Basis.from_scale(Vector3(.028, .022, .028)), center + Vector3(0, height + .006, 0)))
		colors.append(Color("bb873d"))
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for i: int in range(transforms.size()):
		batch.set_instance_transform(i, transforms[i]); batch.set_instance_color(i, colors[i])
	plant.multimesh = batch
	house.add_child(plant)
