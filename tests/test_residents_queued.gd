extends SceneTree
var app:Node
var assertions:int=0
var failures:int=0
var completions:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
 assertions+=1;print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func run()->void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty():push_error("Set JUSTLIFE_DATA_DIR to an isolated test folder.");quit(2);return
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
 if "--consume-absent" in OS.get_cmdline_user_args():await consume()
 else:await produce()
 app.queue_free();await process_frame;await process_frame;await create_timer(.15).timeout
 print("RESIDENTS_QUEUED_RESULT ",assertions,"/",failures);quit(0 if failures==0 else 1)
func produce()->void:
 app.start_household()
 for member:Dictionary in app.household.members:member.sim.autonomy=false
 await process_frame
 var shelf:Dictionary={};var plant:Dictionary={}
 for item:Dictionary in app.world.items:
  if item.kind=="bookshelf":shelf=item
  if item.kind=="plant":plant=item
 for i:int in range(4):app.queue_interaction(shelf,"read")
 app.queue_interaction({"id":"maya","kind":"neighbor","node":app.world.actors.maya,"size":Vector2(.6,.6)},"friendly")
 app.queue_interaction(plant,"water")
 for i:int in range(800):
  app._process(.05)
  if i%10==0:await process_frame
  if not app.residents.present("maya"):break
 check(not app.residents.present("maya"),"Maya leaves naturally while earlier activities are queued")
 check(app.sim.action_queue.any(func(a:Dictionary):return str(a.id)=="friendly"),"The deferred conversation is still queued before its turn")
 var before:int=app.sim.action_queue.size()
 app.queue_interaction({"id":"maya","kind":"neighbor","node":app.world.actors.maya,"size":Vector2(.6,.6)},"friendly")
 check(app.sim.action_queue.size()==before,"An immediate interaction cannot target an absent resident")
 check(app.save_game("","Queued conversation while neighbor away"),"An ordinary named save is produced during resident absence")
 var expected:Dictionary={"slot":app.active_save_id,"wallet":app.household.funds,"friendship":app.sim.relationships.maya.friendship,"charisma":app.sim.skills.charisma.xp,"queue":app.sim.action_queue.map(func(a:Dictionary):return {"id":str(a.id),"target":str(a.target_id)})}
 FileAccess.open("user://absent_resident_expected.json",FileAccess.WRITE).store_string(JSON.stringify(expected))
 app.household.member_action_finished.connect(func(_id:String,action:Dictionary):completions.append(str(action.id)))
 while not app.sim.action_queue.is_empty() and str(app.sim.get_current_action().id)=="read":app.cancel_current_action()
 check(app.residents._speaker("maya").is_empty(),"An absent resident is never held while cancellation is pending")
 await process_frame;await process_frame
 check(not app.sim.action_queue.any(func(a:Dictionary):return str(a.id)=="friendly"),"An absent conversation is removed when it reaches the front")
 check(not app.sim.action_queue.is_empty() and str(app.sim.get_current_action().id)=="water","The later instruction remains and starts normally")
 check(app.path.size()>0 and str(app.pending_action.get("id",""))=="water","Cancellation preserves the later action’s own route")
 check(float(app.sim.relationships.maya.friendship)==float(expected.friendship) and float(app.sim.skills.charisma.xp)==float(expected.charisma),"The absent conversation gives no friendship or charisma effects")
 check(app.household.funds==int(expected.wallet),"Canceling the absent conversation has no charge")
 await finish_queue()
 check(completions==["water"],"Only the subsequent real activity completes")
 check(not app.residents.can_visit("maya"),"The absent conversation cannot unlock a home visit")
func consume()->void:
 var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://absent_resident_expected.json"))
 app.load_game(str(expected.slot));await process_frame
 check(app.has_active_game and not app.residents.present("maya"),"A fresh process restores the named save during resident absence")
 var remaining:Array=expected.queue.filter(func(a:Dictionary):return str(a.id)!="friendly")
 var actual:Array=app.sim.action_queue.map(func(a:Dictionary):return {"id":str(a.id),"target":str(a.target_id)})
 check(actual==remaining,"Fresh load removes only the unavailable social target and preserves other queued instructions")
 check(app.household.funds==int(expected.wallet) and float(app.sim.relationships.maya.friendship)==float(expected.friendship),"Fresh load preserves wallet and friendship")
 app.household.member_action_finished.connect(func(_id:String,action:Dictionary):completions.append(str(action.id)))
 await finish_queue()
 check(not completions.has("friendly") and completions.has("water"),"Fresh-load continuation completes later work without a remote conversation")
 check(float(app.sim.relationships.maya.friendship)==float(expected.friendship) and float(app.sim.skills.charisma.xp)==float(expected.charisma),"Fresh continuation never grants absent social rewards")
func finish_queue()->void:
 var remote_active:bool=false
 for i:int in range(2200):
  app._process(.05)
  if i%10==0:await process_frame
  var action:Dictionary=app.sim.get_current_action()
  if str(action.get("id",""))=="friendly" and str(action.get("phase",""))=="active" and not app.residents.present("maya"):remote_active=true
  if action.is_empty():break
 check(not remote_active,"No social activity becomes active with a hidden resident")
 check(app.sim.action_queue.is_empty(),"The remaining queue completes without hanging")
