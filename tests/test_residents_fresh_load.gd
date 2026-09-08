extends SceneTree
var app:Node
var checks:int=0
var failures:int=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
 checks+=1
 print("PASS " if ok else "FAIL ",message)
 if not ok:failures+=1
func equal_values(a:Variant,b:Variant)->bool:
 if (a is float or a is int) and (b is float or b is int):return float(a)==float(b)
 if a is Dictionary and b is Dictionary:
  if a.size()!=b.size():return false
  for key:Variant in a:
   if not b.has(key) or not equal_values(a[key],b[key]):return false
  return true
 if a is Array and b is Array:
  if a.size()!=b.size():return false
  for index:int in range(a.size()):
   if not equal_values(a[index],b[index]):return false
  return true
 return a==b
func run()->void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():push_error("Set JUSTLIFE_DATA_DIR to an isolated test folder.");quit(2);return
 var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://resident_expected.json"))
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false)
 app.load_game(str(expected.slot));app.set_sound(false);await process_frame
 check(app.current_venue=="maya_home","A fresh process loads the named friend-home save")
 check(app.residents.present("maya") and not app.residents.present("leo"),"Fresh load restores resident presence")
 check(equal_values(app.residents.snapshot(),expected.residents),"Fresh load restores exact resident location and route phase")
 check(is_equal_approx(float(app.sim.relationships.maya.friendship),float(expected.friendship)),"Earned friendship survives a fresh process")
 check(JSON.stringify(app.home_layout)==JSON.stringify(expected.home),"The player’s own furnished home survives the away save")
 check(app.residents.can_visit("maya"),"The known friend remains visitable")
 var actor:LifeActor=app.world.actors.maya
 app.queue_interaction({"id":"maya","kind":"neighbor","node":actor,"size":Vector2(.6,.6)},"friendly")
 check(not app.sim.action_queue.is_empty() and str(app.sim.get_current_action().target_id)=="maya","The restored resident can be approached socially")
 app.queue_free();await process_frame;await process_frame
 print("RESIDENTS_FRESH_RESULT ",checks,"/",failures);quit(0 if failures==0 else 1)
