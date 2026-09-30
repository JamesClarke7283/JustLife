extends SceneTree
var app:Node
var failures:Array[String]=[]
var checks:int=0
var captured:Dictionary={}
var biggest_hand_gap:float=0.0
class CustodyProbe:
 extends LifeStrollerFlow
 var releases:int=0
 func cleanup(_id:String,_action:Dictionary)->void:releases+=1
func custody_guard()->void:
 var flow:=CustodyProbe.new()
 var sim:=LifeSim.new()
 sim.stroller_service=flow
 var queued:Dictionary={"id":LifeOutdoorActs.ACTION_ID,"target_kind":"baby_pram"}
 sim.action_queue=[queued.duplicate(true),queued.duplicate(true)]
 sim.action_queue[0]["stroller"]={"child":"test_child"}
 sim.cancel_action(1)
 check(flow.releases==0 and sim.action_queue.size()==1,"Canceling a later queued stroller instruction preserves current passenger custody")
 sim.cancel_action()
 check(flow.releases==1,"Canceling the started stroller instruction releases custody once")
 flow.free();sim.free()
func check(ok:bool,message:String)->void:
 checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
 if not ok:failures.append(message)
func _initialize()->void:
 if not ProjectSettings.globalize_path("res://").trim_suffix("/").get_file().begins_with("justlife-") or OS.get_environment("JUSTLIFE_DATA_DIR").is_empty() or ProjectSettings.has_setting("autoload/MCPRuntimeServer"):
  printerr("Run in an isolated justlife- test project with JUSTLIFE_DATA_DIR set.");quit(2);return
 run.call_deferred()
func item(kind:String)->Dictionary:
 for entry:Dictionary in app.world.items:
  if str(entry.kind)==kind:return entry
 return {}
func step()->void:
 app._process(.1)
func frame(label:String,at:Vector3)->void:
 var output:String=OS.get_environment("STROLLER_EVIDENCE_DIR")
 if output.is_empty() or DisplayServer.get_name()=="headless":return
 app.world.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
 app.world.camera.fov=48
 app.world.camera.global_position=at+Vector3(1.9,1.35,2.2)
 app.world.camera.look_at(at+Vector3(0,.7,0))
 app.ui.visible=false
 await process_frame
 await RenderingServer.frame_post_draw
 get_root().get_texture().get_image().save_png(output+"/"+label+".png")
 app.ui.visible=true
func run()->void:
 custody_guard()
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
 await process_frame
 app.set_process(false)
 app.household_profiles=[{"name":"Ada Vale","age_stage":"young_adult","frame":0,"gender":"female"},{"name":"Ben Vale","age_stage":"adult","frame":1,"gender":"male"}]
 app.selected_lot=0;app.start_household();app.world.set_process(false)
 for member:Dictionary in app.household.members:
  member.sim.autonomy=false
  for key:String in member.sim.needs:member.sim.needs[key]=90.0
 var a:LifeSim=app.household.members[0].sim
 var b:LifeSim=app.household.members[1].sim
 var aid:String=app.household.members[0].id
 var bid:String=app.household.members[1].id
 a.romantic_partner=bid;b.romantic_partner=aid
 for pair:Array in [[a,bid],[b,aid]]:
  pair[0].relationships[pair[1]].bond="partners"
 var bed:Dictionary=item("bed")
 check(bool(a.get_action_availability(LifeBabyPlan.ACTION_ID,bed.id).available),"Awake Young Adult and Adult partners can choose Make Baby at a bed")
 b.character.age_stage="elder"
 check(not bool(a.get_action_availability(LifeBabyPlan.ACTION_ID,bed.id).available),"Elders are excluded from Make Baby")
 b.character.age_stage="adult"
 if not OS.get_cmdline_user_args().has("--stroller-only"):
  app.try_for_baby(bed)
  var bed_frames:int=0
  var on_bed:bool=false
  for n:int in 1800:
   step()
   if n%20==0:await process_frame
   if not on_bed and str(a.get_current_action().get("phase",""))=="active" and n>30:
    var adult:LifeActor=app.world.actors[aid]
    on_bed=absf(adult.visual.global_basis.orthonormalized().y.y)<.15
    if on_bed:await frame("make_baby_bed",bed.node.position)
   if n%200==0:print("BED frame ",n," phases ",a.get_current_action()," ",b.get_current_action())
   if a.action_queue.is_empty() and not app.household.pregnancy.active:break
   if not app.household.pregnancy.active:continue
   bed_frames=n;break
  check(bool(app.household.pregnancy.active),"Awake partners physically approach both bed halves and complete the cooperative beat")
  check(on_bed,"The active Make Baby beat places partners horizontally in the bed")
  print("BED elapsed frames ",bed_frames," queues ",a.get_current_action()," / ",b.get_current_action())
 for sim:LifeSim in [a,b]:
  while not sim.action_queue.is_empty():sim.cancel_action()
 app.household.pregnancy=LifeBabyPlan.fresh()
 var toilet:Dictionary=item("toilet")
 var sink:Dictionary=app.sanitation_flow.bathroom_sink(a,toilet.id)
 check(not sink.is_empty(),"A reachable bathroom sink is found")
 if not sink.is_empty():
  print("BATH sink ",sink.target_id," toilet ",toilet.id)
  a._queue_follow_up("wash_hands",toilet.id)
  check(a.get_current_action().target_id==sink.target_id,"Toilet follow-up queues the bathroom sink")
  a.cancel_action()
  app.select_household_member(0)
  app.queue_interaction(toilet,"toilet")
  var washed_in_bathroom:bool=false
  for n:int in 900:
   step()
   if n%30==0:await process_frame
   if str(a.get_current_action().get("id",""))=="wash_hands":
    washed_in_bathroom=str(a.get_current_action().target_id)==str(sink.target_id)
    break
   if a.action_queue.is_empty():break
  check(washed_in_bathroom,"Completing an actual toilet visit automatically routes to the bathroom sink")
  while not a.action_queue.is_empty():a.cancel_action()
 # Isolated real family, with baby and pram inside the home.
 var child_id:String=app.household.add_member({"name":"Kit Vale","age_stage":"baby","gender":"female","frame":0})
 var child_sim:LifeSim=app.household.member_sim(child_id);child_sim.autonomy=false
 var child_at:Vector3=app.world.nearest_clear_point(Vector3(0,.16,1),0,8)
 var child:LifeActor=app.spawn_actor(child_id,child_sim.character.duplicate(true),child_at)
 child.animate(.1,1,false,"")
 app.motion_states[child_id]=app._empty_motion()
 app.world.add_item({"id":"test_pram","kind":"baby_pram","x":1.5,"z":2.0,"rotation":0})
 app._refresh_sim_targets()
 app.select_household_member(0)
 app.queue_interaction(app._find_item("test_pram"),LifeOutdoorActs.ACTION_ID)
 check(a.get_current_action().has("stroller"),"Pram click creates a physical stroller sequence")
 var reached_street:bool=false
 var stages:Dictionary={};var walked:float=0.0;var previous:Vector3=app.world.actors[aid].position
 var paused_checked:bool=false
 var saved_id:String=""
 var saved_child_position:Vector3=Vector3.ZERO
 for n:int in 2400:
  step()
  var action:Dictionary=a.get_current_action()
  if action.has("stroller"):
   var stage:String=str(action.stroller.stage);stages[stage]=true
   var adult:LifeActor=app.world.actors[aid]
   if stage in ["walk","home"]:
    walked+=adult.position.distance_to(previous)
    if adult.position.z>7.5:reached_street=true
    if adult.position.z>7.5 and not captured.has("sidewalk"):
     captured.sidewalk=true
     await frame("sidewalk",child.visual.global_position)
    var handle:Vector3=app.stroller_flow._handle(app._find_item("test_pram"))
    for side:String in ["L","R"]:
     var forearm:Node3D=adult._joints["Forearm_"+side]
     var palm:Vector3=forearm.to_global(adult._grip_offset(side))
     var target:Vector3=handle+Basis(Vector3.UP,adult.rotation.y).x*(-.22 if side=="L" else .22)
     if adult.door_presentation.is_empty():biggest_hand_gap=maxf(biggest_hand_gap,palm.distance_to(target))
    if not paused_checked:
     var before:Transform3D=child.visual.global_transform
     var saved_time:float=float(action.stroller.time)
     app.household.set_speed(0);step();step()
     check(child.visual.global_transform.is_equal_approx(before) and float(action.stroller.time)==saved_time,"Pause freezes stroller and seated child")
     var encoded:Dictionary=a._json_safe(a.get_state())
     check(LifeStrollerFlow.save_error(encoded.action_queue[0]).is_empty(),"Stroller state serializes and validates mid-route")
     var saved:bool=app.save_game("", "Stroller paused test")
     if not saved:print("SAVE ERROR ",LifeSaveLibrary._validate_household(app.household.get_state(app.world.serialize_items())))
     check(saved,"Full game saves safely during a stroller route")
     saved_id=app.active_save_id;saved_child_position=child.visual.global_position
     app.household.set_speed(1);paused_checked=true
   if not captured.has(stage) and stage in ["pickup","buckle","walk","home"]:
    if stage not in ["pickup","buckle"] or float(action.stroller.time)>.8:
     captured[stage]=true
     await frame(stage,child.visual.global_position)
   previous=adult.position
  if n%30==0:await process_frame
  if n%300==0:print("STROLLER frame ",n," stage ",action.get("stroller",{})," pos ",app.world.actors[aid].position)
  if action.is_empty():break
 check(stages.has("pickup") and stages.has("carry") and stages.has("buckle") and stages.has("walk") and stages.has("home") and stages.has("put_down"),"Pram runs pickup, carry, buckle, neighborhood, return and put-down stages")
 check(reached_street,"Stroller leaves the house and reaches the neighborhood sidewalk")
 check(walked>15.0,"Pram travels a real neighborhood route: %.2f m" % walked)
 check(walked>0.0 and biggest_hand_gap<.07,"Both hands contact the actual pram handle, max %.4f m" % biggest_hand_gap)
 check(a.action_queue.is_empty() and app.stroller_flow.views.is_empty() and child.visible and child.visual.get_parent()==child,"Completed walk restores child and releases stroller custody")
 if not saved_id.is_empty():
  app.load_game(saved_id)
  a=app.household.member_sim(aid);child=app.world.actors[child_id]
  check(a.get_current_action().has("stroller") and app.household.speed==0,"Full game reload restores the paused stroller stage")
  check(child.visual.global_position.distance_to(saved_child_position)<.03,"Reload reconstructs the same seated child without restarting pickup")
  app.household.set_speed(1);app._bind_member(aid)
  app.cancel_current_action()
  check(bool(a.get_current_action().get("stroller",{}).get("cancelled",false)),"Cancel starts a physical return instead of abandoning the passenger")
  for n:int in 1800:
   step()
   if n%30==0:await process_frame
   if a.action_queue.is_empty():break
  check(a.action_queue.is_empty() and app.stroller_flow.views.is_empty() and child.visual.get_parent()==child,"Canceled restored walk returns and releases the child safely")
 app.world.remove_item("test_pram")
 app.world.add_item({"id":"test_pushchair","kind":"pushchair","x":1.5,"z":2.0,"rotation":0})
 app._refresh_sim_targets();app.select_household_member(0)
 app.queue_interaction(app._find_item("test_pushchair"),LifeOutdoorActs.ACTION_ID)
 var push_seated:bool=false
 for n:int in 900:
  step()
  if n%30==0:await process_frame
  if str(a.get_current_action().get("stroller",{}).get("stage",""))=="walk":
   var contact:Vector3=child.visual.to_global(Vector3(0,child._hip_height,0))
   var seat:Vector3=app.stroller_flow._seat(app._find_item("test_pushchair"))
   push_seated=contact.distance_to(seat)<.03
   await frame("pushchair",child.visual.global_position)
   break
  if a.action_queue.is_empty():break
 check(push_seated,"Pushchair seats the real child on its authored cushion")
 app.cancel_current_action()
 for n:int in 900:
  step()
  if n%30==0:await process_frame
  if a.action_queue.is_empty():break
 check(a.action_queue.is_empty() and app.stroller_flow.views.is_empty(),"Pushchair cancel releases its passenger and handles")
 print("LIFELET_INTERACTIONS ",checks," checks, ",failures.size()," failures; stages ",stages)
 app.queue_free();await process_frame
 quit(0 if failures.is_empty() else 1)
