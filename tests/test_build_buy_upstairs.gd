extends SceneTree
const Building=preload("res://scripts/building_state.gd")
const Edits=preload("res://scripts/building_edits.gd")
const Presets=preload("res://scripts/upstairs_presets.gd")
const Transactions=preload("res://scripts/build_transactions.gd")
const ToolsPanel=preload("res://scripts/build_buy_panel.gd")
class AppFixture extends Node:
	var world:Node3D
	var sim:Node
	var floor_color:String="cfa97e"
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func room(width:float=12.,depth:float=10.)->Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.,"z":0.,"w":width,"d":depth,"material":"cfa97e"}]
	for side:int in [-1,1]:
		state.walls.append({"id":"north" if side<0 else "south","level":0,"x":0.,"z":side*depth*.5,"w":width,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
		state.walls.append({"id":"west" if side<0 else "east","level":0,"x":side*width*.5,"z":0.,"w":.14,"d":depth,"height":2.6,"cut":true,"material":"eae7d7"})
	return state
func choices(index:int)->Dictionary:return {"choice":index,"wall_color":"8faf9f","floor_color":"896953","roof_color":"56606b","roof_style":"hipped","window_style":"c","door_style":"b","window_sides":Presets.SIDES.duplicate()}
func check_bundle_refunds()->void:
	for index:int in 3:
		var operation:Dictionary=Presets.candidates(room(),choices(index))[0]
		var purchase:Dictionary=Presets.propose(room(),operation,10000)
		check(bool(purchase.ok),"Refund fixture has a valid preset")
		if not bool(purchase.ok):continue
		for item:Dictionary in purchase.added_furnishings:
			if item.kind!="house_window":continue
			var horizontal:bool=int(item.rotation)%180==0
			var frame:=Rect2(Vector2(item.x,item.z)-Vector2(.99,.22),Vector2(1.98,.44)) if horizontal else Rect2(Vector2(item.x,item.z)-Vector2(.22,.99),Vector2(.44,1.98))
			var clear:bool=true
			for wall:Dictionary in purchase.after.walls:
				if int(wall.level)==1 and (float(wall.w)>float(wall.d))!=horizontal and frame.intersects(Building.rect(wall)):clear=false
			check(clear,"Preset window frame does not cross a perpendicular room partition")
		# Two valid bearing frames let a roof shrink without its eaves crossing
		# a longer wall. Retain the preset's actual discounted refund basis.
		var roof_base:Dictionary=room()
		for inner_wall:Dictionary in room(4,6).walls:
			inner_wall.id="inner_"+str(inner_wall.id);roof_base.walls.append(inner_wall)
		var roof:Dictionary=purchase.after.roofs[0].duplicate(true)
		roof.level=0;roof.supports=["west","east"]
		roof_base.roofs=[roof]
		var smaller_record:Dictionary=roof.duplicate(true)
		smaller_record.erase("id");smaller_record.w=4.;smaller_record.d=6.;smaller_record.supports=["inner_west","inner_east"]
		var smaller:Dictionary=LifeRoofEdits.propose(roof_base,{"op":"roof_edit","id":roof.id,"record":smaller_record},10000)
		check(bool(smaller.ok),"Bundled roof can be resized: "+str(smaller.get("error","")))
		if bool(smaller.ok):
			check(-int(smaller.cost)<=float(roof.w)*float(roof.d)*float(roof.refund_rate),"Shrinking a bundled roof cannot refund its undiscounted retail price")
			check(is_equal_approx(float(smaller.after.roofs[0].refund_rate),float(roof.refund_rate)),"Resizing retains the discounted roof refund basis")
		var state:Dictionary=purchase.after
		var refunded:int=0
		for item:Dictionary in purchase.added_furnishings:
			var credit:int=LifeCatalogVariants.resale_value(item)
			refunded+=credit
			var stored:Dictionary=LifeHouseholdFlow._stored_record(item)
			check(stored.has("refund_value") and LifeCatalogVariants.resale_value(stored)==credit,"Storing a bundled fixture retains its capped resale value")
		for group:String in ["roofs","stairs","walls","floors"]:
			for piece:Dictionary in state[group].duplicate(true):
				if group!="stairs" and int(piece.level)!=1:continue
				var deletion:Dictionary=Building.propose(state,{"op":"remove","id":piece.id},10000)
				check(bool(deletion.ok),"Bundled "+group+" can be dismantled in support order")
				if bool(deletion.ok):refunded-=int(deletion.cost);state=deletion.after
		check(refunded<=Presets.PRICES[index]/2 and refunded>0,"Full bundle liquidation cannot exceed half its purchase price")
		var json_state:Dictionary=JSON.parse_string(JSON.stringify(purchase.after))
		check(Building.validate(json_state).is_empty(),"Bundle refund metadata survives building save/load")
	var sized:Dictionary={"kind":"sofa","size":Vector2(2,1),"variant":{"size":"large"}}
	check(LifeCatalogVariants.resale_value(sized)==int(LifeCatalogVariants.price(LifeCatalog.get_item("sofa"),"large")*.7),"Live footprint does not replace the furnishing's size variant in resale")

func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():quit(2);return
	check(load("res://scripts/main.gd")!=null,"Production build controls compile")
	check_bundle_refunds()
	for side:String in ["north","south","west","east"]:
		var base:Dictionary=room(4,4)
		var extended:Dictionary=Edits.propose(base,{"op":"structure","tool":"grab","level":0,"id":side,"line":-3. if side in ["north","west"] else 3.},10000)
		check(bool(extended.ok),"Wall extension is valid on "+side+": "+str(extended.get("error","")))
		if not bool(extended.ok):continue
		check(is_equal_approx(Building._union_area(Building._rects(extended.after,"floors",0)),20.),"Outward wall extension adds its exact floor strip")
		check(int(extended.cost)==96,"Wall extension charges once for wall movement and new floor")
	var base:Dictionary=room()
	base.walls.append({"id":"partition","level":0,"x":0.,"z":0.,"w":.14,"d":10.,"height":2.6,"cut":true,"material":"eae7d7"})
	for style:String in Edits.HOME_PAINT_STYLES:
		var paint:Dictionary=Edits.propose(base,{"op":"structure","tool":"paint","level":0,"scope":"room","palette":"home","pattern":style,"material":"8faf9f","px":-3.,"pz":0.},10000)
		check(bool(paint.ok),"Room-interior click accepts "+style+" paint: "+str(paint.get("error","")))
		if bool(paint.ok):check(Building.find(paint.after,"partition").material=="8faf9f" and Building.find(paint.after,"east").material=="eae7d7","Room paint includes its divider but not the next room's outside wall")
	var carpet:Dictionary=Edits.propose(base,{"op":"structure","tool":"carpet","level":0,"px":-3.,"pz":0.,"style":"geometric","material":"6aa6e0"},10000)
	check(bool(carpet.ok),"Room carpet can be applied by interior click")
	if bool(carpet.ok):
		check(carpet.after.floors.size()==1 and carpet.after.floors[0].id=="ground","Room finish preserves its structural slab identity")
		for tile:Dictionary in Building.surface_tiles(carpet.after,0):
			if tile.rect.has_point(Vector2(-3,0)):check(tile.material=="6aa6e0" and tile.carpet=="geometric","Selected room receives the chosen carpet")
			if tile.rect.has_point(Vector2(3,0)):check(tile.material=="cfa97e" and tile.carpet=="","Adjacent room keeps its finish")
	if bool(carpet.ok):
		var extension:Dictionary=Edits.propose(carpet.after,{"op":"structure","tool":"grab","level":0,"id":"west","line":-7.0},10000)
		check(bool(extension.ok),"Extending a carpeted room remains valid")
		if bool(extension.ok):
			var matched:bool=false
			for tile:Dictionary in Building.surface_tiles(extension.after,0):
				if tile.rect.has_point(Vector2(-6.5,0)):matched=tile.material=="6aa6e0" and tile.carpet=="geometric"
			check(matched,"New floor extension inherits its adjacent room's carpet")
	var floor_removed:Dictionary=Building.propose(room(),{"op":"remove","id":"ground"},1000)
	check(bool(floor_removed.ok) and int(floor_removed.cost)==-480,"Deleting floor refunds its removed area")
	if OS.get_cmdline_user_args().has("--policy-only"):
		print("BUILD_BUY_POLICY ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1);return
	var app:=AppFixture.new();root.add_child(app)
	app.world=LifeWorld.new();app.add_child(app.world)
	app.sim=LifeSim.new();app.add_child(app.sim);app.sim.new_household({});app.sim.autonomy=false;app.sim.set_speed(0);app.sim.funds=10000
	app.world.load_home([room()]);app.world.set_process(false)
	var tx:=Transactions.new(app)
	for index:int in ([2] if OS.get_cmdline_user_args().has("--preset2") else [0,1,2]):
		print("PRESET_BEGIN ",index)
		var quote:Dictionary={}
		for operation:Dictionary in Presets.candidates(tx.current().state,choices(index)):
			quote=tx.prepare(operation)
			if bool(quote.ok):break
		check(bool(quote.get("ok",false)),"Preset "+str(index)+" has a valid whole-house quote: "+str(quote.get("error","")))
		if not bool(quote.get("ok",false)):continue
		check(int(quote.cost)==Presets.PRICES[index],"Preset has its exact bundled price")
		var before:int=app.sim.funds
		var purchase:Dictionary=tx.commit(quote)
		check(bool(purchase.ok),"Preset commit succeeds atomically")
		if not bool(purchase.ok):continue
		check(app.sim.funds==before-Presets.PRICES[index],"Preset debits exactly once")
		check(not bool(tx.commit(quote).ok),"Duplicate preset confirmation cannot duplicate or charge twice")
		var state:Dictionary=app.world.construction.snapshot()
		check(state.stairs.size()==1 and state.openings.size()==1 and state.roofs.size()==1,"Preset contains real stairs, opening and roof")
		check(app.world.lot_navigation.stair_connected(str(state.stairs[0].id)),"Preset staircase connects both navigation floors")
		for saved_item:Dictionary in app.world.serialize_items():
			if str(saved_item.get("kind","")) in ["house_door","house_window"]:check(saved_item.has("refund_value"),"Placed bundle fixture preserves refund in a saved layout")
		var rooms:Array=state.upstairs_preset.rooms
		check(rooms.filter(func(entry:Dictionary)->bool:return entry.kind=="bedroom").size()==(4 if index==2 else 3),"Preset has the promised bedroom count")
		check(rooms.filter(func(entry:Dictionary)->bool:return entry.kind=="ensuite").size()==index,"Preset has the promised en-suite count")
		check(rooms.filter(func(entry:Dictionary)->bool:return entry.kind=="bathroom").size()==1,"Preset has a main bathroom")
		for room_entry:Dictionary in rooms:
			# Bathrooms now contain their bundled fixtures; their old geometric
			# centres may be inside a shower or vanity. Query real free floor.
			var start:Vector3=app.world.nearest_clear_point(Vector3(room_entry.x,Building.level_y(1),room_entry.z),1,8)
			var destination:Vector3=Building.stair_point(state.stairs[0],-.5)
			var route:Dictionary=app.world.lot_navigation.route(LifeLotNavigation.floor_location(1,start),LifeLotNavigation.floor_location(0,destination))
			check(start.is_finite() and Building.rect(room_entry).has_point(Vector2(start.x,start.z)) and bool(route.ok),str(room_entry.name)+" has a usable route through its door and stairs")
		app.world.set_cutaway(false)
		check(app.world.items.filter(func(item:Dictionary)->bool:return item.kind=="house_window" and item.node.visible).size()==8,"All four exterior sides have supported visible windows")
		check(app.world.items.filter(func(item:Dictionary)->bool:return item.kind=="house_door").size()==4+index+(1 if index==2 else 0),"Every room and en-suite has a door")
		var test_room:Dictionary=rooms[1]
		for style:String in ([] if OS.get_cmdline_user_args().has("--capture") else Edits.CARPET_STYLES):
			for color:String in ToolsPanel.CARPET_COLORS:
				var finish:Dictionary=Edits.propose(state,{"op":"structure","tool":"carpet","level":1,"px":test_room.x,"pz":test_room.z,"style":style,"material":color},10000)
				check(bool(finish.ok),"Upper room accepts carpet "+style+" / "+color)
		if OS.get_cmdline_user_args().has("--capture"):
			app.world.set_view_level(1);app.world.construction.set_roof_visibility(false)
			app.world.camera.position=Vector3(0,19,10);app.world.camera.look_at(Vector3(0,3.5,0));app.world.camera.size=17
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			var folder:String=OS.get_environment("JUSTLIFE_DATA_DIR").path_join("captures")
			DirAccess.make_dir_recursive_absolute(folder)
			root.get_texture().get_image().save_png(folder.path_join("upstairs-"+str(index)+".png"))
		check(bool(tx.undo(purchase.receipt).ok) and app.sim.funds==before,"Preset undo restores funds and removes bundled doors and windows")
		check(app.world.items.is_empty() and app.world.construction.building_state.stairs.is_empty(),"Preset undo leaves no orphan furnishings or staircase")
		await process_frame
		print("PRESET_END ",index)
	check(LifeCatalog.ITEMS.corner_counter.styles.size()==5 and LifeCatalog.ITEMS.corner_counter.colors.size()==10 and LifeCatalog.ITEMS.corner_counter.styles==LifeCatalog.ITEMS.fridge.styles and LifeCatalog.ITEMS.corner_counter.colors==LifeCatalog.ITEMS.fridge.colors,"Corner counter shares all five fridge styles and ten colours")
	app.world.create_home(LifeCatalog.starter_layout());app.world.set_process(false)
	var furnished_quote:Dictionary={}
	for operation:Dictionary in Presets.candidates(tx.current().state,choices(0)):
		furnished_quote=tx.prepare(operation)
		if bool(furnished_quote.ok):break
	check(bool(furnished_quote.get("ok",false)),"A staircase can be fitted around the real starter furnishings: "+str(furnished_quote.get("error","")))
	app.queue_free();await process_frame;await process_frame
	print("BUILD_BUY_UPSTAIRS ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
