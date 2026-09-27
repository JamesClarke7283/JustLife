extends Node
class_name LifeSafety
## Bridges the physical police response, shared purse, phone, and saved policy dates.
const P=preload("res://scripts/palette.gd")
var app:Node
var crime:Node3D
var legacy_next_payment:int=0
var seen_day:int=-1
var alert:Panel
var alert_text:Label
var alert_button:Button
var bound_household:LifeHousehold

func _init(owner:Node) -> void:
	app=owner

func enter_world(saved:Dictionary={}) -> void:
	var carried:Dictionary=snapshot() if is_instance_valid(crime) and bound_household==app.household else {}
	if not saved.is_empty():carried=saved
	if is_instance_valid(crime):crime.free()
	crime=load("res://scripts/crime_response.gd").new()
	app.world.add_child(crime)
	crime.setup(app.world,app.household)
	crime.notice.connect(app.show_notice)
	crime.layout_changed.connect(_layout_changed)
	crime.changed.connect(_refresh_alert)
	legacy_next_payment=int(carried.get("legacy_next_payment",0))
	if carried.get("crime") is Dictionary:
		var restored:Dictionary=crime.restore(carried.crime)
		if not bool(restored.ok):app.show_notice(str(restored.error))
	crime.set_sound(app.sound_enabled)
	crime.set_home_visible(app.current_venue=="home")
	_present_station()
	if bound_household!=app.household:
		bound_household=app.household
		bound_household.burglary_due.connect(_night)
		bound_household.insurance_changed.connect(_insurance_changed)
	seen_day=-1
	_connect_members()
	_refresh_alert()

func _connect_members() -> void:
	for member:Dictionary in app.household.members:
		var person:LifeSim=member.sim
		if not person.robbery_requested.is_connected(_requested):person.robbery_requested.connect(_requested)

func _requested() -> void:
	if app.current_venue=="home" and is_instance_valid(crime):crime.begin_break_in()

func _night(day:int) -> void:
	if app.current_venue=="home" and is_instance_valid(crime):crime.consider_night(day)


func tick(delta:float) -> void:
	if not is_instance_valid(crime):return
	_connect_members()
	crime.set_sound(app.sound_enabled and app.household.speed>0 and app.mode=="live")
	if app.mode=="live" and app.household.speed>0:
		if seen_day!=app.household.day:
			seen_day=app.household.day
			_collect_insurance()
		if app.current_venue=="home":crime.tick(delta*minf(float(app.household.speed),3.0),delta*LifeSim.GAME_MINUTES_PER_SECOND*float(app.household.speed))
	_refresh_alert()

func snapshot() -> Dictionary:
	return {"version":1,"crime":crime.snapshot() if is_instance_valid(crime) else {},"legacy_next_payment":legacy_next_payment}

func call_police() -> void:
	if app.current_venue!="home":app.show_notice("Return home to report this burglary.");return
	app.close_overlay()
	var answer:Dictionary=crime.call_police(app.household.selected_id())
	if not bool(answer.get("ok",false)):app.show_notice(str(answer.get("error",answer.get("reason","The police could not be called."))))
	_refresh_alert()

func _layout_changed() -> void:
	if app.current_venue=="home":app.home_layout=app.world.serialize_items()
	app._refresh_sim_targets(false)

func _refresh_alert() -> void:
	if not is_instance_valid(app.ui) or not is_instance_valid(crime):return
	var active:bool=app.mode=="live" and app.current_venue=="home" and crime.phase not in ["idle","jailed"]
	if not active:
		if is_instance_valid(alert):alert.queue_free()
		alert=null;return
	if not is_instance_valid(alert):
		alert=app.card(Vector2(430,126),Vector2(620,92),P.WHITE,15)
		alert.name="BurglarAlert"
		alert_text=app.text_label("",Vector2(14,10),Vector2(378,70),16,P.INK,true,alert)
		alert_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		alert_button=app.button("Call the police",Vector2(408,26),Vector2(198,40),call_police,true,alert)
		alert_button.name="CallPoliceAlert"
	alert_text.text="Burglar alert · "+str(crime.phase).replace("_"," ").capitalize()+". Use a phone or call here."

func _insurance_changed(policy:String) -> void:
	if policy in ["home","premium"]:
		if LifeProperties.active(app.properties).is_empty():legacy_next_payment=app.household.day+7
		install_alarm()
	else:legacy_next_payment=0

func policy_bought(policy:String) -> void:
	if policy in ["home","premium"]:install_alarm()

func install_alarm() -> void:
	if app.current_venue!="home" or not is_instance_valid(app.world.house):return
	if not app.world.closest_item("burglar_alarm",Vector3.ZERO).is_empty():return
	var snapped:Dictionary={}
	# Follow the actual building walls, including custom homes and expansions.
	for wall:Dictionary in app.world.construction.records:
		if int(wall.get("level",0))!=0:continue
		if not wall.has("w") or not wall.has("d"):continue
		var center:=Vector3(float(wall.x),.16,float(wall.z))
		var inward:Vector3=(Vector3.ZERO-center).normalized()*.25
		snapped=app.world.wall_snap("burglar_alarm",center+inward,1.0)
		if not snapped.is_empty():break
	var at:Vector3=snapped.get("position",Vector3(-1.8,.16,4.85))
	app.world.add_item({"id":"insurance_alarm_%d" % Time.get_ticks_usec(),"kind":"burglar_alarm","x":at.x,"z":at.z,"rotation":float(snapped.get("angle",180.0)),"level":0,"hang":1.45})
	_layout_changed()
	app.show_notice("Home insurance includes a wall alarm. Next payment: ℒ200 on day %d." % next_payment_day())

func next_payment_day() -> int:
	var id:String=LifeProperties.active(app.properties)
	return int(LifeProperties.house(app.properties,id).get("next_insurance_day",app.household.day+7)) if not id.is_empty() else legacy_next_payment

func _collect_insurance() -> void:
	var billed:Dictionary=LifeProperties.collect_premiums(app.properties,app.household.day,app.household.funds)
	app.properties=billed.state
	if int(billed.charged)>0:
		app.household.set_funds(int(billed.funds))
		app.show_notice("Scheduled insurance payment · ℒ%d paid on day %d." % [int(billed.charged),app.household.day])
	for title:String in billed.unpaid:app.show_notice("Insurance payment missed for %s: ℒ200 was due today." % title)
	if not LifeProperties.active(app.properties).is_empty() or app.household.insurance().is_empty():return
	if legacy_next_payment==0:legacy_next_payment=app.household.day+7
	if app.household.day==legacy_next_payment:
		if app.household.funds>=200:
			app.household.set_funds(app.household.funds-200)
			app.show_notice("Scheduled insurance payment · ℒ200 paid today.")
		else:app.show_notice("Insurance payment missed: ℒ200 was due today.")
	if app.household.day>=legacy_next_payment:
		while legacy_next_payment<=app.household.day:legacy_next_payment+=7


func _exit_tree() -> void:
	if is_instance_valid(crime):crime.queue_free()


static func validate(value:Variant) -> String:
	if value==null:return ""
	if not value is Dictionary:return "Save contains invalid household safety state."
	if int(value.get("version",0))!=1:return "Save contains an unsupported household safety version."
	if not LifeBuildingState.number(value.get("legacy_next_payment",0),0,1000007,true):return "Save contains an invalid insurance payment day."
	if not value.get("crime",{}) is Dictionary:return "Save contains an invalid police case."
	return preload("res://scripts/crime_response.gd").validate_snapshot(value.get("crime",{}))


func unresolved() -> bool:
	return is_instance_valid(crime) and crime.phase not in ["idle","jailed"]


func _present_station() -> void:
	var remaining:Array=app.world.extra_obstacles.filter(func(entry:Dictionary)->bool:return not str(entry.get("id","")).begins_with("police_station_"))
	var changed_obstacles:bool=remaining.size()!=app.world.extra_obstacles.size()
	app.world.pick_extras.erase("police_reception")
	if app.current_venue=="police_station":
		var origin:=Vector3(2,0,-1)
		var building:Node3D=crime.decorate_station(app.world.house,origin,crime.phase=="jailed")
		var bands:Array=[
			{"id":"police_station_cell","x":1.68,"z":-.6,"w":2.8,"d":3.85},
			{"id":"police_station_desk","x":-1.6,"z":1.1,"w":2.0,"d":.68},
			{"id":"police_station_back","x":0.0,"z":-2.5,"w":6.0,"d":.18},
			{"id":"police_station_side","x":-3.0,"z":0.0,"w":.18,"d":5.0}]
		for band:Dictionary in bands:
			band.x=float(band.x)+origin.x;band.z=float(band.z)+origin.z;band["level"]=0
			remaining.append(band)
		var body:=StaticBody3D.new();body.collision_layer=LifeWorld.PICK_GROUND;body.set_meta("item_id","police_reception")
		building.add_child(body);body.position=Vector3(-1.6,.68,1.1)
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,1.05,.68);shape.shape=box;body.add_child(shape)
		app.world.pick_extras["police_reception"]={"id":"police_reception","kind":"police_station","label":"Police reception","node":body,"size":Vector2(2,.68)}
		changed_obstacles=true
	app.world.extra_obstacles=remaining
	if changed_obstacles:app.world.rebuild_navigation()
