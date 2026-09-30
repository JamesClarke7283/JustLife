extends SceneTree
## Saved while away: cached furnishings must return with their original pose,
## cabinet choices and raised-appliance anchors, through the real trip flow.
var app:Node
var checks:int=0
var failures:int=0
var completed:bool=false
const OLD_ANGLE:float=23422.853515625

func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func frames(count:int=2)->void:
	for i:int in count:await process_frame
func record(layout:Array,id:String)->Dictionary:
	for entry:Dictionary in layout:
		if str(entry.get("id",""))==id:return entry
	return {}
func fixture()->Array:
	return [{"id":"cached_cabinet","kind":"counter","x":-8.0,"z":3.0,"rotation":90.0,"style":"slatted","color":"1f3b6b"},
		{"id":"cached_coffee","kind":"coffee_machine","x":-8.1,"z":2.92,"rotation":120.0,"support_id":"cached_cabinet","support_x":.08,"support_z":-.1,"support_rotation":30.0,"hang":.952},
		{"id":"cached_toy","kind":"pet_toy_dog","x":-8.0,"z":4.8,"rotation":OLD_ANGLE}]
func model_controls()->void:
	var controller:Node=load("res://scripts/main.gd").new()
	controller.household=LifeHousehold.new();controller.add_child(controller.household)
	var source:Array=fixture();var before:Array=source.duplicate(true)
	var restored:Array=controller._safe_layout(source)
	check(is_equal_approx(float(record(restored,"cached_toy").rotation),fmod(OLD_ANGLE,360.0)),"Cached legacy turns normalize before the old numeric clamp")
	check(record(restored,"cached_cabinet").style=="slatted" and record(restored,"cached_cabinet").color=="1f3b6b","Cached cabinets retain their nondefault style and color")
	var coffee:Dictionary=record(restored,"cached_coffee")
	check(coffee.support_id=="cached_cabinet" and is_equal_approx(float(coffee.hang),.952) and is_equal_approx(float(coffee.support_x),.08) and is_equal_approx(float(coffee.support_z),-.1) and is_equal_approx(float(coffee.support_rotation),30.0),"Cached appliances retain their raised support and local anchor")
	check(source==before,"Cache sanitization does not edit the source save")
	var turned:Array=fixture();turned[1].support_rotation=10830.0
	check(is_equal_approx(float(record(controller._safe_layout(turned),"cached_coffee").support_rotation),30.0),"Full turns in a support anchor normalize without losing the worktop link")
	var invalid:Array=fixture();invalid[1].support_x=NAN
	var rejected:Dictionary=record(controller._safe_layout(invalid),"cached_coffee")
	check(not rejected.has("support_id") and not rejected.has("hang"),"A nonfinite support offset cannot become a raised appliance")
	invalid=fixture();invalid[1].support_id="missing_counter"
	rejected=record(controller._safe_layout(invalid),"cached_coffee")
	check(not rejected.has("support_id") and not rejected.has("hang"),"A missing support safely leaves the appliance on the floor")
	invalid=fixture();invalid[0].style="unknown";invalid[0].color="not-a-color"
	rejected=record(controller._safe_layout(invalid),"cached_cabinet")
	check(rejected.style==LifeCatalogVariants.styles(LifeCatalog.get_item("counter"))[0] and rejected.color==LifeCatalogVariants.colors(LifeCatalog.get_item("counter"))[0],"Unknown cabinet choices resolve through the catalog's normal defaults")
	var edges:Array=[{"id":"west_edge","kind":"plant","x":-17.0,"z":0.0,"rotation":0.0},{"id":"east_edge","kind":"plant","x":17.0,"z":0.0,"rotation":0.0}]
	var edge_copy:Array=controller._safe_layout(edges,LifeLand.fresh())
	check(edge_copy[0].x==-17.0 and edge_copy[1].x==17.0,"Valid furnishings near both base-lot edges are not moved by cache restoration")
	var expanded:Dictionary={"version":1,"west":1,"east":0,"north":1}
	var outside:Array=[{"id":"bought_plot_easel","kind":"easel","x":-22.0,"z":-18.0,"rotation":0.0}]
	var outer_copy:Array=controller._safe_layout(outside,expanded)
	check(outer_copy[0].x==-22.0 and outer_copy[0].z==-18.0,"Furnishings on purchased west and north land keep their exact coordinates")
	for bad_x:float in [NAN,10001.0]:
		var bad_position:Array=outside.duplicate(true);bad_position[0].x=bad_x
		check(controller._safe_layout(bad_position,expanded).is_empty(),"Nonfinite or out-of-range coordinates remain excluded: "+str(bad_x))
	controller.world=LifeWorld.new();controller.add_child(controller.world)
	var original_land:Dictionary=LifeBuildingState.land
	LifeBuildingState.set_land({"version":1,"west":0,"east":1,"north":0})
	var live_land:Dictionary=LifeBuildingState.land
	var canonical:Array=outside.duplicate(true);canonical.append(LifeBuildingState.fresh())
	var canonical_before:Array=canonical.duplicate(true)
	check(controller._safe_layout(canonical,expanded)==canonical,"Canonical cached geometry is admitted against its supplied home land")
	check(is_same(LifeBuildingState.land,live_land) and LifeBuildingState.land.east==1,"Successful cached-home validation restores the exact live venue land object")
	check(controller._safe_layout(canonical,LifeLand.fresh()).is_empty(),"Canonical cached geometry outside the supplied land is rejected")
	check(is_same(LifeBuildingState.land,live_land) and canonical==canonical_before,"Rejected cache validation preserves the exact live land reference and source array")
	LifeBuildingState.land=original_land
	controller.free()
func run()->void:
	model_controls()
	if OS.get_environment("JUSTLIFE_CACHED_HOME_FULL_APP")=="1":
		if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():push_error("Use an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
		await public_controls()
		check(completed,"The complete cached-home return regression reached its final assertions")
	print("CACHED_HOME_FURNISHINGS %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func finish_trip(destination:String)->void:
	for i:int in 1800:
		if app.mode!="travel":break
		app._process(.05)
		if i%10==0:await process_frame
	check(app.mode=="live" and app.current_venue==destination,"The normal car trip completes to "+destination)
func public_controls()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
	await frames();app.set_sound(false)
	app.household_profiles=[{"name":"Cache Keeper","age_stage":"adult","traits":[],"hair":0}]
	app.creator_family_links=[];app.start_household();await frames(3)
	app.household.set_speed(0);app.sim.autonomy=false
	while not app.sim.action_queue.is_empty():app.sim.cancel_action()
	for entry:Dictionary in fixture():app.world.add_item(entry)
	app.travel_to("park");await finish_trip("park");await frames()
	if app.current_venue!="park":app.queue_free();await frames();return
	check(app.save_game("cached_home_source","Saved away from the kitchen"),"Public save writes the household while visiting the park")
	var read:Dictionary=LifeSaveLibrary.read_slot("cached_home_source")
	if not bool(read.get("ok",false)):check(false,"The away save can be read");app.queue_free();await frames();return
	var legacy:Dictionary=read.data
	check(not legacy.has("journeys"),"The away fixture exercises the legacy cache sanitizer")
	var context:Dictionary=legacy.members[int(legacy.selected_index)].state.character.world_state
	record(context.home_layout,"cached_toy").rotation=OLD_ANGLE
	check(bool(LifeSaveLibrary.save_slot("cached_home_legacy","Cached old toy turns",legacy).get("ok",false)),"The private legacy fixture keeps the original accumulated angle in world_state.home_layout")
	app.home_layout.clear();app.load_game("cached_home_legacy");await frames(3)
	check(app.current_venue=="park" and str(app.active_save_id)=="cached_home_legacy","Public load resumes the saved venue with its cached home")
	var cached_toy:Dictionary=record(app.home_layout,"cached_toy")
	var cached_cabinet:Dictionary=record(app.home_layout,"cached_cabinet")
	var cached_coffee:Dictionary=record(app.home_layout,"cached_coffee")
	check(not cached_toy.is_empty() and is_equal_approx(float(cached_toy.rotation),fmod(OLD_ANGLE,360.0)),"Loading world_state.home_layout preserves the old toy's visible orientation")
	check(cached_cabinet.get("style")=="slatted" and cached_cabinet.get("color")=="1f3b6b" and cached_coffee.get("support_id")=="cached_cabinet" and is_equal_approx(float(cached_coffee.get("hang",0)),.952),"The restored cache retains cabinet choices and the raised coffee machine")
	app.travel_to("home");await finish_trip("home");await frames(3)
	var cabinet:Dictionary=record(app.world.items,"cached_cabinet")
	var coffee:Dictionary=record(app.world.items,"cached_coffee")
	var toy:Dictionary=record(app.world.items,"cached_toy")
	check(not cabinet.is_empty() and cabinet.variant.style=="slatted" and cabinet.variant.color=="1f3b6b","Returning home rebuilds the cabinet in the purchased style and color")
	check(not coffee.is_empty() and coffee.get("support_id")=="cached_cabinet" and is_equal_approx(float(coffee.node.position.y),LifeBuildingState.GROUND_Y+.952) and coffee.node.position.distance_to(Vector3(-8.1,LifeBuildingState.GROUND_Y+.952,2.92))<.001,"Returning home restores the coffee machine on its actual rotated worktop")
	check(not toy.is_empty() and absf(angle_difference(deg_to_rad(OLD_ANGLE),toy.node.rotation.y))<.0001,"Returning home preserves the old toy's orientation modulo complete turns")
	completed=true;app.queue_free();await frames(3)
