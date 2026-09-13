extends SceneTree
## Explicit geometry/body fixtures. Actual transaction and paid queue controls;
## these are not a household traversal or named persistence demonstration.
const Building=preload("res://scripts/building_state.gd")
const World=preload("res://scripts/world.gd")
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
func base()->Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"}]
	for inner:bool in [false,true]:
		var prefix:String="inner_" if inner else ""
		var w:float=4.0 if inner else 8.0;var d:float=6.0 if inner else 10.0;var z:float=-1.0 if inner else 0.0
		for sign:int in [-1,1]:
			state.walls.append({"id":prefix+("west" if sign<0 else "east"),"level":0,"x":sign*w*.5,"z":z,"w":.14,"d":d,"height":2.6,"cut":true,"material":"eae7d7"})
			state.walls.append({"id":prefix+("north" if sign<0 else "south"),"level":0,"x":0.0,"z":z+sign*d*.5,"w":w,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
	return state
func record(inner:bool=false)->Dictionary:
	return {"level":0,"x":0.0,"z":-1.0 if inner else 0.0,"w":4.0 if inner else 8.0,"d":6.0 if inner else 10.0,"pitch":.75 if inner else .5,"rotation":90 if inner else 0,"material":"56606b" if inner else "57736a","supports":["inner_north","inner_south"] if inner else ["west","east"]}
func _run()->void:
	var app:=AppFixture.new();root.add_child(app);app.world=World.new();app.add_child(app.world)
	app.sim=LifeSim.new();app.add_child(app.sim);app.sim.new_household({});app.sim.autonomy=false;app.sim.set_speed(0);app.sim.funds=3000
	await process_frame
	var state:Dictionary=base()
	check(bool(app.world.load_home([state,{"id":"fridge","kind":"fridge","x":0.0,"z":-2.0,"rotation":0}]).ok),"Actual two-bearing-frame home and refrigerator load before roof edits.")
	var actor:=Node3D.new();app.world.add_child(actor);actor.position=Vector3(-.7,.16,3);app.world.actors["player"]=actor
	app.sim.register_targets(app.world.simulation_targets())
	check(app.sim.queue_action("snack","fridge",Vector3(0,.16,-1)),"Existing snack enters the real controlled queue.")
	app.sim.begin_current_action();check(bool(app.sim.get_current_action().paid) and app.sim.funds==2996,"One actual paid snack is the positive queue preservation control.")
	check(app.sim.queue_action("read","book",Vector3(-3,.16,3)),"A later explicit instruction is retained behind that paid action.")
	var queue:Array=app.sim.action_queue.duplicate(true);var needs:Dictionary=app.sim.needs.duplicate(true);var minutes:float=app.sim.minutes;var funds:int=app.sim.funds
	var tx=Transactions.new(app);var add:Dictionary={"op":"add","collection":"roofs","record":record()}
	var quote:Dictionary=tx.prepare(add)
	check(bool(quote.ok) and int(quote.cost)==1440 and app.sim.funds==funds and app.world.construction.snapshot()==state,"Detached roof preview costs exactly§1440 and changes no live geometry or funds.")
	if not bool(quote.ok):print(quote);_finish(app);return
	var tampered:Dictionary=quote.duplicate(true);tampered.cost=0;tampered.funds_after=funds
	check(not bool(tx.commit(tampered).ok) and app.sim.funds==funds,"A forged free-roof confirmation rejects without a charge.")
	var purchase:Dictionary=tx.commit(quote)
	check(bool(purchase.ok) and app.world.construction.roof_nodes.size()==1 and app.sim.funds==funds-1440,"Purchase installs one real parameterized roof and debits once.")
	if not bool(purchase.ok):print(purchase);_finish(app);return
	var old:Dictionary=app.world.construction.building_state.roofs[0].duplicate(true);var id:String=str(old.id)
	check(not bool(tx.commit(quote).ok) and app.world.construction.roof_nodes.size()==1 and app.sim.funds==funds-1440,"Replaying the purchase cannot charge or allocate a second roof.")
	var edit:Dictionary={"op":"roof_edit","id":id,"record":record(true)}
	var edit_quote:Dictionary=tx.prepare(edit)
	check(bool(edit_quote.ok) and int(edit_quote.cost)==-1008 and app.sim.funds==funds-1440,"Smaller rotated roof previews the exact area difference refund without changing the live roof.")
	if not bool(edit_quote.ok):print(edit_quote);_finish(app);return
	actor.position=Vector3(0,4.0,-1)
	check(not bool(tx.commit(edit_quote).ok) and app.sim.funds==funds-1440 and app.world.construction.building_state.roofs[0]==old,"A body entering the new roof headroom after preview blocks replacement before refund.")
	actor.position=Vector3(-.7,.16,3)
	var replaced:Dictionary=tx.commit(edit_quote)
	check(bool(replaced.ok) and app.sim.funds==funds-432,"Clear replacement refunds exactly§1008 once.")
	if not bool(replaced.ok):print(replaced);_finish(app);return
	var smaller:Dictionary=app.world.construction.building_state.roofs[0].duplicate(true)
	check(str(smaller.id)==id and int(smaller.rotation)==90 and float(smaller.pitch)==.75 and str(smaller.material)=="56606b" and app.world.construction.roof_nodes.size()==1,"Replacement preserves identity while reconstructing changed dimensions, yaw, pitch and material.")
	check(not bool(tx.commit(edit_quote).ok) and app.sim.funds==funds-432,"Repeated replacement cannot refund twice.")
	for value:Variant in [false,"0",.25]:
		var invalid:Dictionary=edit.duplicate(true);invalid.record.rotation=value
		check(not bool(tx.prepare(invalid,true).ok) and app.sim.funds==funds-432 and app.world.construction.building_state.roofs[0]==smaller,"Malformed replacement rotation rejects atomically: "+str(value))
	var foreign:Dictionary=edit.duplicate(true);foreign.record.id="forged"
	check(not bool(tx.prepare(foreign,true).ok),"A replacement cannot smuggle a different roof identity.")
	foreign=edit.duplicate(true);foreign.id="ground"
	check(not bool(tx.prepare(foreign,true).ok),"A floor identity cannot be used as a roof replacement.")
	var remove_quote:Dictionary=tx.prepare({"op":"remove","id":id},true)
	check(bool(remove_quote.ok) and int(remove_quote.cost)==0,"Demolition previews zero resale value separately from resize refunds.")
	var removed:Dictionary=tx.commit(remove_quote)
	check(bool(removed.ok) and app.world.construction.roof_nodes.is_empty() and app.sim.funds==funds-432,"Demolition removes the model and record together without a fabricated refund.")
	if not bool(removed.ok):print(removed);_finish(app);return
	check(not bool(tx.commit(remove_quote).ok) and app.sim.funds==funds-432,"Repeated demolition cannot mutate the wallet.")
	check(bool(tx.undo(removed.receipt).ok) and app.world.construction.building_state.roofs[0]==smaller and app.sim.funds==funds-432,"Undo demolition reconstructs the edited roof once, with no money change.")
	check(bool(tx.undo(replaced.receipt).ok) and app.world.construction.building_state.roofs[0]==old and app.sim.funds==funds-1440,"Undo replacement restores the original roof and reverses only its area refund.")
	check(bool(tx.undo(purchase.receipt).ok) and app.world.construction.roof_nodes.is_empty() and app.sim.funds==funds,"Undo purchase restores the exact initial wallet and roof-free structure.")
	check(not bool(tx.undo(purchase.receipt).ok) and app.sim.funds==funds,"Consumed roof history cannot refund twice.")
	check(app.sim.action_queue==queue and app.sim.needs==needs and app.sim.minutes==minutes,"All roof transactions preserve paid action, later instruction, needs and clock exactly.")
	_finish(app)
func _finish(app:Node)->void:
	var file:=FileAccess.open("user://roof_transactions.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	app.queue_free();await process_frame;print("ROOF_TRANSACTIONS checks=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
