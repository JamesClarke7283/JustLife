extends SceneTree
## Exercise the laid-out controls and their hit targets, including scrolled swatches.
var app:Node
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)

func frames()->void:
	for index:int in 5:await process_frame

func named(name:String)->Button:
	return app.ui.find_child(name,true,false) as Button

func nonoverlapping(scope:Node,label:String)->void:
	var buttons:Array=scope.find_children("*","Button",true,false)
	var overlap:Array[String]=[]
	for i:int in buttons.size():
		for j:int in range(i+1,buttons.size()):
			var a:Button=buttons[i];var b:Button=buttons[j]
			# The transparent full-screen dismissal button intentionally sits below the card.
			if a.flat or b.flat:continue
			if a.visible and b.visible and a.get_global_rect().grow(-.1).intersects(b.get_global_rect().grow(-.1)):
				overlap.append(str(a.name)+" / "+str(b.name))
	check(overlap.is_empty(),label+" gives every control a separate rectangle: "+", ".join(overlap))

func click(button:Button)->void:
	check(is_instance_valid(button),"Requested control exists")
	if not is_instance_valid(button):return
	var parent:Node=button.get_parent()
	while parent!=null and not parent is ScrollContainer:parent=parent.get_parent()
	if parent is ScrollContainer:parent.ensure_control_visible(button)
	await frames()
	var point:Vector2=button.get_global_transform_with_canvas()*(button.size*.5)
	print("POINTER ",button.name," at ",point," in viewport ",root.get_visible_rect())
	for down:bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true)
		await frames()

func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():quit(2);return
	root.size=Vector2i(960,600)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await frames()
	app.set_sound(false);app.selected_lot=0;app.start_household();await frames()
	app.set_process(false);app.world.set_process(false);app.household.set_speed(0)
	app.set_build_mode(true);app.catalog_category="Structure";app.draw_live();await frames()
	for tool:String in ["paint","carpet"]:
		await click(named("BuildTool_"+tool))
		check(app.world.construction.tool==tool,"Pointer selects "+tool+" tool")
		nonoverlapping(app.ui.find_child("StructureTools",true,false),tool+" toolbar")
		if tool=="paint":
			check(app.ui.find_children("PaintColor_*","Button",true,false).size()==10,"All ten paint colours have independent controls")
			await click(named("PaintStyle_patterned"))
			check(app.world.construction.paint_pattern=="patterned","Pointer selects patterned paint")
			await click(named("PaintColor_6aa6e0"))
			check(app.world.construction.paint_material=="6aa6e0","Scrolled paint swatch receives the pointer")
		else:
			check(app.ui.find_children("CarpetStyle_*","Button",true,false).size()==5,"All five carpet styles are offered")
			check(app.ui.find_children("CarpetColor_*","Button",true,false).size()==10,"All ten carpet colours are offered")
			await click(named("CarpetStyle_geometric"))
			check(app.world.construction.carpet_style=="geometric","Pointer selects geometric carpet")
			await click(named("CarpetColor_f4b6c8"))
			check(app.world.construction.carpet_color=="f4b6c8","Scrolled carpet swatch receives the pointer")
	await click(named("BuildTool_delete"))
	check(app.world.construction.tool=="delete","Delete remains reachable after swatch selection")
	await click(named("UpstairsPresets"))
	nonoverlapping(app.overlay,"Upstairs preset chooser")
	for side:String in ["front","back","east","west"]:
		check(is_instance_valid(app.overlay.find_child("UpstairsSide_"+side,true,false)),"Windows can be selected on "+side+" exterior")
	app.close_overlay();app.cancel_placement();app.household.set_funds(50000)
	var toilet:Dictionary=app.world.closest_item("toilet",Vector3.ZERO)
	var floor_point:Vector3=app.world.approach(toilet)
	app.on_ground_clicked(floor_point);await frames()
	check(is_instance_valid(app.overlay.find_child("RoomFinishPanel",true,false)),"Clicking a room floor opens its finish menu")
	await click(app.overlay.find_child("RoomFinish_paint",true,false))
	await click(app.overlay.find_child("RoomStyle_two_tone",true,false))
	await click(app.overlay.find_child("RoomColor_f4b6c8",true,false))
	nonoverlapping(app.overlay,"Room paint chooser")
	var history:int=app.build_undo.size()
	await click(app.overlay.find_child("RoomFinishApply",true,false))
	check(app.build_undo.size()==history+1,"Room paint applies through the priced undoable transaction")
	app.on_ground_clicked(floor_point);await frames()
	await click(app.overlay.find_child("RoomFinish_floor",true,false))
	await click(app.overlay.find_child("RoomStyle_geometric",true,false))
	await click(app.overlay.find_child("RoomColor_6aa6e0",true,false))
	nonoverlapping(app.overlay,"Room floor chooser")
	check(app.overlay.find_children("RoomColor_*","Button",true,false).size()==10,"Clicked room offers ten carpet colours")
	await click(app.overlay.find_child("RoomFinishApply",true,false))
	var matched:bool=false
	for tile:Dictionary in LifeBuildingState.surface_tiles(app.world.construction.building_state,0):
		if tile.rect.has_point(Vector2(floor_point.x,floor_point.z)):
			matched=tile.material=="6aa6e0" and tile.carpet=="geometric"
	check(matched,"Clicked floor receives the exact carpet style and colour")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("JUSTLIFE_DATA_DIR").path_join("build-toolbar.png"))
	app.queue_free();await frames()
	print("BUILD_TOOLBAR_LAYOUT ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
