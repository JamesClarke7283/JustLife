extends SceneTree
## Appliance choices are real model changes, persist through public saves and
## share preview geometry. Fridge snapping is measured at the rendered back.
const Kitchen=preload("res://scripts/kitchen_furnishings.gd")
const Variants=preload("res://scripts/catalog_variants.gd")
var app:Node
var checks:int=0
var failures:Array[String]=[]
var capture:bool=false
func check(ok:bool,label:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label);push_error(label)
func _initialize()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path():
		push_error("Use an isolated absolute JUSTLIFE_DATA_DIR.");quit(2);return
	capture=OS.get_cmdline_user_args().has("--capture")
	run.call_deferred()
func frames(count:int=3)->void:
	for index:int in count:await process_frame
func bounds(node:Node3D)->AABB:
	var result:AABB;var first:bool=true
	for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var part:AABB=mesh.global_transform*mesh.get_aabb()
		result=part if first else result.merge(part);first=false
	return result
func screenshot(label:String)->void:
	if not capture:return
	await frames(5);await RenderingServer.frame_post_draw
	var folder:String=OS.get_environment("JUSTLIFE_DATA_DIR").path_join("captures")
	DirAccess.make_dir_recursive_absolute(folder)
	var picture:Image=root.get_texture().get_image()
	check(picture.save_png(folder.path_join(label+".png"))==OK,"Rendered "+label)
func gallery()->void:
	var scene:=Node3D.new();root.add_child(scene)
	for index:int in Kitchen.STYLES.size():
		for kind:String in ["fridge","sink"]:
			var model:Node3D=Kitchen.build(kind,{"style":Kitchen.STYLES[index],"color":Kitchen.COLORS[[0,1,3,5,8][index]]})
			scene.add_child(model);model.position=Vector3((float(index)-2.0)*1.45,0,-.8 if kind=="fridge" else 1.6)
			model.scale*=Kitchen.model_scale(kind)
		var label:=Label3D.new();scene.add_child(label)
		label.text=Kitchen.STYLE_LABELS[Kitchen.STYLES[index]];label.font_size=36;label.pixel_size=.007
		label.position=Vector3((float(index)-2.0)*1.45,.15,2.6);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	var camera:=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=7.8;camera.position=Vector3(2,5,10);camera.look_at(Vector3(0,.6,.7));camera.current=true
	var light:=DirectionalLight3D.new();scene.add_child(light);light.rotation_degrees=Vector3(-40,-30,0);light.light_energy=1.1
	var environment:=WorldEnvironment.new();scene.add_child(environment);environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("d5dedb")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6
	await screenshot("all-appliance-styles")
	scene.queue_free();await frames()
func run()->void:
	if OS.get_cmdline_user_args().has("--gallery-only"):
		await gallery();quit(0 if failures.is_empty() else 1);return
	for kind:String in ["fridge","sink"]:
		var data:Dictionary=LifeCatalog.get_item(kind)
		check(data.styles==Kitchen.STYLES and data.colors==Kitchen.COLORS,kind+" shares all five styles and ten cabinet colours")
		var signatures:Array[String]=[]
		for style:String in Kitchen.STYLES:
			for color:String in Kitchen.COLORS:
				var model:Node3D=Kitchen.build(kind,{"style":style,"color":color})
				var signature:String="";var painted:int=0;var correct:bool=true
				for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
					signature+=str(mesh.transform)+str(mesh.mesh.get_aabb())
					if str(mesh.name).begins_with("Tint"):
						painted+=1;correct=correct and mesh.material_override!=null and mesh.material_override.albedo_color.is_equal_approx(Color(color))
				check(painted>0 and correct,kind+" "+style+" visibly applies #"+color)
				if color==Kitchen.COLORS[0]:
					check(not signatures.has(signature),kind+" "+style+" has a distinct model")
					signatures.append(signature)
					var body_count:int=model.find_children("*","MeshInstance3D",true,false).size()
					for child:Node in model.find_children("*","",true,false):child.owner=model
					var packed:=PackedScene.new();packed.pack(model)
					var preview:Node3D=packed.instantiate()
					check(preview.find_children("*","MeshInstance3D",true,false).size()==body_count,kind+" "+style+" packed preview preserves the exact appliance parts")
					preview.free()
					if kind=="sink":check(model.find_children("Basin*","MeshInstance3D",true,false).size()==2 and model.find_children("Tap*","MeshInstance3D",true,false).size()==2,"Sink retains both basin and both tap pieces")
					else:
						check(model.find_children("Brass*","MeshInstance3D",true,false).size()==2,"Fridge retains both working door handles")
						var note:MeshInstance3D=model.find_children("Note*","MeshInstance3D",true,false)[0]
						var note_box:AABB=note.transform*note.get_aabb()
						var clear_note:bool=true
						for face:MeshInstance3D in model.find_children("Tint*","MeshInstance3D",true,false):
							var face_box:AABB=face.transform*face.get_aabb()
							var overlap:bool=note_box.position.x<face_box.end.x and note_box.end.x>face_box.position.x and note_box.position.y<face_box.end.y and note_box.end.y>face_box.position.y
							if overlap and note_box.position.z<face_box.end.z-.001:clear_note=false
						check(clear_note,"Fridge note is not clipped by its "+style+" finish")
				model.free()
	check(Variants.price(LifeCatalog.get_item("corner_counter"),"")==15,"Corner unit costs exactly15")
	var world:=LifeWorld.new();root.add_child(world);world.create_home([]);world.set_process(false)
	for trial:Array in [[Vector3(-3,.16,-4.25),0.0],[Vector3(-3,.16,4.25),180.0],[Vector3(-5.25,.16,3),90.0],[Vector3(5.25,.16,3),270.0]]:
		var point:Vector3=trial[0];var angle:float=trial[1]
		world.begin_placement("fridge","slatted","","c97c66");world.placement_angle=angle;world.update_ghost(point)
		var snapped:Vector3=world.ghost_position
		check(snapped.distance_to(point)>.01,"Fridge snaps toward its back wall at "+str(angle))
		check(world.ghost_valid,"Flush fridge is placeable at "+str(angle))
		var actual:AABB=bounds(world.ghost)
		var panels:Array=world.construction.records.filter(func(record:Dictionary)->bool:return int(record.get("level",0))==0)
		var back:Vector3=snapped-Basis(Vector3.UP,deg_to_rad(angle))*Vector3(0,0,.425)
		var touching:bool=false
		for record:Dictionary in panels:
			var wall:Rect2=world.construction.wall_rect(record)
			if wall.grow(.001).has_point(Vector2(back.x,back.z)):touching=true
		check(touching,"Fridge rear meets actual wall surface at "+str(angle))
		var rear:float=actual.position.z if is_zero_approx(angle) else (actual.end.z if is_equal_approx(angle,180) else (actual.position.x if is_equal_approx(angle,90) else actual.end.x))
		check(absf(rear-(back.z if int(angle)%180==0 else back.x))<.001,"Rendered fridge rear agrees with snap footprint at "+str(angle))
		var front:Vector3=Basis(Vector3.UP,deg_to_rad(angle))*Vector3.BACK
		check(not world.can_place("fridge",snapped-front*.03,angle),"Fridge penetrating wall remains refused at "+str(angle))
	world.clear_placement();world.queue_free();await frames()
	if capture:await gallery()
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await frames(5)
	print("KITCHEN_PHASE starting household")
	app.set_sound(false);app.selected_lot=0;app.start_household();await frames(5)
	print("KITCHEN_PHASE entering build mode")
	app.set_process(false);app.household.set_speed(0);app.world.set_process(false);app.household.set_funds(10000);app.set_build_mode(true)
	print("KITCHEN_PHASE moving original fridge")
	var original_fridge:Dictionary=app.world.closest_item("fridge",Vector3(-5,.16,-4))
	var original_id:String=str(original_fridge.id)
	var original_at:Vector3=original_fridge.node.position
	app.move_item(original_fridge);await frames();app.world.update_ghost(original_at)
	check(app.world.ghost_valid,"Existing kitchen fridge has a valid wall-snapped move preview")
	var wall_position:Vector3=app.world.ghost_position
	app.on_placement("fridge",wall_position,app.world.placement_angle,app.world.placement_style,app.world.placement_size)
	var moved_fridge:Dictionary=app._find_item(original_id)
	check(not moved_fridge.is_empty() and moved_fridge.node.position.is_equal_approx(wall_position),"Public move commits the fridge flush against its kitchen wall")
	if not moved_fridge.is_empty():
		check(absf(bounds(moved_fridge.node).position.z+4.96)<.001,"Purchased kitchen fridge physically touches the rear wall without clipping")
		var camera_before:Transform3D=app.world.camera.transform
		app.world.camera.position=Vector3(-3,3.2,-1.5);app.world.camera.look_at(moved_fridge.node.position+Vector3(0,.8,0))
		await screenshot("fridge-wall")
		app.world.camera.transform=camera_before
	var purchased:Array[String]=[]
	for index:int in 2:
		var kind:String=["fridge","sink"][index]
		app.pick_furnishing(kind)
		check(app.overlay.find_children("VariantStyle_*","Button",true,false).size()==5 and app.overlay.find_children("VariantColor_*","Button",true,false).size()==10,kind+" shop offers five styles and ten swatches")
		app.overlay.find_child("VariantStyle_farmhouse",true,false).pressed.emit();await frames()
		app.overlay.find_child("VariantColor_8",true,false).pressed.emit();await frames()
		await screenshot(kind+"-chooser")
		var preview:Node=app.overlay.find_child("VariantPreview",true,false)
		check(not preview.find_children("Tint*","MeshInstance3D",true,false).is_empty(),kind+" chooser contains its styled model")
		app.overlay.find_child("VariantConfirm",true,false).pressed.emit();await frames()
		var at:=Vector3(-3.0+float(index)*2.0,.16,7)
		app.world.update_ghost(at)
		check(app.world.ghost_valid,kind+" selected preview has a legal floor position")
		var before:AABB=bounds(app.world.ghost)
		var funds:int=app.sim.funds
		app.on_placement(kind,app.world.ghost_position,0,app.world.placement_style,app.world.placement_size)
		var item:Dictionary=app.world.closest_item(kind,at,.2)
		check(not item.is_empty(),kind+" public purchase succeeds")
		if item.is_empty():continue
		purchased.append(str(item.id))
		check(item.variant.style=="farmhouse" and item.variant.color=="c97c66",kind+" public purchase retains selected style and colour")
		check(app.sim.funds==funds-int(LifeCatalog.get_item(kind).price),kind+" purchase charges its declared price once")
		var after:AABB=bounds(item.node)
		check(before.position.is_equal_approx(after.position) and before.size.is_equal_approx(after.size),kind+" ghost and purchased model have identical geometry")
		var anchor:Dictionary=app.world.activity_anchor(item,"snack" if kind=="fridge" else "wash_hands")
		check(is_equal_approx(anchor.position.y,.16) and anchor.position.distance_to(item.node.position)>.45,kind+" keeps its reachable floor-level use point")
	check(app.save_game("appliance_styles","Kitchen appliance styles"),"Styled appliances save publicly")
	app.load_game("appliance_styles");await frames(5);app.set_process(false);app.world.set_process(false)
	for id:String in purchased:
		var item:Dictionary=app._find_item(id)
		check(not item.is_empty() and item.variant.style=="farmhouse" and item.variant.color=="c97c66","Fresh load restores appliance "+id+" finish")
	app.queue_free();await frames(3)
	print("KITCHEN_APPLIANCE_STYLES %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
