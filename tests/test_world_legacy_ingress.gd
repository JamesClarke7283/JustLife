extends SceneTree
const World=preload("res://scripts/world.gd")
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func _run()->void:
	var world:Node3D=World.new();root.add_child(world);await process_frame
	var plant:Dictionary={"id":"existing","kind":"plant","x":-2.0,"z":2.0,"rotation":0.0}
	var empty:Dictionary={"kind":"__construction","walls":[],"floors":[]}
	check(bool(world.load_home([plant,empty]).ok),"Valid imported plant and unversioned empty marker load successfully.")
	var normal:Dictionary={"kind":"__construction","walls":[{"id":"normal","x":0.0,"z":-4.0,"w":4.0,"d":.14}],"floors":[]}
	check(bool(world.load_home([plant,normal]).ok),"Legitimate legacy wall defaults still load without a version field.")
	await process_frame
	var original:Array=world.serialize_items();var original_house:Node3D=world.house
	var original_wall:Node3D=world.construction.wall_nodes["normal"]
	var malformed:Array=[]
	for value:Variant in [false,null,{},"walls"]:
		var marker:Dictionary=normal.duplicate(true);marker.walls=value;malformed.append(marker)
	var bad:Dictionary=normal.duplicate(true);bad.floors=false;malformed.append(bad)
	bad=normal.duplicate(true);bad.walls=[false];malformed.append(bad)
	bad=normal.duplicate(true);bad.walls[0].x="bad";malformed.append(bad)
	bad=normal.duplicate(true);bad.walls[0].color="notacolor";malformed.append(bad)
	for index:int in range(malformed.size()):
		var marker:Dictionary=malformed[index]
		check(not world.validate_home_layout([plant,marker]).is_empty(),"Malformed legacy marker rejects before scene validation: "+str(index))
		var result:Dictionary=world.load_home([plant,marker])
		check(not bool(result.ok) and world.house==original_house and world.serialize_items()==original,"Rejected legacy load preserves actual scene, furnishing and data: "+str(index))
		world.construction.restore(marker)
		check(not world.construction.last_error.is_empty() and world.construction.wall_nodes.get("normal")==original_wall and world.serialize_items()==original,"Direct restore also rejects before freeing actual geometry: "+str(index))
	world.construction.restore(normal)
	check(world.construction.last_error.is_empty() and world.items.size()==1,"Valid direct legacy restoration remains available after rejections.")
	var file:=FileAccess.open("user://world_legacy_ingress.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	world.queue_free();await process_frame
	print("WORLD_LEGACY_INGRESS checks=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
