extends RefCounted
class_name LifeResidents
## Stable residents own homes; only actors physically present can be approached.
const PEOPLE={
 "maya":{"name":"Maya Chen","home":"maya_home","frame":0,"hair":2,"skin_color":"b77e58","hair_color":"2a2420","top_color":"417a71","bottom_color":"eadfc9"},
 "leo":{"name":"Leo Morgan","home":"leo_home","frame":1,"hair":0,"skin_color":"e7b98f","hair_color":"89563a","top_color":"7195b3","bottom_color":"493e37"}}
var app:Node
var locations:Dictionary={}
var active_place:String=""
var trip:Dictionary={}
var car:Node3D

func _init(controller:Node) -> void:app=controller

func reset() -> void:
 locations.clear();active_place="";trip.clear()

func _default_state(id:String,place:String) -> Dictionary:
 var at:Vector3=Vector3(-8.25,.16,8.25) if id=="maya" else Vector3(8.25,.16,8.65)
 var phase:String="walking" if id=="maya" else "home"
 var wait:float=0 if id=="maya" else 24.0
 if place==str(PEOPLE[id].home):at=Vector3(-.5,.16,.1);phase="visiting";wait=5.0
 elif place in ["maya_home","leo_home"]:phase="home";wait=999999.0
 elif place!="home":at=Vector3(-2.5 if id=="maya" else 2.5,.16,2.75);phase="visiting";wait=3.0 if id=="maya" else 7.0
 return {"position":[at.x,at.y,at.z],"direction":1 if id=="maya" else -1,"phase":phase,"wait":wait,"rotation":PI*.5 if id=="maya" else -PI*.5,"waypoint":0}

func attach(place:String) -> void:
 active_place=place
 if not locations.has(place):locations[place]={}
 for id:String in PEOPLE:
  if not locations[place].has(id):locations[place][id]=_default_state(id,place)
  var state:Dictionary=locations[place][id]
  var at:Array=state.position
  var actor:LifeActor=app.spawn_actor(id,PEOPLE[id],Vector3(at[0],at[1],at[2]))
  actor.rotation.y=float(state.rotation)
  app.world.set_actor_away(id,str(state.phase)=="home",str(state.phase)=="home")

func present(id:String) -> bool:
 return PEOPLE.has(id) and is_instance_valid(app.world.actors.get(id)) and app.world.actors[id].visible and not bool(app.world.actors[id].get_meta("away",false))

func can_visit(id:String) -> bool:
 for member:Dictionary in app.household.members:
  if float(member.sim.relationships.get(id,{}).get("friendship",0))>=20:return true
 return false

func prepare_social(action:Dictionary) -> void:
 var id:String=str(action.get("target_id",""))
 if PEOPLE.has(id) and present(id) and str(action.get("id","")) in LifeSim.SOCIAL_ACTIONS:
  var at:Vector3=app.world.actors[id].position+Vector3(0,0,.8)
  var cell:Vector2i=app.world.nearest_free(at)
  action.target_position=Vector3(cell.x*.25,.16,cell.y*.25)

func _speaker(id:String) -> Dictionary:
 if not present(id):return {}
 for member:Dictionary in app.household.members:
  var action:Dictionary=member.sim.get_current_action()
  if str(action.get("target_id",""))==id and str(action.get("id","")) in LifeSim.SOCIAL_ACTIONS and str(action.get("phase","")) in ["approach","active"]:return member
 return {}

func publish_targets() -> void:
 var targets:Array=app.world.simulation_targets()
 for member:Dictionary in app.household.members:member.sim.register_targets(targets.filter(func(t:Dictionary):return str(t.id)!=str(member.id)))

func tick(delta:float) -> void:
 if active_place.is_empty() or not locations.has(active_place):return
 var speed:float=float(app.sim.speed)
 for id:String in PEOPLE:
  var actor:LifeActor=app.world.actors.get(id)
  if not is_instance_valid(actor):continue
  var state:Dictionary=locations[active_place][id]
  var speaker:Dictionary=_speaker(id)
  var moving:bool=false
  var talk:String=""
  if not speaker.is_empty():
   var action:Dictionary=speaker.sim.get_current_action()
   talk=str(action.id) if str(action.phase)=="active" else ""
   var direction:Vector3=app.world.actors[speaker.id].position-actor.position
   if speed>0:actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.z),minf(delta*4,1))
  elif speed>0:
   if str(state.phase)=="home":
    state.wait=maxf(0,float(state.wait)-delta*speed*LifeSim.GAME_MINUTES_PER_SECOND)
    if float(state.wait)<=0 and active_place=="home":
     state.phase="walking";app.world.set_actor_away(id,false,false)
   elif str(state.phase)=="walking":
    var before:Vector3=actor.position
    actor.position.x=move_toward(actor.position.x,8.5*float(state.direction),delta*speed*1.1)
    actor.rotation.y=PI*.5*float(state.direction)
    moving=actor.position.distance_to(before)>.00001
    if is_equal_approx(actor.position.x,8.5*float(state.direction)):
     state.phase="home";state.wait=48.0 if id=="maya" else 72.0;state.direction=-int(state.direction)
     app.world.set_actor_away(id,true,true)
   elif str(state.phase)=="visiting":
    state.wait=maxf(0,float(state.wait)-delta*speed)
    if float(state.wait)<=0:
     var destinations:Array=[Vector3(-.5,.16,2.9),Vector3(1.8,.16,2.8),Vector3(-.5,.16,.1)]
     var destination:Vector3=destinations[int(state.waypoint)%destinations.size()]
     var route:PackedVector3Array=app.world.path_to(actor.position,destination)
     if route.size()>1:
      var direction:Vector3=route[1]-actor.position
      actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.z),minf(delta*6,1))
      actor.position=actor.position.move_toward(route[1],delta*speed*.75);moving=true
     if actor.position.distance_to(destination)<.35 or route.size()<2:state.waypoint=(int(state.waypoint)+1)%destinations.size();state.wait=8.0
  actor.animate(delta,speed,moving,talk)
  state.position=[actor.position.x,actor.position.y,actor.position.z];state.rotation=actor.rotation.y
 publish_targets()

func snapshot() -> Dictionary:
 return {"version":1,"locations":locations.duplicate(true)}

func restore(value:Variant) -> void:
 reset()
 if not value is Dictionary or not _integer(value.get("version"),1,1) or not value.get("locations") is Dictionary:return
 for raw_place:Variant in value.locations:
  if not raw_place is String:continue
  var place:String=raw_place
  if not LifeNeighborhood.PLACES.has(place) or not value.locations[place] is Dictionary:continue
  var accepted:Dictionary={}
  for id:String in PEOPLE:
   var record:Variant=value.locations[place].get(id)
   if not record is Dictionary or not record.get("position") is Array or record.position.size()!=3:continue
   var valid:bool=true
   for number:Variant in record.position:
    if not (number is float or number is int) or not is_finite(float(number)):valid=false
   if not valid or absf(float(record.position[0]))>9 or absf(float(record.position[2]))>9 or absf(float(record.position[1])-.16)>.001:continue
   if str(record.get("phase","")) not in ["home","walking","visiting"]:continue
   if not (record.get("wait") is float or record.get("wait") is int) or not is_finite(float(record.wait)) or float(record.wait)<0:continue
   if not (record.get("rotation") is float or record.get("rotation") is int) or not is_finite(float(record.rotation)):continue
   var direction:Variant=record.get("direction",1)
   var waypoint:Variant=record.get("waypoint",0)
   if not _integer(direction,-1,1) or float(direction)==0 or not _integer(waypoint,0,2):continue
   var allowed:Array=["home","walking"] if place=="home" else (["home"] if place in ["maya_home","leo_home"] and place!=str(PEOPLE[id].home) else ["visiting"])
   if str(record.phase) not in allowed:continue
   accepted[id]={"position":record.position.duplicate(),"phase":str(record.phase),"wait":minf(float(record.wait),999999.0),"direction":int(direction),"rotation":float(record.rotation),"waypoint":int(waypoint)}
  locations[place]=accepted

func _integer(value:Variant,minimum:int,maximum:int) -> bool:
 if not (value is int or value is float):return false
 return is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and float(value)==floorf(float(value))

func begin_trip(destination:String) -> bool:
 if not trip.is_empty():return false
 for member:Dictionary in app.household.members:
  if member.sim.is_away():app.show_notice("Wait until everyone is home before taking a trip together.");return false
 var boarding:Dictionary={}
 for index:int in range(app.household.members.size()):
  var member:Dictionary=app.household.members[index]
  var actor:LifeActor=app.world.actors[member.id]
  var endpoint:Vector3=Vector3(-1.25+float(index%4)*.65,.16,8.5-float(index/4)*.5)
  var route:PackedVector3Array=app.world.path_to(actor.position,endpoint)
  if route.is_empty():app.show_notice("Clear a path to the sidewalk so everyone can reach the car.");return false
  boarding[member.id]={"path":route,"index":0}
 app.cancel_placement()
 if app.current_venue=="home":app.home_layout=app.world.serialize_items()
 else:app.venue_layouts[app.current_venue]=app.world.serialize_items()
 var resume:int=app.pause_before_menu if app.overlay_pauses_sim else (app.speed_before_build if app.mode=="build" else app.sim.speed)
 app.close_overlay(false);app._cancel_all_cooperative_actions()
 for member:Dictionary in app.household.members:
  while not member.sim.action_queue.is_empty():member.sim.cancel_action()
  member.sim.character.erase("world_state")
 app.household.set_speed(0);app.mode="travel";app.world.live_enabled=false
 app.clear_ui();app.overlay_open=true;app.menus.shade()
 # The world remains visible through the light transition shade.
 app.overlay.get_child(0).modulate.a=.15
 app.card(Vector2(440,730),Vector2(560,125),app.P.WHITE,18,app.overlay)
 app.text_label("Off to "+str(LifeNeighborhood.PLACES[destination].name),Vector2(463,744),Vector2(515,35),24,app.P.INK,true,app.overlay)
 var caption:Label=app.paragraph("Walking to the shared car · Saving is available on arrival.",Vector2(464,791),Vector2(515,47),14,app.P.MUTED,app.overlay)
 caption.name="TripPhase"
 car=_make_car();app.world.house.add_child(car);car.position=Vector3(0,0,10.25);car.rotation.y=PI*.5
 app.world.camera_target=Vector3(0,0,6.5);app.world.update_camera()
 trip={"destination":destination,"resume":resume,"phase":"boarding","time":0.0,"boarding":boarding}
 return true

func _make_car() -> Node3D:
 return load("res://assets/models/juniper_car.glb").instantiate()

func tick_trip(delta:float) -> void:
 if trip.is_empty():return
 trip.time=float(trip.time)+delta
 var phase:String=str(trip.phase)
 if phase=="boarding":
  var all_boarded:bool=true
  for id:String in trip.boarding:
   var record:Dictionary=trip.boarding[id]
   var actor:LifeActor=app.world.actors[id]
   var route:PackedVector3Array=record.path
   var budget:float=delta*2.1
   while int(record.index)<route.size() and budget>0:
    var point:Vector3=route[int(record.index)]
    var distance:float=actor.position.distance_to(point)
    if distance>.001:
     var direction:Vector3=point-actor.position;actor.rotation.y=atan2(direction.x,direction.z)
    var step:float=minf(distance,budget);actor.position=actor.position.move_toward(point,step);budget-=step
    if distance<=step+.00001:record.index=int(record.index)+1
   var boarded:bool=int(record.index)>=route.size()
   actor.animate(delta,1.0,not boarded,"")
   if boarded:actor.visible=false
   else:all_boarded=false
  if all_boarded:trip.phase="departure";trip.time=0.0;_trip_caption("Driving across Juniper Bay · 15 minutes")
 elif phase=="departure":
  car.position.x=minf(float(trip.time)/2.8,1.0)*21.0
  app.world.camera_target.x=minf(car.position.x*.45,7.0);app.world.update_camera()
  if float(trip.time)>=2.8:_arrive()
 elif phase=="arrival":
  car.position.x=lerpf(-19.0,0.0,minf(float(trip.time)/2.2,1.0))
  if float(trip.time)>=2.2:
   for member:Dictionary in app.household.members:
    var actor:LifeActor=app.world.actors[member.id]
    actor.visible=true
   car.queue_free();car=null
   var resume:int=int(trip.resume);trip.clear()
   app.close_overlay(false);app.mode="live";app.world.live_enabled=true;app.household.set_speed(resume)
   app.world.camera_target=Vector3(0,0,.25);app.world.update_camera();app.draw_live();app._sync_actor_sound()
   app.show_notice("Welcome to "+str(LifeNeighborhood.PLACES[app.current_venue].name)+".")

func _trip_caption(value:String) -> void:
 var caption:Label=app.overlay.find_child("TripPhase",true,false)
 if is_instance_valid(caption):caption.text=value

func _arrive() -> void:
 var destination:String=str(trip.destination)
 var automatic:Array=[]
 for member:Dictionary in app.household.members:automatic.append(member.sim.autonomy);member.sim.autonomy=false
 app.household.set_speed(1);app.household.tick(2.5);app.household.set_speed(0)
 for index:int in range(app.household.members.size()):app.household.members[index].sim.autonomy=automatic[index]
 app.current_venue=destination
 var layout:Array=app.home_layout if destination=="home" else app.venue_layouts.get(destination,LifeNeighborhood.layout(destination))
 if destination=="home" and layout.is_empty():layout=LifeCatalog.starter_layout(app.selected_lot)
 app.loading_game=true;app.setup_live(layout);app.loading_game=false
 for index:int in range(app.household.members.size()):
  var member:Dictionary=app.household.members[index]
  var actor:LifeActor=app.world.actors[member.id]
  actor.position=Vector3(-1.25+float(index%4)*.65,.16,8.5-float(index/4)*.5);actor.visible=false
  member.sim.remember("A visit across town","Drove to "+str(LifeNeighborhood.PLACES[destination].name)+".")
 app.clear_ui();app.mode="travel";app.world.live_enabled=false
 car=_make_car();app.world.house.add_child(car);car.position=Vector3(-19,0,10.25);car.rotation.y=PI*.5
 app.world.camera_target=Vector3(0,0,6.5);app.world.update_camera()
 app.overlay_open=true
 app.card(Vector2(440,730),Vector2(560,125),app.P.WHITE,18,app.overlay)
 app.text_label("Arriving at "+str(LifeNeighborhood.PLACES[destination].name),Vector2(463,744),Vector2(515,35),24,app.P.INK,true,app.overlay)
 app.paragraph("Pulling up outside · Saving is available when everyone steps out.",Vector2(464,791),Vector2(515,47),14,app.P.MUTED,app.overlay)
 trip.phase="arrival";trip.time=0.0
