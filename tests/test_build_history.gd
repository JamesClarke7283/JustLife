extends SceneTree
## Controlled real-main interleaved history regression. No traversal claim.
const Building=preload("res://scripts/building_state.gd")
var app:Node
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func frames(count:int=3)->void:
	for index:int in range(count):await process_frame
func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app;await frames()
	app.set_sound(false);app.start_household();app.sim.set_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	for item:Dictionary in app.world.items:item.node.queue_free()
	app.world.items.clear()
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"}]
	for side:int in [-1,1]:state.walls.append({"id":"north" if side<0 else "south","level":0,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	app.world.construction.restore(state);app._refresh_sim_targets(false);await frames()
	app.set_build_mode(true);app.set_build_level(1)
	var initial:int=app.sim.funds
	var floor:Dictionary=app.build_transactions.prepare({"op":"add","collection":"floors","record":{"level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e","supports":["north","south"]}})
	check(bool(floor.ok),"Controlled first actual structure quote is valid.")
	app.on_construction({"valid":true,"build_quote":floor});await frames()
	app.on_placement("plant",Vector3(-3,3.16,3),0);await frames()
	var stair:Dictionary=app.build_transactions.prepare({"op":"add","collection":"stairs","record":{"x":-2.0,"z":0.0,"rotation":90}})
	check(bool(stair.ok),"Controlled second actual structure quote is valid after furnishing.")
	app.on_construction({"valid":true,"build_quote":stair});await frames()
	check(app.build_undo.size()==3 and app.sim.funds==initial-1655,"Actual main has structure A, furnishing F, structure B with their exact charges.")
	app.undo_build();await frames()
	var rebased_revision:int=app.world.construction.building_state.revision
	check(app.world.construction.stair_nodes.is_empty() and app.build_undo.size()==2 and app.sim.funds==initial-1005,"Actual main undo B restores its own charge first.")
	app.undo_build();await frames()
	check(app.world.items.is_empty() and app.sim.funds==initial-960,"Actual main furnishing undo removes only its plant and restores§45.")
	check(int(app.world.construction.building_state.revision)>=rebased_revision,"Furnishing undo never rewinds the current structural revision.")
	app.undo_build();await frames()
	check(app.build_undo.is_empty() and app.world.construction.building_state.floors.size()==1 and app.sim.funds==initial,"Actual main can still undo A after the intervening furnishing undo.")
	# Reverse interleaving crosses a legitimate legacy-to-canonical migration.
	app.set_build_level(0);app.world.construction.restore({"kind":"__construction","walls":[],"floors":[]});app.world.rebuild_navigation();app.floor_color="896953"
	app.on_placement("plant",Vector3(-3,.16,3),0);await frames()
	var wall:Dictionary=app.build_transactions.prepare({"op":"structure","tool":"wall","level":0,"ax":1.0,"az":-2.0,"bx":3.0,"bz":-2.0})
	app.on_construction({"valid":true,"build_quote":wall});await frames()
	check(app.build_undo.size()==2 and app.sim.funds==initial-155,"Actual main retains a pre-migration furnishing followed by a canonical wall purchase.")
	app.undo_build();await frames()
	var migration_revision:int=app.world.construction.building_state.revision
	app.undo_build();await frames()
	check(app.build_undo.is_empty() and app.world.items.is_empty() and app.sim.funds==initial and int(app.world.construction.building_state.revision)==migration_revision,"Legacy furnishing undo preserves the migrated structure/revision while refunding only itself.")
	check(app.world.construction.building_state.floors[0].material=="896953","Reverse interleaving preserves the legitimate legacy floor finish.")
	var file:=FileAccess.open("user://build_history.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	app.queue_free();await frames();print("BUILD_HISTORY checks=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
