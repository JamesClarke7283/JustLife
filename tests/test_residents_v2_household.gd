extends "res://tests/test_stair_controller.gd"
func _run()->void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty() or OS.get_environment("XDG_DATA_HOME").is_empty():push_error("Use isolated save and user-data folders.");quit(2);return
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
 _setup(8)
 var positions:Array[Vector3]=[Vector3(-2,.16,-3.5),Vector3(2,3.16,3.5),Vector3(-2,3.16,3.5),Vector3(2,3.16,-3.5),Vector3(-2,3.16,-3.5),Vector3(-3,.16,3),Vector3(3,.16,3),Vector3(-2,.16,.75)]
 for i:int in 8:app.world.actors[app.household.members[i].id].position=positions[i]
 app._store_motion();app.world.refresh_actor_layers()
 var home:Array=app.world.serialize_items().duplicate(true);var gait:Dictionary={};var grounded:Dictionary={};var minimum:float=INF
 app.travel_to("park")
 check(app.mode=="travel" and app.residents.trip.boarding.size()==8,"All eight household members receive preflighted boarding routes")
 for frame:int in 5000:
  if app.mode!="travel":break
  app._process(.05)
  if app.current_venue=="home":
   for i:int in 8:
    var id:String=str(app.household.members[i].id);var a:LifeActor=app.world.actors[id]
    if not a.stair_presentation.is_empty():gait[id]=true
    if not a.visible and app.world.point_level(a.position)==0:grounded[id]=true
    for j:int in range(i+1,8):
     var b:LifeActor=app.world.actors[app.household.members[j].id]
     if a.visible and b.visible:minimum=minf(minimum,a.position.distance_to(b.position))
  if frame%20==0:await process_frame
 check(app.current_venue=="park" and app.mode=="live","Maximum-size household completes real canonical boarding and car arrival")
 check(gait.size()==4 and grounded.size()==8,"All four upstairs Lifelets use stair gait and every member reaches the ground before boarding")
 check(minimum>=LifeTraversal.BODY_GAP-.001,"Canonical boarding retains physical body separation throughout all eight routes: "+str(minimum))
 check(app.household.members.size()==8 and app.world.actors.size()==12 and app.world.actors.values().filter(func(a:LifeActor):return a.visible).size()==12,"Destination retains the eight-member household and the four public-venue residents")
 check(app.home_layout==home,"Maximum household travel retains its canonical two-floor home records")
 var file:=FileAccess.open("user://resident_v2_household.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"gait":gait.keys(),"boarded_ground":grounded.keys(),"minimum_separation":minimum,"venue":app.current_venue,"mode":app.mode,"routes":str(app.traversal.routes)},"  "));file.close()
 print("RESIDENT_V2_HOUSEHOLD checks=",checks," failures=",failures.size())
 app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
