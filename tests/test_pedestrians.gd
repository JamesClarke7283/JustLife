extends SceneTree
var app:Node
var checks:int=0
var failures:int=0
var observations:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
 checks+=1;print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func exclude(node:Node)->void:
 node.set_process_input(false);node.set_process_unhandled_input(false);node.set_process_unhandled_key_input(false);node.set_process_shortcut_input(false)
 if node is LifeWorld:node.set_process(false)
 for child:Node in node.get_children():exclude(child)
func step()->void:
 # Controlled resident component: normal simulation clock, stationary household.
 app.household.tick(.05);app.residents.tick(.05)
func gap()->float:
 var result:float=INF;var ids:Array=app.world.actors.keys()
 for a:int in range(ids.size()):
  var first:LifeActor=app.world.actors[ids[a]]
  if not first.visible:continue
  for b:int in range(a+1,ids.size()):
   var second:LifeActor=app.world.actors[ids[b]]
   if second.visible and absf(first.position.y-second.position.y)<.1:result=minf(result,first.position.distance_to(second.position))
 return result
func record(id:String,point:Vector3,phase:String,wait:float,direction:int)->void:
 var actor:LifeActor=app.world.actors[id];actor.position=point
 var state:Dictionary=app.residents.locations.home[id]
 state.position=[point.x,point.y,point.z];state.phase=phase;state.wait=wait;state.direction=direction
 app.world.set_actor_away(id,phase=="home",phase=="home")
func flow(speed:int)->void:
 app.household.set_speed(speed)
 var minimum:float=gap();var visible:Dictionary={"maya":app.residents.present("maya"),"leo":app.residents.present("leo")}
 var appeared:Dictionary={"maya":0,"leo":0};var left:Dictionary={"maya":0,"leo":0};var swept_ok:bool=true;var speed_ok:bool=true
 # Walkers rest 48-72 game minutes at home between passes and normal speed runs one game
 # minute per real second, so three hundred game minutes are needed to see two cycles each.
 for index:int in range(ceili(300.0/(float(speed)*.05))):
  var before:Dictionary={}
  for id:String in ["maya","leo"]:before[id]=app.world.actors[id].position
  step();minimum=minf(minimum,gap())
  for id:String in ["maya","leo"]:
   var present:bool=app.residents.present(id);var actor:LifeActor=app.world.actors[id]
   if present and not bool(visible[id]):appeared[id]+=1
   if not present and bool(visible[id]):left[id]+=1
   if bool(visible[id]):
    speed_ok=speed_ok and actor.position.distance_to(before[id])<=.05*speed*1.1+.00001
    swept_ok=swept_ok and app.world.lot_navigation.segment_clear(0,before[id],actor.position)
   visible[id]=present
  if index%10==0:await process_frame
 check(minimum>=.72-.000001,"Every visible pair retains the .72m body gap at speed "+str(speed))
 check(speed_ok,"Walkers respect their distance budget at speed "+str(speed))
 check(swept_ok,"Each walking step has supported unobstructed floor at speed "+str(speed))
 check(int(left.maya)>=2 and int(left.leo)>=2 and int(appeared.maya)>=2 and int(appeared.leo)>=2,"Both walkers leave and return repeatedly at speed "+str(speed))
 app.household.set_speed(0)
 var paused:String=JSON.stringify({"residents":app.residents.snapshot(),"day":app.household.day,"minutes":app.household.minutes})
 for index:int in range(20):step()
 check(JSON.stringify({"residents":app.residents.snapshot(),"day":app.household.day,"minutes":app.household.minutes})==paused,"Pause preserves exact resident facts and clock")
 observations={"minimum_visible_gap":minimum,"left":left,"appeared":appeared,"speed":speed}
func obstacle()->void:
 record("leo",Vector3(8.25,.16,8.65),"home",999999,-1)
 app.player.position=Vector3(0,.16,8.0);app.household.set_speed(1)
 var minimum:float=gap();var moved_off_lane:bool=false;var completed:bool=false;var max_step:float=0
 for index:int in range(1100):
  var before:Vector3=app.world.actors.maya.position;step()
  minimum=minf(minimum,gap());max_step=maxf(max_step,app.world.actors.maya.position.distance_to(before))
  moved_off_lane=moved_off_lane or absf(app.world.actors.maya.position.z-8.0)>.1
  if not app.residents.present("maya"):completed=true;break
  if index%10==0:await process_frame
 check(minimum>=.72-.000001,"A stationary household body is never crossed")
 check(completed and moved_off_lane,"The pedestrian walks a real detour around the stationary body and reaches the exit")
 check(max_step<=.055+.00001,"A blocked-route detour never teleports")
 observations={"minimum_visible_gap":minimum,"completed":completed,"left_lane":moved_off_lane,"max_step":max_step}
func endpoint()->void:
 record("maya",Vector3(8.5,.16,8.0),"home",0,-1)
 record("leo",Vector3(8.25,.16,8.65),"home",999999,-1)
 app.player.position=Vector3(8.5,.16,8.0);app.household.set_speed(1)
 for index:int in range(20):step()
 check(not app.residents.present("maya"),"A returning resident stays hidden while another body occupies the appearance point")
 check(app.world.actors.maya.position==Vector3(8.5,.16,8.0),"Blocked appearance preserves the stored body position")
 app.player.position=Vector3(0,.16,0)
 for index:int in range(40):step()
 check(app.residents.present("maya") and app.world.actors.maya.position.x<7.0,"Clearing the appearance point admits the resident and walking resumes")
 check(gap()>=.72-.000001,"Admitted appearance maintains physical separation")
func legacy()->void:
 record("maya",Vector3(-2,.16,8.25),"walking",0,1)
 record("leo",Vector3(2,.16,8.65),"walking",0,-1)
 app.household.set_speed(0)
 var before:Dictionary=app.residents.snapshot()
 check(app.save_game("","Controlled legacy sidewalk positions"),"Public save accepts the old supported lane positions")
 var slot:String=app.active_save_id;app.load_game(slot);await process_frame
 check(app.residents.snapshot()==before,"Public load preserves every resident fact and old physical position exactly while paused")
 app.household.set_speed(1)
 var minimum:float=gap();var maximum_step:float=0
 for index:int in range(500):
  var positions:Dictionary={"maya":app.world.actors.maya.position,"leo":app.world.actors.leo.position}
  step();minimum=minf(minimum,gap())
  for id:String in ["maya","leo"]:maximum_step=maxf(maximum_step,app.world.actors[id].position.distance_to(positions[id]))
  if index%10==0:await process_frame
 check(minimum>=.72-.000001,"Walkers loaded on the old lanes remain physically separated")
 check(maximum_step<=.055+.00001,"Old lane positions join the new route on foot without snapping")
 observations={"slot":slot,"minimum_visible_gap":minimum,"max_step":maximum_step,"provenance":"Explicit controlled legacy positions; public save/load"}
func run()->void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():quit(2);return
 root.gui_disable_input=true;node_added.connect(exclude)
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);exclude(root)
 app.start_household();app.set_sound(false);exclude(root)
 for member:Dictionary in app.household.members:member.sim.autonomy=false
 await process_frame
 var scenario:String=OS.get_cmdline_user_args()[0]
 if scenario.begins_with("flow"):await flow(int(scenario.trim_prefix("flow")))
 elif scenario=="obstacle":await obstacle()
 elif scenario=="endpoint":endpoint()
 elif scenario=="legacy":await legacy()
 var report:Dictionary={"scenario":scenario,"checks":checks,"failures":failures,"observations":observations,"scope":"Controlled resident-component tick with ordinary household clock; no full household playthrough or native input claim"}
 FileAccess.open("user://pedestrians_"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
 app.queue_free();await process_frame;await create_timer(.2).timeout;await process_frame
 print("PEDESTRIANS_RESULT ",checks,"/",failures);quit(0 if failures==0 else 1)
