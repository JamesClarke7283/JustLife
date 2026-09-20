extends Node3D
class_name LifeWorld
const Building=preload("res://scripts/building_state.gd")
const RoofRules=preload("res://scripts/roof_rules.gd")
const Variants=preload("res://scripts/catalog_variants.gd")
const LotNavigation=preload("res://scripts/lot_navigation.gd")
const VIEW_ENVIRONMENT:int=1
const VIEW_GROUND:int=2
const VIEW_UPPER:int=4
const VIEW_STAIRS:int=8
const VIEW_ACTOR_GROUND:int=16
const VIEW_ACTOR_UPPER:int=32
const PICK_GROUND:int=2
const PICK_UPPER:int=4
## A second, always-on pick bit for the things that rest *on* furniture or lie
## under it: plates, serving dishes and wet patches. A furnishing's collision box
## is a plain volume from the floor to its full authored height, and that volume
## is taller than the surface it offers (the dining table is 1.0 m tall, so its
## box reaches 1.16 m while its tabletop sits at 0.847 m). Anything set down on
## that table therefore lies *inside* the table's own box, and a single ray always
## reached the table first: plates could never be clicked, so they could not be
## taken, cleared or put in the fridge. These picks are resolved first, on their
## own ray, so food and spills stay reachable wherever they are put down.
const PICK_SURFACE:int=64

signal object_clicked(info: Dictionary, screen_position: Vector2)
signal ground_clicked(world_position: Vector3)
signal placement_requested(kind: String, world_position: Vector3, angle: float, style: String, size: String)
signal construction_requested(data: Dictionary)

## Camera limits, in one place so the wheel, the HUD buttons, the drag handlers
## and the save round-trip cannot drift apart. Closer zoom and a wider pitch let
## a player look into a room and around it; the orbit scales are per mouse pixel.
const CAMERA_MIN_ZOOM: float = 3.5
const CAMERA_MAX_ZOOM: float = 40.0
const CAMERA_MIN_PITCH: float = .18
const CAMERA_MAX_PITCH: float = 1.42
const CAMERA_ORBIT_PER_PIXEL: float = .014
const CAMERA_PITCH_PER_PIXEL: float = .008
const CAMERA_WHEEL_STEP: float = .8
const CAMERA_BUTTON_ZOOM_STEP: float = 1.5
const CAMERA_PAN_SPEED: float = 10.0
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var house: Node3D
var furniture: Node3D
## The ground and its dressing (lawn, hedge, street, trees), kept apart from the
## house so buying a neighbouring plot redraws only the land.
var ground_node: Node3D
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
## The style and size being placed, so the ghost, the validity check and the
## committed record all describe the same object the player is buying.
var placement_style: String = ""
var placement_size: String = ""
var placement_angle: float = 0.0
var ghost: Node3D
var ghost_valid: bool = false
var placement_reach_check: Callable  # set by the app: (kind, position, angle) -> bool, the same doorway rule a click applies
## The world owns the ghost's own style and size in `placement_style` and
## `placement_size`, so a check that only knows a kind still describes the object
## actually being placed.
var ghost_position = Vector3.ZERO
var cutaway: bool = true
var grid: Node3D
var elapsed: float = 0.0
var rng = RandomNumberGenerator.new()
var material_cache: Dictionary = {}
var construction: LifeConstruction
var landscape_trees:Array[Node3D]=[]
var ceiling_beams:Array[MeshInstance3D]=[]
var indoor_lights:Array[Dictionary]=[]
var indoor_lights_lit:bool=true
var _desk_boosters:Dictionary={}
var oven_presentations:Dictionary={}
var oven_food_views:Dictionary={}
## Picks the world does not own. Pets live in the controller's own registry
## rather than in `items` (a furnishing record would be saved as furniture), so
## the controller registers each picked body here and a click on one opens that
## pet's own card instead of falling through to a walk on the ground.
var pick_extras:Dictionary={}
## Solid bands contributed by something that is not a saved furnishing: the
## weekly food truck, which parks on the sidewalk on its own schedule and must
## still be walked around. Like `pick_extras`, this is a plain list the owning
## service writes, so the van blocks routes without ever entering `items`, the
## saved layout or the catalogue.
var extra_obstacles:Array=[]

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
	environment.ssao_enabled = false
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
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	# A world always owns a construction. It starts empty, which is already the
	# "nothing built here yet" state every caller reads, so no reader has to
	# check whether a home happens to have been built before it can ask about
	# walls, floors or support.
	construction = LifeConstruction.new()
	construction.name = "Construction"
	add_child(construction)
	construction.initialize(self)
	update_camera()

func material(hex: String, roughness: float = .8) -> StandardMaterial3D:
	if material_cache.has(hex): return material_cache[hex]
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = roughness
	material_cache[hex] = m
	return m

func ensure_memorial(member_id: String) -> bool:
	if member_id.is_empty():
		return false
	for item: Dictionary in items:
		if str(item.get("kind", "")) == "memorial" and str(item.get("for", "")) == member_id:
			return true
	var spots: Array = [
		Vector3(1.8, 0.16, 4.4), Vector3(-1.8, 0.16, 4.4), Vector3(0.0, 0.16, 4.6),
		Vector3(3.6, 0.16, 3.2), Vector3(-3.6, 0.16, 3.2), Vector3(2.4, 0.16, -3.6),
		Vector3(-4.6, 0.16, 1.2), Vector3(4.2, 0.16, 1.8), Vector3(0.8, 0.16, 3.0),
	]
	# The garden stone is walkable, so `can_place` accepts it everywhere and never
	# reports the stones already standing there. A household can farewell more
	# Lifelets than the nine authored places hold, and without comparing against
	# the stones present every later remembrance was stacked inside the first.
	var spacing: float = float(LifeCatalog.ITEMS["memorial"].size.x) + 0.18
	var taken: Array[Vector2] = []
	for item: Dictionary in items:
		if str(item.get("kind", "")) == "memorial" and is_instance_valid(item.get("node")):
			taken.append(Vector2(item.node.position.x, item.node.position.z))
	# Further ground along the front garden, so a long-lived household still has
	# somewhere to remember each of its own.
	for index: int in range(14):
		spots.append(Vector3(-5.0 + 0.76 * float(index), 0.16, 4.4))
	var fallback: Vector3 = Vector3(0.8, 0.16, 3.0)
	var used_fallback: bool = false
	for at: Vector3 in spots:
		if not can_place("memorial", at, 0):
			continue
		var crowded: bool = false
		for other: Vector2 in taken:
			if other.distance_to(Vector2(at.x, at.z)) < spacing:
				crowded = true
				break
		if crowded:
			continue
		add_item({"id":"memorial_%s" % member_id,"kind":"memorial","x":at.x,"z":at.z,"rotation":0.0,"for":member_id})
		return true
	# Every candidate is walled off: shift the last one clear of what stands there
	# rather than planting a second stone inside a first.
	var offset: Vector3 = fallback
	for step: int in range(24):
		offset = Vector3(fallback.x + 0.76 * float(step + 1), fallback.y, fallback.z)
		if not can_place("memorial", offset, 0):
			continue
		used_fallback = true
		for other: Vector2 in taken:
			if other.distance_to(Vector2(offset.x, offset.z)) < spacing:
				used_fallback = false
				break
		if used_fallback:
			break
	# No candidate survived support and spacing checks. Keep the household's
	# memorial pending rather than adding an overlapping or out-of-lot stone.
	if not used_fallback:
		return false
	add_item({"id":"memorial_%s" % member_id,"kind":"memorial","x":offset.x,"z":offset.z,"rotation":0.0,"for":member_id})
	return true

func _build_memorial(parent: Node3D) -> void:
	# Original garden stone: a low tablet and a small offering dish. Built here
	# so a household can remember someone without a shipped mesh.
	box(parent, Vector3(0, 0.08, 0), Vector3(0.62, 0.16, 0.42), "8c8a84")
	box(parent, Vector3(0, 0.28, -0.04), Vector3(0.46, 0.28, 0.10), "6f6c66")
	box(parent, Vector3(0, 0.18, 0.14), Vector3(0.16, 0.04, 0.16), "c8a562")

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
	landscape_trees.clear();ceiling_beams.clear();indoor_lights.clear()
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
	# The ground and everything dressing it live in their own node, so buying a
	# neighbouring plot redraws only the land without disturbing the house, the
	# furnishings or the actors standing on it.
	ground_node=Node3D.new()
	ground_node.name="Ground"
	house.add_child(ground_node)
	draw_ground()
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
	# One warm ceiling light per room. The kitchen, lounge, bedroom and bathroom
	# can each be switched from their own light, and Build carries the state.
	ceiling_light(house,Vector3(-3.4,2.52,-3.0),"kitchen")
	ceiling_light(house,Vector3(-3.2,2.52,2.4),"lounge")
	ceiling_light(house,Vector3(3.6,2.52,1.4),"bedroom")
	ceiling_light(house,Vector3(3.6,2.52,-3.0),"bathroom")
	ceiling_light(house,Vector3(-4.6,2.52,5.0),"hall")
	set_indoor_lights(true)
	# Wall accents, skirting, door thresholds and entry.
	var back_skirting:MeshInstance3D=box(house,Vector3(0,.24,-4.94),Vector3(12,.18,.04),"fcf5e6")
	back_skirting.set_meta("wall_decoration",true);back_skirting.set_meta("wall_support_normal",Vector3.FORWARD)
	var side_skirting:MeshInstance3D=box(house,Vector3(-5.94,.24,0),Vector3(.04,.18,10),"fcf5e6")
	side_skirting.set_meta("wall_decoration",true);side_skirting.set_meta("wall_support_normal",Vector3.LEFT)
	box(house,Vector3(0,.02,5.72),Vector3(2.4,.2,1.35),"c7bea9")
	box(house,Vector3(0,-.025,7.1),Vector3(1.75,.08,1.8),"dcd5be")
	# The house's own foundation beds and doorstep flowers stay beside the
	# building; the lawn, hedges, street and trees belong to draw_ground(), which
	# is redrawn whenever the household buys a neighbouring plot.
	for x in [-6.85,6.85]:
		for z in range(-5,5):
			if z%2==0:sphere(house,Vector3(x,.16,z),Vector3(.68,.34,.65),"84a366").set_meta("garden_decoration",true)
	for x in [-3.5,3.5]:
		for i in range(12):
			var p=Vector3(x+rng.randf_range(-.9,.9),-.09,6.8+rng.randf_range(-.45,.45))
			flower_clump(p, rng, "d4868e" if i%2 else "f5e5ad")
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
		if not Building.lot().encloses(furnishing_rect(entry)):return "A furnishing extends beyond the navigable lot."
	# Align ingress with the detached graph's obstacle bound so a valid layout
	# cannot replace the live scene and only then fail graph construction.
	if ids.size()>512:return "Too many furnishings for this lot."
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))=="__construction":continue
		var level:int=int(entry.get("level",0))
		if level==1 and canonical.is_empty():return "Upper furniture needs a validated two-level building."
		if canonical.is_empty():continue # Preserve old ground layout migration behavior.
		# Everything below is asked of each solid band rather than of the whole
		# declared outline, so a kind with an open interior is judged on the
		# floor it really covers. The roof test stays on the whole volume: the
		# garage's roof slab is genuinely under the home's own roof and only the
		# volume can say so.
		for area:Rect2 in furnishing_panels(entry):
			# Level 0 may stand on the lot itself, so a kennel or garden bed
			# belongs in the garden; an upper furnishing still needs real slab.
			if not Building.footprint_supported(canonical,level,area,level==0):return "A furnishing crosses unsupported floor or a stair opening."
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
	var data:Dictionary=LifeCatalog.get_item(str(entry.kind))
	var size:Vector2=Variants.footprint(data, str(entry.get("size","")))
	var basis:=Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0))))
	var x_axis:Vector3=basis*Vector3(size.x*.5,0,0)
	var z_axis:Vector3=basis*Vector3(0,0,size.y*.5)
	var half:=Vector2(absf(x_axis.x)+absf(z_axis.x),absf(x_axis.z)+absf(z_axis.z))
	return Rect2(Vector2(float(entry.get("x",0)),float(entry.get("z",0)))-half,half*2)

func _furnishing_basis(entry:Dictionary) -> Basis:
	return Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0))))

## The solid floor bands an entry really occupies. Most furnishings are one
## solid box, so their outline is their blocker. A kind whose single box would
## swallow a space the household uses — the garage, whose two side walls, back
## wall and corner posts are thin bands around an open, roofed bay — lists its
## own bands in its local metres, exactly as a staircase contributes `stair_rect`
## plus its guard footprints rather than one solid volume. Nothing in the
## obstacle, placement or collider code needs to know which kind it is holding.
func furnishing_panels(entry:Dictionary) -> Array[Rect2]:
	var origin:=Vector2(float(entry.get("x",0)),float(entry.get("z",0)))
	var basis:Basis=_furnishing_basis(entry)
	var result:Array[Rect2]=[]
	for panel:Dictionary in LifeCatalog.local_panels(str(entry.get("kind",""))):
		result.append(_oriented_panel(origin,basis,panel))
	return result

## The axis-aligned rectangle a band's local centre and size occupy once the
## entry's yaw is applied. Every rectangle this file builds for a furnishing goes
## through here, so an entry's outline, its solid bands and its collider can
## never disagree about how a rotation maps one onto the world. The centre is a
## floor-plan point — local x and local z — because a yaw moves only those.
func _oriented_panel(origin:Vector2,basis:Basis,panel:Dictionary) -> Rect2:
	var offset:Vector3=basis*Vector3(float(panel.x),0,float(panel.z))
	var x_axis:Vector3=basis*Vector3(float(panel.w)*.5,0,0)
	var z_axis:Vector3=basis*Vector3(0,0,float(panel.d)*.5)
	var half:=Vector2(absf(x_axis.x)+absf(z_axis.x),absf(x_axis.z)+absf(z_axis.z))
	return Rect2(origin+Vector2(offset.x,offset.z)-half,half*2)

## The same bands for a placed item, read off the node the live world owns.
func item_panels(item:Dictionary) -> Array[Rect2]:
	var source:Dictionary={"kind":str(item.kind),"x":item.node.position.x,"z":item.node.position.z,"rotation":item.node.rotation_degrees.y}
	return furnishing_panels(source)

## The navigation obstacle records an entry contributes: one per solid band, and
## a band's record reuses the entry's own identity unless there are several, so
## a single-box furnishing keeps exactly the obstacle identity it always had.
func furnishing_obstacles(entry:Dictionary,level:int) -> Array:
	var areas:Array[Rect2]=furnishing_panels(entry)
	var result:Array=[]
	var id:String=str(entry.get("id",""))
	for index:int in range(areas.size()):
		var area:Rect2=areas[index]
		var identifier:String=id if areas.size()==1 else "%s_%d"%[id,index]
		result.append({"id":identifier,"level":level,"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y})
	return result

## Repaint an authored surface by name, exactly as the character actor and the
## pet actor repaint their own materials: the released glTF names the car's
## paint surface "Body", so a chosen shade overrides that one surface and leaves
## the glass, tyres, hubs and lamps at the finish they were authored with.
func apply_paint(model:Node3D,shade:String) -> void:
	if not is_instance_valid(model) or shade.length()!=6:return
	for node:Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh:MeshInstance3D=node
		if mesh.mesh==null:continue
		for surface_index:int in range(mesh.mesh.get_surface_count()):
			var original:Material=mesh.mesh.surface_get_material(surface_index)
			if not original is StandardMaterial3D or str(original.resource_name)!="Body":continue
			var material:StandardMaterial3D=original.duplicate() as StandardMaterial3D
			material.albedo_color=Color(shade)
			mesh.set_surface_override_material(surface_index,material)

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
	var style:String=Variants.style_or_default(str(entry.get("style","")),LifeCatalog.get_item(kind))
	var cache_key:String=kind+"|"+style
	if not _furnishing_volume_cache.has(cache_key):
		var data:Dictionary=LifeCatalog.get_item(kind)
		# The authored mesh is measured once at its own size; the declared box is
		# the authored footprint and height, and the size choice scales both, so
		# the envelope follows the size the player actually bought.
		var box:=AABB(Vector3(-data.size.x*.5,0,-data.size.y*.5),Vector3(data.size.x,data.height,data.size.y))
		var path:String=Variants.model_path(kind,style)
		if ResourceLoader.exists(path):
			var scene:Node3D=load(path).instantiate();var vertices:Array[Vector3]=[]
			_gather_visual_bounds(scene,Transform3D.IDENTITY,vertices);scene.free()
			for point:Vector3 in vertices:box=box.expand(point)
		_furnishing_volume_cache[cache_key]=box
	var local:AABB=_scaled_volume(_furnishing_volume_cache[cache_key],Variants.size_scale(str(entry.get("size",""))))
	var transform:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0)))),Vector3(float(entry.get("x",0)),Building.level_y(int(entry.get("level",0))),float(entry.get("z",0))))
	return transform*local

## An authored envelope scaled by a size choice, about its own origin.
##
## Godot 4 removed `AABB * float`, so the envelope is rebuilt from its two
## corners instead: the origin scales with the box, because the authored model is
## centred on its own footprint and a larger table grows outward from the middle.
static func _scaled_volume(box:AABB,scale:float) -> AABB:
	if is_equal_approx(scale,1.0):
		return box
	var scaled:=AABB(box.position*scale,box.size*scale)
	return scaled

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

func tree(p: Vector3, s: float, parent: Node3D = null) -> void:
	# Coordinate-only variation preserves the world's shared random stream.
	var key:int=(roundi(p.x*100.0)*73856093) ^ (roundi(p.z*100.0)*19349663)
	var variant:String="a" if posmod(key,5)<3 else "b"
	var tree_root:Node3D=load("res://assets/models/tree_field_maple_%s.glb"%variant).instantiate()
	if parent == null: parent = house
	parent.add_child(tree_root)
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

## Draw the household's land: the lawn it covers, the boundary hedges on its own
## outer edges, the street in front and the trees behind.
##
## Everything here is derived from `Building.lot()`, so it is drawn again from
## scratch whenever the land grows. Redrawing is cheap and complete, which is
## what keeps a bought plot from leaving the old hedge standing in the middle of
## the new lawn.
func draw_ground() -> void:
	if not is_instance_valid(ground_node):
		return
	for child:Node in ground_node.get_children():
		ground_node.remove_child(child)
		child.queue_free()
	# The camera's transparency list must not keep trees that have been redrawn.
	landscape_trees = landscape_trees.filter(func(node: Node3D) -> bool: return is_instance_valid(node) and node.get_parent() != null)
	ground_node.position=Vector3.ZERO
	var ground:Rect2=Building.lot()
	var parent:Node3D=ground_node
	box(parent,Vector3(ground.get_center().x,-.3,ground.get_center().y),Vector3(ground.size.x+80,.3,ground.size.y+80),"b8cdaa")
	# Trees behind the house, kept clear of the lawn the household can walk on by
	# sitting them beyond the lot's own back edge.
	for x in [-7.55,7.55]:
		for z in [-6.8,-1.2,5.9]: tree(Vector3(x,-.10,z),0.55,parent)
	var back_edge:float=ground.position.y
	for x in [-10.5,10.6,16,-17]:tree(Vector3(x,-.12,back_edge+4.0),1.0,parent)
	# The boundary hedges sit on the garden's own edges, so a deeper or wider
	# garden moves them rather than leaving them standing in the middle of the
	# lawn. The frontage is left open for the street.
	var west_edge:float=ground.position.x
	var east_edge:float=ground.end.x
	for z in [back_edge+.6, back_edge+1.2]:
		for x in range(int(west_edge)+1,int(east_edge)):sphere(parent,Vector3(x,.25,z),Vector3(1.0,.64,.80),"71945e")
	for side_x:float in [west_edge+.85, east_edge-.85]:
		var span:int=int(maxf(1.0,(ground.end.y-2.0)-back_edge))
		for step:int in range(span):
			var z:float=back_edge+1.0+float(step)
			sphere(parent,Vector3(side_x,.25,z),Vector3(.9,.5,.80),"71945e")
	# The street stays where it is: the lot grows away from the frontage.
	box(parent,Vector3(0,-.02,8.5),Vector3(75,.10,1.25),"e0d9c7")
	box(parent,Vector3(0,-.07,11.0),Vector3(100,.12,3.7),"798781")
	for x in range(-30,31,5): box(parent,Vector3(x,.003,11),Vector3(2,.009,.08),"e6ddbc")
	for x in [-23,25]: neighbor_home(Vector3(x,0,-1))
	# A simple open mailbox with a brass house number plate.
	box(parent,Vector3(2,.52,7.8),Vector3(.10,1.1,.10),"ab7951")
	box(parent,Vector3(2,1.06,7.8),Vector3(.45,.35,.33),"397e70")
	box(parent,Vector3(2,1.07,7.98),Vector3(.26,.05,.008),"c8a562")


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

func _dress_mirror(node:Node3D,model:Node3D) -> void:
	# The glass reflects the room: a mirror-finish material fed by a reflection
	# probe captured once in front of the frame, so the oval shows the walls,
	# floor and furnishings around it instead of a flat pale disc.
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		for index:int in range(mesh.mesh.get_surface_count()):
			var source:Material=mesh.get_active_material(index)
			if source==null or not str(source.resource_name).to_lower().contains("mirror_glass"):continue
			var glass:StandardMaterial3D=StandardMaterial3D.new()
			glass.albedo_color=Color(.93,.95,.97)
			glass.metallic=1.0;glass.metallic_specular=1.0;glass.roughness=.04
			mesh.set_surface_override_material(index,glass)
	var probe:ReflectionProbe=ReflectionProbe.new()
	probe.name="MirrorReflection"
	probe.size=Vector3(7,3.2,7)
	probe.position=Vector3(0,1.3,1.3)
	probe.origin_offset=Vector3.ZERO
	probe.box_projection=true
	probe.interior=true
	probe.enable_shadows=false
	probe.intensity=.9
	probe.max_distance=12.0
	probe.update_mode=ReflectionProbe.UPDATE_ONCE
	node.add_child(probe)

func refresh_mirror_reflections() -> void:
	# A world exists before a home does — the construction it always owns says so
	# — so a rebuild with no furniture container yet simply has no mirror to
	# refresh rather than failing on a missing node.
	if not is_instance_valid(furniture):
		return
	# Furnishings and walls changed: capture the rooms again for every mirror.
	for probe:ReflectionProbe in furniture.find_children("MirrorReflection","ReflectionProbe",true,false):
		probe.update_mode=ReflectionProbe.UPDATE_ALWAYS
		probe.set_deferred("update_mode",ReflectionProbe.UPDATE_ONCE)

func add_item(entry: Dictionary, rebuild: bool = true) -> void:
	var kind: String=str(entry.get("kind","plant"))
	if not LifeCatalog.ITEMS.has(kind):return
	if not Building.number(entry.get("level",0),0,1,true):return
	var level:int=int(entry.get("level",0))
	if level==1 and (not is_instance_valid(construction) or construction.building_state.is_empty()):return
	var data:Dictionary=LifeCatalog.get_item(kind)
	var variant:Dictionary=Variants.resolve(data,entry)
	var path:String=Variants.model_path(kind,str(variant.style))
	var has_model:bool=ResourceLoader.exists(path)
	if not has_model and kind!="memorial":return
	var node=Node3D.new()
	node.name=str(entry.get("id","item_%d" % Time.get_ticks_usec()))
	furniture.add_child(node)
	var model:Node3D=null
	if has_model:
		model=load(path).instantiate()
		node.add_child(model)
		# A size choice scales the whole authored model uniformly, so a large
		# table is the same object made bigger rather than a stretched one.
		var scale:float=Variants.size_scale(str(variant.size))
		if not is_equal_approx(scale,1.0):model.scale=Vector3.ONE*scale
	else:
		_build_memorial(node)
	node.position=Vector3(float(entry.get("x",0)),Building.level_y(level),float(entry.get("z",0)))
	node.rotation_degrees.y=float(entry.get("rotation",0))
	if is_instance_valid(model):_apply_variant_colour(model,data,variant)
	if kind=="mirror" and is_instance_valid(model):_dress_mirror(node,model)
	if kind=="floor_lamp":
		# The arc lamp's warm pool of light is runtime state: the menu switch
		# toggles it and the layout record carries it across save and load.
		var glow:=OmniLight3D.new();glow.name="LampGlow"
		glow.position=Vector3(0,1.44,.38);glow.light_color=Color("ffd9a1");glow.light_energy=.95;glow.omni_range=4.2
		glow.shadow_enabled=false;glow.visible=bool(entry.get("lit",true))
		node.add_child(glow)
	if kind=="rubbish_bin":
		# A soft bag rises above the rim once the bin is full; the household
		# service toggles it, so the bin visibly needs emptying.
		var bag:MeshInstance3D=box(node,Vector3(0,.60,0),Vector3(.30,.20,.30),"2b3330")
		bag.name="BinBag";bag.visible=false
	if kind=="bookshelf":
		# Empty slots wait on the shelf; buying a book fills one and colours it.
		for index:int in range(6):
			var shelf_book:MeshInstance3D=box(node,Vector3(-.42+float(index%3)*.42,.42+float(index/3)*.62,-.06),Vector3(.10,.34,.22),"b6b29c")
			shelf_book.name="ShelfBook_%d" % index
			shelf_book.visible=false
			for face:Node in shelf_book.find_children("*","MeshInstance3D",true,false):pass
			shelf_book.set_meta("book_cover",true)
	if kind in LifeCatalog.INSTRUMENTS:
		pass
	var info:Dictionary=entry.duplicate(true)
	info["node"]=node
	info["label"]=data.label
	# A live item's `size` is its real footprint, which every placement, seat and
	# approach calculation reads; the player's choice rides beside it under
	# `variant` so the two meanings never collide. The variant is stored as the
	# record — only the axes this family actually offers — so an unsized kind
	# carries no size key and two saves describing the same object compare equal.
	info.erase("style");info.erase("color");info.erase("size")
	info["variant"]=Variants.record(data, str(variant.style), str(variant.color), str(variant.size))
	info["size"]=Variants.footprint(data,str(variant.size))
	info["height"]=Variants.height(data,str(variant.size))
	info["level"]=level
	assign_structure_layer(node,level)
	var body=StaticBody3D.new()
	body.collision_layer=PICK_GROUND if level==0 else PICK_UPPER
	node.add_child(body)
	# One box per solid band, from the same catalogue data the placement, the
	# navigation obstacle and the build quote read. The bands are local metres
	# and the node already carries the placement's position and yaw, so an
	# ordinary furnishing gets exactly the single box it always had while a
	# kind with an open interior keeps its bays walkable — which is what lets a
	# car park inside the two-car garage and the player click its wall to sell it.
	for panel:Dictionary in LifeCatalog.local_panels(kind):
		var shape=CollisionShape3D.new()
		var bounds=BoxShape3D.new()
		bounds.size=Vector3(float(panel.w),info.height,float(panel.d))
		shape.shape=bounds
		shape.position=Vector3(float(panel.x),float(info.height)/2,float(panel.z))
		body.add_child(shape)
	body.set_meta("item_id",info.id)
	items.append(info)
	if rebuild:rebuild_navigation()

## Paint a placed furnishing's own colour choice onto the authored surface the
## model reserves for it. A model with no such surface — every older furnishing
## — is left exactly as authored, so this is additive rather than a rewrite of
## the existing artwork.
func _apply_variant_colour(model:Node3D,data:Dictionary,variant:Dictionary) -> void:
	if Variants.colors(data).size()<=1:return
	var tint:Color=Color(str(variant.color))
	for node:Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh_node:MeshInstance3D=node
		if not Variants.is_tint(mesh_node.name):continue
		var painted:=StandardMaterial3D.new()
		painted.albedo_color=tint
		painted.roughness=.62
		painted.metallic=.04
		mesh_node.material_override=painted

## A live world body's own colour, so the ghost, the placement preview and the
## placed furnishing agree.
func item_colour(entry:Dictionary) -> Color:
	var data:Dictionary=LifeCatalog.get_item(str(entry.get("kind","")))
	return Color(str(Variants.resolve(data,entry).color))

## A model path for a variant entry, used by the placement ghost and the
## catalogue thumbnail so both draw the style the player is about to buy.
func variant_model_path(kind:String,style:String="") -> String:
	return Variants.model_path(kind,style)

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
		if bool(item.get("transient_food",false)) or bool(item.get("transient_puddle",false)) or bool(item.get("derived",false)):continue
		var entry:Dictionary={"id":item.id,"kind":item.kind,"x":item.node.position.x,"z":item.node.position.z,"rotation":item.node.rotation_degrees.y}
		if item_level(item)!=0:entry["level"]=item_level(item)
		# The chosen style, colour and size ride the layout record, so a save
		# resumes the same object rather than the family's first choice. Only the
		# axes the entry offers are written, so an unsized furnishing stores no
		# size key and old and new saves of it compare equal.
		var variant:Dictionary=item.get("variant",Variants.resolve(LifeCatalog.get_item(item.kind),item))
		for key:String in variant:
			entry[key]=variant[key]
		if str(item.kind)=="floor_lamp" and not bool(item.get("lit",true)):entry["lit"]=false
		if str(item.kind)=="memorial" and str(item.get("for",""))!="":entry["for"]=str(item.get("for"))
		if LifeCatalog.paints(str(item.kind)):entry["paint"]=LifeCatalog.paint_of(item)
		out.append(entry)
	if construction:out.append(construction.snapshot())
	return out

func rebuild_navigation() -> void:
	# Even a rejected rebuild can replace the compatibility grid.
	_target_approaches.clear()
	# Compatibility grid stays ground-only until main/food callers are migrated.
	navigation.region=Building.cell_range()
	navigation.cell_size=Vector2(.25,.25)
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	# The solid walls and panels do not depend on the cell, and this loop runs on
	# every build edit and every home load. They used to be re-derived inside it:
	# roughly five thousand allocations of cell-independent work, which was the
	# single largest stall in the game (about 1.1 s with a handful of furnishings).
	var solid_panels:Array[Rect2]=[]
	for item:Dictionary in items:
		if item_level(item)!=0:continue
		if str(item.kind) in ["meal","plate","puddle"] or bool(item.get("derived",false)) or LifeCatalog.passable(str(item.kind)):continue
		for panel:Rect2 in item_panels(item):solid_panels.append(panel.grow(.16))
	# A non-furnishing blocker (the parked food truck) contributes the same way.
	for record:Dictionary in extra_obstacles:
		if int(record.get("level",0))!=0:continue
		var half:=Vector2(float(record.get("w",0)),float(record.get("d",0)))*.5
		solid_panels.append(Rect2(Vector2(float(record.get("x",0)),float(record.get("z",0)))-half,half*2).grow(.16))
	# `point_blocked` grows every wall rectangle by 0.15 m on each call, so it
	# allocates a fresh Rect2 per wall per cell. The grown rectangles do not
	# depend on the cell, so they are resolved once for the whole grid.
	var solid_walls:Array[Rect2]=[]
	for record:Dictionary in construction.records:
		if int(record.get("level",0))==0:solid_walls.append(construction.wall_rect(record).grow(.15))
	# Walk exactly the region the graph uses. These bounds were once hardcoded
	# narrower than `cell_range()`, so the outer strip of the lot was never
	# marked or cleared as solid — invisible while the lot was small, and a real
	# hole the moment the garden grew.
	var grid_region:Rect2i=navigation.region
	for x in range(grid_region.position.x,grid_region.end.x):
		for z in range(grid_region.position.y,grid_region.end.y):
			var p=Vector2(x*.25,z*.25)
			var solid:=false
			for wall:Rect2 in solid_walls:
				if wall.has_point(p):solid=true;break
			if not solid:
				for panel:Rect2 in solid_panels:
					if panel.has_point(p):solid=true;break
			navigation.set_point_solid(Vector2i(x,z),solid)
	var result:Dictionary=construction.validated_state()
	if not bool(result.ok):last_layout_error=str(result.error);return
	var obstacles:Array=[]
	for item:Dictionary in items:
		if str(item.kind) in ["meal","plate","puddle"] or bool(item.get("derived",false)) or LifeCatalog.passable(str(item.kind)):continue
		for record:Dictionary in furnishing_obstacles(item,item_level(item)):obstacles.append(record)
	obstacles.append_array(extra_obstacles)
	var built:Dictionary=lot_navigation.rebuild(result.state,obstacles)
	if not bool(built.ok):last_layout_error=str(built.error)

	refresh_mirror_reflections()

func nearest_free(p:Vector3) -> Vector2i:
	var cell=Vector2i(roundi(p.x*4),roundi(p.z*4))
	var bounds:Rect2i=Building.cell_range()
	cell.x=clampi(cell.x,bounds.position.x,bounds.end.x-1)
	cell.y=clampi(cell.y,bounds.position.y,bounds.end.y-1)
	if not navigation.is_point_solid(cell):return cell
	for radius in range(1,14):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				if absi(x)!=radius and absi(z)!=radius:continue
				var c=cell+Vector2i(x,z)
				if navigation.region.has_point(c) and not navigation.is_point_solid(c):return c
	return cell

func path_to(from:Vector3,to:Vector3) -> PackedVector3Array:
	# The floor graph is the authority a walker is held to: every cell carries
	# the full body radius. The ground compatibility grid is a coarser model
	# that can still admit a tile the walker is refused, so plan on the graph
	# first and only fall back to the grid when the graph has no route at all.
	var planned:Dictionary=route_to(from,to)
	if bool(planned.ok):return planned.points
	if not construction.building_state.is_empty():return PackedVector3Array()
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

func layout_approach(entry:Dictionary) -> Vector3:
	# The standing spot in front of a furnishing described by its layout record
	# alone (kind, x, z, rotation, level), for placement checks before a node exists.
	var size:Vector2=LifeCatalog.ITEMS.get(str(entry.get("kind","")),{}).get("size",Vector2(1,1))
	var level:int=int(entry.get("level",0))
	var forward:Vector3=Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0.0))))*Vector3(0,0,size.y*.5+.55)
	return Vector3(float(entry.x),Building.level_y(level),float(entry.z))+forward

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
	var cell:Vector2i=nearest_outdoor(Vector3((member_index-3.5)*.75,.16,8.5))
	return Vector3(cell.x*.25,.16,cell.y*.25)

func lot_return_position(member_index:int=0) -> Vector3:
	var cell:Vector2i=nearest_outdoor(Vector3((member_index%4-1.5)*.75,.16,6.5+(member_index/4)*.75))
	return Vector3(cell.x*.25,.16,cell.y*.25)

func outdoor_cell(cell:Vector2i) -> bool:
	# A garden room's interior is free floor, but a lot exit or return spot
	# must stay in the open so departures never walk into somebody's bedroom.
	if not navigation.region.has_point(cell):return false
	if navigation.is_point_solid(cell):return false
	return not construction.floor_contains(Vector2(cell.x*.25,cell.y*.25),0)

func nearest_outdoor(p:Vector3) -> Vector2i:
	var cell=Vector2i(roundi(p.x*4),roundi(p.z*4))
	var bounds:Rect2i=Building.cell_range()
	cell.x=clampi(cell.x,bounds.position.x,bounds.end.x-1)
	cell.y=clampi(cell.y,bounds.position.y,bounds.end.y-1)
	if outdoor_cell(cell):return cell
	for radius in range(1,14):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				if absi(x)!=radius and absi(z)!=radius:continue
				var c=cell+Vector2i(x,z)
				if navigation.region.has_point(c) and outdoor_cell(c):return c
	return nearest_free(p)

## Show a candidate look on a real actor without committing it. The wardrobe
## panel previews on the Lifelet standing in front of the mirror, so what the
## player sees is exactly what they would keep. The actor's own profile is kept
## so the preview can be dropped without a trace.
func set_actor_preview(id:String,look:Dictionary) -> void:
	var actor:LifeActor=actors.get(id)
	if not is_instance_valid(actor):return
	if not actor.has_meta("preview_profile"):
		actor.set_meta("preview_profile",actor.profile.duplicate(true))
	actor.apply_wardrobe(look)


func actor_preview(id:String) -> Dictionary:
	var actor:LifeActor=actors.get(id)
	return actor.profile.duplicate(true) if is_instance_valid(actor) else {}


func clear_actor_preview(id:String) -> void:
	var actor:LifeActor=actors.get(id)
	if not is_instance_valid(actor) or not actor.has_meta("preview_profile"):return
	var saved:Variant=actor.get_meta("preview_profile")
	actor.remove_meta("preview_profile")
	if saved is Dictionary:actor.apply_wardrobe(saved)


## The organic delivery van, parked outside while a grocery order is dropped off.
##
## It is scenery with the household's own sign on it: three leaves on a cream
## panel, so a player sees which van the order came in. It is created when the
## delivery is on its way and removed once it has been taken in.
var delivery_van: Node3D


## Bring the delivery van onto the street with its organic sign. Called when a
## delivery is due, so the arrival the notice describes is a thing the player
## can actually see.
func show_delivery_van() -> void:
	if is_instance_valid(delivery_van):
		return
	if not is_instance_valid(house):
		return
	var van: Node3D = load("res://assets/models/car_van.glb").instantiate()
	van.name = "OrganicDeliveryVan"
	house.add_child(van)
	van.position = Vector3(0, 0, 10.6)
	van.rotation.y = PI * .5
	assign_structure_layer(van, 0)
	# The sign: a cream panel on each flank with three leaves, so the van reads
	# as the organic grocer rather than any other vehicle.
	for sx: float in [-1.0, 1.0]:
		var panel: MeshInstance3D = box(van, Vector3(sx * .98, 1.35, -.3), Vector3(.04, .62, 1.5), "f4efe0")
		panel.set_meta("delivery_sign", true)
		for leaf: int in range(3):
			var offset: float = (float(leaf) - 1.0) * .42
			sphere(van, Vector3(sx * 1.01, 1.42, -.3 + offset), Vector3(.20, .26, .16), "5f8f52").set_meta("delivery_leaf", true)
		var word: Label3D = Label3D.new()
		word.text = "ORGANIC"
		word.font_size = 96
		word.pixel_size = .0032
		word.modulate = Color("3f6b3a")
		word.position = Vector3(sx * 1.04, 1.14, -.3)
		word.rotation.y = PI * .5 if sx > 0 else -PI * .5
		van.add_child(word)
	delivery_van = van


## Take the van away once the shopping has been carried in.
func hide_delivery_van() -> void:
	if is_instance_valid(delivery_van):
		delivery_van.queue_free()
	delivery_van = null


func set_actor_away(id:String,away:bool,unavailable:bool) -> bool:
	var actor:LifeActor=actors.get(id)
	if not is_instance_valid(actor):return false
	# A Lifelet left off this lot by a partial trip is not shown again by an
	# unrelated away-state refresh: the trip's own left-behind list owns them
	# until the party comes home.
	if bool(actor.get_meta("left_behind",false)):
		actor.visible=false
		return false
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

func begin_placement(kind:String,style:String="",size:String="") -> void:
	if construction:construction.cancel()
	clear_placement()
	placement_kind=kind
	placement_style=style
	placement_size=size
	placement_angle=0
	var path:String=Variants.model_path(kind,style)
	if not ResourceLoader.exists(path):path="res://assets/models/%s.glb" % kind
	ghost=load(path).instantiate()
	var scale:float=Variants.size_scale(size)
	if not is_equal_approx(scale,1.0):ghost.scale=Vector3.ONE*scale
	add_child(ghost)
	for n in ghost.find_children("*","MeshInstance3D",true,false):
		var m=StandardMaterial3D.new()
		m.albedo_color=Color(.38,.8,.63,.48)
		m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		n.material_override=m

func clear_placement() -> void:
	placement_kind=""
	placement_style=""
	placement_size=""
	if is_instance_valid(ghost):ghost.queue_free()
	ghost=null
	if construction:construction.cancel()

func begin_construction(tool:String) -> void:
	clear_placement()
	construction.begin(tool)

## The ground a furnishing may stand on: the lot itself at ground level, and a
## real slab upstairs. The garden is part of the lot, so a kennel, a garden bed
## or a bench all stand outside as readily as a chair stands inside a room.
func grounds(point:Vector2,level:int) -> bool:
	if construction.floor_contains(point,level):return true
	if level!=0:return false
	return Building.lot().has_point(point)

## Whether this style and size of a kind may stand here. `style` and `size`
## default to the family's own first choice, so every existing caller that knows
## only a kind keeps the behaviour it had.
func can_place(kind:String,p:Vector3,angle:float,style:String="",size_choice:String="") -> bool:
	if not LifeCatalog.ITEMS.has(kind) or not p.is_finite():return false
	var level:int=point_level(p)
	if level<0:return false
	var data:Dictionary=LifeCatalog.get_item(kind)
	var variant:Dictionary=Variants.resolve(data,{"style":style,"size":size_choice})
	var size:Vector2=Variants.footprint(data,str(variant.size))
	var depth:float=size.y
	if int(roundf(angle/90))%2:size=Vector2(size.y,size.x)
	var rect=Rect2(Vector2(p.x,p.z)-size/2,size)
	if LifeCatalog.wall_mounted(kind):
		# Wall decor sits flush against a wall, so only its room-facing half must
		# lie on the floor; the shift uses the unrotated depth at every angle.
		var forward:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3(0,0,1)
		rect.position+=Vector2(forward.x,forward.z)*(depth*.5+.04)
	if not construction.building_state.is_empty():
		# Level 0 stands on the lot itself, so the garden counts as ground. An
		# upper furnishing still needs real slab beneath it.
		if not Building.footprint_supported(construction.building_state,level,rect,level==0):return false
		if Building.blocked_rect(construction.building_state,level,rect):return false
		if not construction.building_state.roofs.is_empty() and not RoofRules.obstruction(construction.building_state,furnishing_volume({"kind":kind,"x":p.x,"z":p.z,"rotation":angle,"level":level,"style":variant.style,"size":variant.size})).is_empty():return false
	for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
		if not grounds(corner,level):return false
	if LifeCatalog.wall_mounted(kind) and not wall_behind(kind,p,angle,variant.size):return false
	if LifeCatalog.passable(kind):return true
	# Interior walls and doorways stay usable.
	if construction.rect_blocked(rect,level):return false
	for item in items:
		if item_level(item)!=level:continue
		if item.kind in ["meal","plate","puddle"] or bool(item.get("derived",false)) or LifeCatalog.passable(str(item.kind)):continue
		# A candidate stands free when it misses every solid band of what is
		# already there, so a car fits in the garage's hollow interior even
		# though the building's own declared outline covers that floor.
		for panel:Rect2 in item_panels(item):
			if rect.grow(.05).intersects(panel):return false
	return true

func wall_snap(kind:String,p:Vector3,reach:float=1.0,size_choice:String="") -> Dictionary:
	if not is_instance_valid(construction) or not LifeCatalog.ITEMS.has(kind):return {}
	var size:Vector2=Variants.footprint(LifeCatalog.get_item(kind),size_choice)
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

func wall_behind(kind:String,p:Vector3,angle:float,size_choice:String="") -> bool:
	# Wall-mounted decor needs a wall directly behind its back face on the same floor.
	if not is_instance_valid(construction) or not LifeCatalog.ITEMS.has(kind):return false
	var size:Vector2=Variants.footprint(LifeCatalog.get_item(kind),size_choice)
	var forward:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3(0,0,1)
	var back:Vector3=p-forward*(size.y*.5+.06)
	var level:int=point_level(p)
	for e in construction.records:
		if int(e.get("level",0))!=level:continue
		if construction.wall_rect(e).grow(.06).has_point(Vector2(back.x,back.z)):return true
	return false

func sight_line_clear(from:Vector3,to:Vector3) -> bool:
	# True when a straight line between two same-floor points meets no wall.
	# Conversation needs this: standing clear of furniture is not the same as
	# being able to see and speak to somebody across a partition. Walls are the
	# only occluders; open doorways (a wall split with a gap) stay clear because
	# the segment simply misses every remaining wall rectangle.
	if not from.is_finite() or not to.is_finite():return false
	var level:int=point_level(from)
	if level<0 or level!=point_level(to):return false
	var a:=Vector2(from.x,from.z);var b:=Vector2(to.x,to.z)
	if construction and not construction.building_state.is_empty():
		for wall:Dictionary in construction.building_state.walls:
			if int(wall.level)!=level:continue
			if _rect_crosses_segment(Building.rect(wall).grow(.02),a,b):return false
		return true
	if not is_instance_valid(construction):return true
	# Legacy meshes keep their own rectangles in `records`.
	for record:Dictionary in construction.records:
		if int(record.get("level",0))!=level:continue
		if _rect_crosses_segment(construction.wall_rect(record).grow(.02),a,b):return false
	return true

func _rect_crosses_segment(rect:Rect2,from:Vector2,to:Vector2) -> bool:
	# Rect2 has no segment test, so compare against its four edges. A segment
	# whose endpoints both fall inside the rectangle also blocks, matching two
	# bodies standing either side of a thick wall at close range.
	if rect.has_point(from) and rect.has_point(to):return true
	var corners:Array[Vector2]=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	for index:int in range(4):
		if Geometry2D.segment_intersects_segment(from,to,corners[index],corners[(index+1)%4])!=null:return true
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
		if ghost_valid:placement_requested.emit(placement_kind,ghost_position,placement_angle,placement_style,placement_size)
		return
	var origin=camera.project_ray_origin(screen)
	refresh_actor_layers()
	var ray=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*150,PICK_GROUND if view_level==0 else PICK_UPPER)
	# Food resting on a surface and wet patches lying under it are picked first,
	# on their own ray. See PICK_SURFACE: the furniture they sit on is a taller
	# box than the surface it offers, so a single ray reached the furniture every
	# time and the plate on the table could never be clicked.
	var surface:=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*150,PICK_SURFACE)
	var hit=get_world_3d().direct_space_state.intersect_ray(surface)
	if hit.is_empty():hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var id:String=str(hit.collider.get_meta("item_id",""))
		for item in items:
			if item.id==id:object_clicked.emit(item,screen);return
		var light:Dictionary=room_light_record(id)
		if not light.is_empty():object_clicked.emit(light,screen);return
		if actors.has(id) and not bool(actors[id].get_meta("away",false)):object_clicked.emit({"id":id,"kind":"neighbor","label":actors[id].get_meta("display_name"),"node":actors[id],"size":Vector2(.6,.6)},screen);return
		if pick_extras.has(id):object_clicked.emit((pick_extras[id] as Dictionary).duplicate(),screen);return
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


## One ceiling light per enclosed room, switched from the room's own control.
## The fixture is a flat disc plus a lit globe; `set_indoor_lights` toggles the
## globes and the matching OmniLight3D together, so the light is visible state.
func ceiling_light(parent:Node3D,at:Vector3,room:String) -> void:
	var fixture:MeshInstance3D=box(parent,at+Vector3(0,.09,0),Vector3(.42,.06,.42),"f6f1e4")
	fixture.name="LightFixture_"+room
	var dome:MeshInstance3D=sphere(parent,at+Vector3(0,0.0,0),Vector3(.20,.13,.20),"fff3d8")
	dome.name="LightDome_"+room
	var light:=OmniLight3D.new()
	light.name="IndoorLight_"+room
	light.position=at+Vector3(0,-.06,0)
	light.light_color=Color("ffe6bd");light.light_energy=1.05;light.omni_range=6.5
	light.shadow_enabled=false
	parent.add_child(light)
	# Clicking the fitting switches the room. The dome is a real pickable body,
	# and the derived record stays out of the saved layout: it is rebuilt from
	# the construction, never stored as furniture.
	var id:String="room_light_"+room
	var body:=StaticBody3D.new()
	body.collision_layer=PICK_GROUND if point_level(at)<=0 else PICK_UPPER
	dome.add_child(body)
	var shape:=CollisionShape3D.new()
	var bounds:=BoxShape3D.new()
	bounds.size=Vector3(.44,.34,.44)
	shape.shape=bounds
	body.add_child(shape)
	body.set_meta("item_id",id)
	var info:Dictionary={"id":id,"kind":"room_light","label":"%s light" % room.capitalize(),"node":fixture,"size":Vector2(.44,.44),"room":room,"derived":true,"level":0}
	indoor_lights.append({"room":room,"light":light,"dome":dome,"fixture":fixture,"info":info})

func room_light_record(id:String) -> Dictionary:
	# Room lights are part of the house, not furnishings: they are rebuilt from
	# the construction on every load and never enter the saved layout or the
	# item list. Picking still resolves them here so a Lifelet can switch one.
	for entry:Dictionary in indoor_lights:
		var info:Dictionary=entry.info
		if str(info.id)!=id:continue
		info["lit"]=is_instance_valid(entry.light) and entry.light.visible
		return info
	return {}

func set_indoor_lights(lit:bool,rooms:Array=[]) -> void:
	indoor_lights_lit=lit
	for entry:Dictionary in indoor_lights:
		if not rooms.is_empty() and str(entry.room) not in rooms:continue
		var light:OmniLight3D=entry.light
		var dome:MeshInstance3D=entry.dome
		if is_instance_valid(light):light.visible=lit
		if is_instance_valid(dome):dome.material_override=material("fff3d8" if lit else "c9c3b6")

func room_of(point:Vector3,level:int=0) -> String:
	# The nearest ceiling light on this floor names the room a Lifelet stands in.
	var best:String=""
	var nearest:float=INF
	for entry:Dictionary in indoor_lights:
		var light:OmniLight3D=entry.light
		if not is_instance_valid(light) or point_level(light.global_position)>1:continue
		if absf(light.global_position.y-(Building.level_y(level)+2.55))>0.6:continue
		var distance:float=Vector2(light.global_position.x-point.x,light.global_position.z-point.z).length()
		if distance<nearest:nearest=distance;best=str(entry.room)
	return best

func _process(delta:float) -> void:
	elapsed+=delta
	if not live_enabled:return
	refresh_actor_layers()
	if build_enabled and construction and not construction.tool.is_empty():construction.update_preview(floor_point(get_viewport().get_mouse_position()))
	if build_enabled and is_instance_valid(ghost):
		var p=floor_point(get_viewport().get_mouse_position())
		p.x=snappedf(p.x,.25);p.z=snappedf(p.z,.25)
		if LifeCatalog.wall_mounted(placement_kind):
			# Wall decor slides along the nearest wall and faces into the room.
			var snap:Dictionary=wall_snap(placement_kind,p,1.0,placement_size)
			if not snap.is_empty():p=snap.position;placement_angle=float(snap.angle)
		ghost.position=p
		ghost.rotation_degrees.y=placement_angle
		ghost_position=p
		ghost_valid=can_place(placement_kind,p,placement_angle,placement_style,placement_size)
		# The preview turns red for a spot the purchase would refuse for sealing a way.
		if ghost_valid and placement_reach_check.is_valid():ghost_valid=bool(placement_reach_check.call(placement_kind,p,placement_angle))
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

func item_lit(item:Dictionary)->bool:return bool(item.get("lit",true))

func set_item_lit(item:Dictionary,lit:bool)->void:
	item["lit"]=lit
	if is_instance_valid(item.get("node")):
		var glow:Node=item.node.find_child("LampGlow",true,false)
		if glow!=null:glow.visible=lit

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

## Beds a partnered pair shares: the left and right halves of the mattress.
const SHARED_BEDS: Array[String] = ["bed"]

## How many people one placed furnishing really seats. The catalogue declares it
## per size, so a large garden table that advertises ten places really holds ten
## and a loveseat holds two; everything else holds one.
func seat_capacity(item:Dictionary) -> int:
	var data:Dictionary=LifeCatalog.get_item(str(item.get("kind","")))
	if data.is_empty():return 1
	if str(item.kind) in SHARED_BEDS:return 2
	var variant:Dictionary=item.get("variant",{})
	var size:String=str(variant.get("size",""))
	return maxi(1,Variants.seats(data,size))

## The names of a furnishing's own places, in the order they are offered. A bed
## keeps its named halves, because a save and the intimacy action both name them;
## every other multi-seat furnishing numbers its places along its own width.
func seat_slots(item:Dictionary) -> Array[String]:
	if str(item.kind) in SHARED_BEDS:return ["left","right"]
	var count:int=seat_capacity(item)
	if count<=1:return [""]
	var out:Array[String]=[]
	for index:int in range(count):out.append("seat_%d" % index)
	return out

## The local offset of one place on a furnishing, spread evenly across its own
## footprint so the seats sit where the model's seats are.
func seat_slot_offset(item:Dictionary,slot:String) -> Vector3:
	if str(item.kind) in SHARED_BEDS:return Vector3(-.42 if slot=="left" else .42,0,0)
	var count:int=seat_capacity(item)
	if count<=1 or slot.is_empty():return Vector3.ZERO
	var index:int=slot.trim_prefix("seat_").to_int()
	index=clampi(index,0,count-1)
	# Half the usable width per gap, inset by a quarter of the span at each end,
	# so the outermost places stay on the model rather than at its edge.
	var span:float=float(item.get("size",Vector2(.6,.6)).x)*.8
	var step:float=span/float(maxi(1,count-1)) if count>1 else 0.0
	return Vector3(-span*.5+step*float(index),0,0)

func slot_approach(item:Dictionary,slot:String) -> Vector3:
	var n:Node3D=item.node
	var p:Vector3=n.to_global(seat_slot_offset(item,slot)+Vector3(0,0,item.size.y*.5+.55))
	if not construction.building_state.is_empty():return nearest_clear_point(p,item_level(item))
	var c=nearest_free(p)
	return Vector3(c.x*.25,.16,c.y*.25)

func activity_resource_ids(item:Dictionary,slot:String="") -> Array[String]:
	var shared_bed:bool=str(item.kind) in SHARED_BEDS
	if shared_bed:
		# A whole-bed claim plus the half: any second sleeper conflicts on the
		# bed itself, and only a partner is allowed to overlap the halves.
		return [str(item.id)+":"+slot,str(item.id)] if not slot.is_empty() else [str(item.id)]
	var resources:Array[String]=[str(item.id)+(":"+slot if seat_capacity(item)>1 and not slot.is_empty() else "")]
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
		for panel:Rect2 in item_panels(other):
			if panel.grow(.29).has_point(Vector2(at.x,at.z)):return false
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
		"bench","book_nook":
			# The nook's bench sits a little lower than a chair; the shelf
			# spines above it stay at the seated reader's eye line.
			local=Vector3(0,.41,.10) if str(item.kind)=="book_nook" else Vector3(0,.522,.05);yaw=node.rotation.y;kind="seat"
		"sofa":
			local=Vector3(0,.66,.08);yaw=node.rotation.y;kind="seat"
		"chair":
			local=Vector3(0,.52,.02);yaw=node.rotation.y;kind="seat"
		"toilet":
			local=Vector3(0,.615,.12);yaw=node.rotation.y;kind="seat"
		"bed":
			local=Vector3(0,.80,.015)+seat_slot_offset(item,str(landmarks.get("seat_slot","left")));yaw=node.rotation.y;kind="bed"
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
	actors.clear();items.clear();walls.clear();landscape_trees.clear();ceiling_beams.clear();indoor_lights.clear()
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
	actors.clear();items.clear();walls.clear();landscape_trees.clear();ceiling_beams.clear();indoor_lights.clear();starter_floor_nodes.clear();view_level=0
	house=Node3D.new();house.name="ResidentHome_"+place;add_child(house)
	construction=LifeConstruction.new();house.add_child(construction);construction.initialize(self)
	furniture=Node3D.new();furniture.name="Furniture";house.add_child(furniture)
	var palettes:Dictionary={
		"maya_home":{"plaster":"cbd8c2","floor":"bb9a73","board":"a98661","accent":"739781","leaf":"73966d"},
		"leo_home":{"plaster":"d5b39d","floor":"c9b299","board":"a98661","accent":"aa705c","leaf":"73966d"},
		"priya_home":{"plaster":"d9c6d4","floor":"b59a7e","board":"a8816a","accent":"8a6d84","leaf":"8bab70"},
		"tom_home":{"plaster":"c2c6ab","floor":"cbb18f","board":"b09a6e","accent":"6f8f5e","leaf":"6f8f5e"}}
	var palette:Dictionary=palettes.get(place,palettes["maya_home"])
	var cottage:bool=place in ["maya_home","priya_home"]
	var width:float={"maya_home":10.0,"leo_home":12.0,"priya_home":11.0,"tom_home":13.0}.get(place,12.0)
	var depth:float={"maya_home":9.0,"leo_home":8.0,"priya_home":8.0,"tom_home":8.0}.get(place,8.0)
	var plaster:String=str(palette.plaster)
	box(house,Vector3(0,-.3,0),Vector3(120,.3,120),"b8cdaa")
	box(house,Vector3(0,-.16,0),Vector3(17,.15,16),"a8c191")
	box(house,Vector3(0,-.025,0),Vector3(width+.4,.25,depth+.4),"d3c9b6")
	box(house,Vector3(0,.105,0),Vector3(width,.045,depth),str(palette.floor))
	# The narrow cottage uses long oak boards; the wide bungalow has parquet blocks.
	if cottage:
		for row:int in range(33):
			box(house,Vector3(-4.9+float(row)*.3,.162,0),Vector3(.009,.004,depth),str(palette.board))
			for joint:int in range(4):box(house,Vector3(-4.75+float(row)*.3,.163,-3.9+float(joint)*2.2+float(row%2)*.9),Vector3(.29,.004,.009),str(palette.board))
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
			box(house,Vector3(x,.35,5.9),Vector3(.8,.55,.65),str(palette.accent))
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
		if cottage:sphere(house,Vector3(x,.25,-6.0),Vector3(1.1,.65,.8),str(palette.leaf))
		else:
			box(house,Vector3(x,.35,-5.5),Vector3(.13,.85,.13),"a88667")
	box(house,Vector3(2,.5,7.7),Vector3(.12,1.1,.12),"a08060")
	box(house,Vector3(2,1.02,7.7),Vector3(.45,.35,.35),str(palette.accent))
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
