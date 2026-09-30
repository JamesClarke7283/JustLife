extends SceneTree
var app:Node
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func frames()->void:
	for i:int in 5:await process_frame
func preview()->SubViewport:
	return app.overlay.find_child("VariantPreview",true,false).get_child(0)
func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():quit(2);return
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await frames()
	app.set_sound(false);app.selected_lot=0;app.start_household();await frames()
	app.set_process(false);app.world.set_process(false);app.household.set_speed(0);app.household.set_funds(10000);app.set_build_mode(true)
	app.pick_furnishing("bath_mat");await frames()
	check(app.overlay.find_children("VariantStyle_*","Button",true,false).size()==3,"All three bath mat styles have controls")
	check(app.overlay.find_children("VariantColor_*","Button",true,false).size()==10,"Ten color swatches are visible")
	for style:String in ["plush","oval","grid"]:
		app.overlay.find_child("VariantStyle_"+style,true,false).pressed.emit();await frames()
		for index:int in [1,4,9]:
			app.overlay.find_child("VariantColor_%d" % index,true,false).pressed.emit();await frames()
			var meshes:Array=preview().find_children("Tint*","MeshInstance3D",true,false)
			check(meshes.size()==(9 if style=="grid" else 1),"Style changes the actual preview geometry")
			var expected:Color=Color(LifeCatalog.get_item("bath_mat").colors[index])
			for mesh:MeshInstance3D in meshes:check(mesh.material_override.albedo_color.is_equal_approx(expected),"Swatch recolors the rendered mat")
		if OS.get_cmdline_user_args().has("--capture"):
			await RenderingServer.frame_post_draw
			var image:Image=preview().get_texture().get_image()
			var visible:int=0
			for x:int in range(0,image.get_width(),4):
				for y:int in range(0,image.get_height(),4):
					if image.get_pixel(x,y).a>.1:visible+=1
			check(visible>150,"Mat occupies a visible area in its live preview")
			var folder:String=OS.get_environment("JUSTLIFE_DATA_DIR").path_join("captures")
			DirAccess.make_dir_recursive_absolute(folder)
			root.get_texture().get_image().save_png(folder.path_join("bath-mat-"+style+".png"))
	app.overlay.find_child("VariantConfirm",true,false).pressed.emit();await frames()
	check(app.world.placement_style=="grid" and app.world.placement_color=="2a9d8f","Confirm keeps the selected style and color")
	var before:int=app.sim.funds
	app.world.update_ghost(Vector3(1,.16,0))
	check(app.world.ghost_valid,"Selected mat has valid placement")
	app.on_placement("bath_mat",app.world.ghost_position,app.world.placement_angle,app.world.placement_style,app.world.placement_size);await frames()
	check(app.sim.funds==before-15,"Mat purchase charges15 once")
	var placed:Array=app.world.serialize_items().filter(func(item:Dictionary)->bool:return str(item.kind)=="bath_mat")
	check(placed.size()==1 and placed[0].style=="grid" and placed[0].color=="2a9d8f","Placed mat saves the previewed choices")
	app.queue_free();await frames()
	print("BATH_MAT_PREVIEW ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
