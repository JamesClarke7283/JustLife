extends "res://tests/test_family_ui.gd"
## One directed adult cooking scenario. The level4 setup grants cooking XP;
## cooking/serving/store/eat and fresh-process continuation use actual frames.
var expected:Dictionary={}
func _run()->void:
 screenshot_dir="res://art/recipe_playthrough";DirAccess.make_dir_recursive_absolute(screenshot_dir)
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
 await frames(4);app.set_sound(false)
 app.household.member_action_finished.connect(func(id:String,a:Dictionary):member_completed.append(id+":"+str(a.id)))
 if resume_only:
  expected=JSON.parse_string(FileAccess.get_file_as_string("user://recipe_expected.json"))
  await _public_load();await resume_cooking()
 else:
  await _enter_new_game();await _age("Adult")
  await press("Find my home",true);await press("Start living",true);await press("Ⅱ")
  app.sim.autonomy=false
  await open_cookbook()
  var pasta:Button=app.find_child("Recipe_herb_pasta",true,false)
  var bake:Button=app.find_child("Recipe_harvest_bake",true,false)
  check(is_instance_valid(pasta) and pasta.disabled and is_instance_valid(bake) and bake.disabled,"Novice cookbook visibly locks advanced dishes")
  check(app.sim.speed==0,"Cookbook preserves the prior pause")
  await screenshot("01_novice_cookbook",false,false);await press("Back to life")
  check(app.sim.speed==0 and app.sim.action_queue.is_empty(),"Cancel cookbook keeps pause and queues nothing")
  app.sim._gain_skill("cooking",450.0) # Fixture setup; natural practice progression covered by the controlled recipe tests.
  check(int(app.sim.skills.cooking.level)==4,"Fixture is a level4 cook")
  await open_cookbook();await screenshot("02_unlocked_cookbook",false,false)
  check(not app.find_child("Recipe_herb_pasta",true,false).disabled and not app.find_child("Recipe_harvest_bake",true,false).disabled,"All authored dishes open at level4")
  await press("Back to life")
  await prepare_recipe("herb_pasta",false)
  if failures.is_empty():await store_recipe("herb_pasta")
  if failures.is_empty():await prepare_recipe("harvest_bake",true)
 _write_report();app.queue_free();await frames(4)
 print("RECIPE_PLAYTHROUGH assertions=%d failures=%d resume=%s"%[assertions,failures.size(),str(resume_only)])
 quit(0 if failures.is_empty() else 1)
func open_cookbook()->void:
 var stove:Dictionary=first_item("stove")
 app.world.object_clicked.emit(stove,app.world.camera.unproject_position(stove.node.position+Vector3(0,.6,0)))
 await frames(3);await press("Cook a fresh meal",true);await frames(4)
func find_batch(recipe:String)->Dictionary:
 for batch:Dictionary in app.household.meals.batches:
  if str(batch.recipe)==recipe:return batch
 return {}
func prepare_recipe(recipe:String,save_partial:bool)->void:
 await open_cookbook()
 var money:int=app.household.funds
 await press("Cook "+str(LifeMeals.RECIPES[recipe].label).to_lower())
 check(app.sim.get_current_action().get("recipe")==recipe,"Public choice queues "+recipe)
 check(app.household.funds==money,"Recipe choice waits to charge at arrival")
 await press("▶▶▶")
 if not await wait_until(func()->bool:return active_is("cook",.1),"physical arrival for "+recipe,35):return
 await press("Ⅱ")
 check(app.household.funds==money-int(LifeMeals.RECIPES[recipe].cost),recipe+" correct ingredient payment")
 check(app.player._presented_cooking_recipe==recipe,recipe+" actual actor receives selected preparation")
 await screenshot("03_preparing_"+recipe,false,false)
 if recipe=="herb_pasta":
  await press("▶▶▶")
  if not await wait_until(func()->bool:return active_is("cook",.53),"actual pasta seasoning phase",25):return
  await press("Ⅱ");await frames(5)
  check(app.player._seasoning_jar.visible,"Real-frame pasta phase displays the seasoning jar")
  await screenshot("03b_pasta_seasoning",false,false)
 if save_partial:
  await press("▶▶▶")
  if not await wait_until(func()->bool:return active_is("cook",54.0/70.0),"bake progress exceeds original45min recipe",35):return
  await press("Ⅱ")
  check(app.player._baking_tray.visible and not app.player._seasoning_jar.visible,"Late bake preparation uses the two-hand oven-ready tray")
  expected={"funds":app.household.funds,"elapsed":app.sim.get_current_action().elapsed,"xp":app.sim.skills.cooking.xp,"food":app.household.meals.get_state()}
  await _public_save("Pasta for later, bake in progress")
  var file:=FileAccess.open("user://recipe_expected.json",FileAccess.WRITE);file.store_string(JSON.stringify(expected));file.close()
  await screenshot("04_bake_saved_in_progress",false,false)
 else:
  await press("▶▶▶")
  if not await wait_until(func()->bool:return not find_batch(recipe).is_empty() and find_batch(recipe).storage=="surface","serving "+recipe,45):return
  await press("Ⅱ");await frames(4)
  var batch:Dictionary=find_batch(recipe)
  check(int(batch.initial)==int(LifeMeals.RECIPES[recipe].servings),recipe+" correct batch size")
  var view:Node=app.meal_flow.views[str(batch.id)]
  check(view.find_child("HerbPastaServing",true,false)!=null,"Pasta serving uses its original model")
  await screenshot("05_served_"+recipe,false,false)
  await press("▶▶▶")
  await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"cook finishes any own serving",40)
  await press("Ⅱ")
func store_recipe(recipe:String)->void:
 var batch:Dictionary=find_batch(recipe);var dish:Dictionary=app._find_item(str(batch.id))
 app.world.object_clicked.emit(dish,app.world.camera.unproject_position(dish.node.position));await frames(3)
 await press("Put away leftovers");await press("▶▶▶")
 if not await wait_until(func()->bool:return find_batch(recipe).storage=="fridge","store "+recipe,35):return
 await press("Ⅱ")
func resume_cooking()->void:
 await press("Ⅱ")
 check(app.household.funds==int(expected.funds),"Named restart preserves paid ingredient balance")
 check(app.sim.get_current_action().get("recipe")=="harvest_bake","Named restart restores selected bake recipe")
 check(is_equal_approx(float(app.sim.get_current_action().elapsed),float(expected.elapsed)),"Named restart preserves bake progress beyond45minutes")
 check(JSON.parse_string(JSON.stringify(app.household.meals.get_state()))==expected.food,"Named restart preserves existing pasta leftovers exactly")
 await press("▶▶▶")
 if not await wait_until(func()->bool:return not find_batch("harvest_bake").is_empty() and find_batch("harvest_bake").storage=="surface","finish and serve the resumed bake",50):return
 await press("Ⅱ");await frames(4)
 var batch:Dictionary=find_batch("harvest_bake")
 check(int(batch.initial)==8,"Bake makes eight servings")
 check(app.household.funds==int(expected.funds),"Resumed bake charges no extra ingredients")
 check(app.meal_flow.views[str(batch.id)].find_child("HarvestBakeServing",true,false)!=null,"Bake serving uses its own original model")
 await screenshot("06_resumed_bake_served",false,false)
 await press("▶▶▶");await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"cook finishes resumed meal",40);await press("Ⅱ")
 await store_recipe("harvest_bake")
 var fridge:Dictionary=first_item("fridge")
 app.world.object_clicked.emit(fridge,app.world.camera.unproject_position(fridge.node.position));await frames(3);await press("Choose leftovers…")
 await screenshot("07_recipe_leftovers",false,false)
 check(is_instance_valid(button_matching("Herb garden pasta ·",true)) and is_instance_valid(button_matching("Harvest vegetable bake ·",true)),"Fridge lists both dishes and their own remaining portions")
 var pasta_count:int=int(find_batch("herb_pasta").remaining)
 var bake_count:int=int(find_batch("harvest_bake").remaining)
 await press("Herb garden pasta ·",true);await press("▶▶▶")
 if not await wait_until(func()->bool:return active_is("eat_meal",1.0/32.0),"eat selected pasta leftovers",40):return
 await press("Ⅱ");await frames(4)
 var plate:Dictionary=app.household.meals.portion(str(app.sim.get_current_action().meal_plate))
 check(app.household.meals.batch(str(plate.batch)).recipe=="herb_pasta","Selected leftovers retain recipe identity")
 check(int(find_batch("herb_pasta").remaining)==pasta_count-1 and int(find_batch("harvest_bake").remaining)==bake_count,"Only selected recipe loses one serving")
 check(app.meal_flow.views[str(plate.id)].find_child("HerbPastaPlate",true,false)!=null,"Individual pasta plate uses its original model")
 await screenshot("08_pasta_dining",false,false)
