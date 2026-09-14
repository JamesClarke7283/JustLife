extends RefCounted
class_name LifeResidents
## Stable residents own homes; only actors physically present can be approached.
const PEOPLE=LifeResidentCatalogue.PEOPLE
var app:Node
var locations:Dictionary={}
var active_place:String=""
var trip:Dictionary={}
var car:Node3D
var home_visit:LifeHomeVisit
var sidewalk_routes:Dictionary={}
var _initiated:Dictionary={}
var _anchor_cache:Dictionary={}
  # resident id -> absolute game day of their last self-started contact
const INITIATE_RADIUS:=2.5
## Sidewalk lane per resident, derived from the catalogue so new roster
## entries join the walking flow without new controller constants.
var SIDEWALK_LANES:Dictionary={}


func _init(controller:Node) -> void:
 app=controller;home_visit=LifeHomeVisit.new(self)
 for id:String in PEOPLE:
  SIDEWALK_LANES[id]=float(PEOPLE[id].get("lane",8.0))

func reset() -> void:
 locations.clear();active_place="";trip.clear();home_visit.reset();sidewalk_routes.clear();_initiated.clear();_anchor_cache.clear()

## A visiting resident with a household member nearby starts one contact per
## game day: a cheerful chat off hours, or looking for company when their
## catalogue mood is drained. Pure decision — the caller applies the effects.
func resident_initiation(resident_id:String,resident_phase:String,resident_position:Vector3,member_positions:Dictionary,weekday:bool,minutes:float,absolute_day:int) -> Dictionary:
 if resident_phase!="visiting":return {}
 if int(_initiated.get(resident_id,-1))>=absolute_day:return {}
 var nearest:String=""
 var best:float=INITIATE_RADIUS
 for member_id:String in member_positions:
  var distance:float=float(member_positions[member_id].distance_to(resident_position))
  if distance<best:best=distance;nearest=member_id
 if nearest.is_empty():return {}
 var catalogue:Dictionary=PEOPLE[resident_id]
 var at_work:bool=weekday and minutes>=540.0 and minutes<=960.0
 var mood:Dictionary=catalogue.get("fun",{"work":40,"off":80})
 var drained:bool=float(mood["work" if at_work else "off"])<45.0
 _initiated[resident_id]=absolute_day
 var first_name:String=str(catalogue.name).split(" ")[0]
 if drained:
  return {"resident":resident_id,"member":nearest,"kind":"vent","social":10.0,"friendship":5.0,
   "notice":"%s comes over, looking for a little company." % first_name}
 if "Cheerful" in catalogue.get("traits",[]):
  return {"resident":resident_id,"member":nearest,"kind":"cheerful_chat","social":16.0,"friendship":8.0,
   "notice":"%s drops by with a big grin and the latest news." % first_name}
 return {"resident":resident_id,"member":nearest,"kind":"chat","social":12.0,"friendship":6.0,
  "notice":"%s stops by to chat for a few minutes." % first_name}

## The effects half of a resident contact: needs and friendship move on the
## member's real sim, inside the same clamps every other social gain uses.
func apply_contact(contact:Dictionary,member_sim:LifeSim) -> void:
 member_sim.needs.social=clampf(float(member_sim.needs.social)+float(contact.social),0.0,100.0)
 var relationship:Dictionary=member_sim.relationships.get(str(contact.resident),{})
 if relationship.has("friendship"):
  relationship.friendship=clampf(float(relationship.friendship)+float(contact.friendship),-100.0,100.0)
  member_sim._update_relationship_status(relationship)

func _default_state(id:String,place:String) -> Dictionary:
 var person:Dictionary=PEOPLE[id]
 var side:int=int(person.get("side",-1))
 var at:=Vector3(8.25*side,.16,float(person.get("lane",8.0)))
 var phase:String="walking" if float(person.get("walk_wait",24.0))<=0.0 else "home"
 var wait:float=float(person.get("walk_wait",24.0)) if phase=="walking" else float(person.get("rest_wait",24.0))
 if place==str(person.home):at=Vector3(-.5,.16,.1);phase="visiting";wait=5.0
 elif place in LifeNeighborhood.RESIDENT_HOMES:phase="home";wait=999999.0
 elif place!="home":at=Vector3(2.5*side,.16,2.75);phase="visiting";wait=float(person.get("visit_wait",5.0))
 return {"position":[at.x,at.y,at.z],"direction":-side,"phase":phase,"wait":wait,"rotation":PI*.5*-side,"waypoint":0}

func attach(place:String) -> void:
 sidewalk_routes.clear()
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
  # A quarter-grid social point must stay beyond the route body clearance.
  # The old .8 offset snapped to .75 and made a home guest an unreachable target.
  var spacing:float=1.0 if home_visit.owns(id) and not app.world.construction.building_state.is_empty() else .8
  var at:Vector3=app.world.actors[id].position+Vector3(0,0,spacing)
  if not app.world.construction.building_state.is_empty():action.target_position=app.world.nearest_clear_point(at,0)
  else:
   var cell:Vector2i=app.world.nearest_free(at)
   action.target_position=Vector3(cell.x*.25,.16,cell.y*.25)

func _speaker(id:String) -> Dictionary:
 if not present(id):return {}
 for member:Dictionary in app.household.members:
  var action:Dictionary=member.sim.get_current_action()
  if str(action.get("target_id",""))==id and str(action.get("id","")) in LifeSim.SOCIAL_ACTIONS and str(action.get("phase","")) in ["approach","active"]:return member
 return {}

var _publish_msec:int=-1000
var _publish_generation:int=-1
func publish_targets(force:bool=false) -> void:
 # Autonomy reads targets at most ten times a second; navigation changes and
 # explicit callers publish at once. Positions of moving people refresh with it.
 var generation:int=app.world.lot_navigation.generation if is_instance_valid(app.world.lot_navigation) else -1
 var now:int=Time.get_ticks_msec()
 if not force and generation==_publish_generation and now-_publish_msec<100:return
 _publish_msec=now;_publish_generation=generation
 var targets:Array=app.world.simulation_targets()
 for member:Dictionary in app.household.members:member.sim.register_targets(targets.filter(func(t:Dictionary):return str(t.id)!=str(member.id) and home_visit.social_allowed(str(t.id),member.sim.get_current_action())))

## The arrival flavor for a host whose routine has them out: who, where,
## and until when. Empty when the host is home.
func routine_note(destination:String) -> String:
 var resident:String=str(LifeNeighborhood.PLACES.get(destination,{}).get("resident",""))
 if resident.is_empty():return ""
 var person:Dictionary=PEOPLE.get(resident,{})
 var routine:Dictionary=person.get("routine",{})
 if routine.is_empty() or not LifeResidentCatalogue.routine_active(person,LifeEducation.weekday(app.sim.day),app.sim.minutes):return ""
 var end_minute:float=LifeResidentCatalogue.routine_until(person)
 var hour:int=int(end_minute/60.0)
 var minute:int=int(fmod(end_minute,60.0))
 return str(person.name).split(" ")[0]+" is out at "+str(routine["place"])+" until %02d:%02d." % [hour,minute]

func _walk_sidewalk(id:String,state:Dictionary,time:float)->bool:
 var actor:LifeActor=app.world.actors[id]
 var goal:=Vector3(8.5*float(state.direction),.16,float(SIDEWALK_LANES[id]))
 var now:float=float(app.household.day-1)*1440.0+app.household.minutes
 var generation:int=app.world.lot_navigation.generation
 if not sidewalk_routes.has(id) or sidewalk_routes[id].goal!=goal:
  # Saved positions stay authoritative. An older narrow lane is joined on foot.
  sidewalk_routes[id]={"goal":goal,"points":PackedVector3Array([actor.position,Vector3(actor.position.x,.16,goal.z),goal]),"point":0,"generation":generation,"retry_at":now}
 var route:Dictionary=sidewalk_routes[id]
 if int(route.generation)!=generation:
  route.points=PackedVector3Array();route.point=0;route.generation=generation;route.retry_at=now
 if route.points.is_empty():
  if now<float(route.retry_at):return false
  route.points=app.traversal._floor_route(actor.position,goal,id);route.point=0;route.retry_at=now+3.0
 var budget:float=maxf(0,time)*1.1;var moving:bool=false
 for iteration:int in range(128):
  if int(route.point)>=route.points.size() or budget<=.0000001:break
  var target:Vector3=route.points[int(route.point)]
  var distance:float=actor.position.distance_to(target)
  if distance<.000001:route.point+=1;continue
  var step:float=minf(minf(distance,budget),.08)
  var next:Vector3=actor.position.move_toward(target,step)
  if not app.world.lot_navigation.segment_clear(0,actor.position,next) or not app.traversal._step_clear(id,actor.position,next):
   # A stopped Lifelet keeps their body and walking intent. Retry is bounded.
   if now>=float(route.retry_at):
    route.points=app.traversal._floor_route(actor.position,goal,id);route.point=0;route.retry_at=now+3.0
   break
  var direction:Vector3=next-actor.position
  actor.rotation.y=atan2(direction.x,direction.z)
  actor.position=next;budget-=step;moving=true
  if distance<=step+.000001:route.point+=1
 if actor.position.distance_to(goal)<.00001:
  state.phase="home";state.wait=float(PEOPLE[id].get("home_wait",60.0));state.direction=-int(state.direction)
  app.world.set_actor_away(id,true,true);sidewalk_routes.erase(id)
 return moving

## Waypoints for a visiting resident: routine residents at their venue idle
## beside their anchor object (desk, planters); everyone else walks the house
## circuit. The lookup is cached per venue.
func _destinations_for(id:String) -> Array:
 var person:Dictionary=PEOPLE[id]
 var anchor_kind:String=str(person.get("routine",{}).get("anchor_kind",""))
 var at_routine_venue:bool=active_place==str(person.get("routine",{}).get("venue",""))
 if anchor_kind.is_empty() or not at_routine_venue:
  return [Vector3(-.5,.16,2.9),Vector3(1.8,.16,2.8),Vector3(-.5,.16,.1)]
 var cache_key:String=active_place+"/"+anchor_kind
 if _anchor_cache.has(cache_key):return _anchor_cache[cache_key]
 var result:Array=[]
 for entry:Dictionary in LifeNeighborhood.layout(active_place):
  if str(entry.get("kind",""))!=anchor_kind:continue
  var p:=Vector3(float(entry.x),.16,float(entry.z))
  result.append_array([p+Vector3(.7,.16,.35),p+Vector3(-.7,.16,.2),p+Vector3(0,.16,.55)])
 if result.is_empty():result=[Vector3(-.5,.16,2.9),Vector3(1.8,.16,2.8),Vector3(-.5,.16,.1)]
 _anchor_cache[cache_key]=result
 return result

func tick(delta:float) -> void:
 if active_place.is_empty() or not locations.has(active_place):return
 var speed:float=float(app.sim.speed)
 for id:String in PEOPLE:
  var actor:LifeActor=app.world.actors.get(id)
  if not is_instance_valid(actor):continue
  var state:Dictionary=locations[active_place][id]
  # A resident whose weekday routine window is open steps out: off-lot and
  # untargetable until the window closes, when the usual home-to-walking
  # flip brings them back on their normal rhythm. An invited guest never
  # vanishes mid-visit: the step-out defers until the visit ends.
  var person:Dictionary=PEOPLE[id]
  var guest:bool=home_visit.owns(id)
  # The routine's named venue is where they ARE during the window: the
  # library keeps Priya, the community garden keeps Tom. Everywhere else the
  # window hides them until it closes.
  var routine_venue:String=str(person.get("routine",{}).get("venue",""))
  var at_routine_venue:bool=routine_venue!="" and active_place==routine_venue
  var routine_on:bool=LifeResidentCatalogue.routine_active(person,LifeEducation.weekday(app.sim.day),app.sim.minutes)
  # The morning jog plays on the home lot's lane: at other venues the
  # resident keeps their normal presence rhythm.
  var morning_on:bool=not home_visit.owns(id) and active_place=="home" and LifeResidentCatalogue.routine_morning_active(person,LifeEducation.weekday(app.sim.day),app.sim.minutes)
  if morning_on and str(state.phase)!="walking":
   # The second beat: a morning spent out on the lane before the routine.
   state.phase="walking";state.routine_away=false
   actor.visible=true
   app.world.set_actor_away(id,false,false);sidewalk_routes.erase(id)
  var routine_due:bool=not home_visit.owns(id) and not at_routine_venue and routine_on and str(state.phase)!="home"
  if routine_due:
   state.phase="home";state.routine_away=true;state.wait=float(person.get("home_wait",60.0))
   actor.visible=false
   app.world.set_actor_away(id,true,true);sidewalk_routes.erase(id);continue
  elif bool(state.get("routine_away",false)) and not routine_on:
   # The routine window closed while they were out at this lot: step back on.
   state.routine_away=false
   state.phase="visiting";state.wait=float(person.get("visit_wait",5.0))
   actor.visible=true
   app.world.set_actor_away(id,false,false);sidewalk_routes.erase(id)
  if guest:sidewalk_routes.erase(id);home_visit.tick(delta);continue
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
    if float(state.wait)<=0 and active_place=="home" and app.traversal._free(id,actor.position) and not LifeResidentCatalogue.routine_active(PEOPLE[id],LifeEducation.weekday(app.sim.day),app.sim.minutes):
     sidewalk_routes.erase(id);state.phase="walking";app.world.set_actor_away(id,false,false)
   elif str(state.phase)=="walking":
    moving=_walk_sidewalk(id,state,delta*speed)
   elif str(state.phase)=="visiting":
    state.wait=maxf(0,float(state.wait)-delta*speed)
    if float(state.wait)<=0:
     # A routine resident at their venue idles by their anchor object; other
     # visitors keep the house lot's front-room circuit.
     var destinations:Array=_destinations_for(id)
     var destination:Vector3=destinations[int(state.waypoint)%destinations.size()]
     var route:PackedVector3Array=app.world.path_to(actor.position,destination)
     if route.size()>1:
      var next:Vector3=actor.position.move_toward(route[1],delta*speed*.75)
      # A visiting resident respects the same body gap as everyone else; a
      # waypoint another body occupies is abandoned for the next one.
      if app.traversal._step_clear(id,actor.position,next):
       var direction:Vector3=route[1]-actor.position
       actor.rotation.y=lerp_angle(actor.rotation.y,atan2(direction.x,direction.z),minf(delta*6,1))
       actor.position=next;moving=true
      else:
       # Blocked by a body: abandon a close waypoint, otherwise slide aside
       # so a held-up member can get past.
       if actor.position.distance_to(destination)<.7:state.waypoint=(int(state.waypoint)+1)%destinations.size();state.wait=8.0
       else:_yield_to_walkers(id)
     if actor.position.distance_to(destination)<.35 or route.size()<2:state.waypoint=(int(state.waypoint)+1)%destinations.size();state.wait=8.0
    else:_yield_to_walkers(id)
  actor.animate(delta,speed,moving,talk)
  state.position=[actor.position.x,actor.position.y,actor.position.z];state.rotation=actor.rotation.y
 publish_targets(true)

func snapshot() -> Dictionary:
 var captured:Dictionary=locations.duplicate(true)
 # Every record carries the routine flag so restores and saves compare
 # structurally regardless of whether the window has touched this resident.
 for place:String in captured:
  for id:String in captured[place]:
   captured[place][id]["routine_away"]=bool(captured[place][id].get("routine_away",false))
 # Detached physical snapshots include actual resident transforms without
 # modifying this live service, clocks, routes or cached location records.
 if captured.has(active_place) and is_instance_valid(app.world):
  for id:String in PEOPLE:
   var actor:LifeActor=app.world.actors.get(id)
   if is_instance_valid(actor) and captured[active_place].has(id):
    captured[active_place][id].position=[actor.position.x,actor.position.y,actor.position.z]
    captured[active_place][id].rotation=actor.rotation.y
 var result:Dictionary={"version":1,"locations":captured}
 if home_visit.active() or home_visit.next_serial>1:result.home_visit=home_visit.snapshot()
 return result

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
   # The z bound covers every catalogue lane (tom walks at z=10.4).
   if not valid or absf(float(record.position[0]))>9 or absf(float(record.position[2]))>12 or absf(float(record.position[1])-.16)>.001:continue
   if str(record.get("phase","")) not in ["home","walking","visiting"]:continue
   if not (record.get("wait") is float or record.get("wait") is int) or not is_finite(float(record.wait)) or float(record.wait)<0:continue
   if not (record.get("rotation") is float or record.get("rotation") is int) or not is_finite(float(record.rotation)):continue
   var direction:Variant=record.get("direction",1)
   var waypoint:Variant=record.get("waypoint",0)
   if not _integer(direction,-1,1) or float(direction)==0 or not _integer(waypoint,0,2):continue
   var allowed:Array=["home","walking"] if place=="home" else (["home"] if place in LifeNeighborhood.RESIDENT_HOMES and place!=str(PEOPLE[id].home) else ["visiting"])
   if str(record.phase) not in allowed:continue
   # Positions restore verbatim: the JSON doubles match the saved snapshot
   # exactly, and the live path re-quantizes to float32 through the actor.
   accepted[id]={"position":record.position.duplicate(),"phase":str(record.phase),"wait":minf(float(record.wait),999999.0),"direction":int(direction),"rotation":float(record.rotation),"waypoint":int(waypoint),"routine_away":bool(record.get("routine_away",false))}
  locations[place]=accepted

 if value.get("home_visit") is Dictionary:home_visit.restore(value.home_visit)

func _integer(value:Variant,minimum:int,maximum:int) -> bool:
 if not (value is int or value is float):return false
 return is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and float(value)==floorf(float(value))

func begin_trip(destination:String) -> bool:
 if home_visit.active():app.show_notice("Say goodbye and wait for your guest to leave before traveling.");return false
 if not trip.is_empty():return false
 for member:Dictionary in app.household.members:
  if member.sim.is_away():app.show_notice("Wait until everyone is home before taking a trip together.");return false
 var canonical:bool=not app.world.construction.building_state.is_empty()
 var planner:LifeTraversal=LifeTraversal.new(app) if canonical else null
 var boarding:Dictionary={}
 var curb_places:Array[Vector3]=[]
 # Preflight against the existing scene; a refusal changes no queue, body,
 # stair owner, dish, selection, clock, resident state or saved home layout.
 for index:int in range(app.household.members.size()):
  var member:Dictionary=app.household.members[index]
  var actor:LifeActor=app.world.actors[member.id]
  if app.traversal.busy(str(member.id)):
   app.show_notice("Let everyone finish the current stair crossing before leaving.");return false
  var endpoint:Vector3=_boarding_point(index,str(member.id),curb_places)
  if not endpoint.is_finite():app.show_notice("Clear the sidewalk so everyone has room beside the car.");return false
  curb_places.append(endpoint)
  var route:PackedVector3Array
  if canonical:
   var proposed:Dictionary=planner.request(str(member.id),endpoint)
   if not bool(proposed.ok):app.show_notice("Clear a path to the sidewalk so everyone can reach the car.");return false
   route=proposed.points
  else:route=app.world.path_to(actor.position,endpoint)
  if route.is_empty():app.show_notice("Clear a path to the sidewalk so everyone can reach the car.");return false
  boarding[member.id]={"path":route,"index":0,"boarded":false,"endpoint":endpoint}
 var food_error:String=preload("res://scripts/travel_food.gd").departure_error(app)
 if not food_error.is_empty():app.show_notice(food_error);return false
 app.cancel_placement()
 if app.current_venue=="home":app.home_layout=app.world.serialize_items()
 else:app.venue_layouts[app.current_venue]=app.world.serialize_items()
 var resume:int=app.pause_before_menu if app.overlay_pauses_sim else (app.speed_before_build if app.mode=="build" else app.sim.speed)
 app.close_overlay(false)
 app.loading_game=true # Cancel queued work without starting the following route.
 app._cancel_all_cooperative_actions()
 for member:Dictionary in app.household.members:
  while not member.sim.action_queue.is_empty():member.sim.cancel_action()
  member.sim.character.erase("world_state")
  app.motion_states[member.id]=app._empty_motion()
 app._bind_member(app.household.selected_id())
 if canonical:app.traversal=planner
 else:app.traversal.reset()
 app.loading_game=false
 app.meal_flow.sync_world()
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
 trip={"destination":destination,"resume":resume,"phase":"boarding","time":0.0,"boarding":boarding,"canonical":canonical}
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
   if bool(record.boarded):continue
   var boarded:bool=false
   if bool(trip.canonical):
    var moved:Dictionary=app.traversal.advance(id,delta,1)
    boarded=bool(moved.get("finished",false))
    # A route planned through a crowded doorway can fairly detour around
    # the whole building. If a boarder stops making straight-line progress
    # toward the car, ask the planner again: the short way is usually clear
    # a few seconds later.
    var straight:float=app.world.actors[id].position.distance_to(Vector3(record.endpoint))
    if not record.has("check_at"):
     record["check_at"]=float(trip.time)+5.0
     record["last_distance"]=straight
    if float(trip.time)>=float(record.check_at):
     if float(record.get("last_distance",INF))-straight<.5 and int(record.get("replans",0))<3:
      record["replans"]=int(record.get("replans",0))+1
      app.traversal.request(id,Vector3(record.endpoint))
     record["last_distance"]=straight
     record["check_at"]=float(trip.time)+6.0
    if moved.has("error") and not str(moved.error).is_empty():
     _trip_caption("The path to the car is blocked. "+str(moved.error))
     _resident_yields(id)
    # LifeTraversal paints the actual stair feet/torso pose while it owns a crossing.
    if not app.traversal.busy(id):actor.animate(delta,1.0,bool(moved.get("moving",false)),"")
   else:
    var route:PackedVector3Array=record.path
    var budget:float=delta*2.1
    while int(record.index)<route.size() and budget>0:
     var point:Vector3=route[int(record.index)]
     var distance:float=actor.position.distance_to(point)
     if distance>.001:
      var direction:Vector3=point-actor.position;actor.rotation.y=atan2(direction.x,direction.z)
     var step:float=minf(distance,budget)
     var next:Vector3=actor.position.move_toward(point,step)
     # Even the bare-lot boarding walk keeps bodies apart; a blocked step
     # simply waits for the next tick instead of walking through someone.
     if not app.traversal._step_clear(id,actor.position,next):break
     actor.position=next;budget-=step
     if distance<=step+.00001:record.index=int(record.index)+1
    boarded=int(record.index)>=route.size()
    actor.animate(delta,1.0,not boarded,"")
   record.boarded=boarded
   if boarded:actor.visible=false
   else:all_boarded=false
  if not all_boarded and float(trip.time)>60.0:
   # A transition must never hold the household hostage: everyone still out
   # after a minute of boarding is already at the car, so they pile in.
   for waiting_id:String in trip.boarding:
    if not bool(trip.boarding[waiting_id].boarded):
     trip.boarding[waiting_id].boarded=true
     var waiting:LifeActor=app.world.actors[waiting_id]
     if waiting!=null:waiting.visible=false
   all_boarded=true
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

func _yield_to_walkers(id:String) -> bool:
 # A standing resident slides one body-width aside when a member with a live
 # route is held up by them: the same courtesy walking bodies already show
 # each other, so seats, doors and routes stay reachable.
 var body:LifeActor=app.world.actors.get(id)
 if body==null or not body.visible:return false
 for member:Dictionary in app.household.members:
  var member_id:String=str(member.id)
  var walker:LifeActor=app.world.actors.get(member_id)
  if walker==null or not walker.visible:continue
  if not app.traversal.active(member_id):continue
  var route:Dictionary=app.traversal.routes.get(member_id,{})
  if not route.has("destination"):continue
  var away:Vector3=body.position-walker.position;away.y=0.0
  var dist:float=away.length()
  if dist>=app.traversal.BODY_GAP+.15 or dist<.01:continue
  var to_body:Vector3=away
  var to_dest:Vector3=Vector3(route.destination)-walker.position;to_dest.y=0.0
  if to_body.length()<.01 or to_dest.length()<.01:continue
  if to_body.normalized().dot(to_dest.normalized())<=.3:continue
  var side:Vector3=Vector3(-away.z,0,away.x).normalized()
  for candidate_dir:Vector3 in [side,-side]:
   var candidate:Vector3=body.position+candidate_dir*.5
   candidate.y=body.position.y
   if app.traversal._step_clear(id,body.position,candidate):
    body.position=candidate
    if active_place!="" and locations.has(active_place) and locations[active_place].has(id):
     var yielded_state:Dictionary=locations[active_place][id]
     yielded_state.position=[candidate.x,candidate.y,candidate.z]
    return true
 return false

func _resident_yields(boarder_id:String) -> void:
 # A resident standing on a boarding route steps aside once, the same
 # courtesy walking bodies already show each other, so a shared trip can
 # finish without anyone walking through anyone.
 var boarder:LifeActor=app.world.actors.get(boarder_id)
 if boarder==null:return
 var record:Dictionary=trip.boarding.get(boarder_id,{})
 var goal:Vector3=boarder.position+Vector3(0,0,1)
 if record.has("endpoint"):goal=Vector3(record.endpoint)
 var toward:Vector3=goal-boarder.position;toward.y=0.0
 if toward.length()<.01:return
 var side:Vector3=Vector3(-toward.z,0,toward.x).normalized()
 for blocker_id:String in _blocking_residents(boarder_id,boarder.position,boarder.position.move_toward(goal,.3)):
  var body:LifeActor=app.world.actors[blocker_id]
  var away:Vector3=body.position-boarder.position;away.y=0.0
  if away.length()<.01:continue
  for candidate_dir:Vector3 in [side,-side]:
   var candidate:Vector3=body.position+candidate_dir*.45+away.normalized()*.1
   candidate.y=body.position.y
   if app.traversal._step_clear(blocker_id,body.position,candidate):
    body.position=candidate
    if active_place!="" and locations.has(active_place) and locations[active_place].has(blocker_id):
     var yielded:Dictionary=locations[active_place][blocker_id]
     yielded.position=[candidate.x,candidate.y,candidate.z]
    break

func _blocking_residents(boarder_id:String,from:Vector3,to:Vector3) -> Array:
 var found:Array=[]
 for other_id:String in app.world.actors:
  if other_id==boarder_id or not PEOPLE.has(other_id):continue
  var body:LifeActor=app.world.actors[other_id]
  if not body.visible:continue
  if body.position.distance_to(to)<app.traversal.BODY_GAP or body.position.distance_to(from)<app.traversal.BODY_GAP:found.append(other_id)
 return found

func _arrive() -> void:
 var destination:String=str(trip.destination)
 var automatic:Array=[]
 for member:Dictionary in app.household.members:automatic.append(member.sim.autonomy);member.sim.autonomy=false
 app.household.set_speed(1);app.household.tick(15.0/LifeSim.GAME_MINUTES_PER_SECOND);app.household.set_speed(0)
 for index:int in range(app.household.members.size()):app.household.members[index].sim.autonomy=automatic[index]
 app.household.journeys.clear() # Old-house floor positions cannot enter the new lot.
 app.current_venue=destination
 var layout:Array=app.home_layout if destination=="home" else app.venue_layouts.get(destination,LifeNeighborhood.layout(destination))
 if destination=="home" and layout.is_empty():layout=LifeCatalog.starter_layout(app.selected_lot)
 app.loading_game=true;app.setup_live(layout);app.loading_game=false
 var note:=routine_note(destination)
 if not note.is_empty():app.show_notice(note)
 var taken_spots:Array[Vector3]=[]
 for index:int in range(app.household.members.size()):
  var member:Dictionary=app.household.members[index]
  var actor:LifeActor=app.world.actors[member.id]
  var spot:Vector3=_curb(index,taken_spots)
  actor.position=spot;actor.visible=false
  taken_spots.append(spot)
  member.sim.remember("A visit across town","Drove to "+str(LifeNeighborhood.PLACES[destination].name)+".")
 app.world.refresh_actor_layers()
 app.clear_ui();app.mode="travel";app.world.live_enabled=false
 car=_make_car();app.world.house.add_child(car);car.position=Vector3(-19,0,10.25);car.rotation.y=PI*.5
 app.world.camera_target=Vector3(0,0,6.5);app.world.update_camera()
 app.overlay_open=true
 app.card(Vector2(440,730),Vector2(560,125),app.P.WHITE,18,app.overlay)
 app.text_label("Arriving at "+str(LifeNeighborhood.PLACES[destination].name),Vector2(463,744),Vector2(515,35),24,app.P.INK,true,app.overlay)
 app.paragraph("Pulling up outside · Saving is available when everyone steps out.",Vector2(464,791),Vector2(515,47),14,app.P.MUTED,app.overlay)
 trip.phase="arrival";trip.time=0.0

func _curb(index:int,taken:Array[Vector3]=[]) -> Vector3:
 # Quarter-grid aligned places leave more than the 72cm body clearance, and a
 # spot under furniture, another body or a place already claimed by an earlier
 # returning member is skipped, so the household does not come home standing
 # inside a chair or on top of each other.
 var preferred:=Vector3(-1.5+float(index%4),.16,7.5-float(index/4))
 return _clear_curb(preferred,index,taken)

func _clear_curb(preferred:Vector3,index:int,taken:Array[Vector3]) -> Vector3:
 var reserved:Array[Vector3]=taken.duplicate()
 for other:Dictionary in app.household.members:
  if str(other.id)==str(app.household.members[index].id):continue
  var body:LifeActor=app.world.actors.get(str(other.id))
  if body!=null and body.visible:reserved.append(body.position)
 for candidate:Vector3 in [preferred,preferred+Vector3(.5,0,0),preferred+Vector3(-.5,0,0),preferred+Vector3(0,0,.5),preferred+Vector3(0,0,-.5),preferred+Vector3(1,0,0),preferred+Vector3(-1,0,0),preferred+Vector3(0,0,1),preferred+Vector3(0,0,-1)]:
  if reserved.any(func(other:Vector3):return other.distance_to(candidate)<LifeTraversal.BODY_GAP):continue
  if not app.world.construction.building_state.is_empty():
   if not app.world.lot_navigation.point_clear(0,candidate):continue
  else:
   var cell:=Vector2i(roundi(candidate.x*4),roundi(candidate.z*4))
   if not app.world.navigation.region.has_point(cell) or app.world.navigation.is_point_solid(cell):continue
  return candidate
 # Every nearby spot is taken: keep the authored place rather than fail.
 return preferred

func _boarding_point(index:int,id:String,reserved:Array[Vector3]) -> Vector3:
 var candidates:Array[Vector3]=[_curb(index)]
 for z:float in [7.5,8.5,6.5]:
  for x:float in [-3.5,-2.5,-1.5,-.5,.5,1.5,2.5,3.5]:candidates.append(Vector3(x,.16,z))
 for point:Vector3 in candidates:
  if reserved.any(func(other:Vector3):return point.distance_to(other)<LifeTraversal.BODY_GAP):continue
  if not app.world.construction.building_state.is_empty() and not app.world.lot_navigation.point_clear(0,point):continue
  var clear:bool=true
  for other_id:String in app.world.actors:
   var other:LifeActor=app.world.actors[other_id]
   if other_id!=id and other.visible and other.position.distance_to(point)<LifeTraversal.BODY_GAP:clear=false;break
  if clear:return point
 return Vector3.INF
