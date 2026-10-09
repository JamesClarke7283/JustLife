extends SceneTree
## Real preset furnishing, upstairs build entry, worktop fit and diner ownership.
const Building=preload("res://scripts/building_state.gd")
const Presets=preload("res://scripts/upstairs_presets.gd")
var checks:int=0
var failures:Array[String]=[]
var app:Node
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func room()->Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.,"z":0.,"w":12.,"d":10.,"material":"cfa97e"}]
	for side:int in [-1,1]:
		state.walls.append({"id":"north" if side<0 else "south","level":0,"x":0.,"z":side*5.,"w":12.,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"})
		state.walls.append({"id":"west" if side<0 else "east","level":0,"x":side*6.,"z":0.,"w":.14,"d":10.,"height":2.6,"cut":true,"material":"eae7d7"})
	return state
func bounds(node:Node3D)->AABB:
	var result:AABB;var first:bool=true
	for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var part:AABB=mesh.global_transform*mesh.get_aabb()
		result=part if first else result.merge(part);first=false
	return result
func starter_passages()->void:
	var world:=LifeWorld.new();root.add_child(world);world.set_process(false)
	for lot:int in [0,1]:
		world.create_home(LifeCatalog.starter_layout(lot))
		var from:Vector3=world.nearest_clear_point(Vector3(-1.75,.16,4.5),0)
		for fixture:Dictionary in world.items:
			if str(fixture.kind) not in ["toilet","shower","sink"] or fixture.node.position.x<1.:continue
			var destination:Vector3=world.approach(fixture)
			check(destination.is_finite() and not world.path_to(from,destination).is_empty(),"Starter lot %d has a full-body bathroom route to %s"%[lot,str(fixture.kind)])
		var easel:Dictionary=world.closest_item("easel",from)
		var television:Dictionary=world.closest_item("tv",from)
		check(not world.item_panels(easel)[0].intersects(world.item_panels(television)[0]),"Starter lot %d doorway clearance leaves easel and television separate"%lot)
	world.queue_free();await process_frame
func presets()->void:
	var world:=LifeWorld.new();root.add_child(world);world.set_process(false)
	for index:int in 3:
		for orientation:int in [0,180]:
			var choices:Dictionary={"choice":index,"wall_color":"8faf9f","floor_color":"cfa97e","roof_color":"57736a","roof_style":"hipped","window_style":"a","door_style":"a"}
			var quote:Dictionary=Presets.propose(room(),Presets.candidates(room(),choices).filter(func(candidate:Dictionary)->bool:return int(candidate.rotation)==orientation)[0],10000)
			check(bool(quote.ok),"Preset %d has valid furnished architecture: %s"%[index,str(quote.get("error",""))])
			if not bool(quote.ok):continue
			check(int(quote.cost)==Presets.PRICES[index],"Bathroom fixtures are included in preset %d base price"%index)
			var layout:Array=quote.added_furnishings.duplicate(true);layout.append(quote.after)
			var loaded:Dictionary=world.load_home(layout)
			check(bool(loaded.ok),"Furnished preset %d passes real world validation: %s"%[index,str(loaded.get("error",""))])
			if not bool(loaded.ok):continue
			var foot:Vector3=Building.stair_point(quote.after.stairs[0],-.5)
			for entry:Dictionary in quote.after.upstairs_preset.rooms:
				if str(entry.kind) not in ["bathroom","ensuite"]:continue
				var area:Rect2=Building.rect(entry)
				var fixtures:Array=[]
				for item:Dictionary in world.items:
					if str(item.kind) in ["toilet","shower","sink","bathtub"] and area.has_point(Vector2(item.node.position.x,item.node.position.z)):fixtures.append(item)
				for kind:String in ["toilet","shower","sink"]:check(fixtures.filter(func(item:Dictionary)->bool:return str(item.kind)==kind).size()==1,"%s has exactly one %s"%[str(entry.name),kind])
				check(fixtures.filter(func(item:Dictionary)->bool:return str(item.kind)=="bathtub").size()==(1 if str(entry.kind)=="bathroom" else 0),"%s has the specified bathtub count"%str(entry.name))
				for item:Dictionary in fixtures:
					check(area.encloses(world.item_panels(item,false)[0]),str(entry.name)+" fixture stays wholly inside its room")
					var at:Vector3=world.approach(item)
					check(at.is_finite() and not world.path_to(foot,at).is_empty(),str(entry.name)+" "+str(item.kind)+" has a usable physical approach "+str(at))
					if str(item.kind)=="sink":
						check(str(item.variant.size)==("bathroom_double" if str(entry.kind)=="bathroom" else "bathroom_single"),str(entry.name)+" has the specified single/double sink")
					for other:Dictionary in fixtures:
						if item.id==other.id:continue
						check(not world.item_panels(item,false)[0].grow(-.01).intersects(world.item_panels(other,false)[0].grow(-.01)),str(entry.name)+" fixtures do not overlap")
			world.set_view_level(1);world.set_cutaway(false);world.construction.set_roof_visibility(true)
			var before:Array=world.serialize_items()
			world.set_build(true)
			check(world.view_level==1 and world.construction.build_level==1 and is_equal_approx(world.grid.position.y,Building.RISE),"Build entry preserves the upstairs floor and grid")
			check(world.cutaway and not world.construction.roofs_visible and world.construction.tool.is_empty(),"Upstairs Build entry exposes furnishings and clears roof interception")
			check(world.serialize_items()==before,"Build entry preserves all purchased architecture and fixtures")
			var saved:Array=JSON.parse_string(JSON.stringify(world.serialize_items()))
			check(bool(world.load_home(saved).ok),"Furnished preset survives marker-last JSON reconstruction")
			world.set_build(false)
	world.queue_free();await process_frame
func kitchen()->void:
	var world:=LifeWorld.new();root.add_child(world);world.create_home([]);world.set_process(false)
	world.add_item({"id":"cabinet","kind":"counter","x":-3.,"z":1.,"rotation":0.},false);world.rebuild_navigation()
	var at:Vector3=world.kitchen_snap("counter",Vector3(-2.,.16,1.1),90.)
	check(not at.is_equal_approx(Vector3(-2.,.16,1.1)) and world.can_place("counter",at,90.),"Perpendicular standard counters snap into a legal L join")
	world.add_item({"id":"return","kind":"counter","x":at.x,"z":at.z,"rotation":90.},false);world.rebuild_navigation()
	world.begin_placement("coffee_machine");world.update_ghost(Vector3(-3.,.16,1.))
	check(world.ghost_valid,"Compact coffee machine is placeable on a standard cabinet")
	var measured:AABB=bounds(world.ghost)
	check(measured.size.x<=.34+.001 and measured.size.z<=.38+.001 and measured.size.y<=.48+.001,"Rendered coffee machine fits its declared compact footprint: "+str(measured.size))
	var ghost_size:Vector3=measured.size
	world.add_item({"id":"coffee","kind":"coffee_machine","x":-3.,"z":1.,"rotation":0.,"support_id":"cabinet","hang":LifeKitchenFurnishings.SURFACES.counter,"support_x":0.,"support_z":0.,"support_rotation":0.},false)
	check(bounds(world.closest_item("coffee_machine",Vector3(-3,.16,1)).node).size.is_equal_approx(ghost_size),"Placed coffee and preview share the same smaller model")
	world.queue_free();await process_frame
func build_entry()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await process_frame;await process_frame
	app.household_profiles=[{"name":"Upstairs Builder","age_stage":"adult","traits":[]}]
	app.selected_lot=2;app.start_household();app.set_process(false);app.set_sound(false);app.world.set_process(false);app.household.set_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.household.set_funds(10000);app.set_build_mode(true)
	app.show_upstairs_presets({"choice":0,"wall_color":"8faf9f","floor_color":"cfa97e","roof_color":"57736a","roof_style":"hipped","window_style":"a","door_style":"a"})
	var confirm:Button=app.overlay.find_child("UpstairsConfirm",true,false)
	check(is_instance_valid(confirm) and not confirm.disabled,"The public upstairs preset planner offers its priced purchase")
	if is_instance_valid(confirm):confirm.pressed.emit()
	for frame:int in 180:
		if app.world.viewable_top()>=1 and not app.overlay_open:break
		await process_frame
	check(app.world.viewable_top()>=1 and app.sim.funds==9000,"Public upstairs purchase includes the furnished bathroom in its base price")
	if app.world.viewable_top()<1:app.queue_free();await process_frame;return
	app.set_build_mode(false);app.set_live_view_level(1);app.toggle_house_view()
	check(not app.world.cutaway and app.world.construction.roofs_visible,"The player can select upstairs in the full-house view")
	var toolbar:Button
	for button:Button in app.find_children("*","Button",true,false):
		if button.text=="Build & buy" and not button.is_queued_for_deletion():toolbar=button
	check(is_instance_valid(toolbar),"The ordinary Build & buy toolbar entry is available upstairs")
	if is_instance_valid(toolbar):toolbar.pressed.emit()
	check(app.mode=="build" and app.world.view_level==1 and app.world.construction.build_level==1,"The real toolbar preserves upstairs when entering Build & buy")
	check(app.world.cutaway and not app.world.construction.roofs_visible and app.world.construction.tool.is_empty(),"The toolbar clears the roof's click interception before furnishing placement")
	app.begin_purchase("chair");app.world.update_ghost(Vector3(-3.5,Building.level_y(1),2.5))
	check(app.world.ghost_valid,"An upstairs furnishing has a valid ordinary preview after toolbar entry")
	var at:Vector3=app.world.ghost_position
	var before:int=app.world.items.size()
	app.world.pick(app.world.camera.unproject_position(at));await process_frame
	check(app.world.items.size()==before+1 and app.sim.funds==8915,"The upstairs floor click purchases the furnishing instead of editing the roof")
	var placed:Dictionary=app.world.closest_item("chair",at,.01)
	check(not placed.is_empty() and app.world.item_level(placed)==1,"The clicked furnishing remains on its selected upstairs floor")
	app.queue_free();await process_frame;await process_frame
func diners()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await process_frame;await process_frame
	app.household_profiles=[{"name":"Bar One","age_stage":"adult","traits":[]},{"name":"Bar Two","age_stage":"adult","traits":[]}]
	app.selected_lot=2;app.start_household();app.set_process(false);app.set_sound(false);app.household.set_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.world.set_process(false);app.household.set_funds(10000);app.set_build_mode(true)
	for item:Dictionary in app.world.items.duplicate():
		if str(item.kind)=="chair":app.world.remove_item(str(item.id))
	app.begin_purchase("corner_counter");app.on_placement("corner_counter",Vector3(-3,.16,0),0)
	var corner:Dictionary=app.world.closest_item("corner_counter",Vector3(-3,.16,0),.1)
	check(not corner.is_empty(),"L counter corner bought through ordinary Build/Buy")
	if corner.is_empty():app.queue_free();await process_frame;return
	for arm:Array in [[Vector3(-3.925,.16,0),0.],[Vector3(-3,.16,-.925),90.]]:
		app.begin_purchase("counter");app.on_placement("counter",arm[0],arm[1])
	check(app.world.items.filter(func(item:Dictionary)->bool:return str(item.kind)=="counter" and item.node.position.z>-2.).size()==2,"Two straight arms join the breakfast bar corner")
	for initial:Vector3 in [Vector3(-3,.16,.8),Vector3(-2.2,.16,0)]:
		app.begin_purchase("stool");app.world.update_ghost(initial)
		check(app.world.ghost_valid,"A stool has a valid snapped breakfast bar preview")
		app.on_placement("stool",app.world.ghost_position,app.world.placement_angle)
	var stools:Array=app.world.items.filter(func(item:Dictionary)->bool:return str(item.kind)=="stool")
	check(stools.size()==2,"Two stools occupy distinct corner counter settings")
	app.set_build_mode(false)
	if stools.size()!=2:app.queue_free();await process_frame;return
	for stool:Dictionary in stools:
		check(str(app.meal_flow._chair_table(stool).get("id",""))==str(corner.id),"Snapped stool faces and offers its L counter for dining")
	var batch:Dictionary=app.household.meals.create_batch("garden_skillet","player",1,"home",app.meal_flow.now())
	var source:Dictionary=app.world.closest_item("counter",Vector3(-3.925,.16,0),.1)
	check(not source.is_empty(),"The meal uses the publicly purchased breakfast-bar arm")
	if source.is_empty():app.queue_free();await process_frame;return
	var meal_at:Vector3=source.node.to_global(Vector3(0,LifeMeals.SURFACE_HEIGHTS.counter,0))
	app.household.meals.set_batch_location(str(batch.id),"surface",str(source.id),meal_at,app.meal_flow.now());batch.offset=[0.,LifeMeals.SURFACE_HEIGHTS.counter,0.]
	app._refresh_sim_targets()
	app.meal_flow.sync_world()
	var before_hunger:Dictionary={}
	for index:int in app.household.members.size():
		var member:Dictionary=app.household.members[index]
		member.sim.needs.hunger=20.;before_hunger[member.id]=20.
		app.select_household_member(index);app.queue_interaction(app._find_item(str(batch.id)),"eat_meal")
	var active:bool=false
	app.household.set_speed(8)
	for index:int in 2000:
		app._process(.05)
		active=app.household.members.all(func(member:Dictionary)->bool:
			var action:Dictionary=member.sim.get_current_action()
			return str(action.get("id",""))=="eat_meal" and str(action.get("phase",""))=="active")
		if active:break
		if index%20==0:await process_frame
	check(active,"Both diners physically collect food, walk to their stools and start eating")
	var chosen:Array=[];var plate_ids:Array=[]
	if active:
		for member:Dictionary in app.household.members:
			var action:Dictionary=member.sim.get_current_action()
			check(stools.any(func(stool:Dictionary)->bool:return str(stool.id)==str(action.get("meal_seat",""))),"Diner reserves a real breakfast bar stool")
			chosen.append(str(action.get("meal_seat","")));plate_ids.append(str(action.get("meal_plate","")))
			var actor:LifeActor=app.world.actors[str(member.id)]
			check(actor.position.distance_to(action.target_position)<.025,"Diner really reached their reserved stool approach")
			var anchor:Dictionary=app.meal_flow.eating_anchor(str(member.id),action)
			check(str(anchor.kind)=="seat" and str(anchor.table_id)==str(corner.id),"Diner sits on the stool and places their plate on the counter")
			check(actor.get("_activity_anchor").get("kind","")=="seat","Live actor presentation uses the seated eating pose")
			check(absf(anchor.plate_position.y-(.16+LifeMeals.SURFACE_HEIGHTS.corner_counter))<.001,"Breakfast bar plate is at the real worktop height")
		check(chosen.size()==2 and not chosen[0].is_empty() and chosen[0]!=chosen[1] and plate_ids.size()==2 and not plate_ids[0].is_empty() and plate_ids[0]!=plate_ids[1],"Two diners occupy separate stools and plates")
		var saved_members:Array=[]
		for member:Dictionary in app.household.members:saved_members.append({"id":str(member.id),"state":member.sim.get_state()})
		var saved_food:Dictionary=JSON.parse_string(JSON.stringify(app.household.meals.get_state()))
		var saved_household:Dictionary={"household_version":2,"selected_index":app.household.selected_index,"members":saved_members,"world":app.world.serialize_items()}
		check(LifeMeals.validate_layout(saved_food,saved_household).is_empty(),"Saved breakfast bar plates accept stools on their counter's floor")
		check(LifeMeals.validate_actions(saved_food,saved_members,{},"home").is_empty(),"Active breakfast bar meals retain valid ownership and progress for reload")
		var completed:bool=false
		for index:int in 1600:
			app._process(.05)
			completed=plate_ids.all(func(id:String)->bool:
				var plate:Dictionary=app.household.meals.portion(id)
				return not plate.is_empty() and float(plate.progress)>=1.)
			if completed:break
			if index%20==0:await process_frame
		check(completed,"Both breakfast bar meals complete through elapsed controller play")
		for member:Dictionary in app.household.members:check(float(member.sim.needs.hunger)>float(before_hunger[member.id])+50.,"Eating on the stool restores real Hunger")
	app.household.set_speed(0)
	app.queue_free();await process_frame;await process_frame
func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():quit(2);return
	if not OS.get_cmdline_user_args().has("--diners-only"):
		await starter_passages();await presets();await kitchen();await build_entry()
	await diners()
	print("BUILD_KITCHEN_REQUESTS %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
