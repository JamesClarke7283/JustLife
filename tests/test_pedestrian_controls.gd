extends "res://tests/test_pedestrians.gd"
class CountingTraversal extends LifeTraversal:
 var searches:Array=[]
 func _floor_route(from:Vector3,to:Vector3,id:String="")->PackedVector3Array:
  searches.append(float(app.household.day-1)*1440+app.household.minutes)
  return super._floor_route(from,to,id)
func overlap()->void:
 record("maya",Vector3(0,.16,8.25),"walking",0,1)
 record("leo",Vector3(0,.16,8.65),"walking",0,-1)
 app.household.set_speed(0);var before:Dictionary=app.residents.snapshot();var initial:float=gap()
 check(initial<.72,"Declared legacy fixture starts overlapped; no frame-zero gap pass is claimed")
 check(app.save_game("","Controlled overlapped legacy residents"),"A controlled old overlapping save can be written")
 var slot:String=app.active_save_id;app.load_game(slot);await process_frame
 check(before==app.residents.snapshot(),"Paused load preserves every legacy resident fact without a corrective teleport")
 app.household.set_speed(1);var prior:float=gap();var monotonic:bool=true;var separated:bool=false;var post_minimum:float=INF
 for index:int in range(200):
  step();var current:float=gap()
  if not separated:monotonic=monotonic and current>=prior;separated=current>=.72
  if separated:post_minimum=minf(post_minimum,current)
  prior=current
  if index%10==0:await process_frame
 check(monotonic,"Initially overlapping bodies never move closer while separating")
 check(separated and post_minimum>=.72-.000001,"Legacy overlap resolves by walking and remains separated")
 observations={"initial_gap":initial,"post_separation_minimum":post_minimum,"slot":slot,"controlled_initial_overlap":true}
func generation_retry()->void:
 record("maya",Vector3(6,.16,8.0),"walking",0,1)
 record("leo",Vector3(8.25,.16,8.65),"home",999999,-1)
 app.player.position=Vector3(8.5,.16,8.0);app.household.set_speed(1)
 app.traversal=CountingTraversal.new(app)
 var minimum:float=gap()
 for index:int in range(160):step();minimum=minf(minimum,gap())
 var searches:Array=app.traversal.searches.duplicate();var bounded:bool=true
 for index:int in range(1,searches.size()):bounded=bounded and float(searches[index])-float(searches[index-1])>=3.0
 check(searches.size()>=3 and bounded,"Occupied goal retries are at least three game minutes apart")
 var before:Vector3=app.world.actors.maya.position;var old_generation:int=app.world.lot_navigation.generation
 app.world.rebuild_navigation()
 check(app.world.lot_navigation.generation>old_generation,"A real layout-navigation rebuild changes generation")
 step()
 check(int(app.residents.sidewalk_routes.maya.generation)==app.world.lot_navigation.generation,"The old sidewalk path is invalidated at the new generation")
 check(app.world.actors.maya.position==before,"A still-blocked rebuilt path preserves the real body")
 app.player.position=Vector3(0,.16,0)
 var exited:bool=false
 for index:int in range(150):
  step();minimum=minf(minimum,gap())
  if not app.residents.present("maya"):exited=true;break
 check(exited,"Removing the goal blocker allows the next bounded retry to finish the walk")
 check(minimum>=.72-.000001,"Blocked, rebuilt, and released movement retains body clearance")
 observations={"search_times_before_rebuild":searches,"minimum_visible_gap":minimum,"explicit_navigation_rebuild":true}
func guest_cache()->void:
 app.household.set_speed(3);step()
 check(app.residents.sidewalk_routes.has("maya"),"An ordinary sidewalk route exists before invitation")
 app.sim.relationships.maya.friendship=30
 check(app.residents.home_visit.invite("maya"),"A declared established-friend fixture uses the real invitation controller")
 step()
 check(not app.residents.sidewalk_routes.has("maya"),"Guest ownership clears the earlier sidewalk cursor")
 app.residents.home_visit.goodbye("Controlled guest departure")
 var left:bool=false;var returned:bool=false;var minimum:float=gap()
 for index:int in range(1000):
  step();minimum=minf(minimum,gap())
  if not app.residents.home_visit.active() and not app.residents.present("maya"):left=true
  if left and app.residents.present("maya"):
   returned=true
   for next_step:int in range(12):step();minimum=minf(minimum,gap())
   break
  if index%10==0:await process_frame
 check(left and returned,"Guest physically exits, waits at home, then returns as a pedestrian")
 check(app.residents.sidewalk_routes.has("maya") and app.world.actors.maya.position.z==8.0,"Returned guest builds a fresh sidewalk route from the actual exit")
 check(minimum>=.72-.000001,"Exercised home-guest and sidewalk bodies remain separated")
 observations={"minimum_visible_gap":minimum,"controlled_friendship":30,"real_invite_goodbye_and_exit":true}
func run()->void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():quit(2);return
 root.gui_disable_input=true;node_added.connect(exclude)
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);exclude(root)
 app.start_household();app.set_sound(false);exclude(root)
 for member:Dictionary in app.household.members:member.sim.autonomy=false
 await process_frame
 var scenario:String=OS.get_cmdline_user_args()[0]
 if scenario=="overlap":await overlap()
 elif scenario=="generation_retry":generation_retry()
 elif scenario=="guest_cache":await guest_cache()
 FileAccess.open("user://pedestrians_"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify({"scenario":scenario,"checks":checks,"failures":failures,"observations":observations,"scope":"Controlled component; explicit fixture placements/prior friendship and passive route-query instrumentation, ordinary clock and real movement"},"\t",true,true))
 app.queue_free();await process_frame;await create_timer(.2).timeout;await process_frame
 print("PEDESTRIANS_EXTRA_RESULT ",checks,"/",failures);quit(0 if failures==0 else 1)
