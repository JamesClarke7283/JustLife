extends SceneTree
## Public panel callbacks and same-frame saves. Both storage roots must be private.
const MainScene=preload("res://scenes/main.tscn")
var app:Node
var checks:int=0
var failures:Array[String]=[]
var comparisons:Array=[]
var direct_id:String=""
var picker_id:String=""
var live_preview:Image
var captures:bool=false
var state_comparisons:Array=[]

func _initialize() -> void:run.call_deferred()

func check(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)

func press(value:String) -> void:
	for node:Node in app.find_children("*","Button",true,false):
		if node.text==value and node.is_visible_in_tree() and not node.disabled:node.pressed.emit();return
	check(false,"Missing enabled public button: "+value)

func frames(count:int=3) -> void:
	for index:int in range(count):await process_frame
	if captures:await RenderingServer.frame_post_draw

func capture(name:String) -> void:
	if captures:check(root.get_texture().get_image().save_png("user://preview_captures/"+name+".png")==OK,"Captured "+name)

func crop() -> Image:
	var source:Image=root.get_texture().get_image()
	var size:Vector2i=source.get_size()
	var image:Image=source.get_region(Rect2i(int(size.x*.21),int(size.y*.22),int(size.x*.61),int(size.y*.49)))
	image.resize(640,380,Image.INTERPOLATE_LANCZOS)
	return image

func saved_preview(id:String) -> Image:
	for slot:Dictionary in LifeSaveLibrary.list_saves():
		if str(slot.id)==id and not str(slot.preview_path).is_empty():return Image.load_from_file(str(slot.preview_path))
	return null

func compare_preview(id:String,label:String) -> void:
	if not captures:return
	var actual:Image=saved_preview(id)
	check(actual!=null and not actual.is_empty(),label+": named PNG exists synchronously.")
	if actual==null or actual.is_empty():return
	actual.convert(Image.FORMAT_RGB8)
	var expected:Image=live_preview.duplicate();expected.convert(Image.FORMAT_RGB8)
	check(actual.get_size()==expected.get_size(),label+": preview has the expected crop dimensions.")
	var a:PackedByteArray=actual.get_data();var b:PackedByteArray=expected.get_data()
	var error:float=0.0
	for index:int in range(mini(a.size(),b.size())):error+=absf(float(a[index])-float(b[index]))
	error/=255.0*float(maxi(1,a.size()))
	comparisons.append({"case":label,"mean_absolute_channel_error":error,"limit":.003})
	check(error<.003,label+": PNG depicts the current Live scene, not the drawn review panel (mean error %.6f)." % error)
	actual.save_png("user://preview_captures/"+label+"_saved.png")

func facts() -> Dictionary:
	var members:Array=[]
	for member:Dictionary in app.household.members:
		var actor:LifeActor=app.world.actors[member.id]
		members.append({"id":member.id,"character":member.sim.character.duplicate(true),"needs":member.sim.needs.duplicate(true),"queue":member.sim.action_queue.duplicate(true),"position":actor.position,"rotation":actor.rotation,"speed":member.sim.speed})
		members[-1].character.erase("world_state") # The ordinary save computes this existing serialization field.
	return {"members":members,"funds":app.household.funds,"minutes":app.household.minutes,"day":app.household.day,"meals":app.household.meals.get_state(),"items":app.world.serialize_items(),"family":app.household.family_graph.duplicate(true),"adoptions":app.household.adoptions.duplicate(true)}

func same_facts(before:Dictionary,label:String) -> bool:
	var current:Dictionary=facts()
	state_comparisons.append({"label":label,"equal":before==current,"before":app.household.json_safe(before),"after":app.household.json_safe(current)})
	return before==current

func review_then_cancel() -> void:
	press("Phone");press("Adopt a child");press("Meet Wren")
	check(is_instance_valid(app.find_child("AdoptionConfirm",true,false)),"Actual adoption review is open before the stale-frame reproduction.")
	await frames()
	capture("02_adoption_review")
	# Deliberately no await/draw between these public callbacks and the caller's save.
	press("Cancel adoption");press("Back to phone");press("Back to life")

func run() -> void:
	var data:String=OS.get_environment("XDG_DATA_HOME")
	var saves:String=OS.get_environment("JUSTLIFE_DATA_DIR")
	if OS.get_name()!="Linux" or not data.is_absolute_path() or not saves.is_absolute_path() or not data.get_file().begins_with("save-preview-") or saves!=data.path_join("save_data"):
		printerr("Save-preview tests require isolated save-preview-* XDG_DATA_HOME with its save_data child.");quit(2);return
	captures=DisplayServer.get_name()!="headless"
	DirAccess.make_dir_recursive_absolute("user://preview_captures")
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	app.set_process(false);app.set_sound(false)
	await frames()
	check(LifeSaveLibrary.list_saves().is_empty(),"No real player saves are present in this isolated run.")
	press("New game");press("+ Add Lifelet");press("Find my home  →");press("Start living  →")
	app.set_game_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	# Settle the ordinary shared pause before freezing the fixture; set_game_speed
	# changes the selected sim first, then the normal household tick synchronizes it.
	app._process(0.0)
	await frames(6)
	check(app.mode=="live" and app.household.members.size()==2,"Public creator starts a two-adult household.")
	if captures:live_preview=crop();live_preview.save_png("user://preview_captures/01_expected_live_crop.png")
	capture("01_live_household")
	var before:Dictionary=facts()
	await review_then_cancel()
	var frame_before:int=Engine.get_process_frames()
	check(app.save_game("","Immediate after cancellation"),"Same-frame direct save returns its final success synchronously.")
	direct_id=app.active_save_id
	check(Engine.get_process_frames()==frame_before,"Same-frame save does not yield through another process tick.")
	check(same_facts(before,"direct"),"Review cancellation and direct save preserve household, actions, money, clock and body transforms.")
	check(bool(LifeSaveLibrary.read_slot(direct_id).ok),"The complete household is readable immediately after saving.")
	compare_preview(direct_id,"03_direct")
	await frames();capture("04_returned_live")
	# Reproduce the packaged public save-picker path, including no frame gap
	# between closing the drawn review and opening the pause/save panels.
	await review_then_cancel()
	frame_before=Engine.get_process_frames()
	app.show_menu();press("Save this life")
	app.menus.name_input.text="Public picker after cancellation"
	press("Save as new")
	picker_id=app.active_save_id
	check(picker_id!=direct_id and LifeSaveLibrary.list_saves().size()==2,"Public save-as-new creates a distinct slot in the same frame.")
	check(not app.overlay_open and app.sim.speed==0,"Public saving closes its picker and preserves the original pause.")
	check(Engine.get_process_frames()==frame_before and same_facts(before,"picker"),"Public panel save introduces no wait, simulation advance or ownership change.")
	compare_preview(picker_id,"05_picker")
	# A normal rendered picker must retain its clean Live capture while confirming
	# overwrite; it must not replace that capture with its own UI.
	app.show_menu();press("Save this life")
	for node:Node in app.find_children("*","Button",true,false):
		if str(node.get_meta("save_id",""))==picker_id and node.is_visible_in_tree():node.pressed.emit();break
	await frames()
	app.menus.name_input.text="Confirmed overwrite"
	press("Overwrite…");await frames();press("Replace save")
	check(app.active_save_id==picker_id and LifeSaveLibrary.list_saves().size()==2,"Confirmed overwrite updates the selected slot without creating a duplicate.")
	check(str(LifeSaveLibrary.read_slot(picker_id).name)=="Confirmed overwrite","Overwrite writes its chosen name synchronously.")
	compare_preview(picker_id,"06_overwrite")
	check(same_facts(before,"overwrite"),"Normal overwrite preserves the exact paused household and food ownership.")
	# No pending async thumbnail can recreate a deleted companion or replace a
	# later save: deletion and a new slot finish before the next process frame.
	var removed_path:String=""
	for slot:Dictionary in LifeSaveLibrary.list_saves():
		if str(slot.id)==picker_id:removed_path=str(slot.preview_path)
	check(bool(LifeSaveLibrary.delete_slot(picker_id).ok),"The just-written slot deletes immediately.")
	app.active_save_id="";app.active_save_name=""
	check(app.save_game("","Subsequent life"),"A subsequent save completes synchronously after deletion.")
	var subsequent:String=app.active_save_id
	await frames(4)
	check(not FileAccess.file_exists(removed_path) and not bool(LifeSaveLibrary.read_slot(picker_id).ok),"No delayed preview or save recreates the deleted slot.")
	check(subsequent!=picker_id and bool(LifeSaveLibrary.read_slot(subsequent).ok),"The later save remains independently valid.")
	compare_preview(subsequent,"07_subsequent")
	app.menus.show_picker("load",subsequent);await frames();capture("08_final_picker")
	var report:Dictionary={"checks":checks,"failures":failures,"comparisons":comparisons,"state_comparisons":state_comparisons,"rendered":captures,"viewport":root.size,"same_frame_public_callbacks":true,"source_main_sha256":FileAccess.get_sha256("res://scripts/main.gd")}
	var file:FileAccess=FileAccess.open("user://preview_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	app.queue_free();await frames(4)
	print("Save preview: %d checks, %d failures." % [checks,failures.size()]);quit(0 if failures.is_empty() else 1)
