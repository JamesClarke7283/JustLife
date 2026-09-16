extends SceneTree

const FurnishingTest = preload("res://tests/test_furnishing.gd")
## Iteration 60 living-room set, through the public paths only: the reading
## nook is bought like any furnishing and hosts the seated Read pastime (with
## the Bookworm chooser preferring it), the coffee table offers a real plate
## surface with its authored book-and-cup prop visible, and the arc lamp's
## menu switch survives serialize, a fresh load and a move. Headless.

var checks:int=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _find(app:Node,kind:String)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind:return item
	return {}

func _find_kind_level(app:Node,kind:String,level:int)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind and app.world.item_level(item)==level:return item
	return {}

func _fun_life(traits:Array)->LifeSim:
	# The component-probe ritual from test_autonomy_policy: a real LifeSim on
	# a fresh calendar with two free leisure targets and low Fun.
	var sim:LifeSim=LifeSim.new()
	sim.new_household({"name":"Rotation Adult","age_stage":"adult","traits":traits})
	sim.set_aging("normal",false);sim.household_bills_enabled=false
	sim.day=1;sim.career.schedule=LifeCareerSchedule.fresh(1);sim.minutes=600.0
	sim.education=LifeEducation.fresh("adult",1);sim.wants.clear()
	sim.register_targets([{"id":"nook","kind":"book_nook","position":Vector3.ZERO},{"id":"easel","kind":"easel","position":Vector3(3,.16,0)}])
	sim.needs.fun=20.0
	return sim

func _initialize()->void:_run.call_deferred()

func _run()->void:
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await process_frame;await process_frame
	app.selected_lot=0;app.start_household();await process_frame
	app.set_process(false)
	var world=app.world

	for expectation:Array in [["book_nook","Activities",240],["coffee_table","Decor",150],["floor_lamp","Decor",110]]:
		var data:Dictionary=LifeCatalog.get_item(str(expectation[0]))
		check(not data.is_empty() and str(data.get("category"))==str(expectation[1]) and int(data.get("price"))==int(expectation[2]),"%s sits in the catalogue at %s for §%d." % [str(expectation[0]),str(expectation[1]),int(expectation[2])])
	check(LifeCatalog.ITEMS.size()==51,"The catalogue now counts 51 furnishings.")

	app.household.set_funds(app.sim.funds+9000)
	app.set_build_mode(true)
	var wallet:int=app.household.funds
	for entry:Array in [["book_nook",-2.2,-2.2,90],["coffee_table",-1.5,2.3,0],["floor_lamp",-5.5,2.6,0]]:
		app.on_placement(str(entry[0]),Vector3(float(entry[1]),0.16,float(entry[2])),float(entry[3]))
	await process_frame
	check(world.items.size()>=3 and app.household.funds==wallet-500,"The three pieces are bought through the public build path for §500 together.")
	var nook:Dictionary=_find(app,"book_nook")
	var rotated:Rect2=world.furnishing_rect({"id":"probe","kind":"book_nook","x":0.0,"z":0.0,"rotation":90.0})
	check(rotated.size.x<rotated.size.y,"The reading nook's footprint turns with its rotation, so a 90° purchase fits a .75 m wall run.")
	check(not nook.is_empty(),"The reading nook is placed.")

	var actions:Array=app.sim.get_actions_for("book_nook",str(nook.id))
	var by_id:Dictionary={}
	for definition:Dictionary in actions:by_id[str(definition.id)]=definition
	check(by_id.has("read") and by_id.has("study") and bool(by_id.read.available) and bool(by_id.study.available),"The nook offers short and long reading through the same menu actions as the bookshelf.")
	check(FurnishingTest.queue_member_action(app,nook,"read"),"Read queues on the nook through the UI-faithful interaction path.")
	var reader:LifeSim=app.household.member_sim("player")
	check(str(reader.get_current_action().get("id",""))=="read" and str(reader.get_current_action().get("target_id",""))==str(nook.id),"The queued read targets the nook itself.")
	app.cancel_current_action()
	var anchor:Dictionary=world.activity_anchor(nook,"read")
	check(str(anchor.get("kind"))=="seat","The nook seats its reader on the bench like a chair, not standing beside it.")


	var plain_life:LifeSim=_fun_life([])
	var plain:Dictionary=plain_life.autonomy_need_choice("fun")
	plain_life.free()
	check(str(plain.get("id",""))=="paint","Without the trait the rotation starts at the canvas even with the nook free.")
	var bookish_life:LifeSim=_fun_life(["Bookworm"])
	var bookish:Dictionary=bookish_life.autonomy_need_choice("fun")
	bookish_life.free()
	check(str(bookish.get("id",""))=="read" and str(bookish.get("target_id",""))=="nook","A Bookworm heads straight for the reading nook, so the pastime is autonomous-eligible and trait-preferred.")

	var table:Dictionary=_find(app,"coffee_table")
	var slot:Vector3=app.meal_flow._surface_slot(table,LifeMeals.PLATTER_HALF_SIZE)
	check(slot.is_finite() and absf(slot.y-.46)<.003,"A platter finds a clear slot on the coffee table's .46 m top, so plates can be put down and taken.")
	var cup:Node=table.node.find_child("Teatime cup",true,false)
	var stack:Node=table.node.find_child("Coffee book",true,false)
	check(cup!=null and stack!=null and cup.is_visible_in_tree() and stack.is_visible_in_tree(),"The authored teacup and book prop stand on the tabletop.")

	var lamp:Dictionary=_find(app,"floor_lamp")
	var glow:Node=lamp.node.find_child("LampGlow",true,false)
	check(glow is OmniLight3D and glow.visible,"The arc lamp carries a warm OmniLight3D that starts lit.")
	app.switch_lamp(lamp)
	check(not world.item_lit(lamp) and not glow.visible,"The public switch turns the lamp off.")
	var saved:Array=world.serialize_items()
	var lamp_record:Dictionary={}
	for record:Dictionary in saved:
		if str(record.get("kind"))=="floor_lamp":lamp_record=record
	check(lamp_record.has("lit") and not bool(lamp_record["lit"]),"The switched-off state rides the layout record.")
	check(world.validate_home_layout(saved).is_empty(),"The layout with the lamp state still validates.")
	check(app.build_transactions.furnishing_error(saved).is_empty(),"The purchase-path validator accepts the saved layout.")

	app.loading_game=true;app.setup_live(saved);app.loading_game=false
	await process_frame
	var reloaded:Dictionary=_find(app,"floor_lamp")
	var reloaded_glow:Node=reloaded.node.find_child("LampGlow",true,false)
	check(not reloaded.is_empty() and reloaded_glow!=null and not reloaded_glow.visible,"A fresh load restores the lamp dark, so the switch persists across save and load.")
	app.set_build_mode(true)
	app.move_item(reloaded)
	await process_frame
	app.on_placement("floor_lamp",Vector3(-4.9,0.16,2.6),90.0)
	await process_frame
	var moved:Dictionary=_find(app,"floor_lamp")
	check(not moved.is_empty() and not world.item_lit(moved) and absf(moved.node.position.x-(-4.9))<.01,"Moving the lamp keeps it switched off.")
	var funds_before_sale:int=app.household.funds
	var nook_for_sale:Dictionary=_find(app,"book_nook")
	app.sell_item(nook_for_sale)
	await process_frame
	check(_find(app,"book_nook").is_empty() and app.household.funds==funds_before_sale+168,"Selling the nook through the build menu refunds §168 (70% of §240).")

	# The same pieces go upstairs through the two-floor suite's pattern: a
	# supported upper floor and the stair bought as public transactions, then
	# the upper build view, a green ghost preview and a real upper purchase.
	var upstairs_wallet:int=app.household.funds
	app.set_build_level(1)
	# The two-floor suite's clicks, driven through the same proposal path:
	# anchor the slab on one corner, propose the opposite corner, commit the quote.
	world.construction.tool="floor"
	world.construction.anchor=Vector3(-6,0,-5);world.construction.anchored=true
	var slab:Dictionary=world.construction.make_proposal(world.construction.snap(Vector3(6,0,5)))
	check(bool(slab.get("valid",false)) and slab.has("build_quote"),"The upper slab quote previews through the public proposal path (%s)." % str(slab.get("error","")))
	var slab_built:Dictionary=app.build_transactions.commit(slab.build_quote)
	check(bool(slab_built.ok),"The supported upper floor commits through the public structure transaction (%s)." % str(slab_built.get("error","")))
	world.construction.tool="stairs";world.construction.anchored=false;world.placement_angle=0.0
	var run:Dictionary=world.construction.make_proposal(world.construction.snap(Vector3(-1.5,0,-2.5)))
	check(bool(run.get("valid",false)) and run.has("build_quote"),"The stair quote previews through the public proposal path (%s)." % str(run.get("error","")))
	var run_built:Dictionary=app.build_transactions.commit(run.build_quote)
	check(bool(run_built.ok),"The stair commits through the public structure transaction (%s)." % str(run_built.get("error","")))
	world.construction.cancel()
	check(app.household.funds==upstairs_wallet-2090,"The supported upper floor and stair charge §1440 plus §650.")
	for buy:Array in [["coffee_table",Vector3(-4.0,3.16,2.5),0.0],["floor_lamp",Vector3(-4.0,3.16,3.5),90.0]]:
		world.begin_placement(str(buy[0]))
		# The same green-ghost computation the pointer preview runs.
		var spot:Vector3=Vector3(snappedf(buy[1].x,.25),3.16,snappedf(buy[1].z,.25))
		var green:bool=world.can_place(str(buy[0]),spot,float(buy[2]))
		if green and world.placement_reach_check.is_valid():green=bool(world.placement_reach_check.call(str(buy[0]),spot,float(buy[2])))
		check(green,"The %s ghost previews green on the supported upper floor." % str(buy[0]))
		app.on_placement(str(buy[0]),spot,float(buy[2]))
		await process_frame
	var upper_table:Dictionary=_find_kind_level(app,"coffee_table",1)
	var upper_lamp:Dictionary=_find_kind_level(app,"floor_lamp",1)
	check(not upper_table.is_empty() and not upper_lamp.is_empty(),"The coffee table and the floor lamp are purchased on the upper floor through the public build path.")
	var upper_glow:Node=upper_lamp.node.find_child("LampGlow",true,false)
	app.switch_lamp(upper_lamp)
	var carried:Array=world.serialize_items()
	var upper_record:Dictionary={}
	for record:Dictionary in carried:
		if str(record.get("kind"))=="floor_lamp" and int(record.get("level",0))==1:upper_record=record
	check(int(upper_record.get("level",0))==1 and upper_record.has("lit") and not bool(upper_record["lit"]),"The upstairs lamp rides its level and switched-off state in the same layout record.")
	check(world.validate_home_layout(carried).is_empty() and app.build_transactions.furnishing_error(carried).is_empty(),"The two-level layout with the lamp state validates and passes the purchase-path gate.")
	app.loading_game=true;app.setup_live(carried);app.loading_game=false
	await process_frame
	var restored:Dictionary=_find_kind_level(app,"floor_lamp",1)
	var restored_glow:Node=restored.node.find_child("LampGlow",true,false)
	check(not restored.is_empty() and restored_glow!=null and not restored_glow.visible,"A fresh load restores the upstairs lamp dark on the upper floor.")
	check(not world.item_lit(_find_kind_level(app,"floor_lamp",0)),"The ground lamp keeps its own independent switched-off state.")
	app.set_build_level(0)

	app.queue_free()
	await process_frame;await process_frame;await process_frame
	print("LIVING_V60 %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
