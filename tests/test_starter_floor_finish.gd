extends SceneTree
## Controlled actual-scene finish/undo checks; no household traversal claim.
const World=preload("res://scripts/world.gd")
const Building=preload("res://scripts/building_state.gd")
const Transactions=preload("res://scripts/build_transactions.gd")
class AppFixture extends Node:
	var world:Node3D
	var sim:Node
	var floor_color:String="896953"
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:_run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",label)
	if not value:failures.append(label)
func wood(world:Node3D)->MeshInstance3D:
	for node:Node in world.house.get_children():
		if node is MeshInstance3D and node.mesh is BoxMesh and node.mesh.size.x==12 and node.mesh.size.z==10:return node
	return null
func color(node:MeshInstance3D)->String:return node.material_override.albedo_color.to_html(false)
func surroundings(world:Node3D)->Array:
	var result:Array=[]
	for node:Node3D in world.starter_floor_nodes:
		if node!=wood(world):result.append([node.get_instance_id(),node.material_override.get_instance_id(),color(node),node.transform,node.visible])
	return result
func navigation(world:Node3D)->Array:
	var result:Array=[]
	for level:int in [0,1]:
		for x:int in range(-28,41):
			for z:int in range(-24,25):result.append(world.lot_navigation.point_clear(level,Vector3(x*.25,Building.level_y(level),z*.25)))
	return result
func other_finishes(world:Node3D)->bool:
	var counts:Dictionary={"annex":0,"upper":0}
	for node:MeshInstance3D in world.construction.floor_nodes:
		var id:String=str(node.get_meta("source_floor",""))
		if not counts.has(id):return false
		counts[id]+=1
		if color(node)!=("dcd6c6" if id=="annex" else "687d74"):return false
	return counts.annex>0 and counts.upper>0
func _run()->void:
	var world:Node3D=World.new();root.add_child(world);await process_frame
	var state:Dictionary=Building.migrate({"kind":"__construction","walls":[],"floors":[]}).state
	for side:int in [-1,1]:state.walls.append({"id":"north" if side<0 else "south","level":0,"x":0.0,"z":side*5.0,"w":12.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	state.floors.append({"id":"annex","level":0,"x":7.5,"z":0.0,"w":3.0,"d":4.0,"material":"dcd6c6"})
	state.floors.append({"id":"upper","level":1,"x":0.0,"z":0.0,"w":12.0,"d":10.0,"material":"687d74","supports":["north","south"]})
	var loaded:Dictionary=world.load_home([state])
	check(bool(loaded.ok),"Mixed-finish ground annex and supported upper floor form a valid actual scene.")
	if not bool(loaded.ok):print(loaded);world.free();quit(1);return
	check(is_instance_valid(wood(world)),"Authored timber surface exists independently of material value.")
	var untouched:Array=surroundings(world)
	var walkability:Array=navigation(world)
	var oak:StandardMaterial3D=world.material("cfa97e")
	for finish:String in ["896953","dcd6c6","cfa97e"]:
		Building.find(state,"legacy_starter_floor").material=finish
		var expected:Dictionary=state.duplicate(true)
		world.construction.restore(state);world.rebuild_navigation()
		check(color(wood(world))==finish,"Actual starter timber changes to "+finish+".")
		check(state==expected and world.construction.snapshot()==expected,"Finish rendering preserves exact canonical records and its caller input.")
		check(surroundings(world)==untouched,"Bathroom tiles, seams and foundation retain materials, transforms and visibility.")
		check(other_finishes(world),"Separate ground and upper slab meshes retain their own finishes.")
		check(navigation(world)==walkability,"Material refresh preserves both storeys' walkability.")
		check(oak.albedo_color.to_html(false)=="cfa97e","Recoloring leaves the shared original Oak material unchanged.")
	var replaced:Dictionary=state.duplicate(true)
	Building.find(replaced,"legacy_starter_floor").id="replacement_ground"
	world.construction.restore(replaced)
	check(world.starter_floor_nodes.all(func(node:Node3D)->bool:return not node.visible),"Removing the legacy identity still hides all authored starter surfaces.")
	world.construction.restore(state)
	check(color(wood(world))=="cfa97e" and surroundings(world)==untouched,"Restoring the legacy identity restores its finish and authored surface visibility.")
	world.queue_free();await process_frame
	var app:=AppFixture.new();root.add_child(app)
	app.world=World.new();app.add_child(app.world);app.sim=LifeSim.new();app.add_child(app.sim)
	app.sim.new_household({});app.sim.autonomy=false;app.sim.set_speed(0);await process_frame
	app.world.load_home([{"kind":"__construction","walls":[],"floors":[]}])
	var tx:=Transactions.new(app)
	var before_funds:int=app.sim.funds
	var quote:Dictionary=tx.prepare({"op":"structure","tool":"finish","level":0,"material":"dcd6c6"})
	var result:Dictionary=tx.commit(quote)
	check(bool(result.ok) and color(wood(app.world))=="dcd6c6","Real finish transaction migrates and paints the authored surface.")
	check(bool(tx.undo(result.receipt).ok) and color(wood(app.world))=="896953","Authenticated finish undo paints the prior Walnut choice onto the same surface.")
	check(app.sim.funds==before_funds,"Finish commit and undo leave the household wallet unchanged.")
	tx=null;app.queue_free();await process_frame;await process_frame
	FileAccess.open("user://starter_floor_finish.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("STARTER_FLOOR_FINISH ",checks,"/",failures.size());quit(1 if failures.size() else 0)
