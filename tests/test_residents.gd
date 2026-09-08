extends SceneTree
var app:Node
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,message:String) -> void:
 checks+=1
 print("PASS " if ok else "FAIL ",message)
 if not ok:failures+=1
func advance(seconds:float) -> void:
 for i:int in range(ceili(seconds/.05)):
  app._process(.05)
  if i%10==0:await process_frame
func travel(place:String) -> void:
 app.travel_to(place)
 check(app.mode=="travel","A car journey begins toward "+place)
 for i:int in range(1000):
  if app.mode!="travel":break
  app._process(.05)
  if i%10==0:await process_frame
 check(app.mode=="live" and app.current_venue==place,"Car journey arrives at "+place)
func run() -> void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():push_error("Set JUSTLIFE_DATA_DIR to an isolated test folder.");quit(2);return
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
 app.start_household();app.set_sound(false)
 for member:Dictionary in app.household.members:member.sim.autonomy=false
 await process_frame
 check(app.residents.present("maya") and not app.residents.present("leo"),"Residents have distinct walking and at-home presence")
 check(not app.world.simulation_targets().any(func(t:Dictionary):return str(t.id)=="leo"),"An absent resident cannot be targeted")
 var before:Vector3=app.world.actors.maya.position
 await advance(1)
 check(app.world.actors.maya.position.distance_to(before)>.9,"Maya walks past the front sidewalk")
 app.household.set_speed(0);before=app.world.actors.maya.position
 await advance(2)
 check(app.world.actors.maya.position==before,"Pause freezes the resident route")
 app.household.set_speed(1)
 var maya:LifeActor=app.world.actors.maya
 var bookshelf:Dictionary={}
 for item:Dictionary in app.world.items:
  if item.kind=="bookshelf":bookshelf=item;break
 app.queue_interaction(bookshelf,"read")
 app.queue_interaction({"id":"maya","kind":"neighbor","node":maya,"size":Vector2(.6,.6)},"friendly")
 before=maya.position
 await advance(1)
 check(maya.position.distance_to(before)>.9,"A conversation queued behind another activity does not freeze the walker")
 while not app.sim.action_queue.is_empty():app.cancel_current_action()
 app.queue_interaction({"id":"maya","kind":"neighbor","node":maya,"size":Vector2(.6,.6)},"friendly")
 before=maya.position
 await advance(1)
 check(maya.position==before,"The neighbor waits while the player approaches to chat")
 app.cancel_current_action();await advance(.5)
 check(maya.position.distance_to(before)>.4,"Canceling chat releases the resident to walk again")
 var home:Array=app.world.serialize_items()
 app.travel_to("maya_home")
 check(app.mode=="live","Unfamiliar households cannot be visited yet")
 var friendship_before:float=float(app.sim.relationships.maya.friendship)
 app.queue_interaction({"id":"maya","kind":"neighbor","node":maya,"size":Vector2(.6,.6)},"friendly")
 for i:int in range(1200):
  app._process(.05)
  if i%10==0:await process_frame
  if app.sim.action_queue.is_empty():break
 check(app.sim.action_queue.is_empty() and float(app.sim.relationships.maya.friendship)>friendship_before,"A completed street conversation earns friendship")
 check(app.residents.can_visit("maya"),"Getting to know the walking neighbor unlocks a home visit")
 var friendship_saved:float=float(app.sim.relationships.maya.friendship)
 app.sim.relationships.leo.friendship=30
 var minutes:float=app.household.minutes
 app.show_neighborhood("maya_home")
 var go:Button
 for button:Node in app.overlay.find_children("*","Button",true,false):
  if button.text=="Travel here  →":go=button
 check(is_instance_valid(go) and not go.disabled,"A friend’s home is available through the map")
 go.pressed.emit()
 check(app.mode=="travel" and not app.residents.trip.is_empty(),"Map button starts the visible car journey")
 check(not app.save_game(),"Saving cannot create a partial in-transit save")
 app.close_overlay()
 check(app.overlay_open and is_instance_valid(app.overlay.find_child("TripPhase",true,false)),"The journey caption stays visible until arrival")
 for i:int in range(1000):
  if app.mode!="travel":break
  app._process(.05)
  if i%10==0:await process_frame
 check(app.current_venue=="maya_home" and app.mode=="live","The household arrives at Maya’s home")
 check(is_equal_approx(app.household.minutes-minutes,15),"The trip advances exactly fifteen game minutes")
 check(app.residents.present("maya") and not app.residents.present("leo"),"Only the home’s resident is present")
 check(app.world.house.name=="ResidentHome_maya_home","Maya owns a dedicated furnished house")
 for item:Dictionary in app.world.items:
  check(not app.world.path_to(app.player.position,app.world.approach(item)).is_empty(),"Maya’s furnishing can be approached: "+str(item.id))
 var maya_walls:int=app.world.construction.records.size()
 var maya_layout:String=JSON.stringify(app.world.serialize_items())
 app.set_build_mode(true);check(app.mode=="live","Visitors cannot sell another resident’s furnishings")
 check(app.save_game("","Neighborhood validation"),"A named save is written while visiting")
 var saved_id:String=app.active_save_id
 var state:Dictionary=app.residents.snapshot()
 var receipt:Dictionary={"slot":saved_id,"residents":state,"friendship":friendship_saved,"home":home}
 var output:=FileAccess.open("user://resident_expected.json",FileAccess.WRITE);output.store_string(JSON.stringify(receipt, "", true, true));output.close()
 app.load_game(saved_id);await process_frame
 check(app.current_venue=="maya_home","Loading returns to the friend’s home")
 check(JSON.stringify(app.residents.snapshot())==JSON.stringify(state),"Resident route state is restored exactly")
 check(float(app.sim.relationships.maya.friendship)==friendship_saved,"Friendship survives the visit save")
 await travel("leo_home")
 check(app.world.house.name=="ResidentHome_leo_home" and app.residents.present("leo") and not app.residents.present("maya"),"Leo has his own visitable home and presence")
 for item:Dictionary in app.world.items:
  check(not app.world.path_to(app.player.position,app.world.approach(item)).is_empty(),"Leo’s furnishing can be approached: "+str(item.id))
 check(JSON.stringify(app.world.serialize_items())!=maya_layout and app.world.construction.records.size()!=maya_walls,"The homes have different floor plans and furniture configurations")
 await travel("home")
 check(JSON.stringify(app.world.serialize_items())==JSON.stringify(home),"Returning preserves the player’s home exactly")
 var absent_seen:bool=false
 var returned:bool=false
 for i:int in range(800):
  app._process(.05)
  if not app.residents.present("maya"):absent_seen=true
  elif absent_seen:returned=true;break
 check(absent_seen and returned,"A walker leaves the street and returns on a later walk")
 app.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
 print("RESIDENTS_RESULT ",checks,"/",failures)
 quit(0 if failures==0 else 1)
