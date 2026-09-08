extends "res://tests/test_stair_food_custody.gd"
func _run()->void:
 if OS.get_environment("JUSTLIFE_DATA_DIR").is_empty() or OS.get_environment("XDG_DATA_HOME").is_empty():push_error("Use isolated save and user-data folders.");quit(2);return
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
 _food_setup()
 var wallet:int=app.household.funds
 app.meal_flow.queue_recipe("ground_stove","garden_skillet")
 var held:Dictionary={}
 for frame:int in 2200:
  _step()
  held=app.household.meals.carried_by("player")
  if not held.is_empty() and not app.traversal.busy("player"):break
 check(not held.is_empty() and not app.traversal.busy("player"),"Actual paid cooking reaches stable-floor carrying before departure")
 if not held.is_empty():
  var id:String=str(held.id);var ledger:Dictionary=app.household.meals.get_state();var journeys:Dictionary=app.traversal.snapshot()
  var error:String=preload("res://scripts/travel_food.gd").departure_error(app)
  check(error.is_empty(),"The actual carried serving dish has a supported release position: "+error)
  check(_equal(ledger,app.household.meals.get_state()) and _equal(journeys,app.traversal.snapshot()),"Release preflight preserves the exact live dish ledger, route and body")
  app.travel_to("park")
  check(app.mode=="travel" and app.household.meals.carried_by("player").is_empty(),"Departure uses normal cancellation to put the cooked meal down before boarding")
  var released:Dictionary=app.household.meals.batch(id)
  check(str(released.venue)=="home" and str(released.storage)=="surface" and str(released.owner).is_empty() and int(released.remaining)==4,"The same original meal remains at home with all four servings and no carrier")
  check(app.household.funds==wallet-25,"Departure does not refund or charge the cooked meal again")
  var position:Vector3=_food_position(released)
  check(app.world.point_level(Vector3(position.x,.16,position.z))==0 and is_finite(app.meal_flow._floor_support(Vector3(position.x,.16,position.z),LifeMeals.PLATTER_HALF_SIZE)) if str(released.host).is_empty() else not app._find_item(str(released.host)).is_empty(),"Released dish rests on supported departure-lot floor or furnishing")
  for frame:int in 2400:
   if app.mode!="travel":break
   app._process(.05)
   if frame%20==0:await process_frame
  check(app.mode=="live" and app.current_venue=="park","Household completes the car trip after safely releasing its meal")
  check(app.household.meals.batch(id).position==released.position and str(app.household.meals.batch(id).venue)=="home","Arrival retains the meal at its original home position")
 _food_setup()
 app.meal_flow.queue_recipe("ground_stove","garden_skillet")
 var admitted:bool=false
 for frame:int in 2200:
  _step()
  if str(_route("player").get("phase",""))=="transit" and float(_route("player").distance)>.6:admitted=true;break
 check(admitted,"A second actual cooked dish reaches an owned stair crossing")
 if admitted:
  var ledger:Dictionary=app.household.meals.get_state();var route:Dictionary=app.traversal.snapshot();var current:Array=app.sim.action_queue.duplicate(true)
  var id:String=str(app.household.meals.carried_by("player").id)
  app.travel_to("park")
  check(app.mode=="live" and _equal(ledger,app.household.meals.get_state()) and _equal(route,app.traversal.snapshot()) and _equal(current,app.sim.action_queue),"Travel refusal leaves actual stair food custody, route, body and queued serving unchanged")
  app.cancel_current_action()
  check(app.traversal.safety("player") and str(_route("player").custody)==id,"Normal cancellation retains the carried dish until the stair's safe landing")
  for frame:int in 2000:
   _step()
   if not app.traversal.busy("player"):break
  var released:Dictionary=app.household.meals.batch(id)
  check(not app.traversal.busy("player") and app.household.meals.carried_by("player").is_empty() and app.meal_flow._food_level(released)==1,"Existing safe-release semantics settle the same dish on the upper floor")
  var position:Array=released.position.duplicate()
  app.travel_to("park")
  for frame:int in 2400:
   if app.mode!="travel":break
   app._process(.05)
   if frame%20==0:await process_frame
  check(app.mode=="live" and app.current_venue=="park" and released.position==position and str(released.venue)=="home" and int(released.remaining)==4,"Retry descends and completes the trip while preserving the released upper-floor meal")
 var file:=FileAccess.open("user://resident_v2_food.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
 print("RESIDENT_V2_FOOD checks=",checks," failures=",failures.size())
 app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout;quit(0 if failures.is_empty() else 1)
