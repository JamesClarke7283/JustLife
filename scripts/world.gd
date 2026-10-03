extends Node3D
class_name LifeWorld
const ToyFlow = preload("res://scripts/toy_flow.gd")
const Building=preload("res://scripts/building_state.gd")
const RoofRules=preload("res://scripts/roof_rules.gd")
const Variants=preload("res://scripts/catalog_variants.gd")
const Kitchen=preload("res://scripts/kitchen_furnishings.gd")
const LotNavigation=preload("res://scripts/lot_navigation.gd")
const ActorMotion=preload("res://scripts/actor_motion.gd")
const GardenSwing=preload("res://scripts/garden_swing.gd")
const GateFlow=preload("res://scripts/gate_flow.gd")
const Road=preload("res://scripts/road.gd")
const WindowGeometry=preload("res://scripts/window_geometry.gd")
const PartyProps=preload("res://scripts/party_props.gd")
const PartyFood=preload("res://scripts/party_food.gd")
const MAX_FURNISHINGS:int=512
const VIEW_ENVIRONMENT:int=1
const VIEW_GROUND:int=2
const VIEW_UPPER:int=4
const VIEW_STAIRS:int=8
const VIEW_ACTOR_GROUND:int=16
const VIEW_ACTOR_UPPER:int=32
const PICK_GROUND:int=2
const PICK_UPPER:int=4
## One render layer for each storey's structure, one for the Lifelets standing on
## it, and one pick bit for clicking things on it. Level 0 and 1 keep the original
## ground/upper bits so older scenes and tests read the same.
const VIEW_LEVELS:Array[int]=[2,4,64,128]
const VIEW_ACTOR_LEVELS:Array[int]=[16,32,256,512]
const PICK_LEVELS:Array[int]=[2,4,8,16]
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
signal wall_clicked
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
## Household cleaning stations (chore_flow.gd), published so queued chores keep their target.
var chore_targets: Array = []
var _furnishing_volume_cache:Dictionary={}
var gate_flow=GateFlow.new(self)
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
## How high a wall piece hangs, in metres above the storey floor. The wheel
## moves it while the ghost is up. Floor furnishings leave this at 0.
var placement_hang: float = 0.0
var placement_color: String = ""
var placement_moving_id: String = ""
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
var _garden_vegetation:Array[Node3D]=[]
var ceiling_beams:Array[MeshInstance3D]=[]
var indoor_lights:Array[Dictionary]=[]
var indoor_lights_lit:bool=true
var _desk_boosters:Dictionary={}
var _garden_swings:Array[Node3D]=[]
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

## A gate is two posts and one or two leaves hung on hinge nodes, so the gate
## flow can swing them. The leaves are the `Tint` surfaces, which is how a
## player's colour choice reaches them; the posts and latch keep their finish.
func _build_garden_gate(parent: Node3D, wide: bool, colour: String = "c9c3a8", span: float = 0.0) -> void:
	if span <= 0.0:span = 2.0 if wide else 1.0
	var post := "6b5344"
	var leaf := colour if not colour.is_empty() else "c9c3a8"
	box(parent, Vector3(-span * .5, .6, 0), Vector3(.08, 1.2, .08), post).name = "GatePost_L"
	box(parent, Vector3(span * .5, .6, 0), Vector3(.08, 1.2, .08), post).name = "GatePost_R"
	if wide:
		var width: float = span * .5 - .06
		for side: String in ["L", "R"]:
			var sign: float = -1.0 if side == "L" else 1.0
			var hinge := Node3D.new()
			hinge.name = "GateHinge_" + side
			hinge.position = Vector3(sign * (span * .5 - .04), 0, 0)
			parent.add_child(hinge)
			# The leaf stands beside its hinge, toward the middle of the gate.
			box(hinge, Vector3(-sign * (width * .5 + .02), .58, 0), Vector3(width, 1.05, .04), leaf).name = "TintLeaf_" + side
		# The catch is on the leaf that swings, at the centre of the closed gate.
		var catch_hinge: Node3D = parent.get_node("GateHinge_L") as Node3D
		box(catch_hinge, Vector3(span * .5 - .04, .7, .03), Vector3(.04, .16, .04), post).name = "GateLatch"
	else:
		var hinge := Node3D.new()
		hinge.name = "GateHinge_L"
		hinge.position = Vector3(-span * .5 + .04, 0, 0)
		parent.add_child(hinge)
		box(hinge, Vector3((span - .1) * .5 + .02, .58, 0), Vector3(span - .1, 1.05, .04), leaf).name = "TintLeaf_L"
		box(hinge, Vector3(span * .78 - .04, .62, .03), Vector3(.04, .08, .04), "c8a562").name = "GateLatch"

## Fence panels laid end to end to fill a chosen length. The count is the nearest
## whole number of authored panels and each is stretched a little to share the
## run equally, so no panel is ever cut or stretched far from its design.
func _build_fence_run(scene: PackedScene, data: Dictionary, size: String) -> Node3D:
	var dims: Vector2 = Variants.custom_dims(data, size)
	var run := Node3D.new()
	run.name = "FenceRun"
	var module: float = maxf(.1, float(data.size.x))
	var count: int = maxi(1, roundi(dims.x / module))
	var each: float = dims.x / float(count)
	var tall: float = dims.y / maxf(.01, float(data.height))
	for index: int in range(count):
		var panel: Node3D = scene.instantiate()
		panel.name = "FencePanel_%d" % index
		panel.scale = Vector3(each / module, tall, 1.0)
		panel.position = Vector3(-dims.x * .5 + each * (float(index) + .5), 0, 0)
		run.add_child(panel)
	return run


func _build_bath_mat(parent: Node3D, variant: Dictionary) -> void:
	var colour: String = str(variant.get("color", "f4f1ea"))
	var style: String = str(variant.get("style", "plush"))
	if style == "oval":
		var disc := MeshInstance3D.new()
		disc.name = "TintOval"
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.28
		mesh.bottom_radius = 0.34
		mesh.height = 0.035
		disc.mesh = mesh
		disc.material_override = material(colour)
		disc.position = Vector3(0, 0.02, 0)
		disc.scale.z = 1.6
		parent.add_child(disc)
		return
	if style == "grid":
		for x: int in range(-1, 2):
			for z: int in range(-1, 2):
				box(parent, Vector3(float(x) * 0.18, 0.02, float(z) * 0.28), Vector3(0.14, 0.03, 0.22), colour).name = "TintPad_%d_%d" % [x,z]
		return
	box(parent, Vector3(0, 0.025, 0), Vector3(0.62, 0.045, 1.05), colour).name = "TintPlush"


func _build_framed_picture(parent: Node3D, variant: Dictionary) -> void:
	var frame: String = str(variant.get("color", "5c3a24"))
	var theme: String = str(variant.get("style", "scenic"))
	var inner: String = {"animals": "c97c66", "scenic": "7eb6a2", "people": "d7ae7e"}.get(theme, "7eb6a2")
	box(parent, Vector3(0, 0.0, 0), Vector3(0.70, 0.52, 0.04), frame)
	box(parent, Vector3(0, 0.0, 0.02), Vector3(0.54, 0.36, 0.02), inner)
	if theme == "animals":
		box(parent, Vector3(-0.08, -0.04, 0.035), Vector3(0.10, 0.08, 0.01), "3a3d42")
		box(parent, Vector3(0.10, -0.02, 0.035), Vector3(0.12, 0.10, 0.01), "e6d8c5")
	elif theme == "people":
		box(parent, Vector3(0, 0.06, 0.035), Vector3(0.12, 0.12, 0.01), "e6c2a0")
		box(parent, Vector3(0, -0.08, 0.035), Vector3(0.18, 0.14, 0.01), "1f3b6b")
	else:
		box(parent, Vector3(0, 0.08, 0.035), Vector3(0.40, 0.10, 0.01), "c8d7e0")
		box(parent, Vector3(0, -0.06, 0.035), Vector3(0.46, 0.12, 0.01), "4a6b5c")


## A small soft toy built from plain shapes, so a toy a child leaves out needs no
## shipped mesh. Every style stands within a 0.2 m footprint and is under 0.16 m high.
func _build_kids_toy(parent: Node3D, variant: Dictionary) -> void:
	match str(variant.get("style", "block")):
		"ball":
			sphere(parent, Vector3(0, .07, 0), Vector3(.14, .14, .14), "c9604f")
			box(parent, Vector3(0, .07, 0), Vector3(.145, .03, .145), "f2ead8")
		"bear":
			sphere(parent, Vector3(0, .06, 0), Vector3(.12, .11, .10), "a77a52")
			sphere(parent, Vector3(0, .15, .01), Vector3(.085, .08, .08), "b58a60")
			sphere(parent, Vector3(-.035, .205, .01), Vector3(.03, .03, .03), "a77a52")
			sphere(parent, Vector3(.035, .205, .01), Vector3(.03, .03, .03), "a77a52")
			sphere(parent, Vector3(0, .14, .06), Vector3(.035, .03, .03), "e0c9a6")
		"rattle":
			cylinder(parent, Vector3(0, .07, 0), .012, .14, "d7ae7e")
			sphere(parent, Vector3(0, .145, 0), Vector3(.09, .09, .09), "c97c66")
			sphere(parent, Vector3(0, .0, 0), Vector3(.04, .04, .04), "d7ae7e")
		"duck":
			sphere(parent, Vector3(0, .05, 0), Vector3(.13, .09, .16), "e8c547")
			sphere(parent, Vector3(0, .115, .06), Vector3(.075, .075, .075), "ecd05b")
			box(parent, Vector3(0, .105, .105), Vector3(.045, .018, .04), "d8803a")
		_:
			box(parent, Vector3(-.04, .035, 0), Vector3(.07, .07, .07), "c9604f")
			box(parent, Vector3(.04, .035, .01), Vector3(.07, .07, .07), "6f8fa8")
			box(parent, Vector3(0, .105, 0), Vector3(.07, .07, .07), "e8c547")


func _build_memorial(parent: Node3D) -> void:
	# Original garden stone: a low tablet and a small offering dish. Built here
	# so a household can remember someone without a shipped mesh.
	box(parent, Vector3(0, 0.08, 0), Vector3(0.62, 0.16, 0.42), "8c8a84")
	box(parent, Vector3(0, 0.28, -0.04), Vector3(0.46, 0.28, 0.10), "6f6c66")
	box(parent, Vector3(0, 0.18, 0.14), Vector3(0.16, 0.04, 0.16), "c8a562")

## Draw a code-made kind (LifeCatalog.PROCEDURAL) under `parent`. The placed piece, its
## placement ghost and the shop thumbnail all come through here, so they cannot disagree
## about which kinds are drawn from code. The result is the node a colour choice repaints:
## the party model, or `parent` itself for a gate whose leaves carry the Tint surfaces.
## The other pieces paint their colour as they are built and return null.
func build_procedural(parent: Node3D, kind: String, variant: Dictionary, data: Dictionary = {}) -> Node3D:
	if data.is_empty():data = LifeCatalog.get_item(kind)
	if PartyProps.builds(kind):
		var model: Node3D = PartyProps.build(kind, variant)
		parent.add_child(model)
		return model
	if kind == "home_phone":_build_home_phone(parent)
	elif kind == "burglar_alarm":_build_burglar_alarm(parent)
	elif kind == "bath_mat":_build_bath_mat(parent, variant)
	elif kind == "framed_picture":_build_framed_picture(parent, variant)
	elif kind == "kids_toy":_build_kids_toy(parent, variant)
	elif LifeCatalog.is_gate(kind):
		_build_garden_gate(parent, float(data.size.x) > 1.5, str(variant.color), float(data.size.x))
		return parent # the recolour finds the leaves' Tint surfaces beneath it
	else:_build_memorial(parent)
	return null

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
	layout=ToyFlow.normalize_layout(normalize_layout_rotations(layout))
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
	# The rear entrance has a clear aisle between the bathroom fixtures.
	wall(Vector3(-1.575,1.4,-5.04),Vector3(9.05,2.6,.16),"eae7d7",false)
	wall(Vector3(5.125,1.4,-5.04),Vector3(1.95,2.6,.16),"eae7d7",false)
	# Door frames and leaves are derived from the real openings, so they follow
	# the wall toggle and Build edits together with the rest of the enclosure.
	box(house,Vector3(3.55,.05,-5.55),Vector3(1.3,.16,1.15),"c7bea9")
	wall(Vector3(-6.04,1.4,0),Vector3(.16,2.6,10.1),"8faf9f",false)
	wall(Vector3(6.04,.4,0),Vector3(.16,.6,10.1),"e6d8c5",true)
	wall(Vector3(-3.55,.4,5.04),Vector3(5.1,.6,.16),"e6d8c5",true)
	wall(Vector3(3.55,.4,5.04),Vector3(5.1,.6,.16),"e6d8c5",true)
	wall(Vector3(1,.47,-3.0625),Vector3(.13,.72,3.975),"e4dfce",true)
	wall(Vector3(1,.47,2.7),Vector3(.13,.72,4.6),"e4dfce",true)
	wall(Vector3(1.9,.47,-1.15),Vector3(1.8,.72,.13),"e4dfce",true)
	wall(Vector3(5.0,.47,-1.15),Vector3(2.1,.72,.13),"e4dfce",true)
	for x in [-4.25,-1.25]: window_panel(Vector3(x,1.78,-4.945),false)
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
	var back_skirting:MeshInstance3D=box(house,Vector3(-1.575,.24,-4.94),Vector3(9.05,.18,.04),"fcf5e6")
	back_skirting.set_meta("wall_decoration",true);back_skirting.set_meta("wall_support_normal",Vector3.FORWARD)
	var side_skirting:MeshInstance3D=box(house,Vector3(-5.94,.24,0),Vector3(.04,.18,10),"fcf5e6")
	side_skirting.set_meta("wall_decoration",true);side_skirting.set_meta("wall_support_normal",Vector3.LEFT)
	box(house,Vector3(0,.02,5.72),Vector3(2.4,.2,1.35),"c7bea9")
	box(house,Vector3(0,-.025,7.1),Vector3(1.75,.08,1.8),"dcd5be")
	# Two low steps from the porch down to the path: a front entry worth sweeping.
	box(house,Vector3(0,.04,6.58),Vector3(2.1,.09,.38),"d3ccb6")
	box(house,Vector3(0,.03,6.94),Vector3(1.9,.06,.34),"cfc8b1")
	# The house's own foundation beds and doorstep flowers stay beside the
	# building; the lawn, hedges, street and trees belong to draw_ground(), which
	# is redrawn whenever the household buys a neighbouring plot.
	for x in [-6.85,6.85]:
		for z in range(-5,5):
			if z%2==0:
				var bush:MeshInstance3D=sphere(house,Vector3(x,.16,z),Vector3(.68,.34,.65),"84a366")
				_register_vegetation(bush,"bush")
	# Keep planting identities stable across repeated reconstruction of this home.
	rng.seed=91517
	for x in [-3.5,3.5]:
		for i in range(12):
			var p=Vector3(x+rng.randf_range(-.9,.9),-.09,6.8+rng.randf_range(-.45,.45))
			flower_clump(p, rng, "d4868e" if i%2 else "f5e5ad")
	rebuild_build_grid()
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

## Older pets accumulated full turns while playing. Full turns do not change an
## object's pose and must not make its entire saved home unloadable. Work on a
## copy so admission never edits the save, and leave invalid values for the
## normal transform validator to reject.
static func normalize_layout_rotations(layout:Array) -> Array:
	var normalized:Array=layout.duplicate(true)
	for entry:Variant in normalized:
		if not entry is Dictionary or str(entry.get("kind",""))=="__construction":continue
		var angle:Variant=entry.get("rotation")
		if (angle is int or angle is float) and is_finite(float(angle)):
			entry["rotation"]=fmod(float(angle),360.0)
	return normalized

func validate_home_layout(layout:Variant) -> String:
	if not layout is Array or layout.size()>1024:return "Invalid home layout."
	layout=normalize_layout_rotations(layout)
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
		if not Building.number(entry.get("level",0),0,Building.MAX_LEVEL,true):return "Invalid furnishing level."
		for key:String in ["x","z","rotation"]:
			if not Building.number(entry.get(key,0),-10000,10000):return "Invalid furnishing transform."
		if not Building.lot().encloses(furnishing_rect(entry)):return "A furnishing extends beyond the navigable lot."
	# Align ingress with the detached graph's obstacle bound so a valid layout
	# cannot replace the live scene and only then fail graph construction.
	if ids.size()>MAX_FURNISHINGS:return "Too many furnishings for this lot."
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))=="__construction":continue
		var level:int=int(entry.get("level",0))
		if level>=1 and canonical.is_empty():return "Upper furniture needs a validated building with that storey."
		if canonical.is_empty():continue # Preserve old ground layout migration behavior.
		# Everything below is asked of each solid band rather than of the whole
		# declared outline, so a kind with an open interior is judged on the
		# floor it really covers. The roof test stays on the whole volume: the
		# garage's roof slab is genuinely under the home's own roof and only the
		# volume can say so.
		# Judged on the declared footprint, not the walking hull: a layout that
		# was legal when it was made must stay loadable and editable.
		for area:Rect2 in furnishing_panels(entry,false):
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
func furnishing_panels(entry:Dictionary,solid:bool=true) -> Array[Rect2]:
	var origin:=Vector2(float(entry.get("x",0)),float(entry.get("z",0)))
	var basis:Basis=_furnishing_basis(entry)
	# The buy size and style ride the layout record or the live variant; either
	# way the solid bands must match the water or furniture the mesh really
	# covers. A live item's own `size` key is its footprint (a Vector2), not the
	# size choice: reading that as the choice left every medium or large
	# furnishing, pools included, blocking only its small footprint.
	var listed:Variant=entry.get("size","")
	var size_choice:String=listed if listed is String else ""
	var style:String=str(entry.get("style",""))
	var variant_data:Variant=entry.get("variant",{})
	if variant_data is Dictionary:
		if size_choice.is_empty():size_choice=str((variant_data as Dictionary).get("size",""))
		if style.is_empty():style=str((variant_data as Dictionary).get("style",""))
	var result:Array[Rect2]=[]
	for panel:Dictionary in LifeCatalog.local_panels(str(entry.get("kind","")),size_choice,style,solid):
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
func item_panels(item:Dictionary,solid:bool=true) -> Array[Rect2]:
	var variant:Dictionary=item.get("variant",{}) if item.get("variant",{}) is Dictionary else {}
	var source:Dictionary={"kind":str(item.kind),"x":item.node.position.x,"z":item.node.position.z,"rotation":item.node.rotation_degrees.y,"size":str(variant.get("size","")),"style":str(variant.get("style",""))}
	return furnishing_panels(source,solid)

## The navigation obstacle records an entry contributes: one per solid band, and
## a band's record reuses the entry's own identity unless there are several, so
## a single-box furnishing keeps exactly the obstacle identity it always had.
func furnishing_obstacles(entry:Dictionary,level:int,solid:bool=true) -> Array:
	var areas:Array[Rect2]=furnishing_panels(entry,solid)
	var result:Array=[]
	var id:String=str(entry.get("id",""))
	for index:int in range(areas.size()):
		# A navigation obstacle must lie inside the lot, and a pool's coping may
		# reach past the edge the placement rule measured, so the band is clipped
		# to the lot exactly as the parked van's is.
		var area:Rect2=areas[index].intersection(Building.lot())
		if not area.is_equal_approx(areas[index]):area=area.grow(-.001)
		if area.size.x<=0.0 or area.size.y<=0.0:continue
		var identifier:String=id if areas.size()==1 else "%s_%d"%[id,index]
		# `item` names the furnishing however many bands it has, so a blocked-route
		# notice can tell the player which piece to move.
		result.append({"id":identifier,"level":level,"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y,"item":id})
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
	var data:Dictionary=LifeCatalog.get_item(kind)
	var hanging:bool=LifeCatalog.wall_mounted(kind) and data.has("hang")
	var style:String=Variants.style_or_default(str(entry.get("style","")),data)
	var cache_key:String=kind+"|"+style
	if not _furnishing_volume_cache.has(cache_key):
		# The authored mesh is measured once at its own size; the declared box is
		# the authored footprint and height, and the size choice scales both, so
		# the envelope follows the size the player actually bought.
		var box:=AABB(Vector3(-data.size.x*.5,0,-data.size.y*.5),Vector3(data.size.x,data.height,data.size.y))
		if hanging:box.position.y=-float(data.height)*.5
		var path:String=Variants.model_path(kind,style)
		if ResourceLoader.exists(path):
			var scene:Node3D=load(path).instantiate();var vertices:Array[Vector3]=[]
			_normalize_wall_model(scene,kind)
			_gather_visual_bounds(scene,Transform3D.IDENTITY,vertices);scene.free()
			if hanging and not vertices.is_empty():box=AABB(vertices[0],Vector3.ZERO)
			for point:Vector3 in vertices:box=box.expand(point)
		_furnishing_volume_cache[cache_key]=box
	var local:AABB=_scaled_volume(_furnishing_volume_cache[cache_key],Variants.volume_scale(data,str(entry.get("size",""))))
	var lift:float=float(entry.get("hang",data.get("hang",0.0) if hanging else 0.0))
	var transform:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0)))),Vector3(float(entry.get("x",0)),Building.level_y(int(entry.get("level",0)))+lift,float(entry.get("z",0))))
	return transform*local

## An authored envelope scaled by a size choice, about its own origin.
##
## Godot 4 removed `AABB * float`, so the envelope is rebuilt from its two
## corners instead: the origin scales with the box, because the authored model is
## centred on its own footprint and a larger table grows outward from the middle.
static func _scaled_volume(box:AABB,scale:Variant) -> AABB:
	var factor:Vector3=scale if scale is Vector3 else Vector3.ONE*float(scale)
	if factor.is_equal_approx(Vector3.ONE):
		return box
	return AABB(box.position*factor,box.size*factor)

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
	_assign_layers(node,view_layer(level))

## The render layer of a storey's structure and furnishings.
static func view_layer(level:int) -> int:return VIEW_LEVELS[clampi(level,0,Building.MAX_LEVEL)]
## The render layer of the Lifelets standing on a storey.
static func actor_layer(level:int) -> int:return VIEW_ACTOR_LEVELS[clampi(level,0,Building.MAX_LEVEL)]
## The pick bit for clicking things on a storey.
static func pick_layer(level:int) -> int:return PICK_LEVELS[clampi(level,0,Building.MAX_LEVEL)]
## Every storey's Lifelet layer at once, for a body between floors on the stairs.
static func all_actor_layers() -> int:
	var mask:int=0
	for layer:int in VIEW_ACTOR_LEVELS:mask|=layer
	return mask
## Every storey's pick bit at once.
static func all_pick_layers() -> int:
	var mask:int=0
	for layer:int in PICK_LEVELS:mask|=layer
	return mask
## The structure layers of every storey up to and including this one: looking at
## an upper floor still shows the floors beneath it.
static func view_layers_through(level:int) -> int:
	var mask:int=0
	for index:int in clampi(level,0,Building.MAX_LEVEL)+1:mask|=VIEW_LEVELS[index]
	return mask

func assign_stair_layer(node:Node) -> void:_assign_layers(node,VIEW_STAIRS)

func item_level(item:Dictionary) -> int:
	if Building.number(item.get("level"),0,Building.MAX_LEVEL,true):return int(item.level)
	if is_instance_valid(item.get("node")):return clampi(roundi((item.node.global_position.y-Building.GROUND_Y)/Building.RISE),0,Building.MAX_LEVEL)
	return 0

func point_level(point:Vector3) -> int:
	if not point.is_finite():return -1
	for level:int in Building.MAX_LEVEL+1:
		if absf(point.y-Building.level_y(level))<.025:return level
	return -1

## The highest storey that can be looked at or built on: one above the top floor
## the home has, so an empty storey can be started, and never past the fourth.
func viewable_top() -> int:
	if not is_instance_valid(construction) or construction.building_state.is_empty():return 0
	return mini(Building.MAX_LEVEL,Building.highest_level(construction.building_state)+1)

func set_view_level(level:int) -> bool:
	if level<0 or level>Building.MAX_LEVEL or (level>=1 and (not is_instance_valid(construction) or construction.building_state.is_empty())):return false
	if level>viewable_top():return false
	var changed:bool=level!=view_level
	if changed:clear_placement()
	view_level=level
	# Lowered walls follow the storey in view: the floors beneath keep theirs up.
	if changed and is_instance_valid(construction) and cutaway:construction.refresh_decorations()
	if construction:construction.build_level=level
	if grid:grid.position.y=Building.RISE*level
	camera.cull_mask=VIEW_ENVIRONMENT|VIEW_STAIRS|view_layers_through(level)|actor_layer(level)
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
		var visual_mask:int=all_actor_layers() if level<0 else actor_layer(level)
		_assign_layers(actor,visual_mask)
		for body:Node in bodies:
			body.collision_layer=0 if away else (all_pick_layers() if level<0 else pick_layer(level))
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
	assign_structure_layer(root,clampi(floori((p.y-Building.GROUND_Y)/Building.RISE),0,Building.MAX_LEVEL))

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
	_register_vegetation(tree_root,"tree")

## Authored planting is tracked separately from purchased furnishings. Its stable
## identity survives a ground redraw; hidden plants remain available for undo.
func _register_vegetation(node:Node3D,kind:String,footprint:Rect2=Rect2())->void:
	if not footprint.has_area():
		var vertices:Array[Vector3]=[]
		_gather_visual_bounds(node,Transform3D.IDENTITY,vertices)
		if vertices.is_empty():return
		var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
		for vertex:Vector3 in vertices:
			low=low.min(Vector2(vertex.x,vertex.z));high=high.max(Vector2(vertex.x,vertex.z))
		footprint=Rect2(low,high-low)
	var id:String="%s_%d_%d" % [kind,roundi(node.position.x*1000),roundi(node.position.z*1000)]
	node.set_meta("garden_decoration",true)
	node.set_meta("vegetation_id",id)
	node.set_meta("vegetation_footprint",footprint)
	_garden_vegetation.append(node)

func _live_vegetation()->Array[Node3D]:
	_garden_vegetation=_garden_vegetation.filter(func(node:Node3D)->bool:return is_instance_valid(node) and not node.is_queued_for_deletion() and is_instance_valid(house) and house.is_ancestor_of(node))
	return _garden_vegetation

## A quote records only planting touched by newly placed or changed ground
## walls/floors. It never changes visibility or the committed construction state.
func construction_clearance_areas(before:Dictionary,after:Dictionary)->Array[Rect2]:
	var changed:Array[Rect2]=[]
	for group:String in ["walls","floors"]:
		for record:Dictionary in after.get(group,[]):
			if int(record.get("level",0))!=0:continue
			var old:Dictionary=Building.find(before,str(record.id))
			var area:Rect2=Building.rect(record)
			if not old.is_empty() and int(old.get("level",0))==0 and Building.rect(old).is_equal_approx(area):continue
			changed.append(area)
	return changed

func vegetation_clearance(before:Dictionary,after:Dictionary)->Array:
	var cleared:Array=before.get("cleared_vegetation",[]).duplicate()
	var changed:Array[Rect2]=construction_clearance_areas(before,after)
	if changed.is_empty():return cleared
	for node:Node3D in _live_vegetation():
		var id:String=str(node.get_meta("vegetation_id"))
		if cleared.has(id):continue
		var footprint:Rect2=node.get_meta("vegetation_footprint")
		for area:Rect2 in changed:
			if footprint.intersects(area):cleared.append(id);break
	cleared.sort()
	return cleared

func refresh_vegetation()->void:
	if not is_instance_valid(construction):return
	for node:Node3D in _live_vegetation():
		node.visible=not construction.cleared_vegetation.has(str(node.get_meta("vegetation_id")))
		if not node.visible:continue
		var footprint:Rect2=node.get_meta("vegetation_footprint")
		for record:Dictionary in construction.records+construction.floor_records:
			if int(record.get("level",0))==0 and footprint.intersects(Building.rect(record)):
				node.visible=false;break

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
		for x in range(int(west_edge)+1,int(east_edge)):
			_register_vegetation(sphere(parent,Vector3(x,.25,z),Vector3(1.0,.64,.80),"71945e"),"hedge")
	for side_x:float in [west_edge+.85, east_edge-.85]:
		var span:int=int(maxf(1.0,(ground.end.y-2.0)-back_edge))
		for step:int in range(span):
			var z:float=back_edge+1.0+float(step)
			_register_vegetation(sphere(parent,Vector3(side_x,.25,z),Vector3(.9,.5,.80),"71945e"),"hedge")
	# The street stays where it is: the lot grows away from the frontage.
	box(parent,Vector3(0,-.02,Road.SIDEWALK_Z),Vector3(Road.SIDEWALK_LENGTH,.10,Road.SIDEWALK_WIDTH),"e0d9c7")
	box(parent,Vector3(0,-.07,Road.ROAD_CENTER_Z),Vector3(Road.ROAD_LENGTH,.12,Road.ROAD_WIDTH),"798781")
	for x in range(-30,31,5): box(parent,Vector3(x,.003,Road.ROAD_CENTER_Z),Vector3(2,.009,.08),"e6ddbc")
	for x in [-23,25]: neighbor_home(Vector3(x,0,-1))
	# A simple open mailbox with a brass house number plate.
	box(parent,Vector3(2,.52,7.8),Vector3(.10,1.1,.10),"ab7951")
	box(parent,Vector3(2,1.06,7.8),Vector3(.45,.35,.33),"397e70")
	box(parent,Vector3(2,1.07,7.98),Vector3(.26,.05,.008),"c8a562")
	rebuild_build_grid()
	refresh_vegetation()


## The Build-mode construction grid covers the whole owned lot (every bought
## plot), not only the starter footprint. The street/south sidewalk stays outside
## the lot rectangle, so growing the grid never swallows the car exit.
func rebuild_build_grid() -> void:
	if not is_instance_valid(house):return
	var was_visible:bool=is_instance_valid(grid) and grid.visible
	if is_instance_valid(grid):
		grid.queue_free()
		grid=null
	grid=Node3D.new();grid.name="BuildGrid";house.add_child(grid)
	var ground:Rect2=Building.lot()
	var step:float=.5
	var x0:float=snappedf(ground.position.x,step)
	var x1:float=snappedf(ground.end.x,step)
	var z0:float=snappedf(ground.position.y,step)
	var z1:float=snappedf(ground.end.y,step)
	var cx:float=ground.get_center().x
	var cz:float=ground.get_center().y
	var width:float=maxf(step,ground.size.x)
	var depth:float=maxf(step,ground.size.y)
	var x:float=x0
	while x<=x1+0.001:
		box(grid,Vector3(x,.17,cz),Vector3(.012,.005,depth),"a6bca9")
		x+=step
	var z:float=z0
	while z<=z1+0.001:
		box(grid,Vector3(cx,.17,z),Vector3(width,.005,.012),"a6bca9")
		z+=step
	grid.visible=was_visible or build_enabled
	grid.position.y=Building.RISE*float(view_level)


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
	if not Building.number(entry.get("level",0),0,Building.MAX_LEVEL,true):return
	var level:int=int(entry.get("level",0))
	if level>=1 and (not is_instance_valid(construction) or construction.building_state.is_empty()):return
	var data:Dictionary=LifeCatalog.get_item(kind)
	var variant:Dictionary=Variants.resolve(data,entry)
	var path:String=Variants.model_path(kind,str(variant.style))
	var has_model:bool=ResourceLoader.exists(path)
	var kitchen_cabinet:bool=Kitchen.cabinet(kind)
	if not has_model and not kitchen_cabinet and not LifeCatalog.procedural(kind):return
	var node=Node3D.new()
	node.name=str(entry.get("id","item_%d" % Time.get_ticks_usec()))
	furniture.add_child(node)
	var model:Node3D=null
	if kitchen_cabinet:
		model=Kitchen.build(kind,variant)
		node.add_child(model)
	elif has_model:
		if Variants.custom_dims(data,str(variant.size))!=Vector2.ZERO:
			# A run of any length is whole panels laid end to end.
			model=_build_fence_run(load(path),data,str(variant.size))
			node.add_child(model)
		else:
			model=load(path).instantiate()
			node.add_child(model)
			# A size choice scales the whole authored model uniformly, so a large
			# table is the same object made bigger rather than a stretched one.
			var scale:float=Variants.size_scale(str(variant.size))
			if not is_equal_approx(scale,1.0):model.scale=Vector3.ONE*scale
	else:
		model=build_procedural(node,kind,variant,data)
	if is_instance_valid(model):
		var fitted:float=float(data.get("model_scale",1.0))
		if not is_equal_approx(fitted,1.0):model.scale*=fitted
		model.scale*=Kitchen.model_scale(kind)
		_normalize_wall_model(model,kind)
	# The study desk's own model already carries the laptop, so none is added.
	var lift:float=float(entry.get("hang",data.get("hang",0.0) if LifeCatalog.wall_mounted(kind) else 0.0))
	node.position=Vector3(float(entry.get("x",0)),Building.level_y(level)+lift,float(entry.get("z",0)))
	node.rotation_degrees.y=fmod(float(entry.get("rotation",0)),360.0)
	# Cars bought or placed near a garage snap into the next free bay so a
	# four-car garage fills predictably instead of stacking on the driveway.
	if kind in ["car", "car_electric", "electric_car"] and level == 0:
		var bay: Dictionary = _nearest_garage_bay(node.position, str(entry.get("id", "")))
		if not bay.is_empty():
			node.position = Vector3(float(bay.x), Building.level_y(level), float(bay.z))
			node.rotation_degrees.y = float(bay.rotation)
			entry["x"] = node.position.x
			entry["z"] = node.position.z
			entry["rotation"] = node.rotation_degrees.y
	if is_instance_valid(model):_apply_variant_colour(model,data,variant)
	if kind=="house_window" and is_instance_valid(model):
		# Authored origin is the pane centre; lift it to the usual wall height.
		model.position.y=1.62
		model.position.z=-.045
		_catalog_window_glass(model)
		# These bounds use the furnishing's floor origin, including its lift.
		_catalog_window_geometry(node)
		node.set_meta("wall_decoration",true)
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
	# A party platter keeps the servings it has left (the model shows that many), and a
	# gathering table may wear a festive cloth: both are settings on the layout record.
	info.erase("cloth");info.erase("servings")
	if kind=="party_food":
		info["servings"]=PartyFood.clean(entry.get("servings"),int(data.get("servings",0)))
		PartyProps.show_servings(model,int(info.servings))
	if kind in PartyProps.CLOTH_HOSTS and LifeCatalog._shade(str(entry.get("cloth",""))):
		info["cloth"]=str(entry.cloth)
		node.add_child(PartyProps.build_cloth(str(entry.cloth)))
	assign_structure_layer(node,level)
	var body=StaticBody3D.new()
	body.collision_layer=pick_layer(level)
	node.add_child(body)
	# A toy nested in a box is out of sight and cannot be clicked.
	if str(entry.get("box_id",""))!="":
		node.visible=false
		body.collision_layer=0
	# One box per solid band, from the same catalogue data the placement, the
	# navigation obstacle and the build quote read. The bands are local metres
	# and the node already carries the placement's position and yaw, so an
	# ordinary furnishing gets exactly the single box it always had while a
	# kind with an open interior keeps its bays walkable — which is what lets a
	# car park inside the two-car garage and the player click its wall to sell it.
	for panel:Dictionary in LifeCatalog.local_panels(kind,str(variant.size),str(variant.style)):
		var shape=CollisionShape3D.new()
		var bounds=BoxShape3D.new()
		bounds.size=Vector3(float(panel.w),info.height,float(panel.d))
		shape.shape=bounds
		shape.position=Vector3(float(panel.x),float(info.height)/2,float(panel.z))
		if LifeCatalog.wall_mounted(kind) and (data.has("hang") or kind=="house_window"):
			# A wall model may extend below its attachment origin. Pick its real
			# raised picture/clock, without a tall invisible box above the wall.
			var vertices:Array[Vector3]=[]
			_gather_visual_bounds(node,node.transform.affine_inverse(),vertices)
			if not vertices.is_empty():
				var visual:=AABB(vertices[0],Vector3.ZERO)
				for point:Vector3 in vertices:visual=visual.expand(point)
				bounds.size=visual.size.max(Vector3.ONE*.01)
				shape.position=visual.get_center()
		body.add_child(shape)
	# The platter sits inside the box of the table that carries it, so it is picked on the
	# food ray like a plate (see PICK_SURFACE).
	if kind=="party_food" and body.collision_layer!=0:body.collision_layer|=PICK_SURFACE
	body.set_meta("item_id",info.id)
	if kind == "car_garage":
		node.set_meta("garage_door_open", bool(entry.get("garage_door_open", false)))
		_apply_garage_door(node, bool(node.get_meta("garage_door_open")))
	if kind=="towel_rack":
		info["towels"]=clampi(int(entry.get("towels",Variants.holds(data,str(variant.size)))),0,Variants.holds(data,str(variant.size)))
	items.append(info)
	_rebuild_supported_items()
	if kind=="towel_rack":refresh_towel_rack(info)
	if kind in ["car", "car_electric", "electric_car"] and level == 0:
		# Snap after the car is registered so bay occupancy and transforms match
		# the live item list the garage helper reads.
		var bay: Dictionary = _nearest_garage_bay(node.position, str(info.id))
		if not bay.is_empty():
			node.position = Vector3(float(bay.x), Building.level_y(level), float(bay.z))
			node.rotation_degrees.y = float(bay.rotation)
			info["x"] = node.position.x
			info["z"] = node.position.z
			info["rotation"] = node.rotation_degrees.y
	if rebuild:rebuild_navigation()
	if rebuild and kind=="house_window":construction.refresh_decorations()

## Imported panes are boxes. A single transparent, two-sided surface lets the
## real sun traverse the matching wall aperture without stacked glass shadows.
func _catalog_window_glass(model:Node3D)->void:
	for pane:MeshInstance3D in model.find_children("Glass*","MeshInstance3D",true,false):
		var glass:=QuadMesh.new();glass.size=Vector2(1.72,1.34);pane.mesh=glass
		var tint:=StandardMaterial3D.new();tint.albedo_color=Color(.72,.82,.84,.13)
		tint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;tint.cull_mode=BaseMaterial3D.CULL_DISABLED
		tint.roughness=.14;tint.metallic_specular=.55
		pane.material_override=tint;pane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _catalog_window_geometry(window:Node3D)->void:
	window.set_meta("window_aperture",Rect2(-.88,.93,1.76,1.38))
	window.set_meta("window_frame_bounds",Rect2(-.96,.83,1.92,1.54))
	window.set_meta("window_attachment_offset",.06)

## A window needs uninterrupted support for its whole frame. Judge the real
## wall height even while the player lowers the displayed walls for building.
func _catalog_window_supported(at:Vector3,angle:float)->bool:
	var window:=Node3D.new()
	window.position=at
	window.rotation_degrees.y=angle
	_catalog_window_geometry(window)
	var descriptors:Array=[]
	for record:Dictionary in construction.records:
		var wall:Dictionary=record.duplicate()
		wall["base_y"]=Building.level_y(int(record.get("level",0)))
		wall["display_height"]=float(record.height)
		descriptors.append(wall)
	var supported:bool=not WindowGeometry.supported_wall_ids(window,descriptors).is_empty()
	window.free()
	return supported

## The towels hanging over a rack's rail: as many as it holds now, each in its own
## slot between the two rail markers the rack model authors. Taking a towel
## leaves its slot empty, and hanging one back fills it again.
func refresh_towel_rack(item:Dictionary) -> void:
	if str(item.get("kind",""))!="towel_rack" or not is_instance_valid(item.get("node")):return
	var node:Node3D=item.node
	var old:Node=node.get_node_or_null("RackTowels")
	if old!=null:
		node.remove_child(old);old.queue_free()
	var group:Node3D=Node3D.new();group.name="RackTowels";node.add_child(group)
	var left:Node3D=node.find_child("TowelRail_L",true,false) as Node3D
	var right:Node3D=node.find_child("TowelRail_R",true,false) as Node3D
	if left==null or right==null:return
	var a:Vector3=node.to_local(left.global_position)
	var b:Vector3=node.to_local(right.global_position)
	var data:Dictionary=LifeCatalog.get_item("towel_rack")
	var variant:Dictionary=item.get("variant",{})
	var size:String=str(variant.get("size",""))
	var capacity:int=maxi(1,Variants.holds(data,size))
	var count:int=clampi(int(item.get("towels",0)),0,capacity)
	var scale:float=Variants.size_scale(size)
	var width:float=minf(.34*sqrt(scale),a.distance_to(b)/float(capacity)*.86)
	for index:int in range(count):
		var at:Vector3=a.lerp(b,(float(index)+.5)/float(capacity))
		_hang_towel(group,at,width,.44*sqrt(scale),rack_towel_color(item,index))
	# The towels belong to the rack's own floor, so an upper rack's do not show below.
	assign_structure_layer(group,item_level(item))

## The colour of the towel hung in one slot of a rack: the rack's own colour
## stepped round the palette, so a full rack is a row of different towels.
func rack_towel_color(item:Dictionary,index:int) -> String:
	var palette:Array=Variants.colors(LifeCatalog.get_item("towel_rack"))
	var base:int=maxi(0,palette.find(str((item.get("variant",{}) as Dictionary).get("color",""))))
	return str(palette[(base+3*(index+1))%palette.size()])

## One towel draped over a rail that runs along local X: a front and a shorter back
## panel joined by a folded top.
func _hang_towel(parent:Node3D,at:Vector3,width:float,drop:float,hex:String) -> void:
	var towel:Node3D=Node3D.new();towel.name="RackTowel";parent.add_child(towel)
	box(towel,at+Vector3(0,-drop*.5,.032),Vector3(width,drop,.024),hex)
	box(towel,at+Vector3(0,-drop*.42,-.032),Vector3(width,drop*.84,.024),hex)
	box(towel,at+Vector3(0,.006,0),Vector3(width,.030,.086),hex)

## Take or hang back towels on a rack, keeping its count within what it holds.
func change_rack_towels(id:String,delta:int) -> bool:
	for item:Dictionary in items:
		if str(item.id)!=id or str(item.kind)!="towel_rack":continue
		var capacity:int=Variants.holds(LifeCatalog.get_item("towel_rack"),str((item.get("variant",{}) as Dictionary).get("size","")))
		var now:int=int(item.get("towels",0))
		var next:int=clampi(now+delta,0,capacity)
		if next==now:return false
		item["towels"]=next
		refresh_towel_rack(item)
		return true
	return false

func rack_towels(id:String) -> int:
	for item:Dictionary in items:
		if str(item.id)==id and str(item.kind)=="towel_rack":return int(item.get("towels",0))
	return 0

## World-space parking bays for every garage on the lot. Occupied bays (another
## car already within 1.2 m) are skipped so placement fills empty slots.
func garage_vehicle_bays(exclude_id: String = "") -> Array:
	var bays: Array = []
	for item: Dictionary in items:
		if str(item.get("kind", "")) != "car_garage": continue
		var node: Node3D = item.get("node")
		if not is_instance_valid(node): continue
		var yaw: float = node.rotation.y
		var basis_x := Vector3(cos(yaw), 0, -sin(yaw))
		var basis_z := Vector3(sin(yaw), 0, cos(yaw))
		for local: Vector3 in LifeCatalog.vehicle_snap_locals("car_garage"):
			var world: Vector3 = node.global_position + basis_x * local.x + basis_z * local.z
			var taken: bool = false
			for other: Dictionary in items:
				if str(other.get("id", "")) == exclude_id: continue
				if str(other.get("kind", "")) not in ["car", "car_electric", "electric_car"]: continue
				var other_node: Node3D = other.get("node")
				if not is_instance_valid(other_node): continue
				if other_node.global_position.distance_to(world) < 1.2:
					taken = true
					break
			if taken: continue
			bays.append({"x": world.x, "z": world.z, "rotation": node.rotation_degrees.y, "garage_id": str(item.id)})
	return bays


func _nearest_garage_bay(at: Vector3, exclude_id: String = "") -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = 14.0
	for bay: Dictionary in garage_vehicle_bays(exclude_id):
		var d: float = at.distance_to(Vector3(float(bay.x), at.y, float(bay.z)))
		if d < best_d:
			best_d = d
			best = bay
	return best


## Raise or lower the authored sectional door mesh when the player clicks it.
func toggle_garage_door(item_id: String) -> bool:
	for item: Dictionary in items:
		if str(item.id) != item_id: continue
		if str(item.kind) != "car_garage": return false
		var node: Node3D = item.get("node")
		if not is_instance_valid(node): return false
		var open: bool = not bool(node.get_meta("garage_door_open", false))
		node.set_meta("garage_door_open", open)
		item["garage_door_open"] = open
		_apply_garage_door(node, open)
		return true
	return false


func _apply_garage_door(node: Node3D, open: bool) -> void:
	# Prefer an authored Door / SectionalDoor child; otherwise nudge any mesh
	# whose name suggests the door so opening is visible without a new asset.
	var door: Node3D = null
	for child: Node in node.find_children("*", "Node3D", true, false):
		var n: String = str(child.name).to_lower()
		if "door" in n or "sectional" in n or "shutter" in n:
			door = child
			break
	if is_instance_valid(door):
		door.position.y = 2.1 if open else 0.0
		door.visible = not open or door.position.y > 0.01
	else:
		node.set_meta("garage_door_open", open)


## After a house move, park every car in the next free garage bay.
func _snap_all_vehicles_to_garages() -> void:
	for item: Dictionary in items:
		if str(item.get("kind", "")) not in ["car", "car_electric", "electric_car"]:
			continue
		var node: Node3D = item.get("node")
		if not is_instance_valid(node):
			continue
		var bay: Dictionary = _nearest_garage_bay(node.global_position, str(item.id))
		if bay.is_empty():
			continue
		node.position = Vector3(float(bay.x), node.position.y, float(bay.z))
		node.rotation_degrees.y = float(bay.rotation)
		item["x"] = node.position.x
		item["z"] = node.position.z
		item["rotation"] = node.rotation_degrees.y

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
		# A balloon's surface is named TintGloss and keeps its shine when repainted.
		painted.roughness=.22 if str(mesh_node.name).begins_with("TintGloss") else .62
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

## Whether a furnishing can be picked with the mouse. A toy in a box, or one a
## Lifelet is carrying, cannot be: it is not on the floor.
func set_item_pickable(item:Dictionary,on:bool) -> void:
	if not is_instance_valid(item.get("node")):return
	for body:Node in item.node.find_children("*","StaticBody3D",false,false):
		(body as StaticBody3D).collision_layer=pick_layer(item_level(item)) if on else 0

func remove_item(id: String, keep_supported:bool=false) -> Dictionary:
	for i in range(items.size()):
		if items[i].id==id:
			var data=items[i]
			data.node.queue_free()
			items.remove_at(i)
			if not keep_supported:
				for supported:Dictionary in items:
					if str(supported.get("support_id",""))!=id:continue
					supported.node.position.y=Building.level_y(item_level(supported))
					for key:String in ["support_id","support_x","support_z","support_rotation","hang"]:supported.erase(key)
			_rebuild_supported_items()
			rebuild_navigation()
			if str(data.kind)=="house_window":construction.refresh_decorations()
			return data
	return {}

func serialize_items() -> Array:
	var out:Array=[]
	for item in items:
		if bool(item.get("transient_food",false)) or bool(item.get("transient_puddle",false)) or bool(item.get("derived",false)):continue
		# A pool toy on its way to the water is saved where it was picked up from.
		var rest:Dictionary=item.get("rest",{}) if bool(item.get("carried",false)) else {}
		var entry:Dictionary={"id":item.id,"kind":item.kind,"x":float(rest.get("x",item.node.position.x)),"z":float(rest.get("z",item.node.position.z)),"rotation":fmod(float(rest.get("rotation",item.node.rotation_degrees.y)),360.0)}
		for key:String in ["support_id","support_x","support_z","support_rotation","refund_value"]:
			if item.has(key):entry[key]=item[key]
		if str(item.kind)=="towel_rack":entry["towels"]=int(item.get("towels",0))
		if item_level(item)!=0:entry["level"]=item_level(item)
		# Preserve custom wall placement through ordinary saves and recovered
		# burglary layouts, as add_item reconstructs y from the floor and hang.
		var lift:float=float(rest.get("y",item.node.position.y))-Building.level_y(item_level(item))
		if not is_zero_approx(lift):entry["hang"]=lift
		# The chosen style, colour and size ride the layout record, so a save
		# resumes the same object rather than the family's first choice. Only the
		# axes the entry offers are written, so an unsized furnishing stores no
		# size key and old and new saves of it compare equal.
		var variant:Dictionary=item.get("variant",Variants.resolve(LifeCatalog.get_item(item.kind),item))
		for key:String in variant:
			entry[key]=variant[key]
		if str(item.kind)=="floor_lamp" and not bool(item.get("lit",true)):entry["lit"]=false
		if str(item.kind)=="party_food":entry["servings"]=int(item.get("servings",0))
		if not item_cloth(item).is_empty():entry["cloth"]=item_cloth(item)
		# A toy nested in its box stays nested through a save, an undo and a trip.
		if str(item.get("box_id",""))!="":entry["box_id"]=str(item.box_id)
		if str(item.kind)=="memorial" and str(item.get("for",""))!="":entry["for"]=str(item.get("for"))
		if LifeCatalog.paints(str(item.kind)):entry["paint"]=LifeCatalog.paint_of(item)
		out.append(entry)
	if construction:out.append(construction.snapshot())
	return out

func rebuild_navigation() -> void:
	if is_instance_valid(construction.doors):construction.doors.sync(construction.records,items)
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
		if str(item.kind) in ["meal","plate","puddle"] or bool(item.get("derived",false)) or bool(item.get("carried",false)) or LifeCatalog.passable(str(item.kind)):continue
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
		if str(item.kind) in ["meal","plate","puddle"] or bool(item.get("derived",false)) or bool(item.get("carried",false)) or LifeCatalog.passable(str(item.kind)):continue
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

## The one sentence every blocked Lifelet or pet route ends in, so a player is
## told which piece to move instead of guessing. The name is the catalogue's own.
const BLOCKED_PATH:String="Please move the %s blocking the path."

## What a navigation blocker is called to the player: a placed item by its
## catalogue label, and the few solids that are not furnishings by their kind.
func blocker_name(blocker:Dictionary) -> String:
	match str(blocker.get("kind","")):
		"item":
			for item:Dictionary in items:
				if str(item.id)==str(blocker.get("id","")):return str(LifeCatalog.get_item(str(item.kind)).get("label",""))
		"wall":return "wall"
		"stair":return "staircase"
		"object":
			var id:String=str(blocker.get("id",""))
			return "police station" if id.begins_with("police_station_") else id.replace("_"," ")
	return ""

## The notice for a blocker, or `fallback` when nothing solid is responsible.
func blocker_notice(blocker:Dictionary,fallback:String="") -> String:
	var label:String=blocker_name(blocker)
	if label.is_empty():return fallback
	return BLOCKED_PATH%label if str(blocker.kind)=="item" else "The %s is blocking the path."%label

## Why a walk between two spots failed, in the player's words: the placed item on
## the cheapest way across (or sitting on either spot), else `fallback`. `ignore`
## lists item ids that are the goal itself and so never the answer.
func blocked_notice(from:Vector3,to:Vector3,fallback:String="",ignore:Array=[]) -> String:
	var from_level:int=point_level(from);var to_level:int=point_level(to)
	if from_level<0 or to_level<0:return fallback
	return blocker_notice(lot_navigation.blocker_between(from_level,from,to_level,to,ignore),fallback)

## The notice for a walker refused at one step: the placed item that step meets.
func step_notice(from:Vector3,to:Vector3,fallback:String="") -> String:
	var level:int=point_level(from)
	if level<0:return fallback
	return blocker_notice(lot_navigation.first_blocker(level,from,to),fallback)

func nearest_clear_point(point:Vector3,level:int,radius:int=13) -> Vector3:
	if level<0 or level>Building.MAX_LEVEL:return Vector3.INF
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

## How far in front of its centre a furnishing's solid reaches, in metres: half its
## declared depth, or further where the measured model reaches past it (a pool's
## coping). The standing spot in front is measured from here so that it is never
## inside the piece that it is the standing spot for.
func front_extent(kind:String,size_choice:String,style:String) -> float:
	var data:Dictionary=LifeCatalog.get_item(kind)
	if data.is_empty():return .5
	var reach:float=float((data.get("size",Vector2.ONE) as Vector2).y)*Variants.size_scale(size_choice)*.5
	for panel:Dictionary in LifeCatalog.local_panels(kind,size_choice,style):
		reach=maxf(reach,float(panel.z)+float(panel.d)*.5)
	return reach

func layout_approach(entry:Dictionary) -> Vector3:
	# The standing spot in front of a furnishing described by its layout record
	# alone (kind, x, z, rotation, level), for placement checks before a node exists.
	var kind:String=str(entry.get("kind",""))
	var choice:String=str(entry.get("size","")) if entry.get("size","") is String else ""
	var variant_data:Variant=entry.get("variant",{})
	if choice.is_empty() and variant_data is Dictionary:choice=str((variant_data as Dictionary).get("size",""))
	var style:String=str(entry.get("style",""))
	if style.is_empty() and variant_data is Dictionary:style=str((variant_data as Dictionary).get("style",""))
	var level:int=int(entry.get("level",0))
	var forward:Vector3=Basis(Vector3.UP,deg_to_rad(float(entry.get("rotation",0.0))))*Vector3(0,0,front_extent(kind,choice,style)+.55)
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
	var variant:Dictionary=item.get("variant",{}) if item.get("variant",{}) is Dictionary else {}
	var reach:float=maxf(float(item.size.y)*.5,front_extent(str(item.kind),str(variant.get("size","")),str(variant.get("style",""))))
	# Something small on the floor is stood right beside, not at arm's length, so it can be bent down to.
	var standoff:float=.55
	if ToyFlow.is_toy(str(item.kind)):standoff=.32
	elif ToyFlow.is_container(str(item.kind)):standoff=.44
	var p:Vector3=n.to_global(Vector3(0,0,reach+standoff))
	if not construction.building_state.is_empty():
		var at:Vector3=nearest_clear_point(p,item_level(item))
		if standoff<.5:at=_stand_beside_small(item,at,reach+standoff)
		# A child's bed is often pushed up against a wall: its foot may then only
		# be reachable from the next room, so check, and use a side if need be.
		return child_bed_approach(item,at) if str(item.kind)=="child_bed" else at
	var c=nearest_free(p)
	return Vector3(c.x*.25,.16,c.y*.25)

## Where somebody stands to reach something small (a toy, a toy box): in front of it
## when that spot is on its own side of every wall and can be walked to, otherwise at
## one of its other sides that is. The spot snapped to the grid is never taken from
## across a wall, so a chest with its front to a wall is used from the side.
func _stand_beside_small(item:Dictionary,front:Vector3,gap:float) -> Vector3:
	var n:Node3D=item.node
	var level:int=item_level(item)
	var flood:Dictionary=_reachable_from_front(level)
	var wanted_front:Vector3=n.to_global(Vector3(0,0,gap))
	var sideways:float=maxf(float(item.size.x)*.5,.1)+(gap-maxf(float(item.size.y)*.5,.1))
	var candidates:Array[Vector3]=[front,n.to_global(Vector3(sideways,0,0)),n.to_global(Vector3(-sideways,0,0)),n.to_global(Vector3(0,0,-gap))]
	for index:int in range(candidates.size()):
		var at:Vector3=candidates[index]
		if index>0:
			at=nearest_clear_point(at,level,1)
			if not at.is_finite():continue
		elif not at.is_finite() or Vector2(at.x-wanted_front.x,at.z-wanted_front.z).length()>.3:continue
		if not sight_line_clear(at,n.global_position):continue
		if not flood.is_empty() and not lot_navigation.point_reachable(flood,level,at):continue
		return at
	return front

## Where a child stands to get into their own bed: its foot when that is clear,
## on the bed's side of any wall and reachable from the front door, otherwise a
## free spot beside it that is. Nothing better than the foot is ever returned
## when no candidate qualifies, so the old behaviour is the floor.
func child_bed_approach(item:Dictionary,foot:Vector3) -> Vector3:
	var level:int=item_level(item)
	var n:Node3D=item.node
	var size:Vector2=item.size
	var flood:Dictionary=_reachable_from_front(level)
	var candidates:Array[Vector3]=[foot]
	for side:float in [1.0,-1.0]:
		for along:float in [.3,.65,-.1,-.5]:
			candidates.append(n.to_global(Vector3(side*(size.x*.5+.4),0,along)))
	for index:int in range(candidates.size()):
		var at:Vector3=candidates[index]
		if index>0:
			var snapped:Vector3=nearest_clear_point(at,level,1)
			if not snapped.is_finite() or Vector2(snapped.x-at.x,snapped.z-at.z).length()>=.3:continue
			at=snapped
		if not at.is_finite():continue
		var local:Vector3=n.to_local(at)
		var edge:Vector3=n.to_global(Vector3(clampf(local.x,-size.x*.5,size.x*.5),0,clampf(local.z,-size.y*.5,size.y*.5)))
		edge.y=at.y
		if not sight_line_clear(at,edge):continue
		if not flood.is_empty() and not lot_navigation.point_reachable(flood,level,at):continue
		return at
	return foot

var _front_flood:Dictionary={}
var _front_flood_generation:int=-1
## Every walkable point the front door reaches, kept for as long as the lot's
## navigation is the one it was computed from.
func _reachable_from_front(level:int) -> Dictionary:
	if _front_flood_generation!=lot_navigation.generation:
		_front_flood=lot_navigation.reachable_from(0,lot_exit_position(),{})
		_front_flood_generation=lot_navigation.generation
	return _front_flood

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
		if child is CollisionObject3D:child.collision_layer=0 if away else pick_layer(maxi(0,point_level(actor.position)))
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
		if at.is_finite():
			var target:Dictionary={"id":item.id,"kind":item.kind,"position":at,"level":item_level(item)}
			if str(item.kind)=="towel_rack":target["towels"]=int(item.get("towels",0))
			if str(item.kind)=="party_food":target["servings"]=int(item.get("servings",0))
			if bool(item.get("carried",false)):target["carried"]=true
			# Which chair a child desk or table offers, so homework can be ranked
			# and refused by what there is to sit on ("" when nothing faces it).
			if str(item.kind) in STUDY_KINDS:target["study_seat"]=str(study_chair(item).get("id",""))
			elif str(item.kind) in LifeCatalog.WORK_DESKS:target["study_seat"]=str(desk_chair(item).get("id",""))
			a.append(target)
	for identity:int in _target_approaches.keys():
		if not present.has(identity):_target_approaches.erase(identity)
	a.append_array(chore_targets)
	# People move independently of the static navigation geometry.
	for id in actors:
		if bool(actors[id].get_meta("away",false)):continue
		a.append({"id":id,"kind":"neighbor","position":actors[id].position+Vector3(0,0,.8)})
	return a

func set_build(enabled:bool) -> void:
	build_enabled=enabled
	if enabled:rebuild_build_grid()
	if grid:grid.visible=enabled
	if not enabled:clear_placement()

## Make the fence being placed one step longer or shorter, or taller or lower.
## Returns whether the size changed. The ghost is rebuilt at the new size and the
## turn, wall height and any move in progress are kept.
func resize_placement(length_steps:int,height_steps:int) -> bool:
	var data:Dictionary=LifeCatalog.get_item(placement_kind)
	if not Variants.resizable(data):return false
	var dims:Vector2=Variants.dims(data,placement_size)
	var limits:Dictionary=Variants.limits(data)
	var next:String=Variants.custom_id(data,dims.x+float(length_steps)*limits.length.z,dims.y+float(height_steps)*limits.height.z)
	if next==Variants.custom_id(data,dims.x,dims.y):return false
	var angle:float=placement_angle
	var moving:String=placement_moving_id
	var hang:float=placement_hang
	begin_placement(placement_kind,placement_style,next,placement_color)
	placement_angle=angle
	placement_moving_id=moving
	placement_hang=hang
	return true

func begin_placement(kind:String,style:String="",size:String="",color:String="") -> void:
	if construction:construction.cancel()
	clear_placement()
	placement_kind=kind
	placement_style=style
	placement_size=size
	placement_color=color
	placement_angle=0
	var bought:Dictionary=LifeCatalog.get_item(kind)
	placement_hang=float(bought.get("hang",0.0)) if bought.has("hang") else 0.0
	if bool(LifeCatalog.get_item(kind).get("room_pack",false)):
		# A room pack is a room, not a model: the ghost is its floor and wall
		# outline, previewed where the room will actually be built.
		ghost=_room_pack_ghost(LifeCatalog.get_item(kind).size)
		add_child(ghost)
		return
	if Kitchen.cabinet(kind):
		ghost=Kitchen.build(kind,Variants.resolve(bought,{"style":style,"size":size,"color":color}))
		ghost.scale*=Kitchen.model_scale(kind)
		add_child(ghost)
		_ghost_materials(ghost)
		return
	var path:String=Variants.model_path(kind,style)
	if not ResourceLoader.exists(path):path="res://assets/models/%s.glb" % kind
	# A family whose art is styled may ship no base model at all, and a caller
	# that names no style would then load a missing path. Fall back to a model
	# the family really ships, and refuse the placement cleanly rather than
	# instancing a null resource and taking the game down with it.
	if not ResourceLoader.exists(path):
		for candidate:String in Variants.model_paths(kind,LifeCatalog.get_item(kind)):
			if ResourceLoader.exists(candidate):path=candidate;break
	if not ResourceLoader.exists(path) and LifeCatalog.procedural(kind):
		ghost=Node3D.new()
		add_child(ghost)
		build_procedural(ghost,kind,Variants.resolve(bought,{"style":style,"size":size,"color":color}),bought)
		_ghost_materials(ghost)
		return
	if not ResourceLoader.exists(path):
		clear_placement()
		return
	var resource:Resource=load(path)
	if resource==null:
		clear_placement()
		return
	if Variants.custom_dims(bought,size)!=Vector2.ZERO and resource is PackedScene:
		ghost=_build_fence_run(resource,bought,size)
	else:
		ghost=resource.instantiate()
	if ghost==null:
		clear_placement()
		return
	if kind=="house_window":
		var pane:Node3D=ghost
		ghost=Node3D.new();ghost.add_child(pane)
		pane.position=Vector3(0,1.62,-.045)
	if Variants.custom_dims(bought,size)==Vector2.ZERO:
		var scale:float=Variants.size_scale(size)
		if not is_equal_approx(scale,1.0):ghost.scale=Vector3.ONE*scale
	ghost.scale*=Kitchen.model_scale(kind)
	add_child(ghost)
	_normalize_wall_model(ghost,kind)
	_ghost_materials(ghost)

## Older decorative GLBs contain their original mounting height in the mesh.
## Use the same attachment origin for bought models and placement previews, so
## the saved hang height is applied exactly once.
func _normalize_wall_model(model:Node3D,kind:String)->void:
	var offset:float=float({"painting":1.0,"shelf":1.4,"wall_clock":1.65,"children_picture":.36}.get(kind,0.0))
	if is_zero_approx(offset) or model.has_meta("wall_origin_normalized"):return
	for child:Node in model.get_children():
		if child is Node3D:child.position.y-=offset
	model.set_meta("wall_origin_normalized",true)

## Every surface of a placement ghost gets a material of its own, so the green
## and red of a valid or refused spot recolour the ghost and nothing else. The
## built-in boxes share one cached material per colour, and tinting that would
## repaint every placed furnishing built from the same colour.
func _ghost_materials(root:Node) -> void:
	for n in root.find_children("*","MeshInstance3D",true,false):
		var m=StandardMaterial3D.new()
		m.albedo_color=Color(.38,.8,.63,.48)
		m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		n.material_override=m

func _room_pack_ghost(size:Vector2) -> Node3D:
	var root:=Node3D.new();root.name="RoomPackGhost"
	box(root,Vector3(0,.03,0),Vector3(size.x,.03,size.y),"8faf9f")
	for edge:Array in [[Vector3(0,.3,-size.y*.5),Vector3(size.x,.6,.14)],[Vector3(0,.3,size.y*.5),Vector3(size.x,.6,.14)],[Vector3(-size.x*.5,.3,0),Vector3(.14,.6,size.y)],[Vector3(size.x*.5,.3,0),Vector3(.14,.6,size.y)]]:
		box(root,edge[0],edge[1],"8faf9f")
	for n in root.find_children("*","MeshInstance3D",true,false):
		var m=StandardMaterial3D.new()
		m.albedo_color=Color(.38,.8,.63,.48)
		m.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		n.material_override=m
	return root

## Where a room pack of this kind would be built for a pointer at `p`: the
## catalogue footprint, turned with the placement angle, snapped onto the walls
## it meets.
func room_pack_area(kind:String,p:Vector3,angle:float) -> Rect2:
	var size:Vector2=LifeCatalog.get_item(kind).size
	if int(roundf(angle/90))%2:size=Vector2(size.y,size.x)
	var walls:Array=construction.building_state.get("walls",[]) if is_instance_valid(construction) and not construction.building_state.is_empty() else (construction.records if is_instance_valid(construction) else [])
	return LifeBuildingEdits.room_pack_rect({"walls":walls},Vector2(p.x,p.z),size,0)

func clear_placement() -> void:
	placement_kind=""
	placement_style=""
	placement_size=""
	placement_moving_id=""
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
	var support:Dictionary=surface_placement(kind,p,angle)
	var depth:float=size.y
	# A piece that only belongs on a tabletop (the party platter) is refused on bare floor.
	if bool(data.get("surface_only",false)) and support.is_empty():return false
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
		var volume_record:Dictionary={"kind":kind,"x":p.x,"z":p.z,"rotation":angle,"level":level,"style":variant.style,"size":variant.size}
		if data.has("hang"):volume_record["hang"]=placement_hang if placement_kind==kind else float(data.hang)
		volume_record.merge(support,true)
		if not construction.building_state.roofs.is_empty() and not RoofRules.obstruction(construction.building_state,furnishing_volume(volume_record)).is_empty():return false
	for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
		if not grounds(corner,level):return false
	if LifeCatalog.wall_mounted(kind) and not wall_behind(kind,p,angle,variant.size):return false
	if kind=="house_window" and not _catalog_window_supported(p,angle):return false
	if LifeCatalog.passable(kind):
		# A rug can lie anywhere. A fence or gate may touch the next panel and
		# the face of a wall, and is refused only when the panels themselves overlap.
		if LifeCatalog.runs_flush(kind):
			if not construction.building_state.is_empty() and construction.rect_blocked(rect,level,-.01):return false
			for item in items:
				if item_level(item)!=level or not LifeCatalog.runs_flush(str(item.kind)):continue
				for panel:Rect2 in item_panels(item):
					if LifeCatalog.blocks_neighbor(rect,panel,kind,str(item.kind)):return false
		return true
	# Interior walls and doorways stay usable. A fence or gate may touch a wall;
	# other furnishings keep the small margin that stops them sinking into it.
	var wall_slack:float=-.001 if kind=="fridge" else (-.01 if LifeCatalog.runs_flush(kind) else .03)
	if construction.rect_blocked(rect,level,wall_slack):return false
	for item in items:
		if item_level(item)!=level:continue
		if not placement_moving_id.is_empty() and str(item.get("support_id",""))==placement_moving_id:continue
		if not support.is_empty() and str(item.id)==str(support.support_id):continue
		if item.kind in ["meal","plate"]:
			# A supported appliance must leave the dishes already on that
			# surface visible. Food on the floor retains its own relocation flow.
			if not support.is_empty() and item.node.visible and str(item.get("food_host",""))==str(support.support_id) and str(item.get("food_storage","")) in ["surface","table","dirty"]:
				var half:Vector2=item.get("surface_half",Vector2(.15,.15))
				var food_rect:Rect2=_oriented_panel(Vector2(item.node.position.x,item.node.position.z),item.node.basis,{"x":0.0,"z":0.0,"w":half.x*2,"d":half.y*2})
				if rect.grow(.005).intersects(food_rect):return false
			continue
		if item.kind=="puddle" or bool(item.get("derived",false)):continue
		if LifeCatalog.passable(str(item.kind)) and not LifeCatalog.runs_flush(str(item.kind)):continue
		# A candidate stands free when it misses every solid band of what is
		# already there, so a car fits in the garage's hollow interior even
		# though the building's own declared outline covers that floor.
		for panel:Rect2 in item_panels(item):
			if LifeCatalog.blocks_neighbor(rect,panel,kind,str(item.kind)):return false
	# The app's own reach rule (set by `main.gd`) refuses a spot that would seal a
	# doorway or cut off a furnishing the household still needs to walk to. The
	# ghost preview and the click both apply it, so this preview must too: without
	# it `can_place` answered true for a point the commit then refused, and a
	# caller could show a green ghost, accept the click and silently not place.
	if placement_reach_check.is_valid() and not bool(placement_reach_check.call(kind,p,angle)):return false
	return true

## Join the side edges of modular units without the ordinary quarter-tile gap.
## A corner cabinet also exposes perpendicular edges for the return run.
func kitchen_snap(kind:String,p:Vector3,angle:float,reach:float=.6) -> Vector3:
	if kind not in Kitchen.UNITS:return p
	var level:int=point_level(p)
	var incoming:Rect2=furnishing_rect({"kind":kind,"x":0.0,"z":0.0,"rotation":angle})
	var best:Vector3=p
	var distance:float=reach
	for item:Dictionary in items:
		if item_level(item)!=level or str(item.kind) not in Kitchen.UNITS:continue
		var other_angle:float=item.node.rotation_degrees.y
		var parallel:bool=absf(sin(deg_to_rad(angle-other_angle)))<.01
		if not parallel and kind!="corner_counter" and str(item.kind)!="corner_counter":continue
		var other:Rect2=item_panels(item,false)[0]
		var half:Vector2=(incoming.size+other.size)*.5
		var center:Vector2=other.get_center()
		var across:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3.RIGHT
		var axes:Array=[Vector2.RIGHT] if absf(across.x)>.5 else [Vector2.DOWN]
		if kind=="corner_counter" or str(item.kind)=="corner_counter":axes=[Vector2.RIGHT,Vector2.DOWN]
		for axis:Vector2 in axes:
			for side:float in [-1.0,1.0]:
				var candidate:=Vector3(center.x+axis.x*half.x*side,p.y,center.y+axis.y*half.y*side)
				var delta:float=Vector2(candidate.x-p.x,candidate.z-p.z).length()
				if delta<distance:
					distance=delta;best=candidate
	return _kitchen_wall_snap(kind,best,angle,reach)

## A fridge's back may meet a solid wall, but never rotate through the wall or
## span a doorway. Keep the chosen orientation and slide only toward its back.
func _kitchen_wall_snap(kind:String,p:Vector3,angle:float,reach:float) -> Vector3:
	if kind!="fridge" or not is_instance_valid(construction):return p
	var front:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3.BACK
	var along_x:bool=absf(front.z)>.999
	if not along_x and absf(front.x)<.999:return p
	var size:Vector2=LifeCatalog.get_item(kind).size
	var level:int=point_level(p)
	var best:Vector3=p
	var nearest:float=reach
	for wall:Dictionary in construction.records:
		if int(wall.get("level",0))!=level or (float(wall.w)>=float(wall.d))!=along_x:continue
		var sign:float=signf(front.z if along_x else front.x)
		var at:float=p.z if along_x else p.x
		var centre:float=float(wall.z) if along_x else float(wall.x)
		if (at-centre)*sign<=0.0:continue
		var along:float=p.x if along_x else p.z
		var wall_along:float=float(wall.x) if along_x else float(wall.z)
		var length:float=float(wall.w) if along_x else float(wall.d)
		if absf(along-wall_along)+size.x*.5>length*.5+.001:continue
		var thickness:float=float(wall.d) if along_x else float(wall.w)
		var target:float=centre+sign*(thickness+size.y)*.5
		var distance:float=absf(target-at)
		if distance>=nearest:continue
		nearest=distance
		if along_x:best.z=target
		else:best.x=target
	return best

## Move countertop appliances with their host; selling a host grounds them.
## Local anchors also make saved order irrelevant and preserve a rotated return.
func relocated_surface_layout(layout:Array,host:Dictionary) -> Array:
	var result:Array=layout.duplicate(true)
	for entry:Dictionary in result:
		if str(entry.get("support_id",""))!=str(host.get("id","")):continue
		var basis:=Basis(Vector3.UP,deg_to_rad(float(host.get("rotation",0))))
		var offset:Vector3=basis*Vector3(float(entry.get("support_x",0)),0,float(entry.get("support_z",0)))
		entry.x=float(host.x)+offset.x;entry.z=float(host.z)+offset.z
		entry.rotation=float(host.get("rotation",0))+float(entry.get("support_rotation",0))
		entry["level"]=int(host.get("level",0))
	return result

func _rebuild_supported_items() -> void:
	for item:Dictionary in items:
		var support_id:String=str(item.get("support_id",""))
		if support_id.is_empty():continue
		for host:Dictionary in items:
			if str(host.id)!=support_id:continue
			var at:Vector3=host.node.to_global(Vector3(float(item.get("support_x",0)),float(item.get("hang",0)),float(item.get("support_z",0))))
			item.node.position=at;item.node.rotation_degrees.y=host.node.rotation_degrees.y+float(item.get("support_rotation",0))
			item["level"]=item_level(host);item["x"]=at.x;item["z"]=at.z;item["rotation"]=item.node.rotation_degrees.y
			assign_structure_layer(item.node,item_level(host))
			for body:CollisionObject3D in item.node.find_children("*","CollisionObject3D",true,false):
				body.collision_layer=pick_layer(item_level(host))|(PICK_SURFACE if str(item.kind)=="party_food" else 0)
			break
	sync_surface_decorations()

## Authored tabletop objects are either working equipment or removable decor.
## Cache their real, host-local bounds, including scaled/rotated model children.
func _surface_props(host:Dictionary) -> Array:
	if host.has("surface_props"):return host.surface_props
	var groups:Array=[]
	match str(host.kind):
		"dining":groups=[{"prefixes":["fruit"]}]
		"table":groups=[{"prefixes":["artbook","pages"]},{"prefixes":["ceramiccup"]}]
		"coffee_table":groups=[{"prefixes":["coffeebook"]},{"prefixes":["coffeesaucer","teatimecup","cuphandle","cupsteam"]}]
		"desk","study_desk":groups=[{"prefixes":["laptop","screencontent","onscreenline"],"equipment":true},{"prefixes":["penpot","pencil"]}]
	var result:Array=[]
	for group:Dictionary in groups:
		var nodes:Array=[];var vertices:Array[Vector3]=[]
		for node:Node in host.node.find_children("*","Node3D",true,false):
			var key:String=str(node.name).to_lower().replace("_","").replace(" ","")
			if not group.prefixes.any(func(prefix:String)->bool:return key.begins_with(prefix)):continue
			nodes.append(node)
			var parent:Node3D=node.get_parent()
			_gather_visual_bounds(node,host.node.global_transform.affine_inverse()*parent.global_transform,vertices)
		if vertices.is_empty():continue
		var area:=Rect2(Vector2(vertices[0].x,vertices[0].z),Vector2.ZERO)
		for point:Vector3 in vertices:area=area.expand(Vector2(point.x,point.z))
		result.append({"nodes":nodes,"area":area,"equipment":bool(group.get("equipment",false))})
	host["surface_props"]=result
	return result

## Keep laptop workspaces usable; a coffee maker can still use clear desk space.
func _surface_equipment_clear(host:Dictionary,area:Rect2) -> bool:
	for prop:Dictionary in _surface_props(host):
		if bool(prop.equipment) and area.grow(.005).intersects(prop.area):return false
	return true

func sync_surface_decorations() -> void:
	var dishes:Dictionary={}
	for item:Dictionary in items:
		if str(item.get("food_storage","")) in ["table","surface","dirty"] and is_instance_valid(item.get("node")) and item.node.visible:
			dishes[str(item.get("food_host",""))]=true
	for host:Dictionary in items:
		var props:Array=_surface_props(host)
		if props.is_empty():continue
		var occupied:Array[Rect2]=[]
		for item:Dictionary in items:
			if str(item.get("support_id",""))!=str(host.id):continue
			var local:Vector3=host.node.to_local(item.node.global_position)
			occupied.append(_oriented_panel(Vector2(local.x,local.z),host.node.global_basis.inverse()*item.node.global_basis,{"x":0.0,"z":0.0,"w":item.size.x,"d":item.size.y}))
		for prop:Dictionary in props:
			if bool(prop.equipment):continue
			var visible:bool=not (str(host.kind)=="dining" and dishes.has(str(host.id)))
			for area:Rect2 in occupied:
				if area.grow(.005).intersects(prop.area):visible=false;break
			for node:Node3D in prop.nodes:node.visible=visible

## Meal footprints are local to their host; supported furnishings retain their
## own yaw. Compare both on the floor plane so rotated tables work identically.
func surface_furnishing_clear(host:Dictionary,at:Vector3,half:Vector2) -> bool:
	var position:Vector3=host.node.to_global(at)
	var rect:Rect2=_oriented_panel(Vector2(position.x,position.z),host.node.basis,{"x":0.0,"z":0.0,"w":half.x*2,"d":half.y*2})
	for item:Dictionary in items:
		if str(item.get("support_id",""))!=str(host.id):continue
		for panel:Rect2 in item_panels(item,false):
			if rect.grow(.005).intersects(panel):return false
	return true

## Full footprint support chooses a worktop/table; open floor remains valid.
## The returned height is local to the floor so upper-storey saves work too.
func surface_placement(kind:String,p:Vector3,angle:float) -> Dictionary:
	if not bool(LifeCatalog.get_item(kind).get("surface_placeable",false)):return {}
	var level:int=point_level(p)
	var size:Vector2=LifeCatalog.get_item(kind).size
	var basis:=Basis(Vector3.UP,deg_to_rad(angle))
	# A piece that names the tables it belongs on (the party platter) skips the rest.
	var hosts:Array=LifeCatalog.get_item(kind).get("surface_hosts",[])
	for host:Dictionary in items:
		if item_level(host)!=level or not Kitchen.SURFACES.has(str(host.kind)):continue
		if not hosts.is_empty() and str(host.kind) not in hosts:continue
		var half:Vector2=host.size*.5
		if str(host.kind)=="coffee_table":half=Vector2(.525,.31)
		var supported:bool=true
		for x:float in [-size.x*.5,size.x*.5]:
			for z:float in [-size.y*.5,size.y*.5]:
				var local:Vector3=host.node.to_local(p+basis*Vector3(x,0,z))
				if absf(local.x)>half.x-.005 or absf(local.z)>half.y-.005:supported=false
				if str(host.kind)=="coffee_table" and pow(local.x/half.x,2)+pow(local.z/half.y,2)>.99:supported=false
		if supported:
			var local:Vector3=host.node.to_local(p)
			var area:Rect2=_oriented_panel(Vector2(local.x,local.z),host.node.global_basis.inverse()*basis,{"x":0.0,"z":0.0,"w":size.x,"d":size.y})
			if not _surface_equipment_clear(host,area):continue
			return {"support_id":str(host.id),"hang":float(Kitchen.SURFACES[str(host.kind)]),"support_x":local.x,"support_z":local.z,"support_rotation":angle-host.node.rotation_degrees.y}
	return {}

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
			best={"position":Vector3(_along_wall(p.x,cx,w,size.x),p.y,cz+side*(d*.5+size.y*.5+.01)),"angle":0.0 if side>0 else 180.0}
		else:
			var side:float=1.0 if p.x>=cx else -1.0
			best={"position":Vector3(cx+side*(w*.5+size.y*.5+.01),p.y,_along_wall(p.z,cz,d,size.x)),"angle":90.0 if side>0 else -90.0}
	return best

## Where along a wall of `length` centred on `centre` a piece `width` wide may
## sit: clear of the corner posts by the usual margin, or, on a stub too short
## for that, as far along as the wall itself allows. The old clamp had its lower
## bound above its upper one on a short wall, which threw the piece off the end
## of it and left the wall looking like it refused the piece.
func _along_wall(at:float,centre:float,length:float,width:float) -> float:
	var reach:float=length*.5-width*.5-.3
	if reach<0.0:reach=maxf(length*.5-width*.5,0.0)
	return clampf(at,centre-reach,centre+reach)

## A furnishing that frames a window (a curtain set) slides along the wall it is
## already snapped to until it is centred on the nearest window in that wall, so
## both panels hang either side of the glass. Windows only exist on walls that
## really carry them, so a curtain on a plain wall stays where it was pointed.
func window_snap(kind:String,p:Vector3,angle:float,reach:float=1.6) -> Vector3:
	if not bool(LifeCatalog.get_item(kind).get("window_snap",false)) or not is_instance_valid(house):return p
	var forward:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3(0,0,1)
	var along:Vector3=Vector3(forward.z,0,-forward.x)
	var best:Vector3=p;var best_distance:float=reach
	var windows:Array=[]
	for window:Node in house.get_children():
		windows.append(window)
	if is_instance_valid(furniture):
		for window:Node in furniture.get_children():
			windows.append(window)
	for window:Node in windows:
		if not window is Node3D or not window.has_meta("window_aperture") or not window.visible:continue
		if absf(window.global_basis.z.normalized().dot(forward))<.99:continue
		# Catalogue windows sit on the floor with the pane raised in the model;
		# starter window_panel nodes already sit at pane height.
		var pane_y:float=window.global_position.y
		if is_instance_valid(furniture) and window.get_parent()==furniture:
			pane_y+=1.62
		var offset:Vector3=Vector3(window.global_position.x,pane_y,window.global_position.z)-p
		if absf(offset.dot(forward))>.45:continue
		var height:float=pane_y-p.y
		if height<.9 or height>2.5:continue
		var slide:float=offset.dot(along)
		if absf(slide)>=best_distance:continue
		best_distance=absf(slide);best=p+along*slide
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

## Aim a hanging preview at the mouse at its mounting height, while keeping
## its placement/validation coordinates on the selected floor.
func placement_point(screen:Vector2)->Vector3:
	if bool(LifeCatalog.get_item(placement_kind).get("surface_placeable",false)):
		var origin:Vector3=camera.project_ray_origin(screen)
		var direction:Vector3=camera.project_ray_normal(screen)
		var best:Vector3=floor_point(screen)
		var nearest:float=INF
		if absf(direction.y)>.00001:
			for host:Dictionary in items:
				if item_level(host)!=view_level or not Kitchen.SURFACES.has(str(host.kind)):continue
				var height:float=host.node.position.y+float(Kitchen.SURFACES[str(host.kind)])
				var distance:float=(height-origin.y)/direction.y
				if distance<0.0 or distance>=nearest:continue
				var candidate:Vector3=origin+direction*distance
				candidate.y=Building.level_y(view_level)
				var support:Dictionary=surface_placement(placement_kind,candidate,placement_angle)
				if str(support.get("support_id",""))==str(host.id):best=candidate;nearest=distance
		return best
	if not LifeCatalog.wall_mounted(placement_kind) or placement_hang<=0.0:return floor_point(screen)
	var origin:Vector3=camera.project_ray_origin(screen)
	var direction:Vector3=camera.project_ray_normal(screen)
	if absf(direction.y)<.00001:return Vector3.INF
	var floor_y:float=Building.level_y(view_level)
	var distance:float=(floor_y+placement_hang-origin.y)/direction.y
	if distance<0.0:return Vector3.INF
	var point:Vector3=origin+direction*distance
	point.y=floor_y
	return point

func pick(screen:Vector2) -> void:
	if not live_enabled:return
	if build_enabled and construction.tool=="delete":
		var origin:Vector3=camera.project_ray_origin(screen)
		var direction:Vector3=camera.project_ray_normal(screen)
		var query:=PhysicsRayQueryParameters3D.create(origin,origin+direction*150,pick_layer(view_level))
		var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(query)
		var wall:Dictionary=construction.pick_wall(origin,direction,view_level)
		if not wall.is_empty() and (hit.is_empty() or float(wall.distance)<origin.distance_to(hit.position)):
			construction_requested.emit(construction.delete_proposal(str(wall.id)));return
		if not hit.is_empty():
			var id:String=str(hit.collider.get_meta("item_id",""))
			for item:Dictionary in items:
				if str(item.id)==id:object_clicked.emit(item,screen);return
		construction_requested.emit(construction._make_level_proposal(floor_point(screen)));return
	if build_enabled and construction and (not construction.tool.is_empty() or construction.roofs_visible):
		var proposal:Dictionary=construction.click(floor_point(screen))
		if not proposal.is_empty():construction_requested.emit(proposal)
		if not construction.tool.is_empty() or not proposal.is_empty():return
	if build_enabled and placement_kind!="":
		if ghost_valid:placement_requested.emit(placement_kind,ghost_position,placement_angle,placement_style,placement_size)
		return
	var origin=camera.project_ray_origin(screen)
	refresh_actor_layers()
	var ray=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*150,pick_layer(view_level))
	# Food resting on a surface and wet patches lying under it are picked first,
	# on their own ray. See PICK_SURFACE: the furniture they sit on is a taller
	# box than the surface it offers, so a single ray reached the furniture every
	# time and the plate on the table could never be clicked.
	var surface:=PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*150,PICK_SURFACE)
	var hit=get_world_3d().direct_space_state.intersect_ray(surface)
	if hit.is_empty():hit=get_world_3d().direct_space_state.intersect_ray(ray)
	var wall_hit:Dictionary=construction.pick_wall(origin,camera.project_ray_normal(screen),view_level)
	if not wall_hit.is_empty() and (hit.is_empty() or float(wall_hit.distance)<origin.distance_to(hit.position)):
		wall_clicked.emit()
		return
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
	body.collision_layer=pick_layer(maxi(0,point_level(at)))
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
	if build_enabled and is_instance_valid(ghost):update_ghost(placement_point(get_viewport().get_mouse_position()))

## Move the placement ghost to a pointed-at floor point and judge it. Split out of
## `_process` so a test can point at a spot without a mouse.
func update_ghost(pointed:Vector3) -> void:
	if not is_instance_valid(ghost):return
	if not pointed.is_finite():ghost_valid=false;return
	var p:=pointed
	p.x=snappedf(p.x,.25);p.z=snappedf(p.z,.25)
	p=kitchen_snap(placement_kind,p,placement_angle)
	if bool(LifeCatalog.get_item(placement_kind).get("room_pack",false)):
		var area:Rect2=room_pack_area(placement_kind,p,placement_angle)
		ghost.position=Vector3(area.get_center().x,Building.level_y(0),area.get_center().y)
		ghost.rotation_degrees.y=placement_angle
		ghost_position=ghost.position
		ghost_valid=view_level==0 and Building.lot().encloses(area)
		for n in ghost.find_children("*","MeshInstance3D",true,false):n.material_override.albedo_color=Color(.4,.85,.6,.48) if ghost_valid else Color(.9,.3,.25,.48)
		return
	var lift:float=0.0
	var support:Dictionary=surface_placement(placement_kind,p,placement_angle)
	if not support.is_empty():lift=float(support.hang)
	if LifeCatalog.wall_mounted(placement_kind):
		lift=maxf(placement_hang,0.0)
		# Wall decor slides along the nearest wall and faces into the room.
		# Pieces that declare a hang height sit up on the wall, and the
		# wheel can still move that height while the ghost is showing. Only
		# the picture of the ghost is raised: the point every rule and the
		# click read stays on the floor, because a placement is judged by the
		# floor it stands over and the wall behind it, never by its height.
		var snap:Dictionary=wall_snap(placement_kind,p,1.0,placement_size)
		if not snap.is_empty():
			p=window_snap(placement_kind,snap.position,float(snap.angle))
			placement_angle=float(snap.angle)
	ghost.position=p+Vector3(0,lift,0)
	ghost.rotation_degrees.y=placement_angle
	ghost_position=p
	ghost_valid=can_place(placement_kind,p,placement_angle,placement_style,placement_size)
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

## The shade of the festive cloth on a gathering table, or "" when the table is bare.
func item_cloth(item:Dictionary)->String:
	var shade:String=str(item.get("cloth",""))
	return shade if LifeCatalog._shade(shade) and str(item.get("kind","")) in PartyProps.CLOTH_HOSTS else ""

## Lay a cloth of this shade on a gathering table, or take it off with "". The cloth is a
## thin drape over the table top, so meals keep the heights they had. False when the
## furnishing cannot wear a cloth or the shade is not a six-digit hex.
func set_item_cloth(item:Dictionary,shade:String)->bool:
	if str(item.get("kind","")) not in PartyProps.CLOTH_HOSTS or not is_instance_valid(item.get("node")):return false
	if not shade.is_empty() and not LifeCatalog._shade(shade):return false
	var old:Node=item.node.get_node_or_null("TableCloth")
	if old!=null:
		item.node.remove_child(old);old.queue_free()
	if shade.is_empty():
		item.erase("cloth");return true
	item["cloth"]=shade
	var cloth:Node3D=PartyProps.build_cloth(shade)
	item.node.add_child(cloth)
	assign_structure_layer(cloth,item_level(item))
	return true

## How many festive touches a storey has: each bunch of balloons, each set of streamers
## and each table wearing a cloth. Party hosting reads it to judge how the home is dressed.
func festive_count(level:int=0) -> int:
	var count:int=0
	for item:Dictionary in items:
		if bool(item.get("transient_food",false)) or item_level(item)!=level:continue
		if str(item.kind) in LifeCatalog.PARTY_DECOR or not item_cloth(item).is_empty():count+=1
	return count

## Set how many servings a party platter has left, from none to its full eight, and show
## exactly that many on the platter.
func set_party_servings(id:String,count:int)->bool:
	for item:Dictionary in items:
		if str(item.id)!=id or str(item.kind)!="party_food":continue
		item["servings"]=clampi(count,0,int(LifeCatalog.get_item("party_food").get("servings",0)))
		var model:Node=item.node.find_child("PartyModel",true,false)
		if model is Node3D:PartyProps.show_servings(model as Node3D,int(item.servings))
		return true
	return false

func item_lit(item:Dictionary)->bool:return bool(item.get("lit",true))

func set_item_lit(item:Dictionary,lit:bool)->void:
	item["lit"]=lit
	if is_instance_valid(item.get("node")):
		var glow:Node=item.node.find_child("LampGlow",true,false)
		if glow!=null:glow.visible=lit

func begin_activity_frame(paused:bool=false,delta:float=0.0,speed:float=1.0) -> void:
	if paused:return
	for index:int in range(_garden_swings.size()-1,-1,-1):
		if not is_instance_valid(_garden_swings[index]):_garden_swings.remove_at(index)
		else:_garden_swings[index].advance(delta*clampf(speed,0.0,3.0))
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
	assign_structure_layer(_desk_boosters[id],clampi(point_level(chair.global_position),0,Building.MAX_LEVEL))
	_desk_boosters[id].visible=true

## The desk model's own size on the floor: the study desk is the plain desk
## scaled down, so its top (.715 m) and its keyboard sit that much lower.
func _desk_scale(kind:String) -> float:
	return float(LifeCatalog.get_item(kind).get("model_scale",1.0))

func _desk_surface(node:Node3D,scale:float=1.0) -> Dictionary:
	return {"hand_center":node.to_global(Vector3(0,.915*scale,.105*scale)),"hand_spread":.105*scale,
		"desk_surface_y":node.to_global(Vector3(0,.87*scale,0)).y,
		"desk_front_edge":node.to_global(Vector3(0,.87*scale,.385*scale)),
		"desk_forward":-node.global_basis.z.normalized()}

## The chair a desk or computer is used from: the nearest everyday chair or desk
## chair just in front of it, whichever way it faces (authored pairs are kept).
func desk_chair(item:Dictionary) -> Dictionary:
	if not is_instance_valid(item.get("node")):return {}
	var from:Vector3=item.node.to_global(Vector3(0,0,.88))
	var found:Dictionary={}
	var nearest:float=1.25
	for kind:String in LifeCatalog.DESK_CHAIRS:
		var candidate:Dictionary=closest_item(kind,from,nearest)
		if candidate.is_empty():continue
		nearest=candidate.node.position.distance_to(from);found=candidate
	return found

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
	return maxi(1,Variants.seats(data,size,str(variant.get("style",""))))

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

## The local offset of one place on a furnishing. A family that authors its own
## `seat_offsets` names where its seats physically are — the sofa's three seat
## cushions, the loveseat's two — so those are used directly. Any other
## multi-seat family spreads its places evenly across the span between its arms,
## because the usable width is the footprint minus the two end margins.
func seat_slot_offset(item:Dictionary,slot:String) -> Vector3:
	if str(item.kind) in SHARED_BEDS:return Vector3(-.42 if slot=="left" else .42,0,0)
	var count:int=seat_capacity(item)
	if count<=1 or slot.is_empty():return Vector3.ZERO
	var index:int=slot.trim_prefix("seat_").to_int()
	index=clampi(index,0,count-1)
	var authored:Array=LifeCatalog.get_item(str(item.kind)).get("seat_offsets",[])
	if authored.size()==count:
		# A size choice scales the whole authored model uniformly, so an
		# authored cushion offset travels with it.
		var base:float=float((LifeCatalog.get_item(str(item.kind)).get("size",Vector2.ONE) as Vector2).x)
		var scale:float=float(item.get("size",Vector2.ONE).x)/maxf(.01,base)
		return Vector3(float(authored[index])*scale,0,0)
	var span:float=maxf(.1,float(item.get("size",Vector2(.6,.6)).x)*(.52 if str(item.kind)=="outdoor_swing" else .8))
	var step:float=span/float(maxi(1,count-1)) if count>1 else 0.0
	return Vector3(-span*.5+step*float(index),0,0)

## Reach the actual bedside, keeping the chosen half on its own side of the
## mattress. A blocked side never snaps through a wall to some other room.
func bed_side_approach(item:Dictionary,slot:String) -> Vector3:
	var n:Node3D=item.node
	var side:float=-1.0 if slot=="left" else 1.0
	for along:float in [.3,.65,-.1]:
		var wanted:Vector3=n.to_global(Vector3(side*(float(item.size.x)*.5+.4),0,along))
		var at:Vector3=nearest_clear_point(wanted,item_level(item),1) if not construction.building_state.is_empty() else Vector3(nearest_free(wanted).x*.25,.16,nearest_free(wanted).y*.25)
		if at.is_finite() and Vector2(at.x-wanted.x,at.z-wanted.z).length()<.3:return at
	return Vector3.INF

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
	var capacity:int=seat_capacity(item)
	var resources:Array[String]=[]
	if capacity>1:
		# Each place is its own resource, so two people really share one couch.
		# A request that holds no place of its own — every seat already taken —
		# claims all of them instead, so it conflicts with the occupants and
		# waits its turn rather than standing on somebody's cushion.
		if slot.is_empty():
			for name:String in seat_slots(item):resources.append(str(item.id)+":"+name)
		else:
			resources.append(str(item.id)+":"+slot)
	else:
		resources.append(str(item.id))
	if str(item.kind) in LifeCatalog.WORK_DESKS:
		var chair:Dictionary=desk_chair(item)
		if not chair.is_empty():resources.append(str(chair.id))
	return resources

func supported_homework_plan(item:Dictionary,learner_from:Vector3,helper_from:Vector3) -> Dictionary:
	if str(item.get("kind","")) not in LifeCatalog.WORK_DESKS:
		return {"ok":false,"error":"Choose a desk for homework together."}
	var node:Node3D=item.node
	var level:int=item_level(item)
	var learner_destination:Vector3=approach(item)
	if path_to(learner_from,learner_destination).is_empty():
		return {"ok":false,"error":"The learner cannot reach this desk."}
	var seat:Dictionary=desk_chair(item)
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

## A swimmer laps the pool along its length at the waterline rather than
## standing at its edge, a ring or noodle floats in that water, and a soaker sits
## on the hot tub's bench in the water (authored at 0.16 m and 0.60 m by
## tools/create_outdoor_water.py). Pool furniture is used in the nearest pool.
## `swim_lane` spreads company across parallel lanes or rim seats so two
## Lifelets who Ask to Join do not occupy the same body of water.
func outdoor_water_anchor(item:Dictionary,landmarks:Dictionary={}) -> Dictionary:
	var kind:String=str(item.get("kind",""))
	var lane:int=clampi(int(landmarks.get("swim_lane",0)),0,LifeOutdoorActs.MAX_JOIN-1)
	if kind=="hot_tub":
		var tub:Node3D=item.node
		var angle:float=float(lane)*(TAU/float(LifeOutdoorActs.MAX_JOIN))
		var local:=Vector3(sin(angle)*.38,.40,-.46+cos(angle)*.12)
		return {"position":tub.to_global(local),"yaw":tub.global_rotation.y+angle,"kind":"seat","outdoor_kind":kind}
	if kind not in ActorMotion.POOL_KINDS:return {}
	var pool:Dictionary=item if kind=="pool" else closest_item("pool",item.node.global_position,6.0)
	if pool.is_empty():return {}
	var basin:Node3D=pool.node
	var scale:float=Variants.size_scale(str((pool.get("variant",{}) as Dictionary).get("size","")))
	var reach:float=maxf(.4,float(LifeCatalog.get_item("pool").size.x)*scale*.5-1.05)
	var half_width:float=maxf(.2,float(LifeCatalog.get_item("pool").size.y)*scale*.5-0.55)
	var lane_z:float=(-half_width*.7)+half_width*1.4*(float(lane)/float(maxi(1,LifeOutdoorActs.MAX_JOIN-1)))
	var from:Vector3=basin.to_global(Vector3(-reach,.16*scale,lane_z))
	var to:Vector3=basin.to_global(Vector3(reach,.16*scale,lane_z))
	# A ring is sat in: its anchor is the hips, so the body tips about them.
	return {"position":from,"yaw":atan2(to.x-from.x,to.z-from.z),"kind":"seat" if kind=="pool_ring" else "swim","outdoor_kind":kind,"swim_from":from,"swim_to":to,"swim_span":half_width,"swim_lane_offset":lane_z}

## Where the hips of someone sitting on a pool's coping go, as a distance across the
## pool from its middle. The wall's inner face is `face`, the coping runs from
## `inner` to `outer` (the authored model's metres, scaled with the pool by `scale`;
## tools/create_outdoor_water.py). The knees come about 0.35 m forward of the hips,
## so the hips sit that far behind the wall's face to leave the legs over the water,
## and never off the coping's inner edge or too near its outer one.
func _coping_hip(face:float,inner:float,outer:float,scale:float) -> float:
	return clampf(face*scale+.30,inner*scale,outer*scale-.10)

## Where one place on a pool's coping lies, in metres from the pool's origin.
## `side` 0 is the pool's front (+z) and 1 its back (-z); `lane` spreads up to
## MAX_JOIN sitters along that side. The classic and roman pools have straight
## copings whose rounded ends the roman one curves round, and the lagoon sits on
## the rim of the lobe each side faces. `inward` is the direction across the water
## from that spot.
func _pool_rim_point(style:String,side:int,lane:int,scale:float) -> Dictionary:
	var front:float=1.0 if side==0 else -1.0
	var step:float=float(lane)-float(LifeOutdoorActs.MAX_JOIN-1)*.5
	match style:
		"lagoon":
			var lobe:Vector3=Vector3(.33,.24,1.19) if side==0 else Vector3(-1.18,-.30,1.24)
			var radius:float=_coping_hip(lobe.z-.10,lobe.z-.06,lobe.z+.34,scale)
			var across:float=step*.6*scale
			var centre:=Vector2(lobe.x,lobe.y)*scale
			var point:=centre+Vector2(across,front*sqrt(radius*radius-across*across))
			return {"point":point,"inward":(centre-point).normalized()}
		"roman":
			var x:float=step*.9
			var round_end:float=maxf(0.0,absf(x)-.9)
			if round_end==0.0:
				return {"point":Vector2(x*scale,front*_coping_hip(1.35,1.5,1.9,scale)),"inward":Vector2(0.0,-front)}
			var radius:float=_coping_hip(1.42,1.5,1.9,scale)
			var centre:=Vector2(signf(x)*.9*scale,0.0)
			var along:float=round_end*scale
			var point:=Vector2(x*scale,front*sqrt(radius*radius-along*along))
			return {"point":point,"inward":(centre-point).normalized()}
	return {"point":Vector2(step*1.1*scale,front*_coping_hip(1.35,1.5,1.9,scale)),"inward":Vector2(0.0,-front)}

## One place to sit on a pool's coping with the legs over the water, facing across
## it. `toward` is the garden television the sitter watches: the body turns a little
## toward it and the head does the rest. The approach, a clear spot outside the
## pool's solid hull where the walker stops before sitting, is only worked out when
## `with_approach` is set: it costs a search, and an anchor is read every frame.
func pool_edge_seat(item:Dictionary,side:int,lane:int,toward:Vector3,with_approach:bool=true) -> Dictionary:
	if str(item.get("kind",""))!="pool" or not is_instance_valid(item.get("node")):return {}
	if side<0 or side>1 or lane<0 or lane>=LifeOutdoorActs.MAX_JOIN:return {}
	var basin:Node3D=item.node
	var variant:Dictionary=item.get("variant",{})
	var scale:float=Variants.size_scale(str(variant.get("size","")))
	var style:String=Variants.style_or_default(str(variant.get("style","")),LifeCatalog.get_item("pool"))
	var rim:Dictionary=_pool_rim_point(style,side,lane,scale)
	var local:Vector2=rim.point
	var seat:Vector3=basin.to_global(Vector3(local.x,.35*scale+.07,local.y))
	var inward:Vector3=basin.global_basis*Vector3(rim.inward.x,0.0,rim.inward.y)
	inward.y=0.0
	inward=inward.normalized()
	var yaw:float=atan2(inward.x,inward.z)
	if toward.is_finite():
		var to_screen:Vector3=toward-seat
		var wanted:float=atan2(to_screen.x,to_screen.z)
		yaw+=clampf(wrapf(wanted-yaw,-PI,PI),-.3,.3)
	var result:Dictionary={"position":seat,"yaw":yaw,"side":side,"lane":lane,"inward":inward}
	if with_approach:
		var wish:Vector3=seat-inward*.65
		var approach:Vector3=nearest_clear_point(wish,item_level(item),8)
		if not approach.is_finite():return {}
		result["approach"]=approach
	return result

## Every place round a pool's coping to watch `toward` from, best first: the side
## that looks across the water toward it comes before the one that turns its back.
## The places carry no approach; ask `pool_edge_seat` for the one that is wanted.
func pool_edge_seats(item:Dictionary,toward:Vector3) -> Array:
	var sides:Array=[]
	for side:int in 2:
		var seat:Dictionary=pool_edge_seat(item,side,1,toward,false)
		if seat.is_empty():continue
		var to_screen:Vector3=toward-seat.position
		to_screen.y=0.0
		sides.append({"side":side,"score":Vector3(seat.inward).dot(to_screen.normalized()) if to_screen.length()>.01 else 0.0})
	sides.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return float(a.score)>float(b.score))
	var seats:Array=[]
	for entry:Dictionary in sides:
		var side_seats:Array=[]
		for lane:int in LifeOutdoorActs.MAX_JOIN:
			var seat:Dictionary=pool_edge_seat(item,int(entry.side),lane,toward,false)
			if not seat.is_empty():side_seats.append(seat)
		# The first to sit takes the place nearest the screen, so company fills in beside them.
		side_seats.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return Vector3(a.position).distance_squared_to(toward)<Vector3(b.position).distance_squared_to(toward))
		seats.append_array(side_seats)
	return seats

## What is done sitting down at a child desk or dining table, and where.
const STUDY_ACTIONS: Array[String] = ["homework", "child_desk_study", "child_draw", "child_colour"]
const STUDY_KINDS: Array[String] = ["child_desk", "dining"]

## The chair a pupil sits on to study at a furnishing, or {}: a child chair that
## faces a child desk, an ordinary chair pulled up to a dining table. Chairs named
## in `taken` are somebody else's. A chair that faces away from the table is no
## seat at it, as at mealtimes.
func study_chair(item:Dictionary,taken:Array=[]) -> Dictionary:
	var kind:String=str(item.get("kind",""))
	if kind not in STUDY_KINDS or not is_instance_valid(item.get("node")):return {}
	var chair_kind:String="child_chair" if kind=="child_desk" else "chair"
	var level:int=item_level(item)
	var best:Dictionary={}
	var nearest:float=1.1 if kind=="child_desk" else 1.6
	for candidate:Dictionary in items:
		if str(candidate.kind)!=chair_kind or item_level(candidate)!=level or taken.has(str(candidate.id)):continue
		var distance:float=candidate.node.position.distance_to(item.node.position)
		if distance>=nearest:continue
		var toward:Vector3=item.node.position-candidate.node.position
		toward.y=0.0
		if toward.length()<.01 or candidate.node.global_basis.z.dot(toward.normalized())<.65:continue
		best=candidate;nearest=distance
	return best

## Where a pupil sits at a child desk or table, facing it with their hands on its
## top, and where they stand before sitting down (a free spot behind the chair).
func study_anchor(item:Dictionary,chair:Dictionary,age_stage:String="") -> Dictionary:
	var table:Node3D=item.node
	var seat_node:Node3D=chair.node
	var toward:Vector3=table.global_position-seat_node.global_position
	toward.y=0.0
	var dir:Vector3=toward.normalized()
	var child_desk:bool=str(item.kind)=="child_desk"
	var seat:Vector3
	var top_y:float
	var inset:float
	if child_desk:
		# A child chair is the child's own height: no booster, and a little
		# forward on the cushion so short arms reach the top.
		seat=seat_node.to_global(Vector3(0,.34,.02))+dir*.17
		top_y=table.global_position.y+float(item.get("height",.72))
		inset=.03
	else:
		seat=seat_node.to_global(Vector3(0,.52,.02))
		if age_stage=="child":
			_show_desk_booster(seat_node)
			seat+=Vector3(0,.18,0)+dir*.10
		top_y=table.global_position.y+.847
		inset=.10
	var local_out:Vector3=table.global_basis.inverse()*(-dir)
	var half:Vector2=(item.size as Vector2)*.5
	var edge:float=INF
	if absf(local_out.x)>.001:edge=minf(edge,half.x/absf(local_out.x))
	if absf(local_out.z)>.001:edge=minf(edge,half.y/absf(local_out.z))
	if not is_finite(edge):edge=half.y
	var hand:Vector3=table.global_position-dir*(edge-inset)
	hand.y=top_y
	var front:Vector3=table.global_position-dir*edge
	front.y=top_y
	return {"position":seat,"yaw":atan2(dir.x,dir.z),"kind":"seat","hand_center":hand,"hand_spread":.10,"desk_surface_y":top_y,"desk_front_edge":front,"desk_forward":dir,"study_surface":"book"}

## Where a pupil waits before sitting: a clear spot behind the chair, within a
## short step of its seat.
func study_stand_point(chair:Dictionary) -> Vector3:
	var level:int=item_level(chair)
	var flood:Dictionary=_reachable_from_front(level) if not construction.building_state.is_empty() else {}
	# Behind the chair first, then to either side: a spot on the chair's own side of every
	# wall that somebody can walk to from the front door.
	for offset:Vector3 in [Vector3(0,0,-.55),Vector3(.7,0,-.2),Vector3(-.7,0,-.2),Vector3(0,0,-.95)]:
		var at:Vector3=nearest_clear_point(chair.node.to_global(offset),level,3)
		if not at.is_finite() or at.distance_to(chair.node.global_position)>1.2:continue
		if not sight_line_clear(at,chair.node.global_position):continue
		if not flood.is_empty() and not lot_navigation.point_reachable(flood,level,at):continue
		return at
	return Vector3.INF

## Where a toddler or child stands to use their own desk: the clear spot the
## household walked to, closed up to an arm's length from the desk when that spot
## is free, facing the desk, with their hands on its top.
func child_desk_anchor(item:Dictionary,landmarks:Dictionary={}) -> Dictionary:
	var node:Node3D=item.node
	var level:int=item_level(item)
	var floor_y:float=Building.level_y(level)
	var centre:Vector3=node.global_position
	var at:Vector3=landmarks.get("standing_position",approach(item))
	if not at.is_finite():at=node.to_global(Vector3(0,0,float(item.size.y)*.5+.36))
	at.y=floor_y
	var flat:Vector3=Vector3(centre.x-at.x,0,centre.z-at.z)
	# A child's arms are short, so stand at whichever side of the desk is within a
	# short free walk of where the household arrived and nearest the desk top:
	# a body's width from the edge, or closer along the way in when none is free.
	var best:Vector3=at
	var best_gap:float=flat.length()
	for side:Vector3 in [Vector3(0,0,1),Vector3(0,0,-1),Vector3(1,0,0),Vector3(-1,0,0)]:
		var edge:float=(float(item.size.y) if not is_zero_approx(side.z) else float(item.size.x))*.5
		var candidate:Vector3=node.global_position+node.global_basis*(side*(edge+.30))
		candidate.y=floor_y
		if candidate.distance_to(at)>1.2 or not lot_navigation.point_clear(level,candidate) or not lot_navigation.segment_clear(level,at,candidate):continue
		var gap:float=Vector2(centre.x-candidate.x,centre.z-candidate.z).length()
		if gap<best_gap:best=candidate;best_gap=gap
	at=best
	flat=Vector3(centre.x-at.x,0,centre.z-at.z)
	for stand:float in [.52,.62,.74]:
		if flat.length()<=stand:break
		var closer:Vector3=at+flat.normalized()*(flat.length()-stand)
		if lot_navigation.point_clear(level,closer):at=closer;break
	var toward:Vector3=Vector3(centre.x-at.x,0,centre.z-at.z)
	var top:Vector3=centre-toward.normalized()*.07
	top.y=floor_y+float(item.height)+.02
	return {"position":at,"yaw":atan2(toward.x,toward.z),"kind":"standing","hand_center":top,"hand_spread":.10,"desk_surface_y":top.y}

func activity_anchor(item:Dictionary,action_id:String,landmarks:Dictionary={}) -> Dictionary:
	var node:Node3D=item.node
	if action_id in STUDY_ACTIONS and str(item.kind) in STUDY_KINDS and not str(landmarks.get("study_seat","")).is_empty():
		for chair:Dictionary in items:
			if str(chair.id)==str(landmarks.study_seat):return study_anchor(item,chair,str(landmarks.get("age_stage","")))
	if str(item.kind)=="child_desk" and action_id in ["child_desk_study","child_draw","child_colour","homework"]:
		return child_desk_anchor(item,landmarks)
	var local:Vector3=Vector3(0,0,float(item.size.y)*.5+.36)
	var yaw:float=node.rotation.y+PI
	var kind:String="standing"
	if bool(item.get("transient_puddle",false)):
		var at:Vector3=landmarks.get("standing_position",approach(item))
		var toward:Vector3=node.global_position-at
		at.y=node.global_position.y
		return {"position":at,"yaw":atan2(toward.x,toward.z),"kind":"standing","mop_contact":node.global_position}
	if str(item.kind) in ["coffee_machine","party_food"]:
		# The appliance can be raised onto a worktop; its user always stands
		# on the supporting floor and faces the machine from a clear approach.
		# A party platter on a table is used the same way.
		var at:Vector3=landmarks.get("standing_position",approach(item))
		at.y=Building.level_y(item_level(item))
		var toward:Vector3=node.global_position-at
		return {"position":at,"yaw":atan2(toward.x,toward.z),"kind":"standing"}
	if action_id==LifeOutdoorActs.ACTION_ID:
		var water:Dictionary=outdoor_water_anchor(item,landmarks)
		if not water.is_empty():return water
	if str(item.kind)=="outdoor_swing" and action_id in [LifeOutdoorActs.ACTION_ID,LifeWetness.DRY_SIT_ID,"host_a_chat","relax"]:
		var motion:Node3D=node.get_node_or_null("GardenSwingMotion")
		if motion==null:
			motion=GardenSwing.new();motion.name="GardenSwingMotion"
			node.add_child(motion);motion.configure(item);_garden_swings.append(motion)
		return motion.anchor(seat_slot_offset(item,str(landmarks.get("seat_slot",""))))
	if action_id==LifeWetness.DRY_SIT_ID:
		# The garden's own seats: a chair at the table (four stand round it, and
		# every place maps onto one of them) and the swing's cushion.
		match str(item.kind):
			"garden_table":
				# The model is scaled by the size choice, the node is not: the chair
				# stands out and up by that same factor.
				var grown:float=Variants.size_scale(str((item.get("variant",{}) as Dictionary).get("size","")))
				var chair:int=posmod(str(landmarks.get("seat_slot","seat_0")).trim_prefix("seat_").to_int(),4)
				var around:float=float(chair)*PI*.5
				return {"position":node.to_global(Vector3(sin(around)*.78*grown,.47*grown,cos(around)*.78*grown)),"yaw":node.rotation.y+around+PI,"kind":"seat"}
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
		"chair","desk_chair":
			local=Vector3(0,.52,.02);yaw=node.rotation.y;kind="seat"
		"toilet":
			local=Vector3(0,.615,.12);yaw=node.rotation.y;kind="seat"
		"bed":
			local=Vector3(0,.80,.015)+seat_slot_offset(item,str(landmarks.get("seat_slot","left")));yaw=node.rotation.y;kind="bed"
		"child_bed":
			# Lying, the body rests on the mattress rather than sinking into it;
			# relaxing, the child sits on the foot end with the shins over it.
			if action_id=="relax":
				local=Vector3(0,.62,.85);yaw=node.rotation.y;kind="seat"
			else:
				local=Vector3(0,.57,-.18);yaw=node.rotation.y;kind="bed"
		"cot":
			local=Vector3(0,.36,0);yaw=node.rotation.y;kind="bed"
		"shower":
			local=Vector3(0,.166,.01);yaw=node.rotation.y+PI
		"armchair":
			local=Vector3(0,.50,.06);yaw=node.rotation.y;kind="seat"
		"loveseat":
			local=Vector3(0,.62,.08);yaw=node.rotation.y;kind="seat"
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
		"desk","computer","study_desk","office_desk":
			var chair:Dictionary=desk_chair(item)
			if not chair.is_empty():
				var seat:Vector3=chair.node.to_global(Vector3(0,.52,.02))
				var desk_scale:float=_desk_scale(str(item.kind))
				var keyboard:Vector3=node.to_global(Vector3(0,.915*desk_scale,.105*desk_scale))
				if str(landmarks.get("age_stage",""))=="child":
					# A visible booster and a forward seat position put short arms
					# within reach. Keep support inside the actual cushion footprint.
					var forward:Vector3=Vector3(keyboard.x-seat.x,0,keyboard.z-seat.z).normalized()
					var child_seat:Vector3=chair.node.to_local(seat+forward*.23)
					child_seat.x=clampf(child_seat.x,-.24,.24)
					child_seat.z=clampf(child_seat.z,-.25,.26)
					# The low study desk (top .715 m) is within a child's reach as it is.
					if desk_scale>=.9:
						child_seat.y+=.18
						_show_desk_booster(chair.node)
					seat=chair.node.to_global(child_seat)
				var seated:Dictionary={"position":seat,"yaw":node.rotation.y+PI,"kind":"seat"}
				seated.merge(_desk_surface(node,desk_scale))
				return seated
			local=Vector3(0,0,.75)
	var anchor: Dictionary={"position":node.to_global(local),"yaw":yaw,"kind":kind}
	if str(item.kind) in LifeCatalog.WORK_DESKS:
		anchor.merge(_desk_surface(node,_desk_scale(str(item.kind))))
	elif kind=="seat" and seat_capacity(item)>1:
		# Every seated place on a multi-seat furnishing holds its own spot along
		# the model's width, so three people share one couch without stacking.
		# A caller that names no place is asking where the furnishing's seating
		# is in general — the household's seat assignment always names one — so
		# the centre stands rather than an arbitrary end cushion.
		var slot:String=str(landmarks.get("seat_slot",""))
		if not slot.is_empty():
			anchor.position=node.to_global(local+seat_slot_offset(item,slot))
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
	if place=="park" or place=="dog_park":
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
		if place=="dog_park":
			# A low fence ring marks the run without blocking the sidewalk exit.
			for x in [-5.5,5.5]:
				box(house,Vector3(x,.55,0),Vector3(.08,.9,9.5),"c9c3a8")
			for z in [-4.8,4.5]:
				box(house,Vector3(0,.55,z),Vector3(11.2,.9,.08),"c9c3a8")
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
	_register_vegetation(plant,"flowers",Rect2(Vector2(at.x-.18,at.z-.12),Vector2(.36,.24)))

func create_resident_home(place:String,layout:Array) -> void:
	layout=normalize_layout_rotations(layout)
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


func _build_burglar_alarm(parent:Node3D) -> void:
	box(parent,Vector3(0,.21,0),Vector3(.30,.42,.075),"e9eee8")
	box(parent,Vector3(0,.34,.045),Vector3(.22,.085,.018),"163d35")
	var display:=Label3D.new();display.text="ARMED";display.font_size=30;display.pixel_size=.0012
	display.position=Vector3(0,.34,.058);parent.add_child(display)
	for row:int in 4:
		for col:int in 3:
			var point:=Vector3((col-1)*.072,.25-row*.055,.048)
			box(parent,point,Vector3(.056,.041,.016),"4b5658")
			var key:=Label3D.new();key.text=str(row*3+col+1) if row<3 else ["*","0","#"][col]
			key.font_size=24;key.pixel_size=.0013;key.position=point+Vector3(0,0,.012);parent.add_child(key)


func _build_home_phone(parent:Node3D) -> void:
	box(parent,Vector3(0,.19,0),Vector3(.24,.38,.08),"e9eee8")
	box(parent,Vector3(-.073,.19,.06),Vector3(.055,.29,.05),"384b51")
	for y:float in [.075,.30]:box(parent,Vector3(-.073,y,.078),Vector3(.08,.07,.055),"384b51")
	for row:int in 4:
		for col:int in 3:box(parent,Vector3(.015+col*.025,.26-row*.048,.048),Vector3(.018,.027,.025),"536665")
