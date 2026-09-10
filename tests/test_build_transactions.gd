extends SceneTree
## Controlled transaction/occupancy tests with actual World and LifeSim.
## Fixture positions/paid snack activation are explicit setup, not traversal proof.
const World=preload("res://scripts/world.gd")
const Building=preload("res://scripts/building_state.gd")
const Transactions=preload("res://scripts/build_transactions.gd")
class AppFixture extends Node:
	var world:Node3D
	var sim:Node
	var floor_color:String="cfa97e"
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)
func base_state()->Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"}]
	for side:int in [-1,1]:state.walls.append({"id":"north" if side<0 else "south","level":0,"x":0.0,"z":side*5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	return state
func _run()->void:
	var app:=AppFixture.new();root.add_child(app)
	app.world=World.new();app.add_child(app.world)
	app.sim=LifeSim.new();app.add_child(app.sim);app.sim.new_household({});app.sim.autonomy=false;app.sim.set_speed(0);app.sim.funds=10000
	await process_frame
	var state:Dictionary=base_state()
	check(bool(app.world.load_home([{"id":"fridge","kind":"fridge","x":-2.5,"z":-3.0,"rotation":0},state]).ok),"Actual ground fixture loads with its real refrigerator.")
	var actor:=Node3D.new();app.world.add_child(actor);actor.position=Vector3(-3,.16,1);app.world.actors["player"]=actor
	app.sim.register_targets(app.world.simulation_targets())
	check(app.sim.queue_action("snack","fridge",Vector3(-2.5,.16,-2)) ,"Existing controlled snack uses the real simulation queue.")
	app.sim.begin_current_action()
	check(bool(app.sim.get_current_action().paid) and app.sim.funds==9992,"Controlled positive setup charges exactly one snack before building.")
	check(app.sim.queue_action("read","book",Vector3(-3,.16,3)),"A later explicit instruction is retained behind the paid activity.")
	var queue:Array=app.sim.action_queue.duplicate(true);var needs:Dictionary=app.sim.needs.duplicate(true);var minutes:float=app.sim.minutes
	var tx=Transactions.new(app)
	var floor_op:Dictionary={"op":"add","collection":"floors","record":{"level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e","supports":["north","south"]}}
	var quote:Dictionary=tx.prepare(floor_op)
	check(bool(quote.ok) and int(quote.cost)==960,"An actual supported upper floor previews its original area price.")
	check(app.world.construction.snapshot()==state and app.sim.funds==9992,"Preview changes neither geometry nor the shared wallet.")
	var forged:Dictionary=quote.duplicate(true);forged.cost=0;forged.funds_after=9992
	check(not bool(tx.commit(forged).ok) and app.sim.funds==9992 and app.world.construction.snapshot()==state,"A tampered free-floor quote rejects atomically.")
	app.sim.funds=959
	check(not bool(tx.prepare(floor_op,true).ok) and app.world.construction.snapshot()==state and app.sim.funds==959,"Insufficient funds cause no geometry or extra wallet mutation.")
	app.sim.funds=9992
	var purchase:Dictionary=tx.commit(quote)
	check(bool(purchase.ok) and app.sim.funds==9032 and app.world.construction.building_state.floors.size()==2,"Confirmation installs the slab and debits its price once.")
	var after_floor:Dictionary=app.world.construction.snapshot()
	check(not bool(tx.commit(quote).ok) and app.sim.funds==9032 and app.world.construction.snapshot()==after_floor,"Duplicate floor confirmation cannot charge or duplicate its identity.")
	check(tx.has_unintegrated_levels(),"Upper draft is explicitly marked unavailable for unfinished live/save flow.")
	var stair_op:Dictionary={"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}}
	var stair_quote:Dictionary=tx.prepare(stair_op)
	check(bool(stair_quote.ok) and int(stair_quote.cost)==650,"Stair quote includes opening and supported guard for one original price.")
	actor.position=Vector3(0,.16,-2.5)
	check(not bool(tx.commit(stair_quote).ok) and app.sim.funds==9032 and app.world.construction.snapshot()==after_floor,"A body arriving at the lower landing after preview blocks confirmation atomically.")
	actor.position=Vector3(-3,.16,1)
	var stair_purchase:Dictionary=tx.commit(stair_quote)
	check(bool(stair_purchase.ok) and app.sim.funds==8382 and app.world.construction.stair_nodes.size()==1 and app.world.construction.guard_nodes.size()==1,"Clear confirmation builds actual stair/opening/guard exactly once.")
	var stair_id:String=str(app.world.construction.building_state.stairs[0].id)
	var upstairs:=Node3D.new();app.world.add_child(upstairs);upstairs.position=Vector3(2,3.16,2);app.world.actors["upstairs_fixture"]=upstairs
	var removal:Dictionary=tx.prepare({"op":"remove","id":stair_id},true)
	check(not bool(removal.ok) and str(removal.error).contains("upstairs"),"Removing the sole stair cannot strand a controlled upstairs resident.")
	upstairs.visible=false
	check(not bool(tx.prepare({"op":"remove","id":stair_id},true).ok),"View-hidden at-home residents retain physical exit protection.")
	upstairs.visible=true;upstairs.position=Vector3(0,1.66,0)
	check(not bool(tx.prepare({"op":"remove","id":stair_id},true).ok),"A controlled mid-stair location blocks structural edits instead of rounding its level.")
	upstairs.position=Vector3(0,3.16,2.25)
	check(not bool(tx.undo(stair_purchase.receipt).ok) and app.sim.funds==8382,"Undo cannot remove an occupied upper landing or refund first.")
	app.world.actors.erase("upstairs_fixture");upstairs.queue_free()
	check(bool(tx.undo(stair_purchase.receipt).ok) and app.sim.funds==9032 and app.world.construction.building_state.stairs.is_empty(),"After the fixture leaves, stair undo restores its price and closes its owned hole.")
	check(bool(tx.undo(purchase.receipt).ok) and app.sim.funds==9992 and not tx.has_unintegrated_levels(),"LIFO undo also restores the earlier floor while retaining monotonic IDs/revisions.")
	check(not bool(tx.undo(stair_purchase.receipt).ok) and not bool(tx.undo(purchase.receipt).ok) and app.sim.funds==9992,"Consumed history tokens cannot refund either purchase twice.")
	check(app.sim.action_queue==queue and app.sim.needs==needs and app.sim.minutes==minutes,"Build transactions preserve the paid current activity, later queue, needs and clock exactly.")
	check(int(app.world.construction.building_state.revision)>int(after_floor.revision) and int(app.world.construction.building_state.next_serial)>int(state.next_serial),"Undo retains monotonic structural revisions and never reuses allocated IDs.")
	# All public structure tools use the same detached quote, occupancy and
	# authenticated undo path. No test writes actor progression or need recovery.
	var original_funds:int=app.sim.funds
	var wall_op:Dictionary={"op":"structure","tool":"wall","level":0,"ax":-1.0,"az":3.0,"bx":1.0,"bz":3.0}
	var wall_quote:Dictionary=tx.prepare(wall_op)
	check(bool(wall_quote.ok) and int(wall_quote.cost)==110,"Wall uses the original per-metre price through the transaction bridge.")
	actor.position=Vector3(0,.16,3)
	check(not bool(tx.commit(wall_quote).ok) and app.sim.funds==original_funds,"A body arriving in a wall preview blocks its later confirmation without charge.")
	actor.position=Vector3(-3,.16,1)
	var wall_purchase:Dictionary=tx.commit(wall_quote)
	check(bool(wall_purchase.ok) and app.sim.funds==original_funds-110,"Cleared wall confirmation creates one wall and debits once.")
	check(not bool(tx.commit(wall_quote).ok) and app.sim.funds==original_funds-110,"Repeated wall confirmation cannot reuse the original paid quote.")
	check(bool(tx.undo(wall_purchase.receipt).ok) and app.sim.funds==original_funds,"Wall history restores its own price.")
	var room_op:Dictionary={"op":"structure","tool":"room","level":0,"ax":1.0,"az":-2.0,"bx":3.0,"bz":0.0}
	var room_quote:Dictionary=tx.prepare(room_op)
	check(bool(room_quote.ok) and int(room_quote.cost)==440 and room_quote.after.floors.size()==1,"Room quotes four walls together and never bills existing floor area again.")
	var room_purchase:Dictionary=tx.commit(room_quote)
	check(bool(room_purchase.ok) and app.sim.funds==original_funds-440,"Whole room confirmation is one atomic transaction.")
	var door_wall:Dictionary={}
	for wall:Dictionary in app.world.construction.building_state.walls:
		if is_equal_approx(float(wall.x),3.0) and is_equal_approx(float(wall.z),-1.0):door_wall=wall
	var door_quote:Dictionary=tx.prepare({"op":"structure","tool":"door","level":0,"id":str(door_wall.id),"center":-1.0})
	check(bool(door_quote.ok) and int(door_quote.cost)==90,"Doorway preview replaces its wall with two validated portions for the original§90 fee.")
	var door_purchase:Dictionary=tx.commit(door_quote)
	check(bool(door_purchase.ok) and app.sim.funds==original_funds-530 and Building.find(app.world.construction.building_state,str(door_wall.id)).is_empty(),"Doorway consumes its exact old wall identity and charges once.")
	check(not bool(tx.commit(door_quote).ok) and app.sim.funds==original_funds-530,"Repeated doorway confirmation cannot charge the removed wall again.")
	check(bool(tx.undo(door_purchase.receipt).ok) and Building.find(app.world.construction.building_state,str(door_wall.id))==door_wall,"Door undo restores the exact original wall identity.")
	var finish_quote:Dictionary=tx.prepare({"op":"structure","tool":"finish","level":0,"material":"896953"})
	var finish_purchase:Dictionary=tx.commit(finish_quote)
	check(bool(finish_purchase.ok) and int(finish_quote.cost)==0 and app.world.construction.building_state.floors[0].material=="896953","A floor finish is a zero-cost validated structural history entry.")
	check(bool(tx.undo(finish_purchase.receipt).ok) and app.world.construction.building_state.floors[0].material=="cfa97e","Finish undo restores material without invalidating earlier geometry history.")
	var painted_wall:Dictionary=app.world.construction.building_state.walls[0]
	var wall_before:String=str(painted_wall.material)
	var paint_colour:String="8faf9f" if wall_before!="8faf9f" else "e6d8c5"
	var paint_quote:Dictionary=tx.prepare({"op":"structure","tool":"paint","level":0,"id":str(painted_wall.id),"material":paint_colour})
	var paint_purchase:Dictionary=tx.commit(paint_quote)
	check(bool(paint_purchase.ok) and int(paint_quote.cost)==int(maxf(float(painted_wall.w),float(painted_wall.d))*6) and str(app.world.construction.building_state.walls[0].material)==paint_colour,"Painting one wall charges by its length and records the colour in the validated building state.")
	check(not bool(tx.prepare({"op":"structure","tool":"paint","level":0,"id":str(painted_wall.id),"material":paint_colour}).ok),"Repainting a wall with its current colour is refused.")
	check(not bool(tx.prepare({"op":"structure","tool":"paint","level":0,"id":"wall_missing","material":paint_colour}).ok),"Painting an unknown wall is refused.")
	check(bool(tx.undo(paint_purchase.receipt).ok) and str(app.world.construction.building_state.walls[0].material)==wall_before,"Paint undo restores the previous wall colour.")
	var room_wall:Dictionary={}
	for wall:Dictionary in app.world.construction.building_state.walls:
		if is_equal_approx(float(wall.x),2.0) and is_equal_approx(float(wall.z),-2.0):room_wall=wall
	var room_colour:String="c8d7e0"
	var room_paint:Dictionary=tx.prepare({"op":"structure","tool":"paint","level":0,"id":str(room_wall.get("id","")),"material":room_colour,"scope":"room"})
	var room_paint_purchase:Dictionary=tx.commit(room_paint)
	var painted_count:int=app.world.construction.building_state.walls.filter(func(wall:Dictionary)->bool:return str(wall.material)==room_colour).size()
	check(bool(room_paint_purchase.ok) and int(room_paint.get("cost",0))==48 and painted_count==4,"Whole-room paint repaints the four walls joined corner to corner for §%d (%d walls)." % [int(room_paint.get("cost",0)),painted_count])
	check(str(app.world.construction.building_state.walls[0].material)==wall_before,"Whole-room paint leaves walls outside that room alone.")
	check(not bool(tx.prepare({"op":"structure","tool":"paint","level":0,"id":str(room_wall.get("id","")),"material":room_colour,"scope":"room"}).ok),"Repainting a room in its current colour is refused.")
	check(not bool(tx.prepare({"op":"structure","tool":"paint","level":0,"id":str(room_wall.get("id","")),"material":"8faf9f","scope":"house"}).ok),"An unknown paint scope is refused.")
	check(bool(tx.undo(room_paint_purchase.receipt).ok) and app.world.construction.building_state.walls.filter(func(wall:Dictionary)->bool:return str(wall.material)==room_colour).is_empty(),"Whole-room paint undo restores all four walls in one step.")
	check(bool(tx.undo(room_purchase.receipt).ok) and app.sim.funds==original_funds,"Room undo still works after doorway, finish and room-paint undos, refunding only its own cost.")
	check(app.sim.action_queue==queue and app.sim.needs==needs and app.sim.minutes==minutes,"Wall, room, door and finish commits preserve paid current action, later instruction and time.")
	var upper_state:Dictionary=after_floor.duplicate(true)
	var unsupported:Dictionary=LifeBuildingEdits.propose(upper_state,{"op":"structure","tool":"wall","level":1,"ax":-4.0,"az":-4.0,"bx":-4.0,"bz":4.0},10000)
	check(bool(unsupported.ok),"A real upper perimeter wall retains the full supported edge-bearing rule.")
	var invalid:Dictionary=LifeBuildingEdits.propose(upper_state,{"op":"structure","tool":"wall","level":1,"ax":5.0,"az":-4.0,"bx":5.0,"bz":4.0},10000)
	check(not bool(invalid.ok) and str(invalid.error).contains("floor"),"An unsupported upper wall is rejected before a quote can spend funds.")
	app.world.construction.tool="wall";app.world.construction.anchored=true;app.world.construction.anchor=Vector3(-2,.16,3)
	var legacy_half_wall:Dictionary=app.world.construction._make_legacy_proposal(Vector3(-1.5,.16,3))
	var current_half_wall:Dictionary=tx.prepare({"op":"structure","tool":"wall","level":0,"ax":-2.0,"az":3.0,"bx":-1.5,"bz":3.0})
	check(bool(current_half_wall.ok) and int(current_half_wall.cost)==int(legacy_half_wall.cost) and int(current_half_wall.cost)==27,"Half-metre wall price matches the actual legacy preview's whole-quote currency truncation.")
	app.world.construction.cancel()
	var legacy_app:=AppFixture.new();root.add_child(legacy_app)
	legacy_app.world=World.new();legacy_app.add_child(legacy_app.world)
	legacy_app.sim=LifeSim.new();legacy_app.add_child(legacy_app.sim);legacy_app.sim.new_household({});legacy_app.sim.set_speed(0);legacy_app.sim.autonomy=false;legacy_app.sim.funds=2500
	legacy_app.floor_color="896953"
	check(bool(legacy_app.world.load_home([{"kind":"__construction","walls":[],"floors":[]}]).ok),"A separate legitimate unversioned home is the migration positive control.")
	var legacy_tx:=Transactions.new(legacy_app)
	var legacy_quote:Dictionary=legacy_tx.prepare({"op":"structure","tool":"wall","level":0,"ax":-2.0,"az":0.0,"bx":2.0,"bz":0.0})
	var legacy_purchase:Dictionary=legacy_tx.commit(legacy_quote)
	check(bool(legacy_purchase.ok) and legacy_app.world.construction.building_state.floors[0].material=="896953","Canonical editing preserves the existing starter-floor finish stored in legacy world presentation.")
	legacy_tx=null;legacy_app.queue_free();await process_frame
	var file:=FileAccess.open("user://build_transactions.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	tx=null;app.queue_free();await process_frame
	print("BUILD_TRANSACTIONS checks=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
