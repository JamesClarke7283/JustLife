extends SceneTree
## Controlled recipe economy/progression/restart tests, not rendered gameplay.
var checks:int=0
var failures:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
 checks+=1
 if not ok:failures.append(message);push_error(message)
func fresh(level:int=1,money:int=2500,age:String="adult")->LifeSim:
 var sim:LifeSim=LifeSim.new();sim.new_household({"name":"Recipe tester","age_stage":age,"traits":[]});sim.autonomy=false;sim.skills.cooking.level=level;sim.funds=money;return sim
func advance(sim:LifeSim,minutes:float)->void:
 while minutes>.0001:
  var step:float=minf(minutes,1);sim.tick(step/LifeSim.GAME_MINUTES_PER_SECOND);minutes-=step
func json_state(sim:LifeSim)->Dictionary:return JSON.parse_string(JSON.stringify(sim._json_safe(sim.get_state())))
func run()->void:
 var beginner:LifeSim=fresh()
 check(not beginner.queue_action("cook","stove",Vector3.ZERO,"missing"),"Unknown recipe cannot enter queue")
 check(not beginner.queue_action("cook","stove",Vector3.ZERO,"herb_pasta"),"Cooking1 does not unlock pasta")
 check(not beginner.queue_action("cook","stove",Vector3.ZERO,"harvest_bake"),"Cooking1 does not unlock bake")
 check(beginner.funds==2500 and beginner.action_queue.is_empty(),"Unavailable recipes change neither money nor queue")
 check(beginner.queue_action("cook","stove"),"Legacy cook command chooses garden skillet")
 check(beginner.get_current_action().recipe=="garden_skillet","Default recipe persists explicitly")
 beginner.cancel_action()
 beginner._gain_skill("cooking",75.0)
 check(int(beginner.skills.cooking.level)==2,"Earned cooking XP reaches level2")
 check(beginner.queue_action("cook","stove",Vector3.ZERO,"herb_pasta"),"Earned level2 opens pasta")
 beginner.free()
 var child:LifeSim=fresh(10,2500,"child")
 for recipe:String in LifeMeals.RECIPES:check(not child.queue_action("cook","stove",Vector3.ZERO,recipe),"Child cannot cook "+recipe)
 child.free()
 for recipe:String in LifeMeals.RECIPES:
  var definition:Dictionary=LifeMeals.RECIPES[recipe]
  var poor:LifeSim=fresh(4,int(definition.cost)-1)
  check(not poor.queue_action("cook","stove",Vector3.ZERO,recipe),recipe+" exact ingredient cost is enforced")
  poor.free()
  var sim:LifeSim=fresh(4,int(definition.cost))
  check(sim.queue_action("cook","stove",Vector3.ZERO,recipe),recipe+" queues with exact funds")
  check(sim.funds==int(definition.cost),recipe+" queueing does not charge")
  sim.begin_current_action();sim.begin_current_action()
  check(sim.funds==0,recipe+" charges once at arrival")
  var elapsed:float=float(definition.duration)*.78
  advance(sim,elapsed)
  var state:Dictionary=json_state(sim)
  var clone:LifeSim=fresh()
  check(bool(clone.restore_state(state).ok),recipe+" partial JSON restores")
  var action:Dictionary=clone.get_current_action()
  check(str(action.get("recipe",""))==recipe and int(action.cost)==int(definition.cost),recipe+" identity and cost survive restart")
  check(is_equal_approx(float(action.elapsed),elapsed),recipe+" preserves elapsed beyond default duration")
  check(is_equal_approx(float(action.duration),float(definition.duration)) and float(action.xp)==float(definition.xp),recipe+" retains canonical time and learning")
  var finished:Array=[];clone.action_finished.connect(func(done:Dictionary):finished.append(done.id))
  clone.begin_current_action()
  check(clone.funds==0 and clone.get_current_action().get("phase")=="active",recipe+" paid zero-fund cook resumes without second charge")
  advance(clone,float(definition.duration)-elapsed)
  check(finished==["cook"] and clone.action_queue.is_empty(),recipe+" finishes once after remaining time")
  var preserve:Dictionary=clone.get_state()
  for field:String in ["recipe","cost","xp","duration","elapsed","paid"]:
   var damaged:Dictionary=state.duplicate(true)
   var corrupt:Dictionary={"recipe":"invalid","cost":0,"xp":999,"duration":1,"elapsed":999,"paid":false}
   damaged.action_queue[0][field]=corrupt[field]
   check(not bool(clone.restore_state(damaged).ok),recipe+" rejects altered "+field)
   check(clone.get_state()==preserve,recipe+" rejected "+field+" restore is atomic")
  for phase:String in ["approach","queued","bogus"]:
   var unpaid:Dictionary=state.duplicate(true);unpaid.action_queue[0].phase=phase;unpaid.action_queue[0].paid=false
   check(not bool(clone.restore_state(unpaid).ok),recipe+" partial unpaid "+phase+" cannot overwrite save")
   check(clone.get_state()==preserve,recipe+" unpaid "+phase+" rejection is atomic")
  var approaching:Dictionary=state.duplicate(true);approaching.action_queue[0].phase="approach"
  check(bool(clone.restore_state(approaching).ok),recipe+" valid paid return to stove restores")
  sim.free();clone.free()
 var queued:LifeSim=fresh(4,24)
 for want:Dictionary in queued.wants:want.complete=true # Isolate ingredient spending from the opening-want cash reward.
 check(queued.queue_action("cook","stove",Vector3.ZERO,"harvest_bake"),"First expensive dish queues")
 check(queued.queue_action("cook","stove",Vector3.ZERO,"herb_pasta"),"Later dish can wait for its ingredients")
 queued.begin_current_action();advance(queued,70)
 check(queued.funds==0,"First dish leaves no ingredient budget without unrelated opening rewards")
 queued.begin_current_action()
 check(queued.funds==0 and queued.action_queue.is_empty(),"Future dish rechecks funds after earlier spending")
 queued.free()
 var old:LifeSim=fresh();old.queue_action("cook","stove");old.begin_current_action();advance(old,12)
 var old_state:Dictionary=json_state(old);old_state.action_queue[0].erase("recipe")
 var migrated:LifeSim=fresh()
 check(bool(migrated.restore_state(old_state).ok) and migrated.get_current_action().recipe=="garden_skillet","Pre-recipe cooking save defaults to original garden dish")
 old.free();migrated.free()
 var file:FileAccess=FileAccess.open("user://recipe_tests.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));file.close()
 print("RECIPES ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
