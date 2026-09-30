extends "res://tests/test_save_land_validation.gd"
## Real controller/world checks for temporary land used by load preflight.
## Reuse the detached fixture; reconstruction refusal happens only after an
## imported candidate house and its three household actors have been built.
var app:Node

func frames(count:int=2)->void:
	for i:int in count:await process_frame

func start_home(name:String)->void:
	app.household_profiles=[{"name":name,"age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household()
	app.set_process(false);app.set_sound(false);app.household.set_speed(0)
	app.sim.autonomy=false
	while not app.sim.action_queue.is_empty():app.sim.cancel_action()
	app.household.set_funds(100000)

func facts()->Dictionary:
	return {"household":app.household.get_state(app.world.serialize_items()).duplicate(true),
		"physical":app._physical_snapshot_context().duplicate(true),"routes":app.traversal.snapshot().duplicate(true),
		"residents":app.residents.snapshot().duplicate(true),"slot":app.active_save_id,
		"epoch":app.load_epoch,"generation":app.route_generation,"venue":app.current_venue,
		"navigation_region":app.world.navigation.region,"children":app.get_child_count()}

func _run()->void:
	var original:Dictionary=Building.land
	app=load("res://tests/rejecting_load_controller.gd").new();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	start_home("Saved west home")
	check(bool(app.build_transactions.buy_land("west").get("ok",false)),"The saved guest home buys a genuine west plot")
	app.world.add_item({"id":"west_easel","kind":"easel","x":-22.0,"z":0.0,"rotation":0.0})
	app.sim.relationships.maya.friendship=30
	check(app.residents.home_visit.invite("maya"),"A normal friend invitation creates a physical arriving guest")
	# Avoid a preview render; the ordinary public save still captures every
	# household, resident, guest, land and motion field.
	app.overlay_open=true
	var saved:bool=app.save_game("land_guest_west","Guest on an expanded west plot")
	check(saved,"The public save records the active guest and the expanded lot")
	if not saved:
		print("SAVE_ERROR ",app.notice_text);await finish(original);return
	var guest:Dictionary=Library.read_slot("land_guest_west").data
	check(not guest.has("journeys") and not LifeHomeVisit.saved_visit(guest).value.visit.is_empty(),"The guest fixture uses the legacy load path with an active visit")
	start_home("Existing east home")
	check(bool(app.build_transactions.buy_land("east").get("ok",false)) and bool(app.build_transactions.buy_land("east").get("ok",false)),"The existing household owns two different east plots")
	await frames()
	var live:Dictionary=Building.land
	var current_world:Node=app.world;var current_household:Node=app.household
	var current_sim:Node=app.sim;var current_actor:Node=app.player
	var canonical:Dictionary=fixture(3)
	check(bool(Library.save_slot("land_staged_west","Canonical west plot",canonical).get("ok",false)),"A valid canonical household is ready for staged reconstruction")
	var before:Dictionary=facts()
	app.load_game("land_staged_west")
	check(str(app.notice_text)=="Controlled reconstruction rejection after staging.","The public load reaches real candidate construction before controlled rejection")
	land_unchanged(live,"Rejected staged load")
	check(is_same(app.world,current_world) and is_same(app.household,current_household) and is_same(app.sim,current_sim) and is_same(app.player,current_actor),"Rejected staging preserves the live world, household, sim and actor identities")
	check(facts()==before,"Rejected staging preserves household, physical state, routes, residents, slot, epochs and candidate node count")
	check(app._legacy_layout_error(guest).is_empty(),"Legacy layout preflight accepts furnishing on the incoming west plot")
	land_unchanged(live,"Successful legacy layout preflight")
	check(app._legacy_visit_error(guest).is_empty(),"Legacy guest preflight builds and validates the guest on the saved west plot")
	land_unchanged(live,"Successful legacy guest preflight")
	check(facts()==before,"Successful preflight preserves the existing household and physical scene")
	var invalid:Dictionary=guest.duplicate(true)
	for entry:Dictionary in invalid.world:
		if str(entry.get("id",""))=="west_easel":entry.x=-99.0
	check(not app._legacy_layout_error(invalid).is_empty(),"Legacy layout preflight rejects furnishing outside the saved plot")
	land_unchanged(live,"Rejected legacy layout preflight")
	check(not app._legacy_visit_error(invalid).is_empty(),"Guest candidate construction also refuses the malformed layout")
	land_unchanged(live,"Rejected guest candidate construction")
	invalid=guest.duplicate(true);invalid.household_version=99
	check(not app._legacy_visit_error(invalid).is_empty(),"Guest preflight propagates an early candidate-household refusal")
	land_unchanged(live,"Rejected guest candidate household")
	check(facts()==before,"Both guest rejection paths preserve the existing household and scene")
	app.load_game("land_guest_west")
	check(int(app.load_epoch)==int(before.epoch)+1 and str(app.active_save_id)=="land_guest_west" and str(app.notice_text).begins_with("Welcome back"),"The public legacy loader actually adopts the valid expanded guest home")
	check(Building.land.west==1 and Building.land.east==0 and not is_same(Building.land,live),"A successful public load adopts the saved land instead of rolling it back")
	check(app.world.items.any(func(item:Dictionary)->bool:return str(item.get("id",""))=="west_easel") and app.world.last_layout_error.is_empty(),"The expanded-lot furnishing is physically reconstructed")
	check(str(app.residents.home_visit.state.get("phase",""))=="arriving" and app.residents.home_visit.physical_error().is_empty(),"The restored guest retains its valid physical arrival")
	await finish(original)

func finish(original:Dictionary)->void:
	app.queue_free();await frames(3);Building.land=original
	print("LOAD_LAND_ROLLBACK checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
