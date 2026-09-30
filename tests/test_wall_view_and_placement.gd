extends SceneTree
## Real wall picking and mouse placement, including mounting height after a move.
var app:Node
var failures:Array[String]=[]
var checks:int=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Run with an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
	run.call_deferred()

func frames(count:int=3)->void:
	for i:int in count:await process_frame

func click(at:Vector2)->void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=at;event.global_position=at
	app.get_viewport().push_input(event,true)
	event=event.duplicate();event.pressed=false
	app.get_viewport().push_input(event,true)
	await frames()

func bounds(node:Node3D)->AABB:
	var result:AABB
	var found:bool=false
	for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var box:AABB=mesh.global_transform*mesh.get_aabb()
		result=result.merge(box) if found else box;found=true
	return result

func run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await frames(6)
	app.selected_lot=0;app.start_household();await frames(6)
	app.set_sound(false);app.household.set_speed(0)
	app.set_process(false);app.world.set_process(false)
	var world:LifeWorld=app.world
	var structure:Dictionary=world.construction.snapshot()
	var generation:int=world.lot_navigation.generation
	check(world.cutaway,"Home starts in the lowered navigation view")
	check(world.construction.records.all(func(e:Dictionary)->bool:return world.construction._visible_wall_height(e)<=.65),"Every wall is lowered, including former uncut back and side walls")
	# Look straight at a clear part of the front wall, outside the HUD.
	world.camera.position=Vector3(-3,3,11);world.camera.look_at(Vector3(-3,.4,5.04))
	var wall_pixel:Vector2=world.camera.unproject_position(Vector3(-3,.4,5.04))
	await physics_frame
	await click(wall_pixel)
	check(not world.cutaway,"First actual wall click raises all walls")
	check(world.construction.records.all(func(e:Dictionary)->bool:return is_equal_approx(world.construction._visible_wall_height(e),float(e.height))),"Raised walls show their full stored height")
	var window_hit:Dictionary=world.construction.pick_wall(Vector3(-4.25,1.78,-6),Vector3.BACK,0)
	check(window_hit.is_empty() or float(window_hit.distance)>2.0,"Window openings do not intercept clicks on objects seen through the glass")
	await click(wall_pixel)
	check(world.cutaway,"Second actual wall click lowers all walls")
	check(world.construction.snapshot()==structure and world.lot_navigation.generation==generation,"Wall clicks preserve structural records and the navigation graph")
	check(world.construction.point_blocked(Vector2(1,-1.3)),"Bedroom and bathroom divider is enclosed at its corner junction")
	# Ghosts keep a sensible mounting height even before reaching a wall.
	app.set_build_mode(true);app.household.set_funds(10000)
	for kind:String in ["framed_picture","painting","shelf","wall_clock","children_picture"]:
		world.begin_placement(kind);world.update_ghost(Vector3(-8,.16,3))
		var shown:AABB=bounds(world.ghost)
		check(shown.position.y>.8 and shown.end.y<2.7,"Unsnapped %s preview is elevated once and remains below the ceiling"%kind)
		world.update_ghost(Vector3(-3,.16,4.8))
		check(world.ghost_valid,"A %s has a valid front-wall preview"%kind)
		shown=bounds(world.ghost)
		var entry:Dictionary={"id":"height_"+kind,"kind":kind,"x":world.ghost_position.x,"z":world.ghost_position.z,"rotation":world.placement_angle,"hang":world.placement_hang}
		world.add_item(entry,false)
		var actual:AABB=bounds(world.items[-1].node)
		check(shown.position.is_equal_approx(actual.position) and shown.size.is_equal_approx(actual.size),"%s preview and placed model occupy exactly the same height"%kind)
		var volume:AABB=world.furnishing_volume(entry)
		check(volume.position.y<=actual.position.y+.001 and volume.end.y>=actual.end.y-.001 and volume.end.y<2.7,"%s roof checks apply mounting height once"%kind)
		var shape:CollisionShape3D=world.items[-1].node.find_children("*","CollisionShape3D",true,false)[0]
		var pick_bounds:AABB=shape.global_transform*AABB(-shape.shape.size*.5,shape.shape.size)
		check(pick_bounds.position.y>=actual.position.y-.001 and pick_bounds.end.y<=actual.end.y+.001,"%s click target fits its visible height"%kind)
		world.remove_item(str(entry.id))
	world.begin_placement("framed_picture")
	world.update_ghost(Vector3(-3,.16,4.8))
	var prior:int=world.items.size()
	var shown:AABB=bounds(world.ghost)
	var floor_point:Vector3=world.ghost_position
	world.camera.position=Vector3(-3,4,0);world.camera.look_at(Vector3(-3,1.5,5))
	var screen:Vector2=world.camera.unproject_position(world.ghost.position)
	check(world.placement_point(screen).distance_to(floor_point)<.001,"Raised preview follows the cursor while validation stays at floor height")
	var wheel:=InputEventMouseButton.new();wheel.pressed=true;wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.position=screen
	app.get_viewport().push_input(wheel,true)
	world.update_ghost(floor_point)
	check(is_equal_approx(world.placement_hang,1.58),"Wheel adjusts mounting height")
	await click(screen)
	check(world.items.size()==prior+1,"Left click commits hanging art instead of being swallowed by the height handler")
	if world.items.size()==prior+1:
		var placed:Dictionary=world.items[-1]
		check(is_equal_approx(placed.node.position.y,.16+1.58),"Committed art uses the adjusted preview height")
		app.move_item(placed)
		check(is_equal_approx(world.placement_hang,1.58),"Moving art preserves its selected mounting height")
		app.cancel_placement()
	var saved:Array=world.serialize_items()
	world.create_home(saved)
	var restored:Dictionary={}
	for item:Dictionary in world.items:
		if item.kind=="framed_picture":restored=item
	check(not restored.is_empty() and is_equal_approx(restored.node.position.y,1.74),"Save/restore preserves mounted art height")
	print("WALL_VIEW_PLACEMENT ",checks," checks, ",failures.size()," failures")
	app.queue_free();await frames();quit(0 if failures.is_empty() else 1)
