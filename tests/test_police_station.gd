extends SceneTree
## Lightweight app shell uses the real station scene, navigation, picking,
## reception UI and service dispatcher without the startup/save-library screens.
class StationApp extends "res://scripts/main.gd":
	var opened_service:String=""
	var observed_notices:Array[String]=[]
	func _ready() -> void:pass
	func _process(_delta:float) -> void:pass
	func _begin_pause_overlay() -> void:
		for child:Node in overlay.get_children():child.free()
		overlay_open=true
	func close_overlay(_restore_speed:bool=true) -> void:
		for child:Node in overlay.get_children():child.free()
		overlay_open=false
	func play_click() -> void:pass
	func show_notice(message:String) -> void:observed_notices.append(message)
	func show_careers() -> void:opened_service="careers"
	func show_career_record() -> void:opened_service="shift"
	func _refresh_sim_targets(_replan:bool=true,_reconcile_food:bool=true) -> void:pass

var app:StationApp
var checks:int=0
var failures:Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok:bool,detail:String) -> void:
	checks+=1
	if not ok:failures.append(detail);push_error(detail)
func frames(count:int=2) -> void:
	for i:int in count:await process_frame
func cell(at:Vector3) -> Vector2i:return Vector2i(roundi(at.x*4.0),roundi(at.z*4.0))
func capture(path:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path)==OK,"Station screenshot saved: "+path)
func run() -> void:
	app=StationApp.new();root.add_child(app);current_scene=app
	app.ui=Control.new();app.ui.size=Vector2(1440,900);app.add_child(app.ui)
	app.overlay=Control.new();app.overlay.size=Vector2(1440,900);app.add_child(app.overlay)
	app.ui.theme=preload("res://scripts/palette.gd").theme();app.overlay.theme=app.ui.theme
	app.household=LifeHousehold.new();app.add_child(app.household)
	app.household.new_household([{"name":"Station visitor","age_stage":"young_adult"}]);app.sim=app.household.selected();app.household.set_speed(0)
	app.world=LifeWorld.new();app.add_child(app.world);await frames()
	app.current_venue="police_station";app.mode="live";app.sound_enabled=false
	app.world.create_public_venue("police_station",preload("res://scripts/venues.gd").layout("police_station"))
	app.world.live_enabled=true
	app.world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL;app.world.camera.size=14.0
	app.world.camera_target=Vector3(0.4,.6,-.5);app.world.camera_angle=.25;app.world.camera_elevation=.85;app.world.update_camera()
	app.safety=LifeSafety.new(app);app.add_child(app.safety);app.safety.enter_world();await frames(3)
	var station:Node3D=app.world.house.get_node_or_null("PoliceStationCustody")
	check(is_instance_valid(station) and station.get_node_or_null("ReceptionDesk")!=null,"Public station includes real reception furniture")
	check(station.get_node_or_null("JailDoor")!=null and is_zero_approx(station.get_node("JailDoor").rotation.y),"Custody room has a closed physical barred door")
	var blockers:Array=app.world.extra_obstacles.filter(func(b:Dictionary)->bool:return str(b.get("id","")).begins_with("police_station_"))
	check(blockers.size()==4,"Cell, reception, back wall and side wall enter the actual navigation graph")
	check(app.world.navigation.is_point_solid(cell(Vector3(3.65,.16,-1))),"A visitor cannot walk into the closed custody cell")
	check(app.world.navigation.is_point_solid(cell(Vector3(.4,.16,.1))),"Reception desk footprint blocks walking through it")
	var approach:Vector3=Vector3(.4,.16,1.3)
	check(not app.world.navigation.is_point_solid(cell(approach)),"Public reception approach remains walkable")
	check(not app.world.path_to(Vector3(0,.16,4.0),approach).is_empty(),"Visitors have an actual route from the entrance to reception")
	check(app.world.pick_extras.has("police_reception"),"Reception is registered as a clickable venue object")
	var reception:Dictionary=app.world.pick_extras.get("police_reception",{})
	check(str(reception.get("kind",""))=="police_station" and reception.node.get_meta("item_id","")=="police_reception","Physical picking identity points to police services")
	app.world.object_clicked.connect(app.on_object_clicked)
	var clicks:Array=[]
	app.world.object_clicked.connect(func(item:Dictionary,_screen:Vector2):clicks.append(str(item.id)))
	var point:Vector3=reception.node.global_position+Vector3(0,.48,.1)
	var ray:=PhysicsRayQueryParameters3D.create(point+Vector3(0,3,0),point-Vector3(0,1,0),LifeWorld.PICK_GROUND)
	var hit:Dictionary=app.world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider.get_meta("item_id","")=="police_reception","Real physics ray hits the reception collider")
	app.world.pick(app.world.camera.unproject_position(point));await frames()
	check(clicks.has("police_reception"),"Screen-space click reaches reception through LifeWorld.pick")
	for id:String in ["police_careers","police_shift","custody_record"]:
		check(app.overlay.get_node_or_null("Service_"+id)!=null,"Clicked reception exposes public service "+id)
	var panels:Array=app.overlay.get_children().filter(func(n:Node)->bool:return n is Panel)
	var back_buttons:Array=app.overlay.get_children().filter(func(n:Node)->bool:return n is Button and n.text=="Back to life")
	check(panels.size()==1 and back_buttons.size()==1 and panels[0].get_rect().encloses(back_buttons[0].get_rect()),"Venue service card contains its return button")
	await capture("/tmp/justlife-police-station-services.png")
	var careers:Button=app.overlay.get_node_or_null("Service_police_careers")
	if careers!=null:careers.pressed.emit()
	check(app.opened_service=="careers","Reception's career button dispatches to career selection")
	var shift:Button=app.overlay.get_node_or_null("Service_police_shift")
	if shift!=null:shift.pressed.emit()
	check(app.opened_service=="shift","Reception's shift button dispatches to the shift panel")
	var custody:Button=app.overlay.get_node_or_null("Service_custody_record")
	if custody!=null:custody.pressed.emit()
	check(app.observed_notices.any(func(n:String)->bool:return n.begins_with("Custody record:")),"Reception's custody button reports the case")
	app.close_overlay()
	await capture("/tmp/justlife-police-station.png")
	# Closed cases are carried into the public station when visiting after arrest.
	var saved:Dictionary=app.safety.snapshot()
	saved.crime.phase="jailed";saved.crime.called=true;saved.crime.recovered=true;saved.crime.jailed_day=1
	saved.crime.burglary_phase="waiting";saved.crime.history=["jailed"]
	check(LifeSafety.validate(saved).is_empty(),"Completed custody record is valid before visiting the station")
	app.world.create_public_venue("police_station",preload("res://scripts/venues.gd").layout("police_station"));await frames()
	app.safety.enter_world(saved);await frames()
	station=app.world.house.get_node_or_null("PoliceStationCustody")
	check(station.find_child("Burglar",true,false)!=null,"Visiting after an arrest presents the detained burglar inside the public cell")
	check(app.world.extra_obstacles.filter(func(b:Dictionary)->bool:return str(b.get("id","")).begins_with("police_station_")).size()==4,"Reloading the public station does not multiply navigation blockers")
	app._use_venue_service("police_station","custody_record")
	check(app.observed_notices.back().contains("jailed"),"Custody desk reflects the restored arrest state")
	await capture("/tmp/justlife-police-station-occupied.png")
	# A subsequent venue has none of the station's special blockers or pick ids.
	app.current_venue="cafe";app.world.create_public_venue("cafe",[]);await frames()
	app.safety.enter_world();await frames()
	check(not app.world.pick_extras.has("police_reception"),"Leaving the station removes its reception pick target")
	check(app.world.extra_obstacles.all(func(b:Dictionary)->bool:return not str(b.get("id","")).begins_with("police_station_")),"Leaving the station removes custody navigation blockers")
	app.queue_free();await frames()
	print("POLICE_STATION %d checks, %d failures: %s"%[checks,failures.size(),str(failures)])
	quit(0 if failures.is_empty() else 1)
