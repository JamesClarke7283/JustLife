extends SceneTree
## Declared material/geometry fixture; no household behavior or travel claim.
const World=preload("res://scripts/world.gd")
const Building=preload("res://scripts/building_state.gd")
var checks:int=0
var failures:Array[String]=[]
var baseline:bool=false
var samples:Array=[]

func _initialize()->void:
	var path:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if OS.get_environment("XDG_DATA_HOME")!=path.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=path.path_join("userdata/save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Wood floor controls require a copied project and private userdata/save_data.");quit(2);return
	baseline="--baseline" in OS.get_cmdline_user_args();_run.call_deferred()

func check(value:bool,label:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",label)
	if not value:failures.append(label)

func vector(v:Vector3)->Array:return [v.x,v.y,v.z]

func same(a:Variant,b:Variant)->bool:
	# JSON represents integral numbers as float. Compare numeric values exactly,
	# retaining every finite bit; there is no tolerance for changed geometry.
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for index:int in a.size():
			if not same(a[index],b[index]):return false
		return true
	if (a is float or a is int) and (b is float or b is int):return float(a)==float(b)
	return typeof(a)==typeof(b) and a==b

func fixture()->Dictionary:
	var state:Dictionary=Building.migrate({"kind":"__construction","walls":[],"floors":[]}).state
	for side:int in [-1,1]:state.walls.append({"id":"north" if side<0 else "south","level":0,"x":0.0,"z":side*5.0,"w":12.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	state.floors.append({"id":"upper_oak","level":1,"x":0.0,"z":0.0,"w":12.0,"d":10.0,"material":"cfa97e","supports":["north","south"]})
	state.floors.append({"id":"upper_walnut","level":1,"x":3.0,"z":0.0,"w":6.0,"d":10.0,"material":"896953","supports":["north","south"]})
	state.floors.append({"id":"stone_annex","level":0,"x":7.5,"z":0.0,"w":3.0,"d":4.0,"material":"dcd6c6"})
	state.floors.append({"id":"custom_annex","level":0,"x":-7.5,"z":0.0,"w":3.0,"d":4.0,"material":"687d74"})
	var result:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":-1.5,"z":-2.5,"rotation":0}},10000)
	check(bool(result.ok),"Declared mixed finishes and real stair/opening are structurally valid.")
	return result.after if bool(result.ok) else state

func surroundings(world:Node3D)->Array:
	var result:Array=[]
	for node:MeshInstance3D in world.starter_floor_nodes:
		result.append([node.get_instance_id(),node.material_override.get_instance_id(),node.material_override.albedo_color.to_html(false),node.transform,node.visible])
	return result

func geometry(world:Node3D)->Array:
	var result:Array=[]
	for node:MeshInstance3D in world.construction.floor_nodes:
		result.append({"id":node.get_meta("source_floor"),"level":node.get_meta("building_level"),"position":vector(node.position),"size":vector(node.mesh.size),"layers":node.layers,"vertices":Array(node.mesh.get_faces()).map(func(v:Vector3):return vector(v))})
	return result

func navigation(world:Node3D)->Array:
	var result:Array=[]
	for level:int in [0,1]:
		for x:int in range(-34,35):
			for z:int in range(-20,21):result.append(world.lot_navigation.point_clear(level,Vector3(x*.25,Building.level_y(level),z*.25)))
	return result

func floor_hits(world:Node3D,point:Vector3)->int:
	var hits:int=0
	for node:MeshInstance3D in world.construction.floor_nodes:
		if int(node.get_meta("building_level"))!=1:continue
		var faces:PackedVector3Array=node.mesh.get_faces()
		for index:int in range(0,faces.size(),3):
			if Geometry3D.segment_intersects_triangle(point+Vector3.UP,point-Vector3.UP*.3,node.to_global(faces[index]),node.to_global(faces[index+1]),node.to_global(faces[index+2]))!=null:hits+=1
	return hits

func materials(world:Node3D)->Dictionary:
	var seen:Dictionary={}
	var valid:bool=true
	for node:MeshInstance3D in world.construction.floor_nodes:
		var id:String=str(node.get_meta("source_floor"))
		var finish:String=str(Building.find(world.construction.building_state,id).get("material","cfa97e"))
		var mat:Material=node.material_override
		if finish in ["cfa97e","896953"] and not baseline:
			valid=valid and mat is ShaderMaterial
			if mat is ShaderMaterial:
				valid=valid and mat.resource_local_to_scene and mat.get_shader_parameter("wood_color")==Color(finish)
		else:valid=valid and mat is StandardMaterial3D and mat.albedo_color==Color(finish)
		if seen.has(finish):valid=valid and seen[finish]==mat
		else:seen[finish]=mat
	check(valid,"Only named wood finishes use the intended material; same-finish tiles share one scene material.")
	return seen

func _run()->void:
	var world:Node3D=World.new();root.add_child(world);await process_frame
	var state:Dictionary=fixture();var original:Dictionary=state.duplicate(true)
	check(bool(world.load_home([state]).ok),"Actual World accepts the declared two-storey material fixture.")
	await process_frame
	var preserved:Array=surroundings(world);var shape:Array=geometry(world);var walkability:Array=navigation(world)
	check(world.construction.snapshot()==original and state==original,"Rendering does not change canonical colors, supports, identities or caller data.")
	var expected_count:int=0
	for level:int in [0,1]:
		for tile:Dictionary in Building.surface_tiles(state,level):
			if level==0 and Building.rect(Building.find(state,"legacy_starter_floor")).encloses(tile.rect):continue
			expected_count+=1
	check(world.construction.floor_nodes.size()==expected_count and world.construction.floor_nodes.all(func(node:Node3D):return node.get_child_count()==0),"Each original surface tile remains one box with no board/seam child nodes.")
	check(floor_hits(world,Vector3(-1.5,3.16,-.5))==0,"Triangle rays pass through the actual unchanged stair aperture.")
	check(floor_hits(world,Vector3(-3,3.16,-.5))>0 and floor_hits(world,Vector3(2,3.16,-.5))>0,"Triangle rays still hit both surrounding Oak and Walnut slabs.")
	check(not Building.footprint_supported(state,1,Rect2(-1.6,-.6,.2,.2)) and Building.footprint_supported(state,1,Rect2(-3.1,-.6,.2,.2)),"Logical support retains the stair void and neighboring slab.")
	var seen:Dictionary=materials(world)
	check(world.material("cfa97e") is StandardMaterial3D and world.material("cfa97e").albedo_color==Color("cfa97e"),"Original shared Oak furniture/starter material remains untouched.")
	for cut:bool in [false,true]:
		world.construction.update_cutaway(cut);world.rebuild_navigation();await process_frame
		check(geometry(world)==shape and navigation(world)==walkability and world.construction.snapshot()==original,"Cutaway rebuild retains exact floor triangles, layers, support and canonical data.")
		check(surroundings(world)==preserved,"Authored starter boards, seams, bathroom and foundation remain exact.")
		materials(world)
	var other:Node3D=World.new();root.add_child(other);await process_frame
	other.load_home([state]);var other_materials:Dictionary=materials(other)
	check(seen["cfa97e"]!=other_materials["cfa97e"] and seen["896953"]!=other_materials["896953"],"Independent World instances own independent finish resources.")
	var material_weak:WeakRef=weakref(other_materials["cfa97e"]);other_materials.clear();other.queue_free();await process_frame;await process_frame
	check(material_weak.get_ref()==null,"Scene-local material resources release with their World.")
	var disk:String="user://wood_floor_state.json"
	FileAccess.open(disk,FileAccess.WRITE).store_string(JSON.stringify(state,"  ",true,true))
	var decoded:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(disk))
	world.construction.restore(decoded);world.rebuild_navigation();await process_frame
	check(same(decoded,original) and same(world.construction.snapshot(),original) and geometry(world)==shape and navigation(world)==walkability,"Exact decoded full-precision state restores the same material identities and floor geometry/support.")
	materials(world)
	var report:Dictionary={"checks":checks,"failures":failures,"baseline":baseline,"canonical":original,"geometry":shape,"navigation":walkability,"node_count":expected_count}
	FileAccess.open("user://wood_floor_report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ",true,true))
	seen.clear();world.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	print("WOOD_FLOOR checks=%d failures=%d baseline=%s"%[checks,failures.size(),str(baseline)])
	quit(0 if failures.is_empty() else 1)
