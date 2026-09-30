extends SceneTree
## A failed physical house move must roll its purchase back before saving.
## Also rejects a subset-party trip while a nontraveller is really on stairs.
const Building=preload("res://scripts/building_state.gd")
const Properties=preload("res://scripts/properties.gd")
const Library=preload("res://scripts/save_library.gd")
const DT:float=.05
var app:Node
var checks:int=0
var failures:int=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func frames(n:int=2)->void:
	for i:int in n:await process_frame
func quiet()->void:
	app.household.set_speed(0)
	for member:Dictionary in app.household.members:
		member.sim.autonomy=false
		while not member.sim.action_queue.is_empty():member.sim.cancel_action()
	for id:String in LifeResidents.PEOPLE:app.world.actors[id].visible=false
func clock_minutes()->float:return (app.household.day-1)*1440.0+app.household.minutes
func insurance()->Dictionary:
	var result:Dictionary={}
	for member:Dictionary in app.household.members:
		var sim:LifeSim=member.sim
		result[str(member.id)]={"policy":sim.insurance_policy_id,"bill":sim.pending_bill.duplicate(true),"cut":sim.utilities_cut,"paid":sim.bills_paid_total,"late":sim.bills_late,"day":sim.last_bill_day}
	return result
func settle_trip()->void:
	for step:int in 1800:
		if app.mode!="travel":return
		app._process(DT)
		if step%20==0:await process_frame

func run()->void:
	if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():push_error("Use private JUSTLIFE_DATA_DIR");quit(2);return
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	app.household_profiles=[{"name":"Moving owner","age_stage":"adult","traits":[],"hair":0},{"name":"Moving companion","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();await frames();quiet()
	app.household.set_funds(200000)
	app._buy_property_policy("premium");app.close_overlay(false);quiet()
	check(bool(app.build_transactions.buy_land("west").get("ok",false)),"The original home owns an expanded plot")
	app.home_layout=app.world.serialize_items();app.properties=app._properties_for_save()
	var prior:Dictionary={"properties":app.properties.duplicate(true),"funds":app.household.funds,"layout":app.world.serialize_items(),"home":app.home_layout.duplicate(true),"insurance":insurance(),"clock":clock_minutes()}
	var world:Node=app.world;var land:Dictionary=Building.land
	var original_home:String=Properties.active(app.properties)
	var cost:int=Properties.move_cost(app.properties,"medium")
	app._move_house("medium")
	check(app.mode=="travel" and not app.pending_house_move.is_empty() and Properties.active(app.properties)=="medium" and app.household.funds==int(prior.funds)-cost,"The physical move reserves the quoted purchase and begins boarding")
	if app.mode!="travel":await finish();return
	var endpoint:Vector3=app.residents.trip.boarding.player.endpoint
	app.world.actors.maya.position=endpoint;app.world.actors.maya.visible=true
	await settle_trip()
	check(app.mode=="live" and app.current_venue=="home" and app.residents.trip.is_empty(),"An unreachable car endpoint cancels the house move within the deadline")
	check(app.pending_house_move.is_empty() and app.properties==prior.properties,"Cancellation removes the pending move and restores all original property records")
	check(app.household.funds==int(prior.funds) and app.home_layout==prior.home and insurance()==prior.insurance,"Cancellation refunds exactly the purchase and restores home cache, insurance and bill mirrors")
	check(is_same(app.world,world) and is_same(Building.land,land) and app.world.serialize_items()==prior.layout and clock_minutes()==float(prior.clock),"Cancellation preserves the original physical house, exact land object and clock")
	check(not Properties.owns(app.properties,"medium") and Properties.active(app.properties)==original_home,"A canceled purchase leaves no newly owned house or changed active property")
	check(app.save_game("house_move_aborted","Canceled move"),"The canceled move can be saved normally")
	var read:Dictionary=Library.read_slot("house_move_aborted")
	check(bool(read.get("ok",false)),"The cancellation save passes the ordinary save validator")
	if bool(read.get("ok",false)):
		var data:Dictionary=read.data
		var context:Dictionary=data.members[int(data.selected_index)].state.character.world_state
		check(str(context.properties.active)==original_home and not context.properties.houses.has("medium") and context.properties.houses[original_home].layout==data.world,"Saving associates the actual furnishings only with the original home")
		check(int(data.funds)==int(prior.funds) and str(data.members[0].state.insurance_policy_id)=="premium","The refund and original insurance survive the disk save")
	# Remove the deliberate obstruction and retry through the same public move
	# callback. A successful purchase commits once and discards rollback data.
	quiet();app._move_house("medium");await settle_trip()
	check(app.mode=="live" and Properties.active(app.properties)=="medium" and app.pending_house_move.is_empty(),"A later unblocked move succeeds and clears its rollback transaction")
	check(app.household.funds==int(prior.funds)-cost and is_equal_approx(clock_minutes(),float(prior.clock)+15.0),"The successful retry charges exactly one purchase and the normal drive time")
	check(Properties.house(app.properties,original_home).layout==prior.layout and app.world.last_layout_error.is_empty(),"The successful move retains the old property's layout and builds a valid destination")
	await nontraveller_stair_control()
	await finish()

func nontraveller_stair_control()->void:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"},{"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]}]
	state.walls=[{"id":"north","level":0,"x":0.0,"z":-5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"},{"id":"south","level":0,"x":0.0,"z":5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"}]
	var quote:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
	check(bool(quote.ok),"The nontraveller control has a supported real staircase")
	if not bool(quote.ok):return
	app.loading_game=true;app.setup_live([quote.after]);app.loading_game=false;await frames();quiet()
	app.world.actors.player.position=Vector3(-3,.16,-3)
	app.world.actors.housemate_1.position=Vector3(0,.16,-3.5)
	var planned:Dictionary=app.traversal.request("housemate_1",Vector3(2,Building.level_y(1),3))
	check(bool(planned.ok),"The companion receives a real route through the staircase")
	if not bool(planned.ok):return
	for step:int in 400:
		app.traversal.advance("housemate_1",DT,1)
		var at:Vector3=app.world.actors.housemate_1.position
		if str(app.traversal.routes.get("housemate_1",{}).get("phase",""))=="transit" and at.y>.6 and at.y<2.7:break
	var at:Vector3=app.world.actors.housemate_1.position
	check(app.traversal.busy("housemate_1") and at.y>.6 and at.y<2.7,"The nontravelling companion is physically between floors")
	var traversal:LifeTraversal=app.traversal
	var route:Dictionary=traversal.routes.get("housemate_1",{})
	var locks:Dictionary=traversal.stairs.duplicate(true)
	check(not app.residents.begin_trip("park",["player"]),"A subset-party trip refuses while somebody staying behind is on stairs")
	check(is_same(app.traversal,traversal) and is_same(app.traversal.routes.get("housemate_1",{}),route) and app.traversal.stairs==locks and app.world.actors.housemate_1.position==at and app.world.actors.housemate_1.visible,"Refusal preserves the exact nontraveller route, stair ownership, body and visibility")
	var before:Dictionary=app.properties.duplicate(true);var funds:int=app.household.funds;var policies:Dictionary=insurance()
	app._move_house("willow")
	check(app.pending_house_move.is_empty() and app.properties==before and app.household.funds==funds and insurance()==policies and app.mode=="live","House-move preflight refusal rolls back its quote instead of completing a forced move")

func finish()->void:
	app.queue_free();await frames(3)
	print("HOUSE_MOVE_ABORT %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
