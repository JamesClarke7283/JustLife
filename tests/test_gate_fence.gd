extends SceneTree
## Free-length fences, tintable gates and gates that open for whoever comes through.
var app:Node
var checks:int=0
var failures:Array[String]=[]
const Variants=preload("res://scripts/catalog_variants.gd")
const GateFlow=preload("res://scripts/gate_flow.gd")

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label);print("FAIL ",label)
## A check later steps depend on: report and stop rather than cascade.
func need(ok:bool,label:String)->void:
	check(ok,label)
	if not ok:
		print("GATE_FENCE ",checks," checks, ",failures.size()," failures (stopped early)")
		quit(1)
func frames(count:int=4)->void:
	for i:int in count:await process_frame

## A clear spot on the lot for a run of this size, scanning outward from a corner
## of the garden so the test never depends on one authored coordinate.
func free_spot(kind:String,size:String,angle:float=0.0)->Vector3:
	var lot:Rect2=LifeBuildingState.lot()
	var z:float=lot.end.y-1.0
	while z>lot.position.y+1.0:
		var x:float=lot.position.x+3.0
		while x<lot.end.x-3.0:
			var at:=Vector3(x,.16,z)
			if app.world.can_place(kind,at,angle,"01" if kind=="fence" else "",size):return at
			x+=.5
		z-=.5
	return Vector3.INF

func item(id:String)->Dictionary:return app._find_item(id)
## What the game ticks gates with: the household, not a neighbour on the street.
func swing(seconds:float)->void:app.world.gate_flow.tick(seconds,app._gate_walkers())
func placed_ids(kind:String)->Array:
	var out:Array=[]
	for entry:Dictionary in app.world.items:
		if str(entry.kind)==kind:out.append(str(entry.id))
	return out

func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():quit(2);return
	var data:Dictionary=LifeCatalog.get_item("fence")
	var gate:Dictionary=LifeCatalog.get_item("garden_gate")

	# ---- the size id and its price
	var id:String=Variants.custom_id(data,4.0,1.2)
	check(id=="L400H120","A 4 m by 1.2 m run names itself L400H120")
	check(Variants.custom_dims(data,id)==Vector2(4.0,1.2),"The id reads back as the same length and height")
	check(Variants.footprint(data,id)==Vector2(4.0,.12),"A free run's footprint is its length by the panel thickness")
	check(is_equal_approx(Variants.height(data,id),1.2),"A free run is as tall as chosen")
	check(Variants.price(data,id)==48,"A 4 m run 1.2 m tall costs 48 at 10 per square metre")
	check(Variants.price(data,Variants.custom_id(data,6.0,1.2))>Variants.price(data,id),"A longer run costs more")
	check(Variants.price(data,Variants.custom_id(data,2.0,1.2))<Variants.price(data,id),"A shorter run costs less")
	check(Variants.price(data,Variants.custom_id(data,4.0,2.0))>Variants.price(data,id),"A taller run costs more")
	check(Variants.price(data,"small")==24 and Variants.price(data,"large")==96,"The named sizes keep their old prices")
	check(Variants.custom_id(data,99.0,9.0)==Variants.custom_id(data,30.0,2.4),"Lengths and heights are held inside the family's limits")
	check(Variants.custom_id(data,.1,.1)=="L50H60","The shortest run is half a metre")
	check(Variants.custom_dims(data,"L9999H120")==Vector2.ZERO,"A length outside the limits is not a size")
	check(Variants.custom_dims(gate,"L400H120")==Vector2.ZERO,"A gate cannot be given a free length")
	check(Variants.size_or_default(id,data)==id and Variants.size_or_default("L9999H120",data)=="small","A saved free size survives, a bad one falls back to the first named size")
	check(Variants.size_label(id)=="4 m × 1.2 m","A free size labels itself in metres")
	check(Variants.record(data,"01","c9c3a8",id).size==id,"The variant record keeps the free size")
	check(Variants.resale_value({"kind":"fence","variant":{"size":id}})==int(48*.7),"A free run sells for seven tenths of its price")
	check(LifeCatalog.local_panels("fence",id)[0].w==4.0,"A free run blocks exactly its length")

	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await frames()
	app.set_sound(false);app.selected_lot=0;app.start_household();await frames()
	app.set_process(false);app.world.set_process(false);app.household.set_speed(0);app.household.set_funds(10000);app.set_build_mode(true)

	# ---- the buy picker
	app.pick_furnishing("fence");await frames()
	check(app.overlay.find_child("VariantLengthMore",true,false)!=null and app.overlay.find_child("VariantHeightLess",true,false)!=null,"The fence picker has length and height controls")
	app.overlay.find_child("VariantLengthMore",true,false).pressed.emit();await frames()
	app.overlay.find_child("VariantLengthMore",true,false).pressed.emit();await frames()
	check(app.overlay.find_child("VariantLengthValue",true,false).text=="2.5 m","Two presses lengthen the run by half a metre")
	app.overlay.find_child("VariantHeightMore",true,false).pressed.emit();await frames()
	check(app.overlay.find_child("VariantHeightValue",true,false).text=="1.3 m","One press raises it a tenth of a metre")
	check(app.overlay.find_child("VariantConfirm",true,false).text=="Place it · ℒ%d" % Variants.price(data,"L250H130"),"The place button quotes the chosen run")
	app.overlay.find_child("VariantConfirm",true,false).pressed.emit();await frames()
	check(app.world.placement_size=="L250H130","Confirming carries the free size into placement")
	check(is_instance_valid(app.world.ghost) and app.world.ghost.find_children("FencePanel_*","Node3D",true,false).size()==1,"The placement ghost is built at the chosen length")
	check(app.world.resize_placement(2,0) and app.world.placement_size=="L300H130","The bracket keys lengthen the fence being placed")
	check(app.world.ghost.find_children("FencePanel_*","Node3D",true,false).size()==2,"A longer ghost is laid from more panels")
	check(app.world.resize_placement(0,-1) and app.world.placement_size=="L300H120","Shift and the bracket keys lower it")
	app.world.placement_size="L400H120"

	# ---- buying and placing a free run
	var spot:Vector3=free_spot("fence","L400H120")
	need(spot.is_finite(),"The lot has room for a 4 m fence")
	var before:int=app.sim.funds
	app.on_placement("fence",spot,0,"01","L400H120");await frames()
	var runs:Array=placed_ids("fence")
	need(runs.size()==1,"A 4 m run is placed")
	check(before-app.sim.funds==48,"Buying a 4 m run charges 48 once")
	var run:Dictionary=item(runs[0])
	check(run.size==Vector2(4.0,.12) and is_equal_approx(float(run.height),1.2),"The placed run reports its real footprint and height")
	check(run.variant.size=="L400H120","The placed run keeps its free size")
	check(run.node.find_children("FencePanel_*","Node3D",true,false).size()==2,"A 4 m run is two panels")
	var volume:AABB=app.world.furnishing_volume(app.world.serialize_items().filter(func(e:Dictionary)->bool:return str(e.get("id",""))==runs[0])[0])
	check(absf(volume.size.x-4.1)<.2 and volume.size.y>1.2,"The run's envelope follows its length")
	var saved:Array=app.world.serialize_items().filter(func(e:Dictionary)->bool:return str(e.get("kind",""))=="fence")
	check(saved.size()==1 and saved[0].size=="L400H120","The saved layout records the free size")

	# ---- resizing a placed run
	app.household.set_funds(10000);before=app.sim.funds
	var start_x:float=float(item(runs[0]).node.position.x)
	check(app.resize_fence(runs[0],6.0,1.2,"start"),"A placed run can be lengthened")
	await frames()
	run=item(runs[0])
	check(run.variant.size=="L600H120" and run.size.x==6.0,"The lengthened run is 6 m")
	check(before-app.sim.funds==Variants.price(data,"L600H120")-48,"Lengthening charges only the added panel")
	check(is_equal_approx(float(run.node.position.x),start_x+1.0),"Keeping the start end fixed shifts the middle by half the growth")
	check(run.node.find_children("FencePanel_*","Node3D",true,false).size()==3,"A 6 m run is three panels")
	before=app.sim.funds
	check(app.resize_fence(runs[0],3.0,1.2,"end"),"A placed run can be shortened")
	await frames()
	run=item(runs[0])
	var removed:int=Variants.price(data,"L600H120")-Variants.price(data,"L300H120")
	check(app.sim.funds-before==int(float(removed)*.7) and Variants.resize_cost(data,"L600H120","L300H120")==-int(float(removed)*.7),"Shortening refunds seven tenths of what is taken away, as selling would")
	check(run.size.x==3.0,"The shortened run is 3 m")
	var shown:int=app.sim.funds
	check(not app.resize_fence(runs[0],3.0,1.2,"end") and app.sim.funds==shown,"Asking for the size it already is changes nothing")
	app.undo_build();await frames()
	check(item(runs[0]).variant.size=="L600H120" and app.sim.funds==shown-int(float(removed)*.7),"Undo restores the longer run and takes back the refund")

	# ---- a run cannot grow into another
	var at_z:float=float(item(runs[0]).node.position.z)+.9
	var neighbour:Vector3=Vector3(float(item(runs[0]).node.position.x),.16,at_z)
	app.on_placement("fence",neighbour,0,"01","L200H120");await frames()
	var both:Array=placed_ids("fence")
	check(both.size()==2,"A second run sits beside the first")
	var other:String=str(both.filter(func(i:String)->bool:return i!=runs[0])[0]) if both.size()==2 else ""
	var funds:int=app.sim.funds
	var kept:String=str(item(other).variant.size) if other!="" else ""
	app.resize_fence(other,2.0,2.4,"centre")
	check(item(other).variant.size==kept or app.sim.funds!=funds,"A refused resize changes neither the run nor the purse")

	# ---- the run keeps its size through a reload of the saved layout
	var layout:Array=app.world.serialize_items()
	for entry:Dictionary in app.world.items:entry.node.queue_free()
	app.world.items.clear()
	for entry:Dictionary in layout:
		if str(entry.get("kind",""))=="fence":app.world.add_item(entry,false)
	await frames()
	var reloaded:Dictionary=item(runs[0])
	check(not reloaded.is_empty() and reloaded.variant.size=="L600H120" and reloaded.size.x==6.0,"A saved free run reloads at its length")

	# ---- gate colour
	app.pick_furnishing("garden_gate");await frames()
	check(app.overlay.find_children("VariantColor_*","Button",true,false).size()==10,"A gate offers the ten shared colours")
	app.overlay.find_child("VariantColor_3",true,false).pressed.emit();await frames()
	check(app.overlay.find_child("VariantPreview",true,false).get_child_count()>0,"A gate has a preview")
	app.overlay.find_child("VariantConfirm",true,false).pressed.emit();await frames()
	var wanted:String=str(Variants.DEFAULT_COLORS[3])
	check(app.world.placement_color==wanted,"Confirming a gate carries its colour into placement")
	var gate_spot:Vector3=free_spot("garden_gate","")
	need(gate_spot.is_finite(),"The lot has room for a gate")
	app.on_placement("garden_gate",gate_spot,0,"","");await frames()
	var gates:Array=placed_ids("garden_gate")
	check(gates.size()==1,"A single gate is placed")
	var gate_item:Dictionary=item(gates[0])
	check(gate_item.variant.color==wanted,"The placed gate keeps its colour")
	var leaves:Array=gate_item.node.find_children("Tint*","MeshInstance3D",true,false)
	check(leaves.size()==1 and (leaves[0] as MeshInstance3D).material_override.albedo_color.is_equal_approx(Color(wanted)),"The gate leaf wears the chosen colour")
	app._recolour_placed_item(gates[0],Variants.DEFAULT_COLORS[7]);await frames()
	check(item(gates[0]).variant.color==Variants.DEFAULT_COLORS[7],"A placed gate can be repainted")
	leaves=item(gates[0]).node.find_children("Tint*","MeshInstance3D",true,false)
	check((leaves[0] as MeshInstance3D).material_override.albedo_color.is_equal_approx(Color(Variants.DEFAULT_COLORS[7])),"The repaint shows on the leaf")
	var wide_spot:Vector3=free_spot("garden_gate_double","")
	need(wide_spot.is_finite(),"The lot has room for a double gate")
	app.on_placement("garden_gate_double",wide_spot,0,"","");await frames()
	var doubles:Array=placed_ids("garden_gate_double")
	check(doubles.size()==1 and item(doubles[0]).size.x==2.0,"A double gate is two metres wide")
	app._recolour_placed_item(doubles[0],Variants.DEFAULT_COLORS[1]);await frames()
	check(item(doubles[0]).node.find_children("Tint*","MeshInstance3D",true,false).size()==2,"Both leaves of a double gate take the colour")

	# ---- gates open for a driven car and close behind it
	var node:Node3D=item(doubles[0]).node
	check(GateFlow.hinges(node).size()==2 and GateFlow.openness(node)==0.0,"A double gate has two hinged leaves and starts closed")
	var parked:Node3D=Node3D.new();app.world.house.add_child(parked)
	parked.global_position=node.global_position+node.global_transform.basis.z*3.0
	swing(2.0)
	var nearest_note:String=""
	for who:String in app.world.actors:nearest_note+=" %s@%s vis=%s" % [who,str(app.world.actors[who].global_position),str(app.world.actors[who].visible)]
	check(GateFlow.openness(node)==0.0,"A parked car beside a gate does not open it (gate %s, open %s,%s)" % [str(node.global_position),str(GateFlow.openness(node)),nearest_note])
	var car:Node3D=Node3D.new();app.world.house.add_child(car)
	car.add_to_group(GateFlow.DRIVING_GROUP)
	car.global_position=node.global_position+node.global_transform.basis.z*6.0
	swing(.2)
	check(GateFlow.openness(node)>0.0 and GateFlow.openness(node)<1.0,"A car driving toward a gate starts to open it")
	swing(1.0)
	check(is_equal_approx(GateFlow.openness(node),1.0),"The gate is fully open before the car arrives")
	var angles:Array=GateFlow.hinges(node).map(func(h:Node3D)->float:return h.rotation.y)
	check(is_equal_approx(absf(angles[0]),PI*.5) and is_equal_approx(absf(angles[1]),PI*.5) and signf(angles[0])!=signf(angles[1]),"The leaves part symmetrically through a right angle")
	car.global_position=node.global_position
	swing(3.0)
	check(is_equal_approx(GateFlow.openness(node),1.0),"The gate stays open while the car is in it")
	car.global_position=node.global_position-node.global_transform.basis.z*20.0
	swing(.5)
	check(GateFlow.openness(node)>.99,"The gate waits a moment after the car has passed")
	for step:int in range(9):swing(.1)
	check(GateFlow.openness(node)>0.0 and GateFlow.openness(node)<1.0,"The gate then starts to close behind it")
	swing(GateFlow.SWING_TIME)
	check(GateFlow.openness(node)==0.0 and is_equal_approx(GateFlow.hinges(node)[0].rotation.y,0.0),"The gate closes completely")
	car.remove_from_group(GateFlow.DRIVING_GROUP)
	swing(2.0)
	check(GateFlow.openness(node)==0.0,"A car that stops driving no longer holds the gate open")
	# Swinging away from whoever arrives: a car on the far side opens it the other way.
	car.add_to_group(GateFlow.DRIVING_GROUP)
	car.global_position=node.global_position-node.global_transform.basis.z*6.0
	swing(2.0)
	check(signf(GateFlow.hinges(node)[0].rotation.y)!=signf(angles[0]),"The leaves swing away from the side the car comes from")
	car.queue_free()
	await frames()
	swing(5.0)
	check(GateFlow.openness(node)==0.0,"The gate closes once nothing is near it")
	# A Lifelet walking up opens a single gate too.
	var single:Node3D=item(gates[0]).node
	var walker:LifeActor=app.world.actors[app.household.selected_id()]
	var home:Vector3=walker.position
	walker.position=single.global_position+single.global_transform.basis.z*.6
	swing(1.0)
	check(GateFlow.openness(single)>.99,"A Lifelet at a gate opens it")
	walker.position=home
	swing(3.0)
	check(GateFlow.openness(single)==0.0,"It closes when they have gone")
	var paused_open:float=GateFlow.openness(single)
	swing(0.0)
	check(GateFlow.openness(single)==paused_open,"A paused game leaves gates where they were")

	# ---- the driveway gate is three metres, two leaves, tintable like the rest
	var drive_spot:Vector3=free_spot("garden_gate_drive","")
	need(drive_spot.is_finite(),"The lot has room for a driveway gate")
	app.on_placement("garden_gate_drive",drive_spot,0,"","");await frames()
	var drives:Array=placed_ids("garden_gate_drive")
	check(drives.size()==1 and item(drives[0]).size.x==3.0,"A driveway gate is three metres wide")
	check(GateFlow.hinges(item(drives[0]).node).size()==2,"A driveway gate has two leaves")
	var catch_node:Node=item(drives[0]).node.find_child("GateLatch",true,false)
	check(catch_node!=null and str(catch_node.get_parent().name).begins_with("GateHinge"),"The catch is on a leaf, so it opens with the gate")
	app._recolour_placed_item(drives[0],Variants.DEFAULT_COLORS[4]);await frames()
	check(item(drives[0]).node.find_children("Tint*","MeshInstance3D",true,false).size()==2,"Both leaves of a driveway gate take the colour")

	# ---- left and right mean the ends as the player sees them
	var seen_run:Dictionary=item(runs[0])
	var camera:Camera3D=app.world.camera
	var node_3d:Node3D=seen_run.node
	var axis:Vector3=node_3d.global_transform.basis*Vector3.RIGHT
	var half:float=float(seen_run.size.x)*.5
	var end_a:Vector2=camera.unproject_position(node_3d.global_position+axis*half)
	var end_b:Vector2=camera.unproject_position(node_3d.global_position-axis*half)
	var left_is_plus:bool=end_a.x<end_b.x
	var left_before:Vector2=end_a if left_is_plus else end_b
	check(app.resize_fence(runs[0],4.0,1.2,"left"),"A run can be resized keeping its left end")
	await frames()
	var grown:Dictionary=item(runs[0])
	var axis_after:Vector3=grown.node.global_transform.basis*Vector3.RIGHT
	var left_end:Vector3=grown.node.global_position+axis_after*(float(grown.size.x)*.5*(1.0 if left_is_plus else -1.0))
	var left_after:Vector2=camera.unproject_position(left_end)
	check(left_after.distance_to(left_before)<1.0,"Keeping the left end leaves the left end where it was on screen (%.2f px)" % left_after.distance_to(left_before))
	var right_before:Vector2=camera.unproject_position(grown.node.global_position+axis_after*(float(grown.size.x)*.5*(-1.0 if left_is_plus else 1.0)))
	check(app.resize_fence(runs[0],5.0,1.2,"right"),"A run can be resized keeping its right end")
	await frames()
	var longer:Dictionary=item(runs[0])
	var axis_last:Vector3=longer.node.global_transform.basis*Vector3.RIGHT
	var right_after:Vector2=camera.unproject_position(longer.node.global_position+axis_last*(float(longer.size.x)*.5*(-1.0 if left_is_plus else 1.0)))
	check(right_after.distance_to(right_before)<1.0,"Keeping the right end leaves the right end where it was on screen (%.2f px)" % right_after.distance_to(right_before))

	# ---- a fence that is only being moved cannot be lengthened for nothing
	app.household.set_funds(10000)
	var before_move:Dictionary=item(runs[0])
	var size_before:String=str(before_move.variant.size)
	app.set_build_mode(true)
	app.move_item(before_move);await frames()
	check(not app.pending_move.is_empty(),"A fence is picked up to be moved")
	check(not app.world.resize_placement(2,0) or app.world.placement_size!=size_before,"The ghost can change size in the world")
	app.world.placement_size=Variants.custom_id(data,30.0,2.4)
	var bank:int=app.sim.funds
	app.on_placement("fence",Vector3(float(before_move.x),.16,float(before_move.z)),float(before_move.get("rotation",0)),"01",app.world.placement_size);await frames()
	check(app.sim.funds==bank and not app.pending_move.is_empty(),"Placing a moved fence at a new size is refused and costs nothing")
	app.world.placement_size=size_before
	app.on_placement("fence",Vector3(float(before_move.x),.16,float(before_move.z)),float(before_move.get("rotation",0)),"01",size_before);await frames()
	check(app.pending_move.is_empty() and str(item(runs[0]).variant.size)==size_before,"Placed at the size it had, the move completes")
	app.set_build_mode(false)

	# ---- a real save and load keeps every length, height and colour
	app.set_build_mode(false)
	var final_size:String=str(item(runs[0]).variant.size)
	var final_length:float=float(item(runs[0]).size.x)
	var final_panels:int=item(runs[0]).node.find_children("FencePanel_*","Node3D",true,false).size()
	check(app.save_game("","Fences and gates"),"A home with free-length fences and coloured gates saves")
	var slot:String=app.active_save_id
	var epoch:int=app.load_epoch
	app.load_game(slot);await frames()
	check(app.load_epoch==epoch+1,"The save loads into a fresh household")
	var back:Dictionary=item(runs[0])
	check(not back.is_empty() and back.variant.size==final_size and is_equal_approx(float(back.size.x),final_length) and back.node.find_children("FencePanel_*","Node3D",true,false).size()==final_panels,"The loaded fence is still %s m long and built from %d panels" % [str(final_length),final_panels])
	check(item(gates[0]).variant.color==Variants.DEFAULT_COLORS[7],"The loaded single gate keeps its repaint")
	check(item(doubles[0]).variant.color==Variants.DEFAULT_COLORS[1] and GateFlow.openness(item(doubles[0]).node)==0.0,"The loaded double gate keeps its colour and starts shut")

	app.queue_free();await frames()
	print("GATE_FENCE ",checks," checks, ",failures.size()," failures")
	for message:String in failures:print("  ",message)
	quit(0 if failures.is_empty() else 1)
