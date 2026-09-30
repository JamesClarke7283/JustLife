extends SceneTree
const Building=preload("res://scripts/building_state.gd")
const Transactions=preload("res://scripts/build_transactions.gd")
class WorldFixture extends Node3D:
	var items:Array=[]
class AppFixture extends Node:
	var world:Node3D
var checks:int=0
var failures:int=0
func check(value:bool,label:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",label)
	if not value:failures+=1
func wall(id:String,x:float,z:float,width:float,level:int=0)->Dictionary:
	return {"id":id,"level":level,"x":x,"z":z,"w":width,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"}
func item(world:Node3D,id:String,x:float,z:float,level:int=0,kind:String="house_window")->Dictionary:
	var node:=Node3D.new();world.add_child(node);node.position=Vector3(x,Building.level_y(level),z)
	var entry:Dictionary={"id":id,"kind":kind,"x":x,"z":z,"level":level,"rotation":0,"node":node}
	world.items.append(entry);return entry
func _initialize()->void:run.call_deferred()
func run()->void:
	var app:=AppFixture.new();root.add_child(app);app.world=WorldFixture.new();app.add_child(app.world)
	var tx:=Transactions.new(app)
	var before:Dictionary=Building.fresh();before.walls=[wall("moving",0,0,4),wall("upper",0,0,4,1),wall("distant",10,0,4)]
	var after:Dictionary=before.duplicate(true);after.walls[0].z=1.0
	var moved:Dictionary=item(app.world,"moved",0,.13)
	var upper:Dictionary=item(app.world,"upper",0,.13,1)
	var distant:Dictionary=item(app.world,"distant",10,.13)
	check(tx._sync_wall_mounted_after_structure(before,after),"Moving a real host reports that a decoration refresh is needed")
	check(is_equal_approx(moved.node.position.z,1.13) and is_equal_approx(float(moved.z),1.13),"Window follows its actual wall in both scene and saved transform")
	check(is_equal_approx(upper.node.position.z,.13) and is_equal_approx(float(upper.z),.13),"Ground wall movement leaves a coincident upstairs window in place")
	check(is_equal_approx(distant.node.position.z,.13) and is_equal_approx(float(distant.z),.13),"Ground wall movement leaves a distant same-line window in place")
	check(tx._sync_wall_mounted_after_structure(after,before) and is_equal_approx(moved.node.position.z,.13),"Reverse movement restores the attached window")
	check(not tx._sync_wall_mounted_after_structure(before,before),"An unchanged wall does not request redundant rebuilding")
	app.world.items.clear()
	before.walls=[wall("left",-1.5,0,2),wall("right",1.5,0,2)]
	after=before.duplicate(true);after.walls[0].z=1.0;after.walls[1].z=1.0
	var door:Dictionary=item(app.world,"gap_door",0,.11,0,"house_door")
	var upper_door:Dictionary=item(app.world,"upper_door",0,.11,1,"house_door")
	check(tx._sync_wall_mounted_after_structure(before,after) and is_equal_approx(door.node.position.z,1.11),"A door between two moving stubs still follows the complete run")
	check(is_equal_approx(upper_door.node.position.z,.11),"Doorway-gap fallback also respects the storey")
	app.queue_free();await process_frame
	print("WALL_MOUNT_FOLLOW checks=%d failures=%d" % [checks,failures]);quit(0 if failures==0 else 1)
