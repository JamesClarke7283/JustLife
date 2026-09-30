extends SceneTree
## Actual scene/quote/commit/undo coverage. Fixture setup does not claim traversal.
const Building=preload("res://scripts/building_state.gd")
const Transactions=preload("res://scripts/build_transactions.gd")
class GardenWorld extends LifeWorld:
	var reject_next_rebuild:bool=false
	func rebuild_navigation()->void:
		super.rebuild_navigation()
		if reject_next_rebuild:
			reject_next_rebuild=false
			last_layout_error="Injected navigation rejection"
class AppFixture extends Node:
	var world:Node3D
	var sim:Node
	var floor_color:String="cfa97e"
var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message)
func _initialize()->void:_run.call_deferred()
func plant(world:Node3D,id:String)->Dictionary:
	for entry:Dictionary in world.items:
		if str(entry.id)==id:return entry
	return {}
func decor(world:Node3D,id:String)->Node3D:
	for node:Node3D in world._live_vegetation():
		if str(node.get_meta("vegetation_id"))==id:return node
	return null
func _run()->void:
	Building.set_land({})
	var app:=AppFixture.new();root.add_child(app)
	app.world=GardenWorld.new();app.add_child(app.world)
	app.sim=LifeSim.new();app.add_child(app.sim);app.sim.new_household({});app.sim.autonomy=false;app.sim.set_speed(0);app.sim.funds=20000
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":12.0,"d":10.0,"material":"896953"}]
	var plants:Array=[
		{"id":"bought_tree","kind":"tree_garden","x":8.0,"z":0.0,"rotation":90,"style":"c","size":"small","color":"749752"},
		{"id":"bought_shrub","kind":"shrub","x":7.5,"z":-2.2,"rotation":45,"style":"02","size":"medium","color":"48794b"},
		{"id":"kept_tree","kind":"tree_garden","x":-9.0,"z":0.0,"rotation":0}]
	check(bool(app.world.load_home(plants+[state]).ok),"Scene loads the garden fixture with an independently finished floor")
	await process_frame
	check(not plant(app.world,"bought_tree").is_empty() and not plant(app.world,"bought_shrub").is_empty(),"Purchased tree and shrub models actually exist")
	var tree:Node3D=decor(app.world,"tree_7550_-1200")
	var bush:Node3D=decor(app.world,"bush_6850_-2000")
	var distant:Node3D=decor(app.world,"tree_-7550_-1200")
	check(is_instance_valid(tree) and is_instance_valid(bush) and is_instance_valid(distant),"Authored tree and foundation bush have stable identities")
	if not is_instance_valid(tree) or not is_instance_valid(bush) or plant(app.world,"bought_tree").is_empty() or plant(app.world,"bought_shrub").is_empty():
		_finish(app);return
	check(tree.visible and bush.visible and distant.visible,"Existing garden is visible before construction")
	var tx:=Transactions.new(app);app.world.construction.quote_provider=tx.prepare
	var original:Array=app.world.serialize_items();var wallet:int=app.sim.funds
	var bought_node:Node3D=plant(app.world,"bought_tree").node
	var shrub_node:Node3D=plant(app.world,"bought_shrub").node
	app.world.construction.begin("room")
	check(app.world.construction.click(Vector3(6.5,.16,-3)).is_empty(),"First real construction click only anchors the room")
	for point:Vector3 in [Vector3(8.5,.16,.5),Vector3(9,.16,1),Vector3(8,.16,0),Vector3(9,.16,1)]:
		app.world.construction.update_preview(point)
		check(app.world.serialize_items()==original and app.sim.funds==wallet and tree.visible and bush.visible and bought_node.is_inside_tree(),"Room drag preview leaves floor, plants, wallet and live state untouched")
	app.world.construction.cancel()
	check(app.world.serialize_items()==original and tree.visible and bush.visible,"Cancel keeps all scenery and purchased plants")
	app.world.construction.begin("room");app.world.construction.click(Vector3(6.5,.16,-3))
	var proposal:Dictionary=app.world.construction.click(Vector3(9,.16,1))
	check(bool(proposal.get("valid",false)),"Room overlapping only garden vegetation receives a valid quote: "+str(proposal.get("error","")))
	if not bool(proposal.get("valid",false)):_finish(app);return
	var quote:Dictionary=proposal.build_quote
	check(quote.cleared_furnishings.size()==2,"Quote identifies precisely the two purchased plants inside the new room")
	var forged:Dictionary=quote.duplicate(true);forged.cleared_furnishings=[]
	check(not bool(tx.commit(forged).ok) and app.world.serialize_items()==original,"A forged vegetation-removal list is rejected without mutation")
	app.world.reject_next_rebuild=true
	check(not bool(tx.commit(quote).ok),"Navigation rejection rolls back the entire room purchase")
	check(app.world.serialize_items()==original and app.sim.funds==wallet and plant(app.world,"bought_tree").node==bought_node and plant(app.world,"bought_shrub").node==shrub_node and tree.visible and bush.visible,"Rollback preserves exact plant nodes, order, transforms, structure and funds")
	var purchase:Dictionary=tx.commit(quote)
	check(bool(purchase.ok),"The same valid room can be bought after a rolled-back failure: "+str(purchase.get("error","")))
	if not bool(purchase.ok):_finish(app);return
	check(not tree.visible and not bush.visible and distant.visible,"Commit clears intersecting authored tree and bush while preserving distant planting")
	check(plant(app.world,"bought_tree").is_empty() and plant(app.world,"bought_shrub").is_empty() and not plant(app.world,"kept_tree").is_empty(),"Commit removes purchased intersecting plants and keeps unrelated plants")
	check(app.sim.funds==wallet-int(quote.cost) and app.world.construction.building_state.floors.size()==2,"Room creates its explicit floor and charges only the quoted construction cost")
	var saved:Array=JSON.parse_string(JSON.stringify(app.world.serialize_items()))
	var reopened:=GardenWorld.new();root.add_child(reopened)
	check(bool(reopened.load_home(saved).ok),"Saved cleared garden layout reconstructs successfully")
	await process_frame
	check(not decor(reopened,"tree_7550_-1200").visible and not decor(reopened,"bush_6850_-2000").visible and plant(reopened,"bought_tree").is_empty() and plant(reopened,"bought_shrub").is_empty(),"Fresh scene reload preserves both scenery and purchased-plant removal")
	var flowers_before:Array=[]
	for node:Node3D in reopened._live_vegetation():
		if str(node.get_meta("vegetation_id")).begins_with("flowers_"):flowers_before.append(str(node.get_meta("vegetation_id")))
	check(bool(reopened.load_home(saved).ok),"The same world can reload its saved garden")
	var flowers_after:Array=[]
	for node:Node3D in reopened._live_vegetation():
		if str(node.get_meta("vegetation_id")).begins_with("flowers_"):flowers_after.append(str(node.get_meta("vegetation_id")))
	check(flowers_before.size()==24 and flowers_after==flowers_before,"Repeated reconstruction keeps all authored flower identities stable")
	reopened.draw_ground()
	check(not decor(reopened,"tree_7550_-1200").visible,"Ground regeneration does not resurrect cleared trees")
	var demolished:Dictionary=reopened.construction.snapshot();demolished.walls=[];demolished.floors=state.floors.duplicate(true)
	reopened.construction.restore(demolished)
	check(not decor(reopened,"tree_7550_-1200").visible and not decor(reopened,"bush_6850_-2000").visible,"Saved clearing remains after the covering structure is removed")
	check(bool(tx.undo(purchase.receipt).ok),"Undo restores the garden and refunds exactly once")
	check(tree.visible and bush.visible and app.sim.funds==wallet and app.world.construction.building_state.floors==state.floors,"Undo restores scenery, original floor finish and wallet")
	var restored:Array=app.world.serialize_items()
	for id:String in ["bought_tree","bought_shrub","kept_tree"]:
		var before_entry:Dictionary={};var after_entry:Dictionary={}
		for entry:Dictionary in original:
			if str(entry.get("id",""))==id:before_entry=entry
		for entry:Dictionary in restored:
			if str(entry.get("id",""))==id:after_entry=entry
		check(before_entry==after_entry,"Undo restores complete saved style/size/colour/transform for "+id)
	check(not bool(tx.undo(purchase.receipt).ok) and app.sim.funds==wallet,"Replaying a consumed undo cannot duplicate plants or money")
	# A genuine two-click wall grab uses the same transaction path.
	var seed:Dictionary=tx.prepare({"op":"structure","tool":"wall","level":0,"ax":5.0,"az":-3.0,"bx":5.0,"bz":-1.0})
	var seed_purchase:Dictionary=tx.commit(seed)
	check(bool(seed_purchase.ok),"A seed wall is built for the actual grab gesture")
	if bool(seed_purchase.ok):
		var before_grab:Array=app.world.serialize_items();var before_floor:Array=app.world.construction.building_state.floors.duplicate(true)
		app.world.construction.begin("grab")
		check(app.world.construction.click(Vector3(5,.16,-2)).is_empty() and not app.world.construction.grab_id.is_empty(),"First grab click selects the real wall")
		app.world.construction.update_preview(Vector3(7.5,.16,-2))
		check(app.world.serialize_items()==before_grab and not plant(app.world,"bought_shrub").is_empty(),"Actual wall drag preview does not move floor or remove the shrub")
		var grab:Dictionary=app.world.construction.click(Vector3(7.5,.16,-2))
		check(bool(grab.get("valid",false)),"Second grab click quotes the moved wall through the shrub")
		if bool(grab.get("valid",false)):
			var moved:Dictionary=tx.commit(grab.build_quote)
			check(bool(moved.ok) and app.world.construction.building_state.floors==before_floor and plant(app.world,"bought_shrub").is_empty(),"Confirmed wall grab clears obstruction without resizing or repainting floor")
			if bool(moved.ok):check(bool(tx.undo(moved.receipt).ok) and not plant(app.world,"bought_shrub").is_empty(),"Grab undo restores the purchased shrub and wall")
		check(bool(tx.undo(seed_purchase.receipt).ok),"Earlier wall history remains usable after grab undo")
	reopened.queue_free();_finish(app)
func _finish(app:Node)->void:
	app.queue_free()
	print("BUILD_VEGETATION checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
