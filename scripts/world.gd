extends Node3D
class_name LifeWorld
const Building=preload("res://scripts/building_state.gd")
const RoofRules=preload("res://scripts/roof_rules.gd")
const LotNavigation=preload("res://scripts/lot_navigation.gd")
const VIEW_ENVIRONMENT:int=1
const VIEW_GROUND:int=2
const VIEW_UPPER:int=4
const VIEW_STAIRS:int=8
const VIEW_ACTOR_GROUND:int=16
const VIEW_ACTOR_UPPER:int=32
const PICK_GROUND:int=2
const PICK_UPPER:int=4

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
var _furnishing_volume_cache:Dictionary={}
var actors: Dictionary = {}
var _target_approaches:Dictionary={}
var _target_navigation_id:int=0
var _target_navigation_generation:int=-1
var navigation = AStarGrid2D.new()
var lot_navigation=LotNavigation.new()
var view_level:int=0
var starter_floor_nodes:Array[Node3D]=[]
var last_layout_error:String=""
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
	last_layout_error=validate_home_layout(layout)
	if not last_layout_error.is_empty():return
	if house: house.queue_free()
	for a in actors.values():
		if is_instance_valid(a): a.queue_free()
	actors.clear()
	landscape_trees.clear();ceiling_beams.clear()
	starter_floor_nodes.clear();view_level=0
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
	var surface_start:int=house.get_child_count()
	box(house,Vector3(0,-.025,0),Vector3(12.35,.25,10.35),"d3c9b6")
	box(house,Vector3(0,.105,0),Vector3(12,.045,10),"cfa97e").set_meta("starter_wood_finish",true)
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
	for index:int in range(surface_start,house.get_child_count()):
		var node:Node3D=house.get_child(index)
		node.set_meta("starter_surface",true);starter_floor_nodes.append(node);assign_structure_layer(node,0)
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
	var back_skirting:MeshInstance3D=box(house,Vector3(0,.24,-4.94),Vector3(12,.18,.04),"fcf5e6")
	back_skirting.set_meta("wall_decoration",true);back_skirting.set_meta("wall_support_normal",Vector3.FORWARD)
	var side_skirting:MeshInstance3D=box(house,Vector3(-5.94,.24,0),Vector3(.04,.18,10),"fcf5e6")
	side_skirting.set_meta("wall_decoration",true);side_skirting.set_meta("wall_support_normal",Vector3.LEFT)
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
	# Structural state must exist before an upper furnishing is instantiated,
	# regardless of the serialized record ordering.
	for entry:Dictionary in layout:
		if entry.get("kind","")=="__construction":construction.restore(entry)
	for entry:Dictionary in layout:
		if entry.get("kind","")!="__construction":add_item(entry,false)
	construction.refresh_decorations()
	rebuild_navigation()
	set_view_level(0)
	update_camera()

func validate_home_layout(layout:Variant) -> String:
	if not layout is Array or layout.size()>1024:return "Invalid home layout."
	var canonical:Dictionary={};var ids:Dictionary={};var marker:bool=false
	for entry:Variant in layout:
		if not entry is Dictionary:return "Invalid layout record."
		if str(entry.get("kind",""))=="__construction":
			if marker:return "Two construction records describe one home."
			marker=true
			var result:Dictionary=Building.migrate(entry)
			if not bool(result.ok):return str(result.error)
			if entry.has("version"):canonical=result.state
			continue
		if not LifeCatalog.ITEMS.has(str(entry.get("kind",""))) or not Building.identifier(entry.get("id")) or ids.has(entry.id):return "Invalid or duplicate furnishing identity."
		ids[entry.id]=true
		if not Building.number(entry.get("level",0),0,1,true):return "Invalid furnishing level."
		for key:String in ["x","z","rotation"]:
			if not Building.number(entry.get(key,0),-10000,10000):return "Invalid furnishing transform."
		if not Building.LOT.encloses(furnishing_rect(entry)):return "A furnishing extends beyond the navigable lot."
	# Align ingress with the detached graph's obstacle bound so a valid layout
	# cannot replace the live scene and only then fail graph construction.
	if ids.size()>512:return "Too many furnishings for this lot."
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))=="__construction":continue
		var level:int=int(entry.get("level",0))
		if level==1 and canonical.is_empty():return "Upper furniture needs a validated two-level building."
		if canonical.is_empty():continue # Preserve old ground layout migration behavior.
		var area:Rect2=furnishing_rect(entry)
		if not Building.footprint_supported(canonical,level,area):return "A furnishing crosses unsupported floor or a stair opening."
		if not LifeCatalog.passable(str(entry.kind)) and Building.blocked_rect(canonical,level,area):return "A furnishing intersects a wall or stair run."
		if not canonical.roofs.is_empty():
			var roof_error:String=RoofRules.obstruction(canonical,furnishing_volume(entry))
			if not roof_error.is_empty():return roof_error
	return ""

func load_home(layout:Variant) -> Dictionary:
	var error:String=validate_home_layout(layout)
	if not error.is_empty():return {"ok":false,"error":error}
	create_home(layout)
	return {"ok":last_layout_error.is_empty(),"error":last_layout_error}

func furnishing_rect(entry:Dictionary) -> Rect2:
	var size:Vector2=LifeCatalog.ITEMS[str(entry.kind)].size
	var basis:=Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0))))
	var x_axis:Vector3=basis*Vector3(size.x*.5,0,0)
	var z_axis:Vector3=basis*Vector3(0,0,size.y*.5)
	var half:=Vector2(absf(x_axis.x)+absf(z_axis.x),absf(x_axis.z)+absf(z_axis.z))
	return Rect2(Vector2(float(entry.get("x",0)),float(entry.get("z",0)))-half,half*2)

func _gather_visual_bounds(node:Node,transform:Transform3D,vertices:Array[Vector3])->void:
	if node is Node3D:transform=transform*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		var box:AABB=node.mesh.get_aabb()
		for x:int in [0,1]:
			for y:int in [0,1]:
				for z:int in [0,1]:vertices.append(transform*(box.position+box.size*Vector3(x,y,z)))
	for child:Node in node.get_children():_gather_visual_bounds(child,transform,vertices)

func furnishing_volume(entry:Dictionary)->AABB:
	var kind:String=str(entry.kind)
	if not _furnishing_volume_cache.has(kind):
		var scene:Node3D=load("res://assets/models/%s.glb"%kind).instantiate();var vertices:Array[Vector3]=[]
		_gather_visual_bounds(scene,Transform3D.IDENTITY,vertices);scene.free()
		var data:Dictionary=LifeCatalog.ITEMS[kind]
		var box:=AABB(Vector3(-data.size.x*.5,0,-data.size.y*.5),Vector3(data.size.x,data.height,data.size.y))
		for point:Vector3 in vertices:box=box.expand(point)
		_furnishing_volume_cache[kind]=box
	var local:AABB=_furnishing_volume_cache[kind]
	var transform:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0)))),Vector3(float(entry.get("x",0)),Building.level_y(int(entry.get("level",0))),float(entry.get("z",0))))
	return transform*local

func set_starter_floor_visible(value:bool) -> void:
	for node:Node3D in starter_floor_nodes:
		if is_instance_valid(node):node.visible=value

func apply_starter_floor_finish(color:String) -> void:
	for node:Node3D in starter_floor_nodes:
		if is_instance_valid(node) and node is MeshInstance3D and node.get_meta("starter_wood_finish",false):
			node.material_override=material(color)

func _assign_layers(node:Node,mask:int) -> void:
	if node is VisualInstance3D:node.layers=mask
	for child:Node in node.get_children():_assign_layers(child,mask)

func assign_structure_layer(node:Node,level:int) -> void:
	_assign_layers(node,VIEW_GROUND if level==0 else VIEW_UPPER)

func assign_stair_layer(node:Node) -> void:_assign_layers(node,VIEW_STAIRS)

func item_level(item:Dictionary) -> int:
	if Building.number(item.get("level"),0,1,true):return int(item.level)
	if is_instance_valid(item.get("node")):return clampi(roundi((item.node.global_position.y-Building.GROUND_Y)/Building.RISE),0,1)
	return 0

func point_level(point:Vector3) -> int:
	if not point.is_finite():return -1
	for level:int in [0,1]:
		if absf(point.y-Building.level_y(level))<.025:return level
	return -1

func set_view_level(level:int) -> bool:
	if level not in [0,1] or (level==1 and (not is_instance_valid(construction) or construction.building_state.is_empty())):return false
	if level!=view_level:clear_placement()
	view_level=level
	if construction:construction.build_level=level
	if grid:grid.position.y=Building.RISE*level
	camera.cull_mask=VIEW_ENVIRONMENT|VIEW_GROUND|VIEW_STAIRS|(VIEW_ACTOR_GROUND if level==0 else VIEW_UPPER|VIEW_ACTOR_UPPER)
	camera_target.y=Building.RISE*level
	refresh_actor_layers();construction.set_roof_visibility(construction.roofs_visible);update_camera()
	return true

func refresh_actor_layers() -> void:
	# Runs every frame for every Lifelet, so only touch the scene when a body's
	# floor or presence changes, and keep each actor's pick bodies cached rather
	# than searching hundreds of model nodes per frame.
	for id:String in actors:
		var actor:Node3D=actors[id]
		if not is_instance_valid(actor):continue
		var level:int=point_level(actor.position)
		var away:bool=bool(actor.get_meta("away",false))
		var cache:Dictionary=actor.get_meta("layer_cache",{})
		var bodies:Array=cache.get("bodies",[])
		var bodies_valid:bool=not bodies.is_empty()
		for body in bodies:
			if not is_instance_valid(body):bodies_valid=false;break
		if not bodies_valid:
			bodies=actor.find_children("*","CollisionObject3D",true,false)
			cache={"bodies":bodies}
		if int(cache.get("level",-99))==level and bool(cache.get("away",not away))==away and bodies_valid and bool(cache.get("visuals_assigned",false)):continue
		var visual_mask:int=VIEW_ACTOR_GROUND|VIEW_ACTOR_UPPER if level<0 else (VIEW_ACTOR_GROUND if level==0 else VIEW_ACTOR_UPPER)
		_assign_layers(actor,visual_mask)
		for body:Node in bodies:
			body.collision_layer=0 if away else (PICK_GROUND|PICK_UPPER if level<0 else (PICK_GROUND if level==0 else PICK_UPPER))
		cache["level"]=level;cache["away"]=away;cache["visuals_assigned"]=true
		actor.set_meta("layer_cache",cache)

func wall(p: Vector3, dimensions: Vector3, color: String, adjustable: bool) -> void:
	construction.add_wall({"x":p.x,"z":p.z,"w":dimensions.x,"d":dimensions.z,"height":2.6,"color":color,"cut":adjustable})

func window_panel(p: Vector3, side: bool) -> void:
	var root=Node3D.new()
	root.name="Window"
	house.add_child(root)
	root.position=p
	root.set_meta("wall_decoration",true)
	root.set_meta("wall_support_normal",Vector3.FORWARD)
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
	assign_structure_layer(root,clampi(floori((p.y-Building.GROUND_Y)/Building.RISE),0,1))

func tree(p: Vector3, s: float) -> void:
	# Coordinate-only variation preserves the world's shared random stream.
	var key:int=(roundi(p.x*100.0)*73856093) ^ (roundi(p.z*100.0)*19349663)
	var variant:String="a" if posmod(key,5)<3 else "b"
	var tree_root:Node3D=load("res://assets/models/tree_field_maple_%s.glb"%variant).instantiate()
	house.add_child(tree_root)
	tree_root.position=p
	# The imported scene has two immediate meshes. Keep the same root transform
	# and immediate GeometryInstance3D contract used by camera transparency.
	var yaw:float=float(posmod(key,8))*PI/4.0
	for mesh:MeshInstance3D in tree_root.get_children():
		mesh.scale*=s
		mesh.rotation.y=yaw
		# Godot imports COLOR_0 but leaves its material contribution disabled.
		var tree_material:StandardMaterial3D=mesh.get_active_material(0)
		tree_material.vertex_color_use_as_albedo=true
	landscape_trees.append(tree_root)

func neighbor_home(p: Vector3) -> void:
	var cottage:bool=p.x<0
	var width:float=6.5 if cottage else 8.4
	var depth:float=7.8 if cottage else 5.9
	var height:float=3.3 if cottage else 2.8
	box(house,p+Vector3(0,height*.5,0),Vector3(width,height,depth),"aabfa7" if cottage else "bd9177")
	var roof:MeshInstance3D=box(house,p+Vector3(-width*.25,height+.48,0),Vector3(width*.56,.16,depth+.6),"627e72" if cottage else "797f7a")
	roof.rotation.z=.32
	roof=box(house,p+Vector3(width*.25,height+.48,0),Vector3(width*.56,.16,depth+.6),"627e72" if cottage else "797f7a");roof.rotation.z=-.32
	var door_x:float=0 if cottage else 2.45
	for x:float in ([-2.0,2.0] if cottage else [-2.9,-.6]):
		box(house,p+Vector3(x,1.8,depth*.5+.01),Vector3(1.2,1.4,.05),"698786")
		for edge:float in [-.64,.64]:box(house,p+Vector3(x+edge,1.8,depth*.5+.05),Vector3(.08,1.55,.07),"ede7d5")
	box(house,p+Vector3(door_x,1.1,depth*.5+.04),Vector3(1,2.2,.08),"b49167" if cottage else "68897c")
	box(house,p+Vector3(door_x,.04,depth*.5+.7),Vector3(3.0 if cottage else 1.6,.18,1.3),"bdb29a")
	if cottage:
		for side:float in [-1.4,1.4]:box(house,p+Vector3(side,1.3,depth*.5+1.2),Vector3(.10,2.6,.10),"ede7d5")
		box(house,p+Vector3(0,2.65,depth*.5+.7),Vector3(3.2,.16,1.65),"627e72")
	else:
		box(house,p+Vector3(-width*.5-.8,.05,0),Vector3(1.6,.2,depth+.4),"bdab91")

func add_item(entry: Dictionary, rebuild: bool = true) -> void:
	var kind: String=str(entry.get("kind","plant"))
	if not LifeCatalog.ITEMS.has(kind):return
	if not Building.number(entry.get("level",0),0,1,true):return
	var level:int=int(entry.get("level",0))
	if level==1 and (not is_instance_valid(construction) or construction.building_state.is_empty()):return
	var data:Dictionary=LifeCatalog.get_item(kind)
	var path="res://assets/models/%s.glb" % kind
	if not ResourceLoader.exists(path):return
	var node=Node3D.new()
	node.name=str(entry.get("id","item_%d" % Time.get_ticks_usec()))
	furniture.add_child(node)
	var model:Node3D=load(path).instantiate()
	node.add_child(model)
	node.position=Vector3(float(entry.get("x",0)),Building.level_y(level),float(entry.get("z",0)))
	node.rotation_degrees.y=float(entry.get("rotation",0))
	var info:Dictionary=entry.duplicate(true)
	info["node"]=node
	info["label"]=data.label
	info["size"]=data.size
	info["level"]=level
	assign_structure_layer(node,level)
	var body=StaticBody3D.new()
	body.collision_layer=PICK_GROUND if level==0 else PICK_UPPER
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
		if bool(item.get("transient_food",false)) or bool(item.get("transient_puddle",false)):continue
		var entry:Dictionary={"id":item.id,"kind":item.kind,"x":item.node.position.x,"z":item.node.position.z,"rotation":item.node.rotation_degrees.y}
		if item_level(item)!=0:entry["level"]=item_level(item)
		out.append(entry)
	if construction:out.append(construction.snapshot())
	return out

func rebuild_navigation() -> void:
	# Even a rejected rebuild can replace the compatibility grid.
	_target_approaches.clear()
	# Compatibility grid stays ground-only until main/food callers are migrated.
	navigation.region=Rect2i(-36,-28,73,65)
	navigation.cell_size=Vector2(.25,.25)
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for x in range(-36,37):
		for z in range(-28,37):
			var p=Vector2(x*.25,z*.25)
			var solid:bool = construction.point_blocked(p)
			for item in items:
				if item_level(item)!=0:continue
				if item.kind in ["meal","plate","puddle"] or LifeCatalog.passable(str(item.kind)):continue
				var local:Vector3=item.node.to_local(Vector3(p.x,.16,p.y))
				var extent:Vector2=item.size*.5+Vector2(.16,.16)
				if absf(local.x)<extent.x and absf(local.z)<extent.y:solid=true;break
			navigation.set_point_solid(Vector2i(x,z),solid)
	var result:Dictionary=construction.validated_state()
	if not bool(result.ok):last_layout_error=str(result.error);return
	var obstacles:Array=[]
	for item:Dictionary in items:
		if str(item.kind) in ["meal","plate","puddle"] or LifeCatalog.passable(str(item.kind)):continue
		var source:Dictionary={"kind":str(item.kind),"x":item.node.position.x,"z":item.node.position.z,"rotation":item.node.rotation_degrees.y}
		var area:Rect2=furnishing_rect(source)
		obstacles.append({"id":str(item.id),"level":item_level(item),"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y})
	var built:Dictionary=lot_navigation.rebuild(result.state,obstacles)
	if not bool(built.ok):last_layout_error=str(built.error)

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
	if not construction.building_state.is_empty():
		var result:Dictionary=route_to(from,to)
		return result.points if bool(result.ok) else PackedVector3Array()
	var points:PackedVector3Array=[]
	var cells=navigation.get_id_path(nearest_free(from),nearest_free(to))
	for c in cells:points.append(Vector3(c.x*.25,.16,c.y*.25))
	return points

func route_to(from:Vector3,to:Vector3) -> Dictionary:
	var from_level:int=point_level(from);var to_level:int=point_level(to)
	if from_level<0 or to_level<0:return {"ok":false,"error":"A floor route needs explicit supported start and destination levels."}
	return lot_navigation.route(LotNavigation.floor_location(from_level,from),LotNavigation.floor_location(to_level,to))

func nearest_clear_point(point:Vector3,level:int,radius:int=13) -> Vector3:
	if level not in [0,1]:return Vector3.INF
	var origin:=Vector2i(roundi(point.x*4),roundi(point.z*4))
	var direct:=Vector3(origin.x*.25,Building.level_y(level),origin.y*.25)
	if lot_navigation.point_clear(level,direct):return direct
	var options:Array[Vector3]=[]
	for x:int in range(-radius,radius+1):
		for z:int in range(-radius,radius+1):
			var at:=Vector3((origin.x+x)*.25,Building.level_y(level),(origin.y+z)*.25)
			if lot_navigation.point_clear(level,at):options.append(at)
	options.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.distance_squared_to(point)<b.distance_squared_to(point))
	return Vector3.INF if options.is_empty() else options[0]

func approach(item:Dictionary) -> Vector3:
	var n:Node3D=item.node
	if bool(item.get("transient_puddle",false)):
		# The wet footprint may shrink at an edge; the cleaner still needs a
		# full-size supported standing place within the mop's physical reach.
		var level:int=item_level(item)
		for offset:Vector3 in [Vector3(0,0,.8),Vector3(.8,0,0),Vector3(-.8,0,0),Vector3(0,0,-.8)]:
			var wanted:Vector3=n.global_position+offset
			var at:Vector3=nearest_clear_point(wanted,level) if not construction.building_state.is_empty() else Vector3(nearest_free(wanted).x*.25,Building.level_y(level),nearest_free(wanted).y*.25)
			if at.is_finite() and Vector2(at.x-wanted.x,at.z-wanted.z).length()<.24:return at
		return Vector3.INF
	var p:Vector3=n.to_global(Vector3(0,0,item.size.y*.5+.55))
	if not construction.building_state.is_empty():return nearest_clear_point(p,item_level(item))
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
		if child is CollisionObject3D:child.collision_layer=0 if away else (PICK_UPPER if point_level(actor.position)==1 else PICK_GROUND)
	if away:actor.clear_speech()
	return changed

func _simulation_approach(item:Dictionary) -> Vector3:
	var node:Node3D=item.node
	var identity:int=node.get_instance_id()
	# These are every input read by approach(); changing a moving dish, puddle,
	# furnishing or parent transform therefore computes a fresh exact result.
	var signature:Array=[node.global_transform,item.size,item_level(item),str(item.kind),bool(item.get("transient_food",false)),bool(item.get("transient_puddle",false)),construction.building_state.is_empty()]
	var cached:Dictionary=_target_approaches.get(identity,{})
	if not cached.is_empty() and cached.signature==signature:return cached.position
	var at:Vector3=approach(item)
	_target_approaches[identity]={"signature":signature,"position":at}
	return at

func simulation_targets() -> Array:
	var navigation_id:int=lot_navigation.get_instance_id()
	if _target_navigation_id!=navigation_id or _target_navigation_generation!=lot_navigation.generation:
		_target_approaches.clear()
		_target_navigation_id=navigation_id;_target_navigation_generation=lot_navigation.generation
	var a:Array=[{"id":"lot_exit","kind":"lot_exit","position":lot_exit_position()}]
	var present:Dictionary={}
	for item in items:
		present[item.node.get_instance_id()]=true
		var at:Vector3=_simulation_approach(item)
		if at.is_finite():a.append({"id":item.id,"kind":item.kind,"position":at,"level":item_level(item)})
	for identity:int in _target_approaches.keys():
		if not present.has(identity):_target_approaches.erase(identity)
	# People move independently of the static navigation geometry.
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
	if not LifeCatalog.ITEMS.has(kind) or not p.is_finite():return false
	var level:int=point_level(p)
	if level<0:return false
	var size:Vector2=LifeCatalog.ITEMS[kind].size
	var depth:float=size.y
	if int(roundf(angle/90))%2:size=Vector2(size.y,size.x)
	var rect=Rect2(Vector2(p.x,p.z)-size/2,size)
	if kind in LifeCatalog.WALL_MOUNTED:
		# Wall decor sits flush against a wall, so only its room-facing half must
		# lie on the floor; the shift uses the unrotated depth at every angle.
		var forward:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3(0,0,1)
		rect.position+=Vector2(forward.x,forward.z)*(depth*.5+.04)
	if not construction.building_state.is_empty():
		if not Building.footprint_supported(construction.building_state,level,rect):return false
		if Building.blocked_rect(construction.building_state,level,rect):return false
		if not construction.building_state.roofs.is_empty() and not RoofRules.obstruction(construction.building_state,furnishing_volume({"kind":kind,"x":p.x,"z":p.z,"rotation":angle,"level":level})).is_empty():return false
	for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
		if not construction.floor_contains(corner,level):return false
	if kind in LifeCatalog.WALL_MOUNTED and not wall_behind(kind,p,angle):return false
	if LifeCatalog.passable(kind):return true
	# Interior walls and doorways stay usable.
	if construction.rect_blocked(rect,level):return false
	for item in items:
		if item_level(item)!=level:continue
		if item.kind in ["meal","plate","puddle"] or LifeCatalog.passable(str(item.kind)):continue
		var s:Vector2=item.size
		if int(roundf(item.node.rotation_degrees.y/90))%2:s=Vector2(s.y,s.x)
		var other=Rect2(Vector2(item.node.position.x,item.node.position.z)-s/2,s)
		if rect.grow(.05).intersects(other):return false
	return true

func wall_snap(kind:String,p:Vector3,reach:float=1.0) -> Dictionary:
	if not is_instance_valid(construction) or not LifeCatalog.ITEMS.has(kind):return {}
	var size:Vector2=LifeCatalog.ITEMS[kind].size
	var level:int=point_level(p)
	var best:Dictionary={};var best_distance:float=reach
	for e in construction.records:
		if int(e.get("level",0))!=level:continue
		var w:float=float(e.w);var d:float=float(e.d);var cx:float=float(e.x);var cz:float=float(e.z)
		var along_x:bool=w>=d
		var distance:float=absf(p.z-cz) if along_x else absf(p.x-cx)
		var within:bool=absf(p.x-cx)<=w*.5+.1 if along_x else absf(p.z-cz)<=d*.5+.1
		if not within or distance>=best_distance:continue
		best_distance=distance
		if along_x:
			var side:float=1.0 if p.z>=cz else -1.0
			# Keep clear of the perpendicular walls that meet this one in the corners
			# (wall thickness plus the floor inset), so a snapped ghost is always placeable.
			best={"position":Vector3(clampf(p.x,cx-w*.5+size.x*.5+.3,cx+w*.5-size.x*.5-.3),p.y,cz+side*(d*.5+size.y*.5+.01)),"angle":0.0 if side>0 else 180.0}
		else:
			var side:float=1.0 if p.x>=cx else -1.0
			best={"position":Vector3(cx+side*(w*.5+size.y*.5+.01),p.y,clampf(p.z,cz-d*.5+size.x*.5+.3,cz+d*.5-size.x*.5-.3)),"angle":90.0 if side>0 else -90.0}
	return best

func wall_behind(kind:String,p:Vector3,angle:float) -> bool:
	# Wall-mounted decor needs a wall directly behind its back face on the same floor.
	if not is_instance_valid(construction) or not LifeCatalog.ITEMS.has(kind):return false
	var size:Vector2=LifeCatalog.ITEMS[kind].size
	var forward:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3(0,0,1)
	var back:Vector3=p-forward*(size.y*.5+.06)
	var level:int=point_level(p)
	for e in construction.records:
		if int(e.get("level",0))!=level:continue
		if construction.wall_rect(e).grow(.06).has_point(Vector2(back.x,back.z)):return true
	return false

func floor_point(screen:Vector2) -> Vector3:
	var origin=camera.project_ray_origin(screen)
	var direction=camera.project_ray_normal(screen)
	if absf(direction.y)<.00001:return Vector3.INF
	var t=(Building.level_y(view_level)-origin.y)/direction.y
	if t<0:return Vector3.INF
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
	refresh_actor_layers()
	var ray=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*150,PICK_GROUND if view_level==0 else PICK_UPPER)
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
	refresh_actor_layers()
	if build_enabled and construction and not construction.tool.is_empty():construction.update_preview(floor_point(get_viewport().get_mouse_position()))
	if build_enabled and is_instance_valid(ghost):
		var p=floor_point(get_viewport().get_mouse_position())
		p.x=snappedf(p.x,.25);p.z=snappedf(p.z,.25)
		if placement_kind in LifeCatalog.WALL_MOUNTED:
			# Wall decor slides along the nearest wall and faces into the room.
			var snap:Dictionary=wall_snap(placement_kind,p)
			if not snap.is_empty():p=snap.position;placement_angle=float(snap.angle)
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
	assign_structure_layer(_desk_boosters[id],clampi(point_level(chair.global_position),0,1))
	_desk_boosters[id].visible=true

func _desk_surface(node:Node3D) -> Dictionary:
	return {"hand_center":node.to_global(Vector3(0,.915,.105)),"hand_spread":.105,
		"desk_surface_y":node.to_global(Vector3(0,.87,0)).y,
		"desk_front_edge":node.to_global(Vector3(0,.87,.385)),
		"desk_forward":-node.global_basis.z.normalized()}

const TWO_SEATERS: Array[String] = ["loveseat"]

func seat_slot_offset(item:Dictionary,slot:String) -> Vector3:
	# Local offset of a named seat on a two-seater; single seats return zero.
	if str(item.kind) not in TWO_SEATERS:return Vector3.ZERO
	return Vector3(-.45 if slot=="left" else .45,0,0)

func slot_approach(item:Dictionary,slot:String) -> Vector3:
	var n:Node3D=item.node
	var p:Vector3=n.to_global(seat_slot_offset(item,slot)+Vector3(0,0,item.size.y*.5+.55))
	if not construction.building_state.is_empty():return nearest_clear_point(p,item_level(item))
	var c=nearest_free(p)
	return Vector3(c.x*.25,.16,c.y*.25)

func activity_resource_ids(item:Dictionary,slot:String="") -> Array[String]:
	var resources:Array[String]=[str(item.id)+(":"+slot if str(item.kind) in TWO_SEATERS and not slot.is_empty() else "")]
	if str(item.kind) in ["desk","computer"]:
		var chair:Dictionary=closest_item("chair",item.node.to_global(Vector3(0,0,.88)),1.25)
		if not chair.is_empty():resources.append(str(chair.id))
	return resources

func supported_homework_plan(item:Dictionary,learner_from:Vector3,helper_from:Vector3) -> Dictionary:
	if str(item.get("kind","")) not in ["desk","computer"]:
		return {"ok":false,"error":"Choose a desk for homework together."}
	var node:Node3D=item.node
	var level:int=item_level(item)
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
			var at:Vector3=Vector3(cell.x*.25,Building.level_y(level),cell.y*.25)
			if construction.building_state.is_empty():
				if not navigation.is_in_boundsv(cell) or navigation.is_point_solid(cell):continue
			elif not lot_navigation.point_clear(level,at):continue
			if not _clear_coaching_space(at) or at.distance_to(seat.node.position)<.85:continue
			if path_to(helper_from,at).is_empty():continue
			options.append(at)
	if options.is_empty():
		return {"ok":false,"error":"Leave clear floor space beside the desk for an adult to help."}
	options.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.distance_squared_to(helper_from)<b.distance_squared_to(helper_from))
	return {"ok":true,"learner_position":learner_destination,"helper_position":options[0]}

func _clear_coaching_space(at:Vector3) -> bool:
	# Check the whole standing footprint, not a distant nearest-free fallback.
	var level:int=point_level(at)
	if level<0:return false
	if not construction.building_state.is_empty() and not lot_navigation.point_clear(level,at,Vector2(.29,.29)):return false
	for offset:Vector2 in [Vector2.ZERO,Vector2(.29,0),Vector2(-.29,0),Vector2(0,.29),Vector2(0,-.29),Vector2(.21,.21),Vector2(-.21,.21),Vector2(.21,-.21),Vector2(-.21,-.21)]:
		if construction.point_blocked(Vector2(at.x,at.z)+offset,level):return false
	for other:Dictionary in items:
		if item_level(other)!=level:continue
		if str(other.kind)=="puddle" or LifeCatalog.passable(str(other.kind)):continue
		var local:Vector3=other.node.to_local(at)
		var extent:Vector2=other.size*.5+Vector2(.29,.29)
		if absf(local.x)<extent.x and absf(local.z)<extent.y:return false
	return true

func activity_anchor(item:Dictionary,action_id:String,landmarks:Dictionary={}) -> Dictionary:
	var node:Node3D=item.node
	var local:Vector3=Vector3(0,0,float(item.size.y)*.5+.36)
	var yaw:float=node.rotation.y+PI
	var kind:String="standing"
	if bool(item.get("transient_puddle",false)):
		var at:Vector3=landmarks.get("standing_position",approach(item))
		var toward:Vector3=node.global_position-at
		at.y=node.global_position.y
		return {"position":at,"yaw":atan2(toward.x,toward.z),"kind":"standing","mop_contact":node.global_position}
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
		"armchair":
			local=Vector3(0,.50,.06);yaw=node.rotation.y;kind="seat"
		"loveseat":
			local=Vector3(0,.62,.08)+seat_slot_offset(item,str(landmarks.get("seat_slot","left")));yaw=node.rotation.y;kind="seat"
		"stool":
			local=Vector3(0,.755,0);yaw=node.rotation.y;kind="seat"
		"bathtub":
			# Sit facing along the tub with legs stretched beneath the water.
			local=Vector3(-.30,.30,0);yaw=node.rotation.y+PI*.5;kind="seat"
		"piano":
			local=Vector3(0,.535,.40);yaw=node.rotation.y+PI;kind="seat"
		"chess":
			local=Vector3(0,.50,.62);yaw=node.rotation.y+PI;kind="seat"
		"treadmill":
			local=Vector3(0,.16,.30);yaw=node.rotation.y+PI
		"yoga_mat":
			local=Vector3(0,.02,0);yaw=node.rotation.y
		"desk","computer":
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
	if str(item.kind) in ["desk","computer"]:
		anchor.merge(_desk_surface(node))
	return anchor

func oven_approach(item:Dictionary)->Vector3:
	var at:Vector3=item.node.to_global(Vector3(0,0,1.0))
	return Vector3(roundf(at.x*4)*.25,Building.level_y(item_level(item)),roundf(at.z*4)*.25)

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
		assign_structure_layer(view,item_level(appliance))
		view.show()
	for id:String in oven_food_views.keys():
		if not visible_ids.has(id):
			var view:Node3D=oven_food_views[id] if is_instance_valid(oven_food_views[id]) else null
			if is_instance_valid(view):view.hide();view.queue_free()
			oven_food_views.erase(id)

func create_public_venue(place:String,layout:Array) -> void:
	if house:house.queue_free()
	actors.clear();items.clear();walls.clear();landscape_trees.clear();ceiling_beams.clear()
	starter_floor_nodes.clear();view_level=0
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
	construction.refresh_decorations();rebuild_navigation();set_view_level(0)

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

func create_resident_home(place:String,layout:Array) -> void:
	last_layout_error=validate_home_layout(layout)
	if not last_layout_error.is_empty():return
	if house:house.queue_free()
	actors.clear();items.clear();walls.clear();landscape_trees.clear();ceiling_beams.clear();starter_floor_nodes.clear();view_level=0
	house=Node3D.new();house.name="ResidentHome_"+place;add_child(house)
	construction=LifeConstruction.new();house.add_child(construction);construction.initialize(self)
	furniture=Node3D.new();furniture.name="Furniture";house.add_child(furniture)
	var cottage:bool=place=="maya_home"
	var width:float=10.0 if cottage else 12.0
	var depth:float=9.0 if cottage else 8.0
	var plaster:String="cbd8c2" if cottage else "d5b39d"
	box(house,Vector3(0,-.3,0),Vector3(120,.3,120),"b8cdaa")
	box(house,Vector3(0,-.16,0),Vector3(17,.15,16),"a8c191")
	box(house,Vector3(0,-.025,0),Vector3(width+.4,.25,depth+.4),"d3c9b6")
	box(house,Vector3(0,.105,0),Vector3(width,.045,depth),"bb9a73" if cottage else "c9b299")
	# The narrow cottage uses long oak boards; the wide bungalow has parquet blocks.
	if cottage:
		for row:int in range(33):
			box(house,Vector3(-4.9+float(row)*.3,.162,0),Vector3(.009,.004,depth),"a98661")
			for joint:int in range(4):box(house,Vector3(-4.75+float(row)*.3,.163,-3.9+float(joint)*2.2+float(row%2)*.9),Vector3(.29,.004,.009),"a98661")
	else:
		for x:int in range(-6,6):
			for z:int in range(-4,4):
				box(house,Vector3(float(x)+.5,.163,float(z)+.5),Vector3(.985,.004,.985),"c6ad8e" if (x+z)%2 else "cfb899")
				for seam:int in range(1,4):
					box(house,Vector3(float(x)+float(seam)*.25,.167,float(z)+.5) if (x+z)%2 else Vector3(float(x)+.5,.167,float(z)+float(seam)*.25),Vector3(.007,.003,.97) if (x+z)%2 else Vector3(.97,.003,.007),"b99e7e")
	wall(Vector3(0,1.4,-depth*.5-.04),Vector3(width+.2,2.6,.16),plaster,false)
	wall(Vector3(-width*.5-.04,1.4,0),Vector3(.16,2.6,depth+.1),plaster,false)
	wall(Vector3(width*.5+.04,.4,0),Vector3(.16,.6,depth+.1),plaster,true)
	for side:int in [-1,1]:wall(Vector3(side*(width*.25+.55),.4,depth*.5+.04),Vector3(width*.5-1.0,.6,.16),plaster,true)
	if cottage:
		wall(Vector3(-2,.4,-2.6),Vector3(.13,.6,3.7),"eee5d5",true)
		wall(Vector3(-3.5,.4,.1),Vector3(3,.6,.13),"eee5d5",true)
		wall(Vector3(.3,.4,-2.9),Vector3(.13,.6,3.0),"eee5d5",true)
		box(house,Vector3(0,.08,5.35),Vector3(5.6,.15,1.7),"c8b79a")
		for x:float in [-2.5,2.5]:
			box(house,Vector3(x,1.35,5.85),Vector3(.13,2.65,.13),"f4efdc")
			box(house,Vector3(x,.35,5.9),Vector3(.8,.55,.65),"739781")
			for j:int in range(4):sphere(house,Vector3(x-.3+j*.2,.67,5.9),Vector3(.27,.30,.32),"bc8398")
		var canopy:MeshInstance3D=box(house,Vector3(0,2.76,5.35),Vector3(5.9,.17,2.0),"759487")
		canopy.visible=not cutaway;ceiling_beams.append(canopy)
	else:
		wall(Vector3(3.2,.4,-2.15),Vector3(.13,.6,3.7),"eadfcd",true)
		wall(Vector3(4.95,.4,1.25),Vector3(2.15,.6,.13),"eadfcd",true)
		box(house,Vector3(-6.65,.04,.2),Vector3(1.15,.12,7.4),"c1b49b")
		for j:int in range(12):box(house,Vector3(-6.65,.11,-3.2+j*.6),Vector3(1.1,.025,.5),"d3c7b2")
		box(house,Vector3(3.9,.07,4.8),Vector3(4.1,.14,1.4),"ac9480")
		for x:float in [2.4,5.5]:box(house,Vector3(x,.47,5.5),Vector3(.11,.8,.11),"937757")
	for x:float in ([-3.45,1.6,3.7] if cottage else [-4.5,-2.0,1.5,4.6]):window_panel(Vector3(x,1.78,-depth*.5+.055),false)
	for z:float in [-2.2,2.1]:window_panel(Vector3(-width*.5+.055,1.75,z),true)
	box(house,Vector3(0,-.02,7.0),Vector3(1.8,.1,2.8),"dcd5be")
	box(house,Vector3(0,-.02,8.5),Vector3(75,.1,1.25),"e0d9c7")
	box(house,Vector3(0,-.07,11),Vector3(100,.12,3.7),"798781")
	for x:int in range(-30,31,5):box(house,Vector3(x,.003,11),Vector3(2,.009,.08),"e6ddbc")
	for x:float in [-7.7,7.7]:
		for z:float in [-5.5,3.3]:tree(Vector3(x,-.1,z),.75 if cottage else 1.05)
	for x:float in [-11.0,12.0]:tree(Vector3(x,-.1,-8),1.4)
	for x:int in range(-6,7):
		if cottage:sphere(house,Vector3(x,.25,-6.0),Vector3(1.1,.65,.8),"73966d")
		else:
			box(house,Vector3(x,.35,-5.5),Vector3(.13,.85,.13),"a88667")
	box(house,Vector3(2,.5,7.7),Vector3(.12,1.1,.12),"a08060")
	box(house,Vector3(2,1.02,7.7),Vector3(.45,.35,.35),"739781" if cottage else "aa705c")
	grid=Node3D.new();house.add_child(grid);grid.visible=false
	# Canonical ground records keep friend homes on the same detached-save path.
	var structure:Dictionary=Building.fresh()
	structure.floors=[{"id":"resident_ground","level":0,"x":0.0,"z":0.0,"w":width,"d":depth,"material":"bb9a73" if cottage else "c9b299"}]
	for original:Dictionary in construction.records:
		var entry:Dictionary=original.duplicate(true)
		entry["id"]="resident_wall_%d"%structure.walls.size();entry["level"]=0;entry["material"]=str(entry.color);entry.erase("color")
		structure.walls.append(entry)
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))!="__construction":continue
		if entry.has("version"):structure=entry
		else:
			structure=Building.migrate(entry).state
			var inherited:Dictionary=Building.find(structure,"legacy_starter_floor")
			if not inherited.is_empty():
				inherited.id="resident_ground";inherited.w=width;inherited.d=depth;inherited.material="bb9a73" if cottage else "c9b299"
	construction.restore(structure)
	if not construction.last_error.is_empty():last_layout_error=construction.last_error;return
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))!="__construction":add_item(entry,false)
	construction.refresh_decorations();rebuild_navigation();set_view_level(0);update_camera()
