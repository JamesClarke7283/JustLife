extends SceneTree
## Run rendered in a sanitized justlife-camera-* copy with private userdata/save_data.

var app: Node
var checks: int = 0
var failures: Array[String] = []
var world_clicks: int = 0

func _initialize() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("Camera projection checks require a rendered viewport.")
		quit(2);return
	var source:String=ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not source.get_file().begins_with("justlife-camera-") or OS.get_environment("XDG_DATA_HOME")!=source.path_join("userdata") or OS.get_environment("JUSTLIFE_DATA_DIR")!=source.path_join("save_data") or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
		printerr("Camera checks require an isolated project and private save folder.")
		quit(2);return
	_run.call_deferred()

func frames(count:int=3) -> void:
	for i:int in range(count):await process_frame

func check(condition:bool,detail:String) -> void:
	checks+=1
	print("CHECK ","PASS " if condition else "FAIL ",detail)
	if not condition:failures.append(detail)

func pointer_button(at:Vector2,button:int,down:bool,shift:bool=false) -> void:
	var event:=InputEventMouseButton.new()
	event.position=at;event.global_position=at
	event.button_index=button;event.pressed=down;event.shift_pressed=shift
	event.button_mask=(1 << (button-1)) if down else 0
	Input.parse_input_event(event)
	await frames()

func pointer_motion(at:Vector2,delta:Vector2,mask:int,shift:bool=false) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=at;event.global_position=at;event.relative=delta
	event.button_mask=mask;event.shift_pressed=shift
	Input.parse_input_event(event)
	await frames()

func drag_case(button:int,shift:bool) -> void:
	var start:=Vector2(720,420)
	var delta:=Vector2(85,-34)
	app.world.camera_target=Vector3(0,0,0);app.world.update_camera()
	var camera:Camera3D=app.world.camera
	var plane:=Plane(Vector3.UP,0)
	var point:Vector3=plane.intersects_ray(camera.project_ray_origin(start),camera.project_ray_normal(start))
	var angle:float=app.world.camera_angle
	var elevation:float=app.world.camera_elevation
	var state:Dictionary=app.household.get_state(app.world.serialize_items())
	var actor_position:Vector3=app.player.position
	var count_before:int=world_clicks
	await pointer_button(start,button,true,shift)
	await pointer_motion(start+delta,delta,1 << (button-1),shift)
	check(camera.unproject_position(point).distance_to(start+delta)<.01,"Grabbed ground point follows the pointer")
	check(app.world.camera_angle==angle and app.world.camera_elevation==elevation and app.world.camera_target.y==0,"Panning retains orbit, tilt and floor height")
	# Releasing over a consuming HUD card must end the world gesture.
	await pointer_button(Vector2(90,40),button,false,shift)
	var released:Vector3=app.world.camera_target
	await pointer_motion(Vector2(100,40),Vector2(10,0),0)
	check(app.world.camera_target==released,"Release over HUD ends camera movement")
	check(world_clicks==count_before and app.household.get_state(app.world.serialize_items())==state and app.player.position==actor_position,"Panning does not pick, place, charge, move a Lifelet or change their queue")

func _run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false);app.start_household();app.household.set_speed(0)
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.world.ground_clicked.connect(func(_point:Vector3):world_clicks+=1)
	app.world.object_clicked.connect(func(_item:Dictionary,_point:Vector2):world_clicks+=1)
	app.world.placement_requested.connect(func(_kind:String,_point:Vector3,_angle:float):world_clicks+=1)
	await frames()
	for build:bool in [false,true]:
		app.set_build_mode(build);await frames()
		for zoom:float in [9.0,24.0]:
			app.world.camera.size=zoom
			app.world.camera_angle=.25 if zoom==9.0 else 1.55
			await drag_case(MOUSE_BUTTON_LEFT,true)
			await drag_case(MOUSE_BUTTON_RIGHT,true)
			await drag_case(MOUSE_BUTTON_MIDDLE,false)
	app.set_build_mode(false);await frames()
	var at:=Vector2(720,420)
	var old_angle:float=app.world.camera_angle
	await pointer_button(at,MOUSE_BUTTON_RIGHT,true)
	await pointer_motion(at+Vector2(30,0),Vector2(30,0),MOUSE_BUTTON_MASK_RIGHT)
	await pointer_button(at,MOUSE_BUTTON_RIGHT,false)
	check(app.world.camera_angle!=old_angle,"Unmodified right-drag still orbits")
	var before:Vector3=app.world.camera_target
	await pointer_button(Vector2(90,40),MOUSE_BUTTON_LEFT,true,true)
	await pointer_motion(at,Vector2(20,0),MOUSE_BUTTON_MASK_LEFT,true)
	await pointer_button(at,MOUSE_BUTTON_LEFT,false,true)
	check(app.world.camera_target==before,"A drag beginning on the HUD cannot pan the world")
	await pointer_button(at,MOUSE_BUTTON_LEFT,true,true)
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await pointer_motion(at+Vector2(25,0),Vector2(25,0),MOUSE_BUTTON_MASK_LEFT,true)
	await pointer_button(at,MOUSE_BUTTON_LEFT,false,true)
	check(app.world.camera_target==before,"Losing window focus clears the drag")
	await pointer_button(at,MOUSE_BUTTON_LEFT,true,true)
	app.show_menu();await frames()
	await pointer_motion(at+Vector2(25,0),Vector2(25,0),MOUSE_BUTTON_MASK_LEFT,true)
	await pointer_button(at,MOUSE_BUTTON_LEFT,false,true)
	check(app.world.camera_target==before,"Opening a modal ends the drag")
	app.close_overlay();await frames()
	app.world.camera_target=Vector3(15.9,0,11.9);app.world.update_camera()
	await pointer_button(at,MOUSE_BUTTON_LEFT,true,true)
	await pointer_motion(at+Vector2(-5000,5000),Vector2(-5000,5000),MOUSE_BUTTON_MASK_LEFT,true)
	await pointer_button(at,MOUSE_BUTTON_LEFT,false,true)
	check(absf(app.world.camera_target.x)<=16 and absf(app.world.camera_target.z)<=12,"Panning respects the existing lot camera bounds")
	app.queue_free();await frames(5)
	print("CAMERA_CONTROLS_RESULT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
