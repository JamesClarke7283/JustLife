extends SceneTree
## Matched material-only variants of the untouched public two-floor checkpoint.
## Requires its recorded original_public_slot.json in the copied evidence folder.
const MainScene=preload("res://scenes/main.tscn")
var app:Node
var checks:int=0
var failures:Array[String]=[]
var captures:Array=[]

func _initialize()->void:
	var path:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if OS.get_environment("XDG_DATA_HOME")!=path.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=path.path_join("userdata/save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Wood captures require a copied project and private userdata/save_data.");quit(2);return
	_run.call_deferred()

func check(ok:bool,label:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)

func frames(count:int=3)->void:
	for index:int in count:await process_frame

func capture(label:String,size:float)->void:
	app.world.camera.size=size
	app.world.camera_target=Vector3(-1,3.16,0)
	app.world.update_camera();await frames(4);await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image.get_size()==Vector2i(1440,900) and image.save_png("user://wood_"+label+".png")==OK,"Actual 1440x900 viewport capture: "+label)
	captures.append({"label":label,"camera":app.world.camera.transform,"size":size,"structure":app.world.construction.snapshot(),"floor_nodes":app.world.construction.floor_nodes.size()})

func _run()->void:
	root.size=Vector2i(1440,900)
	var original_bytes:PackedByteArray=FileAccess.get_file_as_bytes("res://evidence/original_public_slot.json")
	var original:Dictionary=JSON.parse_string(original_bytes.get_string_from_utf8())
	var slot:String=str(original.metadata.id)
	var path:String=OS.get_environment("JUSTLIFE_DATA_DIR").path_join("saves")
	DirAccess.make_dir_recursive_absolute(path)
	var file:=FileAccess.open(path.path_join(slot+".json"),FileAccess.WRITE);file.store_buffer(original_bytes);file.close()
	app=MainScene.instantiate();root.add_child(app);current_scene=app
	app.set_process(false);app.set_sound(false);await frames(4)
	app.load_game(slot);app.set_process(false);await frames(4)
	check(app.mode=="live" and app.world.point_level(app.player.position)==1,"Actual untouched public checkpoint restores the upstairs Lifelet.")
	var structure:Dictionary=app.world.construction.snapshot()
	var actors:Dictionary={}
	for id:String in app.world.actors:actors[id]=app.world.actors[id].transform
	var queue:Array=app.sim.action_queue.duplicate(true)
	var funds:int=app.household.funds;var minutes:float=app.household.minutes
	for sample:Dictionary in [{"label":"oak","color":"cfa97e"},{"label":"walnut","color":"896953"},{"label":"stone","color":"dcd6c6"}]:
		var state:Dictionary=structure.duplicate(true)
		for floor:Dictionary in state.floors:
			if int(floor.level)==1:floor.material=sample.color
		app.world.construction.restore(state);app.world.set_view_level(1);app.draw_live();await frames(3)
		await capture(str(sample.label)+"_wide",19.0)
		if sample.label!="stone":await capture(str(sample.label)+"_close",9.0)
		check(app.world.construction.snapshot()==state,"Only the declared upper finish variant changes: "+str(sample.label))
	check(app.household.funds==funds and app.household.minutes==minutes and app.sim.action_queue==queue,"Material captures preserve funds, paused time and the saved reading instruction.")
	check(app.world.actors.keys().all(func(id:String):return app.world.actors[id].transform==actors[id]),"Material changes move no Lifelet root.")
	check(FileAccess.get_file_as_bytes(path.path_join(slot+".json"))==original_bytes,"Original public save bytes remain unchanged.")
	FileAccess.open("user://wood_floor_capture.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"scope":"Actual named public checkpoint; only upper finish changes for Walnut/stone samples and camera framing. No actions, actors, money, needs or time are injected."},"  ",true,true))
	app.queue_free();await frames(5);await create_timer(.2).timeout
	print("WOOD_CAPTURE checks=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
