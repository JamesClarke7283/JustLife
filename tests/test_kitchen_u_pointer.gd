extends SceneTree
## One private X11 process supplies genuine mouse events. This fixture only
## observes controls and publishes screen coordinates; it never emits their
## signals or injects Input events. The rest of the U uses public build commits.
const Library=preload("res://scripts/save_library.gd")
var app:Node
var checks:int=0
var failures:Array[String]=[]
var sequence:int=0
var receipts:Array=[]
var bought:Array[Dictionary]=[]
var start_funds:int=20000
var u_only:bool="--u-only" in OS.get_cmdline_user_args()
var pointer_only:bool="--pointer-only" in OS.get_cmdline_user_args()
const SITE_OFFSET=Vector3(10,0,-6)
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func frames(n:int=3)->void:
	for i:int in n:await process_frame
func write_json(path:String,value:Variant)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(Library._json_safe(value),"  ",true,true));file.close()
func native_pointer(point:Vector2,action:String="click")->bool:
	sequence+=1
	var scale:Vector2=Vector2(DisplayServer.window_get_size())/root.get_visible_rect().size
	write_json("res://evidence/pointer_request.json",{"sequence":sequence,"action":action,"x":roundi(point.x*scale.x),"y":roundi(point.y*scale.y)})
	for i:int in 180:
		await process_frame
		if not FileAccess.file_exists("res://evidence/pointer_reply.json"):continue
		var reply:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/pointer_reply.json"))
		if reply is Dictionary and int(reply.get("sequence",-1))==sequence:
			await frames(4)
			receipts.append({"sequence":sequence,"action":action,"requested":point,"actual":root.get_mouse_position(),"os":reply})
			return bool(reply.get("ok",false))
	check(false,"Native mouse driver replied to request %d"%sequence);return false
func click_control(control:Control)->bool:
	if not is_instance_valid(control):check(false,"Expected visible shop control exists");return false
	return await native_pointer(control.get_global_rect().get_center())
func named(key:String)->Control:return app.find_child(key,true,false) as Control
func text_button(label:String)->Button:
	for button:Button in app.find_children("*","Button",true,false):
		if button.visible and button.text==label:return button
	return null
func screenshot(label:String)->void:
	if u_only:return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+".png")
func locate(kind:String,point:Vector3)->Dictionary:
	for item:Dictionary in app.world.items:
		if str(item.kind)==kind and Vector2(item.node.position.x-point.x,item.node.position.z-point.z).length()<.04:return item
	return {}
func buy(kind:String,desired:Vector3,angle:float=0)->Dictionary:
	desired+=SITE_OFFSET
	app.begin_purchase_variant(kind,{"style":"drawers","color":"c97c66","size":""})
	app.world.placement_angle=angle
	# Deliberately point between grid positions; the shared preview/commit snap
	# must recover the exact modular join, including non-quarter-width fridges.
	app.world.update_ghost(desired+Vector3(.075,0,.04))
	var preview:Vector3=app.world.ghost_position
	check(preview.distance_to(desired)<.001,"%s previews at its exact U-shaped join"%kind)
	check(app.world.ghost_valid,"%s joined preview remains legal"%kind)
	var funds:int=app.household.funds
	app.on_placement(kind,preview,angle,app.world.placement_style,app.world.placement_size)
	var item:Dictionary=locate(kind,desired)
	check(not item.is_empty() and app.household.funds==funds-int(LifeCatalog.get_item(kind).price),"%s purchase commits once at its previewed position"%kind)
	if not item.is_empty():bought.append(item)
	return item
func rect_of(item:Dictionary)->Rect2:return app.world.item_panels(item,false)[0]
func joins(a:Dictionary,b:Dictionary,axis:String)->bool:
	if a.is_empty() or b.is_empty():return false
	var ar:Rect2=rect_of(a);var br:Rect2=rect_of(b)
	return is_equal_approx(ar.end.x,br.position.x) and minf(ar.end.y,br.end.y)>maxf(ar.position.y,br.position.y) if axis=="x" else is_equal_approx(ar.end.y,br.position.y) and minf(ar.end.x,br.end.x)>maxf(ar.position.x,br.position.x)
func blocked_exit_control()->void:
	# Preserve the first fixture's real refusal: its last left cabinet stood
	# on the household's front exit. Probe that complete proposal without
	# changing live furnishings, funds, navigation or the protected exit.
	var proposal:Array=app.world.serialize_items()
	var old_site:Array=[["counter",-1.5,6.0,0.0],["corner_counter",-2.425,6.0,0.0],["stove",-.45,6.0,0.0],["counter",.6,6.0,0.0],["fridge",1.575,6.0,0.0],["corner_counter",2.425,6.0,270.0],["counter",-2.425,6.925,90.0],["counter",-2.425,7.975,90.0]]
	for i:int in old_site.size():
		var row:Array=old_site[i]
		proposal.append({"id":"blocked_u_%d"%i,"kind":row[0],"x":row[1],"z":row[2],"rotation":row[3]})
	var exit_at:Vector3=app.world.lot_exit_position()
	var blocked:Rect2=app.world.furnishing_rect(proposal.back())
	var error:String=app.build_transactions.furnishing_error(proposal)
	write_json("res://evidence/blocked-original-site.json",{"lot_exit":exit_at,"last_left_counter":blocked,"error":error,"proposal":proposal})
	print("ORIGINAL_SITE exit=",exit_at," counter=",blocked," error=",error)
	check(blocked.grow(.25).has_point(Vector2(exit_at.x,exit_at.z)),"The original fixture's last left counter covers the protected lot exit")
	check(error.contains("route out of the home"),"Original-site refusal is the existing exit-protection rule, not a modular-join defect")
func run()->void:
	if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path() or (not u_only and OS.get_environment("DISPLAY")==":0"):
		push_error("Requires private data and an isolated native X display.");quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence"))
	root.size=Vector2i(960,600);DisplayServer.window_set_title("JustLife Kitchen Native Pointer Test")
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false);app.selected_lot=0;app.start_household()
	app.household.set_speed(0);app.household.set_funds(start_funds)
	app.world.camera_target=Vector3(9,.16,0);app.world.camera.size=12;app.world.update_camera()
	if not u_only:
		# Software OpenGL is only the native-input witness. These presentation
		# settings leave the UI, models, picking, placement and simulation intact.
		root.msaa_3d=Viewport.MSAA_DISABLED;root.scaling_3d_scale=.5
		app.world.sun.shadow_enabled=false
	# Fixture setup keeps this purchase-focused run bounded under software GL.
	# It is the ordinary visible search filter; the actual card/style/colour and
	# ground actions below still come exclusively from the external OS pointer.
	app.catalog_search="cabinet";await frames()
	var first_at:=Vector3(-1.5,.16,6)+SITE_OFFSET
	var first:Dictionary={}
	if not u_only:
		check(await click_control(text_button("Build & buy")),"OS mouse clicks the visible Build and buy control")
		check(app.mode=="build","Native Build click enters purchase mode")
		check(await click_control(text_button("Kitchen")),"OS mouse clicks the Kitchen category")
		check(await click_control(named("Catalog_counter")),"OS mouse clicks the cabinet catalogue card")
		check(app.overlay_open and named("VariantConfirm")!=null,"Catalogue pointer opens the actual cabinet chooser")
		check(app.overlay.find_children("VariantStyle_*","Button",true,false).size()==5 and app.overlay.find_children("VariantColor_*","Button",true,false).size()==10,"Actual chooser exposes five styles and ten colours")
		check(await click_control(named("VariantStyle_drawers")),"OS mouse chooses the drawer-stack style")
		check(await click_control(named("VariantColor_8")),"OS mouse chooses the terracotta colour swatch")
		var holder:Control=named("VariantPreview")
		var previews:Array=holder.find_children("*","TextureRect",false,false)
		check(previews.size()==1 and previews[0].position.is_equal_approx(Vector2.ZERO) and holder.get_global_rect().encloses(previews[0].get_global_rect()),"The furniture preview stays inside its intended chooser panel")
		check(previews.size()==1 and previews[0].texture.get_image().get_used_rect().has_area(),"The chooser preview contains rendered cabinet pixels")
		await screenshot("01-native-style-and-colour")
		check(await click_control(named("VariantConfirm")),"OS mouse confirms the selected cabinet")
		check(app.world.placement_kind=="counter" and app.world.placement_style=="drawers" and app.world.placement_color=="c97c66","Native choices reach the live placement preview")
		app.world.camera_target=first_at;app.world.camera.size=12;app.world.update_camera();await frames()
		var screen:Vector2=app.world.camera.unproject_position(first_at)
		check(await native_pointer(screen,"move"),"OS pointer moves the placement ghost on real ground")
		check(root.get_mouse_position().distance_to(screen)<2.0,"Actual OS pointer coordinates match the projected world point")
		check(app.world.ghost_valid and app.world.ghost_position.distance_to(first_at)<.01,"Native ground ray produces the valid intended preview")
		await screenshot("02-native-placement-preview")
		check(await native_pointer(screen),"OS mouse commits the cabinet on the ground")
		first=locate("counter",first_at)
		check(not first.is_empty() and app.household.funds==start_funds-150,"Native placement buys one cabinet at its quoted price")
		if first.is_empty():await finish();return
		check(first.variant.style=="drawers" and first.variant.color=="c97c66","The native purchase retains the chosen style and colour")
		bought.append(first)
		if pointer_only:
			app.world.clear_placement();await frames();await screenshot("03-native-purchased-cabinet")
			check(app.save_game("native_pointer_cabinet","Native cabinet purchase"),"The OS-selected cabinet saves through the public save path")
			var native_saved:Dictionary=Library.read_slot("native_pointer_cabinet")
			var native_match:bool=false
			if bool(native_saved.get("ok",false)):
				for entry:Dictionary in native_saved.data.world:
					if str(entry.get("id",""))==str(first.id):native_match=str(entry.get("style",""))=="drawers" and str(entry.get("color",""))=="c97c66" and is_equal_approx(float(entry.x),first_at.x) and is_equal_approx(float(entry.z),first_at.z)
			check(native_match,"Disk save preserves the native pointer's exact cabinet, finish and position")
			await finish();return
	else:
		app.set_build_mode(true);app.world.set_process(false)
		blocked_exit_control()
		app.begin_purchase_variant("counter",{"style":"drawers","color":"c97c66","size":""})
		app.world.update_ghost(first_at);app.on_placement("counter",first_at,0,"drawers","")
		first=locate("counter",first_at)
		check(not first.is_empty(),"Public purchase creates the first cabinet for the U")
		if first.is_empty():await finish();return
		bought.append(first)
	app.world.set_process(false)
	var left:Dictionary=buy("corner_counter",Vector3(-2.425,.16,6),0)
	var oven:Dictionary=buy("stove",Vector3(-.45,.16,6))
	var middle:Dictionary=buy("counter",Vector3(.6,.16,6))
	var fridge:Dictionary=buy("fridge",Vector3(1.575,.16,6))
	var right:Dictionary=buy("corner_counter",Vector3(2.425,.16,6),270)
	var left1:Dictionary=buy("counter",Vector3(-2.425,.16,6.925),90)
	var left2:Dictionary=buy("counter",Vector3(-2.425,.16,7.975),90)
	var right1:Dictionary=buy("counter",Vector3(2.425,.16,6.925),270)
	var right2:Dictionary=buy("counter",Vector3(2.425,.16,7.975),270)
	var back:Array=[left,first,oven,middle,fridge,right]
	for i:int in 5:check(joins(back[i],back[i+1],"x"),"Back-run join %d has zero gap, including oven and fridge"%i)
	for pair:Array in [[left,left1],[left1,left2],[right,right1],[right1,right2]]:check(joins(pair[0],pair[1],"z"),"Both U returns join their corner and next cabinet flush")
	check(bought.size()==10,"A complete U contains ten purchased units with two corner turns")
	var overlaps:bool=false
	for i:int in bought.size():
		for j:int in range(i+1,bought.size()):overlaps=overlaps or rect_of(bought[i]).grow(-.001).intersects(rect_of(bought[j]).grow(-.001))
	check(not overlaps,"No nonadjacent U units overlap")
	check(app.household.funds==start_funds-6*150-2*15-480-520,"The U charges six cabinets, two 15-Simoleon corners, oven and fridge once")
	app.world.clear_placement();app.world.camera_target=Vector3(0,.5,6.9)+SITE_OFFSET;app.world.camera.size=9;app.world.camera_angle=0;app.world.camera_elevation=1.05;app.world.update_camera()
	await frames();await screenshot("03-complete-u-kitchen")
	check(app.save_game("native_u_kitchen","Native kitchen U"),"The completed U and native finish choices save through the public save path")
	var saved:Dictionary=Library.read_slot("native_u_kitchen")
	check(bool(saved.get("ok",false)),"Saved U passes the ordinary household validator")
	if bool(saved.get("ok",false)):
		var match_count:int=0
		for item:Dictionary in bought:
			for entry:Dictionary in saved.data.world:
				if str(entry.get("id",""))==str(item.id) and is_equal_approx(float(entry.x),item.node.position.x) and is_equal_approx(float(entry.z),item.node.position.z):
					if str(item.kind)!="counter" or (str(entry.get("style",""))=="drawers" and str(entry.get("color",""))=="c97c66"):match_count+=1
		check(match_count==10,"Disk save preserves all ten exact joined positions and selected cabinet finishes")
	await finish()
func finish()->void:
	write_json("res://evidence/u-only-result.json" if u_only else "res://evidence/result.json",{"checks":checks,"failures":failures,"native_receipts":receipts,"units":app.world.serialize_items() if is_instance_valid(app) else [],"scope":"Headless public-handler U-layout and disk-save qualification; no native-input evidence." if u_only else ("Native XTest OS pointer for Build, Kitchen, cabinet, style, colour, confirm and ground placement, followed by public disk-save verification." if pointer_only else "Native XTest OS pointer for Build, Kitchen, cabinet, style, colour, confirm and initial ground placement; remaining U units use public preview/purchase handlers with exact edge and saved-state assertions.")})
	if is_instance_valid(app):app.queue_free();await frames()
	print("KITCHEN_U_NATIVE %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
