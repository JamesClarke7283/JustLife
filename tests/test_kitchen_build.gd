extends SceneTree
## Public shop -> preview -> purchase -> move/save coverage for modular kitchens.
const Kitchen = preload("res://scripts/kitchen_furnishings.gd")
const Variants = preload("res://scripts/catalog_variants.gd")
var checks:int=0
var failures:Array[String]=[]
var app:Node
func check(ok:bool,message:String)->void:
	checks+=1
	print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message);push_error(message)
func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Run with an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
	run.call_deferred()
func frames(count:int=2)->void:
	for i:int in count:await process_frame
func find_item(kind:String,at:Vector3)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind and Vector2(item.node.position.x-at.x,item.node.position.z-at.z).length()<.25:return item
	return {}
func run()->void:
	for kind:String in ["counter","corner_counter"]:
		var data:Dictionary=LifeCatalog.get_item(kind)
		check(data.styles.size()==5 and data.colors.size()==10,kind+" offers five styles and ten colours")
		var signatures:Array=[]
		for style:String in data.styles:
			var model:Node3D=Kitchen.build(kind,{"style":style,"color":"c97c66"})
			var signature:String=""
			var tint_ok:bool=true
			for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				signature+=str(mesh.transform)+str(mesh.mesh.get_aabb())
				if str(mesh.name).begins_with("Tint"):tint_ok=tint_ok and mesh.material_override.albedo_color.is_equal_approx(Color("c97c66"))
			check(tint_ok,style+" tints its cabinet front")
			check(not signatures.has(signature),kind+" "+style+" has distinct geometry")
			signatures.append(signature);model.free()
	check(Variants.price(LifeCatalog.get_item("corner_counter"),"")==20,"Corner cabinet costs 20")
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	await frames(3)
	app.set_sound(false);app.selected_lot=0;app.start_household();await frames(3)
	app.set_process(false);app.household.set_speed(0);app.household.set_funds(20000);app.set_build_mode(true)
	var world:LifeWorld=app.world
	world.set_process(false)
	# Buy a real cabinet through the same variant picker the catalogue opens.
	app.pick_furnishing("counter")
	check(app.overlay.find_children("VariantStyle_*","Button",true,false).size()==5,"Shop exposes every cabinet style")
	check(app.overlay.find_children("VariantColor_*","Button",true,false).size()==10,"Shop exposes every cabinet colour")
	app.overlay.find_child("VariantStyle_drawers",true,false).pressed.emit();await frames()
	app.overlay.find_child("VariantColor_8",true,false).pressed.emit();await frames()
	app.overlay.find_child("VariantConfirm",true,false).pressed.emit();await frames()
	check(world.placement_style=="drawers" and world.placement_color=="c97c66","Picker passes selected style and colour to placement")
	var at:=Vector3(-3,.16,7)
	world.update_ghost(at)
	check(world.ghost_valid,"Cabinet preview can stand on clear garden floor")
	app.on_placement("counter",world.ghost_position,0,world.placement_style,world.placement_size)
	var cabinet:Dictionary=find_item("counter",at)
	check(not cabinet.is_empty(),"Cabinet purchase creates the previewed object")
	if cabinet.is_empty():quit(1);return
	check(cabinet.variant.style=="drawers" and cabinet.variant.color=="c97c66","Placed cabinet keeps style and colour")
	for pair:Array in [["fridge",Vector3(-2,.16,7),0.0],["stove",Vector3(-2,.16,7),0.0],["counter",Vector3(-2,.16,7),0.0]]:
		var kind:String=pair[0]
		var snapped:Vector3=world.kitchen_snap(kind,pair[1],pair[2])
		var incoming:Rect2=world.furnishing_rect({"kind":kind,"x":snapped.x,"z":snapped.z,"rotation":pair[2]})
		var existing:Rect2=world.item_panels(cabinet,false)[0]
		check(is_equal_approx(incoming.position.x,existing.end.x),kind+" joins cabinet edge exactly")
		check(world.can_place(kind,snapped,pair[2]),kind+" flush join is allowed by collision rules")
	check(not world.can_place("stove",at,0),"Modular overlap is still refused")
	app.begin_purchase_variant("corner_counter",{"style":"slatted","color":"1f3b6b","size":""})
	world.update_ghost(Vector3(-2,.16,7))
	var corner_at:Vector3=world.ghost_position
	var funds:int=app.sim.funds
	app.on_placement("corner_counter",corner_at,0,"slatted","")
	var corner:Dictionary=find_item("corner_counter",corner_at)
	check(not corner.is_empty() and app.sim.funds==funds-20,"Public corner purchase charges exactly 20")
	var returned:Vector3=world.kitchen_snap("counter",corner_at+Vector3(0,0,1),90)
	var return_rect:Rect2=world.furnishing_rect({"kind":"counter","x":returned.x,"z":returned.z,"rotation":90})
	var corner_rect:Rect2=world.item_panels(corner,false)[0]
	check(is_equal_approx(return_rect.position.y,corner_rect.end.y) and world.can_place("counter",returned,90),"Rotated cabinet joins a corner in an L-shaped run")
	app.begin_purchase("coffee_machine");world.update_ghost(at)
	check(world.ghost_valid and is_equal_approx(world.ghost.position.y,1.112),"Coffee preview rests on the worktop")
	app.on_placement("coffee_machine",world.ghost_position,0)
	var coffee:Dictionary=find_item("coffee_machine",at)
	check(not coffee.is_empty() and is_equal_approx(coffee.node.position.y,1.112),"Coffee machine can be bought on a cabinet")
	check(not world.can_place("coffee_machine",at,0),"Two coffee machines cannot overlap on one worktop")
	check(is_equal_approx(world.activity_anchor(coffee,"drink_coffee").position.y,.16),"Coffee interaction keeps the Lifelet on the floor beside the worktop")
	var saved:Array=world.serialize_items()
	var saved_coffee:Dictionary={}
	for entry:Dictionary in saved:
		if str(entry.get("id",""))==str(coffee.id):saved_coffee=entry
	check(is_equal_approx(float(saved_coffee.get("hang",0)),.952) and str(saved_coffee.get("support_id",""))==str(cabinet.id),"Save records coffee support and elevation")
	app.move_item(coffee);await frames()
	var floor_at:=Vector3(-5.5,.16,8)
	world.update_ghost(floor_at)
	check(world.ghost_valid and is_equal_approx(world.ghost.position.y,.16),"Moving coffee to the floor lowers its preview")
	app.on_placement("coffee_machine",floor_at,0)
	coffee=find_item("coffee_machine",floor_at)
	check(not coffee.is_empty() and is_equal_approx(coffee.node.position.y,.16),"Coffee can be freely moved from worktop to floor")
	var table_at:Vector3=Vector3.INF
	app.begin_purchase("dining")
	for candidate:Vector3 in [Vector3(3,.16,7),Vector3(3,.16,8),Vector3(-5,.16,0),Vector3(7,.16,0)]:
		if world.can_place("dining",candidate,0):table_at=candidate;break
	check(table_at.is_finite(),"Fixture has clear floor for a table")
	if not table_at.is_finite():quit(1);return
	app.on_placement("dining",table_at,0)
	var table:Dictionary=find_item("dining",table_at)
	check(not table.is_empty(),"Table purchase succeeds")
	if table.is_empty():quit(1);return
	app.move_item(coffee);await frames()
	world.update_ghost(table_at+Vector3(.5,0,0))
	check(world.ghost_valid and is_equal_approx(world.ghost.position.y,1.007),"Coffee preview rests on a table")
	app.on_placement("coffee_machine",world.ghost_position,0)
	coffee=find_item("coffee_machine",table_at+Vector3(.5,0,0))
	check(not coffee.is_empty() and is_equal_approx(coffee.node.position.y,1.007),"Coffee is placed at the actual tabletop height")
	if coffee.is_empty():quit(1);return
	app.move_item(table);await frames()
	var moved_table_at:Vector3=Vector3.INF
	world.placement_angle=90
	for candidate:Vector3 in [Vector3(4.5,.16,7),Vector3(3,.16,9),Vector3(-5,.16,-2),Vector3(7,.16,3)]:
		if world.can_place("dining",candidate,90):moved_table_at=candidate;break
	check(moved_table_at.is_finite(),"Fixture has clear floor to move the table")
	if not moved_table_at.is_finite():quit(1);return
	app.on_placement("dining",moved_table_at,90)
	table=find_item("dining",moved_table_at)
	check(not table.is_empty() and coffee.node.position.distance_to(table.node.to_global(Vector3(.5,.847,0)))<.01,"Moving and rotating a table carries its coffee machine")
	if table.is_empty():quit(1);return
	# Reload the saved records through the real scene constructor, regardless of order.
	var reloaded:=LifeWorld.new();root.add_child(reloaded)
	var roundtrip:Array=world.serialize_items();roundtrip.reverse();reloaded.create_home(roundtrip)
	var restored:Dictionary=reloaded.closest_item("coffee_machine",coffee.node.position,.3)
	check(not restored.is_empty() and is_equal_approx(restored.node.position.y,coffee.node.position.y),"Reload preserves tabletop coffee elevation")
	var restored_cabinet:Dictionary=reloaded.closest_item("counter",at,.3)
	check(restored_cabinet.variant.style=="drawers" and restored_cabinet.variant.color=="c97c66","Reload preserves cabinet choices")
	reloaded.queue_free()
	app.sell_item(table);await frames()
	check(is_equal_approx(coffee.node.position.y,.16) and not coffee.has("support_id"),"Selling the table returns its coffee machine to floor level")
	app.queue_free();await frames(3)
	print("KITCHEN_BUILD %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
