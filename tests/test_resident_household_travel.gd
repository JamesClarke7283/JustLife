extends SceneTree
## Controlled whole-household travel; real controller paths, no simulated arrivals.
var app:Node
var checks:int=0
var failures:int=0

func _initialize()->void:
	var saves:String=OS.get_environment("JUSTLIFE_DATA_DIR")
	if not saves.is_absolute_path() or not OS.get_environment("XDG_DATA_HOME").is_absolute_path() or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Household travel checks require a sanitized project and private save directories.")
		quit(2);return
	_run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures+=1

func clock_minutes()->float:return (app.household.day-1)*1440.0+app.household.minutes

func same_values(a:Variant,b:Variant,at:String="home")->bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for field:Variant in a:
			if not b.has(field) or not same_values(a[field],b[field],at+"."+str(field)):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i:int in a.size():
			if not same_values(a[i],b[i],at+"["+str(i)+"]"):return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		if a!=b:print("VALUE_DIFFERENCE ",at," ",String.num(float(a),20)," != ",String.num(float(b),20))
		return a==b
	if typeof(a)!=typeof(b) or a!=b:print("VALUE_DIFFERENCE ",at," ",str(a)," != ",str(b))
	return typeof(a)==typeof(b) and a==b

func box_geometry(node:Node3D)->Dictionary:
	var result:Dictionary={"transform":node.transform,"parts":[]}
	if node is MeshInstance3D and node.mesh is BoxMesh:
		result["size"]=node.mesh.size
		if node.material_override is StandardMaterial3D:result["color"]=node.material_override.albedo_color
	for child:Node in node.get_children():
		if child is Node3D:result.parts.append(box_geometry(child))
	return result

func physical_home()->Dictionary:
	var result:Dictionary={"furniture":{},"walls":{},"floors":[]}
	for item:Dictionary in app.world.items:
		if bool(item.get("transient_food",false)) or bool(item.get("transient_puddle",false)):continue
		result.furniture[item.id]={"kind":item.kind,"transform":item.node.transform}
	for id:String in app.world.construction.wall_nodes:
		result.walls[id]=box_geometry(app.world.construction.wall_nodes[id])
	for node:Node3D in app.world.construction.floor_nodes:result.floors.append(box_geometry(node))
	return result

func finish_trip()->void:
	for i:int in range(1600):
		if app.mode!="travel":return
		app._process(.05)
		if i%10==0:await process_frame

func key(code:Key)->void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true
	app._unhandled_input(event)

func _run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
	app.household_profiles=[]
	for i:int in range(8):
		var person:Dictionary=app.profile.duplicate(true)
		person.name="Traveler %d" % (i+1)
		app.household_profiles.append(person)
	app.start_household();app.set_sound(false)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	await process_frame
	check(app.household.members.size()==8,"All eight household members enter the live lot")
	var ids:Array=[]
	for member:Dictionary in app.household.members:ids.append(str(member.id))
	app.sim.relationships.maya.friendship=30
	app.household.set_speed(0)
	var home:Array=app.world.serialize_items()
	var original_geometry:Dictionary=physical_home()
	var funds:int=app.household.funds
	var before:float=clock_minutes()
	app.travel_to("maya_home")
	check(app.mode=="travel" and app.residents.trip.boarding.size()==8,"A paused household receives eight real boarding paths")
	var starts:Dictionary={}
	for id:String in ids:starts[id]=app.world.actors[id].position
	key(KEY_ESCAPE);key(KEY_SPACE);key(KEY_B);key(KEY_F5)
	check(app.mode=="travel" and app.overlay_open and app.household.speed==0,"Travel ignores pause/build/save shortcuts and retains its caption")
	check(not app.save_game(),"A whole-household trip cannot write a partial save")
	app._process(.2)
	var moved:int=0
	for id:String in ids:
		if app.world.actors[id].position!=starts[id]:moved+=1
	check(moved==8 and clock_minutes()==before,"Every member walks toward the curb while simulation time is held")
	await finish_trip()
	check(app.mode=="live" and app.current_venue=="maya_home","All eight finish the car trip without hanging")
	check(clock_minutes()==before+15.0 and app.household.speed==0,"The trip adds fifteen minutes and restores the paused speed")
	var positions:Array=[]
	for id:String in ids:
		var actor:LifeActor=app.world.actors.get(id)
		check(is_instance_valid(actor) and actor.visible,"The arriving actor is visible: "+id)
		positions.append(actor.position)
	check(positions.size()==8 and app.household.members.size()==8 and app.household.funds==funds,"Travel preserves every member and the shared wallet")
	var unique:bool=true
	for i:int in positions.size():
		for j:int in range(i):
			if positions[i].distance_to(positions[j])<.49:unique=false
	check(unique,"Arriving members have separate curb positions")
	check(same_values(app.home_layout,home),"Travel retains the exact in-memory home before any JSON boundary")
	check(app.save_game("","Eight neighbors visiting"),"The arrived household can save in the configured home data folder")
	var slot:String=app.active_save_id
	var decoded:Dictionary=LifeSaveLibrary.read_slot(slot)
	check(bool(decoded.get("ok",false)),"The named household slot validates before restoration")
	var decoded_home:Array=decoded.data.members[int(decoded.data.selected_index)].state.character.world_state.home_layout
	var decoded_construction:Dictionary={}
	for entry:Dictionary in decoded_home:
		if str(entry.get("kind",""))=="__construction":decoded_construction=entry
	app.load_game(slot);await process_frame
	check(app.current_venue=="maya_home" and app.household.members.size()==8,"Loading retains the eight-member household at the friend’s address")
	for id:String in ids:check(app.world.actors.has(id) and app.world.actors[id].visible,"Loaded household actor remains present: "+id)
	app.household.set_speed(3);before=clock_minutes()
	app.travel_to("home");await finish_trip()
	check(app.mode=="live" and app.current_venue=="home" and app.household.speed==3,"Returning home restores fast live speed")
	check(clock_minutes()==before+15.0,"The return journey advances fifteen game minutes")
	# JSON numbers are doubles; the native parser can shift a double by one ULP.
	# Check decoded records exactly and physical float32 geometry independently.
	check(not decoded_construction.is_empty() and same_values(app.world.construction.snapshot(),decoded_construction),"Returning preserves every decoded wall and floor record exactly")
	var restored_geometry:Dictionary=physical_home()
	check(same_values(restored_geometry.walls,original_geometry.walls) and same_values(restored_geometry.floors,original_geometry.floors),"Returning restores exact rendered wall and floor geometry")
	# Furniture persists position plus a Y Euler angle. Reconstructing its basis
	# may round a float32 component once; allow at most FLT_EPSILON per component.
	var furniture_ok:bool=restored_geometry.furniture.size()==original_geometry.furniture.size()
	var max_basis_error:float=0.0
	for id:String in original_geometry.furniture:
		if not restored_geometry.furniture.has(id):furniture_ok=false;continue
		var original:Dictionary=original_geometry.furniture[id]
		var restored:Dictionary=restored_geometry.furniture[id]
		if original.kind!=restored.kind or original.transform.origin!=restored.transform.origin:furniture_ok=false
		for axis:int in 3:
			for component:int in 3:
				max_basis_error=maxf(max_basis_error,absf(original.transform.basis[axis][component]-restored.transform.basis[axis][component]))
	print("FURNITURE_MAX_BASIS_COMPONENT_ERROR=",String.num(max_basis_error,20))
	check(furniture_ok and max_basis_error<=1.1920928955078125e-7,"Every furnishing retains its exact position and orientation within float32 Euler reconstruction precision")
	app.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
	print("RESIDENT_HOUSEHOLD_TRAVEL_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
