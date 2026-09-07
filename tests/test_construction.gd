extends SceneTree

var checks:int=0
var failures:int=0

func check(value:bool,message:String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world=LifeWorld.new()
	root.add_child(world)
	world.create_home(LifeCatalog.starter_layout())
	await process_frame
	check(world.construction.records.size()==9,"All nine starter wall segments are editable")
	check(world.path_to(Vector3(-.7,.16,2.8),Vector3(-7,.16,4.5)).size()>0,"The front door reaches a neighbor")
	var original=world.serialize_items()
	var counts=world.construction.records.size()
	world.construction.begin("wall")
	check(world.construction.click(Vector3(6.7,.16,-1)).is_empty(),"First wall click establishes anchor")
	var proposal=world.construction.click(Vector3(6.7,.16,2))
	check(proposal.get("valid",false),"Wall can be drawn on clear area of lot")
	check(proposal.cost==165,"Wall quote uses length")
	world.construction.commit(proposal)
	check(world.construction.records.size()==counts+1,"Committing adds a wall")
	check(world.construction.point_blocked(Vector2(6.5,.5)),"New wall blocks navigation")
	world.construction.begin("door")
	var doorway=world.construction.click(Vector3(6.5,.16,.5))
	check(doorway.get("valid",false),"Door opening selects wall")
	world.construction.commit(doorway)
	check(not world.construction.point_blocked(Vector2(6.5,.5)),"Doorway opens a real walkable gap")
	check(world.construction.point_blocked(Vector2(6.5,-.7)),"Door keeps the adjacent wall solid")
	world.construction.begin("room")
	world.construction.click(Vector3(-4,.16,5.8))
	var room=world.construction.click(Vector3(-1,.16,7))
	check(room.is_empty() or room.has("error"),"Room needs at least 1.5m in both dimensions")
	world.construction.cancel()
	world.construction.begin("room")
	world.construction.click(Vector3(-4,.16,5.5))
	room=world.construction.click(Vector3(-1,.16,7))
	check(room.get("valid",false),"Room rectangle fits the lot")
	world.construction.commit(room)
	check(world.construction.floor_contains(Vector2(-2.5,6.2)),"Room creates an extended floor")
	check(world.can_place("plant",Vector3(-2.5,.16,6.2),0),"New room accepts furniture")
	var serialized=world.serialize_items()
	var new_world=LifeWorld.new();root.add_child(new_world)
	new_world.create_home(serialized)
	await process_frame
	check(new_world.construction.records.size()==world.construction.records.size(),"Walls survive a fresh world reconstruction")
	check(new_world.construction.floor_records.size()==1,"Extended floor survives reload")
	check(not new_world.construction.point_blocked(Vector2(6.5,.5)),"Doorway survives reload")
	new_world.set_cutaway(false)
	check(new_world.construction.records.size()==world.construction.records.size(),"Changing wall view preserves structural data")
	world.construction.begin("wall")
	world.construction.click(Vector3(-5,.16,-4.5))
	var collision=world.construction.click(Vector3(-2,.16,-4.5))
	check(collision.has("error"),"Wall cannot pass through kitchen appliances")
	world.construction.cancel()
	var marker:Dictionary={}
	for entry in original:
		if entry.kind=="__construction":marker=entry
	world.construction.restore(marker)
	world.rebuild_navigation()
	check(world.construction.records.size()==counts,"Undo restores the original architecture")
	check(world.construction.floor_records.is_empty(),"Undo removes the added floor")
	world.queue_free();new_world.queue_free()
	await process_frame
	print("CONSTRUCTION_TESTS ",checks," assertions; ",failures," failures")
	quit(1 if failures>0 else 0)
