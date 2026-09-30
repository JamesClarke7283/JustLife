extends SceneTree
## Replays an immutable real-play checkpoint in isolated storage. The live
## controller advances ordinary clocks and walking; no saved poses are repaired.
## Default: fixed-step app._process integration; --engine-frames: actual engine
## callbacks for three game hours, with rendering when Godot is not headless.
const Library=preload("res://scripts/save_library.gd")
const Residents=preload("res://scripts/residents.gd")
var app:Node
var checks:int=0
var failures:int=0

func _initialize()->void:
 if not OS.get_environment("JUSTLIFE_DATA_DIR").is_absolute_path() or not OS.get_environment("XDG_DATA_HOME").is_absolute_path() or not OS.get_environment("JUSTLIFE_RESIDENT_CHECKPOINT").is_absolute_path():
  push_error("Use isolated absolute save/user directories and JUSTLIFE_RESIDENT_CHECKPOINT.");quit(2);return
 _run.call_deferred()

func check(ok:bool,message:String)->void:
 checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
 if not ok:failures+=1

func _run()->void:
 var source:String=OS.get_environment("JUSTLIFE_RESIDENT_CHECKPOINT")
 DirAccess.make_dir_recursive_absolute(Library.SAVE_DIR)
 var out:FileAccess=FileAccess.open(Library.SAVE_DIR.path_join("resident_recovery.json"),FileAccess.WRITE)
 out.store_buffer(FileAccess.get_file_as_bytes(source));out.close()
 app=load("res://tests/observed_resident_controller.gd").new();root.add_child(app)
 app.set_process(false);app.set_sound(false);app.load_game("resident_recovery")
 check(str(app.active_save_id)=="resident_recovery" and str(app.notice_text).begins_with("Welcome back"),"The public loader accepts the unmodified real checkpoint")
 if failures:app.queue_free();await process_frame;quit(1);return
 var initial:Dictionary={};var moved:Dictionary={};var departed:Dictionary={};var completed_at:Dictionary={}
 var began:float=float(app.household.day-1)*1440.0+app.household.minutes
 for id:String in Residents.PEOPLE:
  initial[id]=app.world.actors[id].position;moved[id]=0.0;departed[id]=false
  var state:Dictionary=app.residents.locations.home[id]
  var goal:=Vector3(8.5*float(state.direction),.16,float(app.residents.SIDEWALK_LANES[id]))
  var legal:Array=[]
  for n:int in 16:
   var to:Vector3=initial[id]+Vector3(cos(float(n)*TAU/16),0,sin(float(n)*TAU/16))*.05
   if app.traversal._step_clear(id,initial[id],to):legal.append(n)
  print("INITIAL ",id," position=",initial[id]," route_size=",app.traversal._floor_route(initial[id],goal,id).size()," clear_directions=",legal)
 app.household.set_speed(0)
 for frame:int in 5:app._process(.05)
 var paused_unchanged:bool=true
 for id:String in Residents.PEOPLE:paused_unchanged=paused_unchanged and app.world.actors[id].position==initial[id]
 check(paused_unchanged,"Loading the old crowd while paused preserves every saved position")
 app.household.set_speed(8)
 var budget_ok:bool=true;var separation_ok:bool=true;var geometry_ok:bool=true;var step_bodies_ok:bool=true;var step_count:int=0;var chord_reports:int=0
 var engine_frames:bool="--engine-frames" in OS.get_cmdline_user_args()
 var count:int=20000 if engine_frames else (300 if "--baseline" in OS.get_cmdline_user_args() else 450)
 if engine_frames:app.set_process(true)
 for frame:int in count:
  var before:Dictionary={};var visible:Dictionary={};var directions:Dictionary={}
  for id:String in Residents.PEOPLE:
   before[id]=app.world.actors[id].position;visible[id]=app.world.actors[id].visible;directions[id]=int(app.residents.locations.home[id].direction)
  app.resident_last=before.duplicate();app.resident_steps.clear();app.record_resident_steps=true
  var previous_elapsed:float=app.elapsed
  if engine_frames:await process_frame
  else:app._process(.05)
  app.record_resident_steps=false
  var actual_delta:float=app.elapsed-previous_elapsed
  for entry:Dictionary in app.resident_steps:
   step_count+=1;geometry_ok=geometry_ok and bool(entry.geometry);step_bodies_ok=step_bodies_ok and bool(entry.bodies)
   if not bool(entry.geometry) or not bool(entry.bodies):print("INVALID_ACTUAL_STEP ",entry)
  for id:String in Residents.PEOPLE:
   var actor:Node3D=app.world.actors[id]
   var step:float=actor.position.distance_to(before[id]);moved[id]+=step
   budget_ok=budget_ok and step<=LifePedestrianPace.distance("adult",actual_delta,8)+.00002
   if not app.world.lot_navigation.segment_clear(0,before[id],actor.position) and chord_reports<3:
    chord_reports+=1
    print("FRAME_CHORD ",id," from=",before[id]," to=",actor.position," delta=",actual_delta," route=",app.residents.sidewalk_routes.get(id,{})," actual_steps=",app.resident_steps.filter(func(entry:Dictionary)->bool:return str(entry.id)==id))
   var goal:=Vector3(8.5*float(directions[id]),.16,float(app.residents.SIDEWALK_LANES[id]))
   if visible[id] and str(app.residents.locations.home[id].phase)=="home" and actor.position.distance_to(goal)<.00001 and int(app.residents.locations.home[id].direction)==-int(directions[id]):
    departed[id]=true
    if not completed_at.has(id):completed_at[id]=float(app.household.day-1)*1440.0+app.household.minutes-began

   for other:String in Residents.PEOPLE:
    if other<=id or not visible[id] or not visible[other] or not actor.visible or not app.world.actors[other].visible:continue
    var old:float=before[id].distance_to(before[other]);var current:float=actor.position.distance_to(app.world.actors[other].position)
    separation_ok=separation_ok and current>=minf(old,LifeTraversal.BODY_GAP)-.00001
  if frame%100==0:print("PROGRESS frame=",frame," completed_at=",completed_at)
  if not engine_frames and frame%100==0:await process_frame
  if engine_frames and float(app.household.day-1)*1440.0+app.household.minutes-began>=180.0:break
 app.set_process(false)
 print("REPLAY elapsed_game_minutes=",float(app.household.day-1)*1440.0+app.household.minutes-began," engine_frames=",engine_frames)
 check(budget_ok,"Every neighbor stays within the ordinary walking speed budget")
 check(step_count>0,"Synchronous transform notifications captured actual walking substeps")
 check(geometry_ok,"Every actual movement substep remains on unobstructed navigation geometry")
 check(step_bodies_ok,"Every actual movement substep respects swept body and reservation clearance")
 check(separation_ok,"Existing body overlaps only separate, and no new overlaps occur")
 for id:String in Residents.PEOPLE:
  print("RECOVERY ",id," moved=",moved[id]," departed=",departed[id]," first_crossing_game_minutes=",completed_at.get(id,-1)," position=",app.world.actors[id].position)
  check(float(moved[id])>.75 and bool(departed[id]) and float(completed_at.get(id,INF))<180.0,id+" physically leaves the saved crowd and completes the sidewalk crossing")
 if "--baseline" not in OS.get_cmdline_user_args():
  _check_emergence();_check_first_leg()
 app.queue_free();await process_frame;await process_frame
 print("RESIDENT_RECOVERY checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)

## Controlled visibility cases after the untouched checkpoint replay. These
## fixture positions/times are test setup, never part of gameplay recovery.
func _check_emergence()->void:
 for actor:Node3D in app.world.actors.values():actor.visible=false
 app.household.day=1;app.sim.day=1
 var blocker:Node3D=app.player;blocker.visible=true
 for id:String in ["priya","tom"]:
  var actor:Node3D=app.world.actors[id]
  var state:Dictionary=app.residents.locations.home[id]
  actor.position=Vector3(6,.16,8);blocker.position=actor.position
  state.phase="home";state.wait=9999.0;state.routine_away=id=="priya"
  var minutes:float=970.0 if id=="priya" else 430.0
  app.household.minutes=minutes;app.sim.minutes=minutes;app.household.set_speed(1)
  app.residents.tick(.05)
  check(not actor.visible and str(state.phase)=="home",id+" waits off-lot when another body occupies the routine entry point")
  blocker.position=Vector3(4,.16,8)
  app.household.set_speed(0);app.residents.tick(.05)
  check(not actor.visible and str(state.phase)=="home",id+" stays off-lot when paused even after the entry point clears")
  app.household.set_speed(1);app.residents.tick(.05)
  check(actor.visible and str(state.phase)=="walking" and not bool(state.routine_away),id+" enters normally once unpaused and the point is clear")
  actor.visible=false;state.phase="home";state.wait=9999.0

func _check_first_leg()->void:
 for actor:Node3D in app.world.actors.values():actor.visible=false
 var actor:Node3D=app.world.actors.maya;actor.position=Vector3(5.95,.16,8);actor.visible=true
 var blocker:Node3D=app.player;blocker.position=Vector3(6.1,.16,8.715);blocker.visible=true
 var from:Vector3=actor.position;var goal:=Vector3(6.25,.16,8)
 check(app.traversal._step_clear("maya",from,from+Vector3(.05,0,0)) and not app.traversal._step_clear("maya",from,from+Vector3(.08,0,0)),"The first-leg witness clears five centimetres but blocks the mover's eight-centimetre step")
 var path:PackedVector3Array=app.traversal._floor_route(from,goal,"maya")
 check(path.size()>1,"The grid can propose the tangential first leg through its start escape cells")
 var route:Dictionary={"goal":goal}
 app.residents._sidewalk_replan("maya",route,0.0)
 check(bool(route.get("detour",false)) and not route.points.is_empty(),"A blocked full first leg selects a legal make-room route instead of retrying forever")
