extends SceneTree
## World + real meal-surface policy: appliances and dishes cannot occupy the
## same worktop area, and corner cabinets participate in serving meals.
class MealApp extends Node:
	var world:LifeWorld
	var household:Dictionary={"meals":LifeMeals.new(),"members":[],"day":1,"minutes":600.0}
	var current_venue:String="home"
	var residents:Variant=null
	func _find_item(id:String)->Dictionary:
		for item:Dictionary in world.items:
			if str(item.id)==id:return item
		return {}
var checks:int=0
var failures:int=0
func check(ok:bool,message:String)->void:
	checks+=1
	print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1;push_error(message)
func _initialize()->void:run.call_deferred()
func props_visible(host:Dictionary,pattern:String) -> bool:
	var props:Array=host.node.find_children(pattern,"Node3D",true,false)
	return not props.is_empty() and props.all(func(node:Node3D)->bool:return node.visible)
func place_coffee(world:LifeWorld,host:Dictionary,local:Vector3) -> Dictionary:
	var at:Vector3=host.node.to_global(local)
	at.y=LifeWorld.Building.level_y(world.item_level(host))
	var entry:Dictionary={"id":"coffee","kind":"coffee_machine","x":at.x,"z":at.z,"rotation":host.node.rotation_degrees.y}
	entry.merge(world.surface_placement("coffee_machine",at,host.node.rotation_degrees.y),true)
	world.add_item(entry)
	return entry
func run()->void:
	var app:=MealApp.new();root.add_child(app)
	app.world=LifeWorld.new();app.add_child(app.world);app.world.create_home([]);app.world.set_process(false)
	var world:LifeWorld=app.world
	var flow:=LifeMealFlow.new();app.add_child(flow);flow.app=app
	world.add_item({"id":"table","kind":"dining","x":-3.0,"z":1.0,"rotation":90.0})
	var table:Dictionary=app._find_item("table")
	var coffee_floor:Vector3=table.node.to_global(Vector3(.4,0,0))
	var coffee:Dictionary={"id":"coffee","kind":"coffee_machine","x":coffee_floor.x,"z":coffee_floor.z,"rotation":90.0}
	coffee.merge(world.surface_placement("coffee_machine",coffee_floor,90),true);world.add_item(coffee)
	check(not flow._surface_clear(table,Vector3(.4,.847,0),LifeMeals.PLATE_HALF_SIZE),"A plate cannot land inside a rotated tabletop coffee machine")
	check(flow._surface_clear(table,Vector3(-.4,.847,0),LifeMeals.PLATE_HALF_SIZE),"The clear half of the same table can still hold a plate")
	world.remove_item("coffee")
	check(props_visible(table,"Fruit*"),"Unoccupied dining fruit is visible")
	check(world.can_place("coffee_machine",table.node.position,90),"The center of a dining table remains usable for coffee")
	place_coffee(world,table,Vector3.ZERO)
	flow._sync_table_settings()
	check(not props_visible(table,"Fruit*"),"A center appliance hides the overlapping fruit even after the meal display refreshes")
	var saved:Array=world.serialize_items();saved.reverse()
	world.create_home(saved);await process_frame
	table=app._find_item("table")
	check(not props_visible(table,"Fruit*"),"Save/load restores the appliance and keeps its overlapping fruit hidden")
	world.remove_item("coffee");flow._sync_table_settings()
	check(props_visible(table,"Fruit*"),"Removing the appliance restores the dining centerpiece")
	place_coffee(world,table,Vector3(.5,0,0));flow._sync_table_settings()
	check(props_visible(table,"Fruit*"),"An appliance beside the centerpiece leaves the nonoverlapping fruit visible")
	world.remove_item("coffee")
	var plate:=Node3D.new();world.house.add_child(plate)
	plate.position=table.node.to_global(Vector3(.4,.847,0));plate.rotation_degrees.y=90
	world.items.append({"id":"plate","kind":"plate","node":plate,"size":Vector2(.3,.3),"level":0,"transient_food":true,"food_host":"table","food_storage":"surface","surface_half":LifeMeals.PLATE_HALF_SIZE})
	check(not world.can_place("coffee_machine",coffee_floor,90),"A coffee machine cannot be placed through a served plate")
	plate.visible=false
	check(world.can_place("coffee_machine",coffee_floor,90),"A hidden carried plate does not reserve tabletop space")
	world.items=world.items.filter(func(item:Dictionary)->bool:return str(item.id)!="plate")
	plate.queue_free();world.remove_item("table")
	world.add_item({"id":"corner","kind":"corner_counter","x":-3.0,"z":1.0,"rotation":0.0})
	var served:Dictionary=flow._serving_surface(Vector3(-3,.16,2.5))
	check(str(served.get("id",""))=="corner","A free corner worktop can receive a cooked meal")
	world.remove_item("corner")
	for kind:String in ["table","coffee_table","desk","study_desk"]:
		world.add_item({"id":"host","kind":kind,"x":-3.0,"z":1.0,"rotation":90.0})
		var host:Dictionary=app._find_item("host")
		if kind in ["desk","study_desk"]:
			check(world.surface_placement("coffee_machine",host.node.position,90).is_empty() and not world.can_place("coffee_machine",host.node.position,90),kind+" keeps its functional laptop workspace clear")
			if kind=="desk":
				var side:Vector3=host.node.to_global(Vector3(-.49,0,0))
				check(not world.surface_placement("coffee_machine",side,90).is_empty() and world.can_place("coffee_machine",side,90),"A coffee maker can still occupy the free side of the desk")
		else:
			var pattern:String="Art book*" if kind=="table" else "Coffee book*"
			check(world.can_place("coffee_machine",host.node.position,90) and props_visible(host,pattern),kind+" starts with a usable top and visible decorative books")
			place_coffee(world,host,Vector3.ZERO)
			check(not props_visible(host,pattern),kind+" hides books overlapping the placed appliance")
			world.remove_item("coffee")
			check(props_visible(host,pattern),kind+" restores its books when the appliance leaves")
		world.remove_item("host")
	app.queue_free();await process_frame
	print("KITCHEN_MEAL_SURFACES %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
