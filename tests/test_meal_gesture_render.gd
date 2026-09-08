extends SceneTree
## Controlled real-render art study using full app/world, imported LOD actors and real meal anchors.
## Simulation time is held; the actual actor animation advances at fixed 60 Hz. This is not a flow/playthrough test.
var app:Node
var checks:int=0
var failures:Array[String]=[]
var samples:Array=[]
var metrics:Dictionary={}
var label:String="baseline"
var out:String
var metrics_only:bool=false
var settled:bool=false
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
 checks+=1
 if not ok:failures.append(message);push_error(message)
func frames(n:int) -> void:
 for i:int in range(n):await process_frame
func run() -> void:
 if "--revised" in OS.get_cmdline_user_args():label="revised"
 metrics_only="--metrics-only" in OS.get_cmdline_user_args()
 settled="--settled" in OS.get_cmdline_user_args()
 if settled:label="diagnostic_settled"
 if metrics_only:label+="_metrics"
 out="user://meal_gesture/"+label;DirAccess.make_dir_recursive_absolute(out)
 app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
 await frames(4);app.set_process(false);app.set_sound(false)
 app.household_profiles=[{"name":"Mara Vale","age_stage":"adult","frame":0,"hair":1,"top_color":"7396a9","skin_color":"d9a17d","hair_color":"54382a"},{"name":"Rowan Vale","age_stage":"adult","frame":1,"hair":0,"top_color":"c97c66","skin_color":"b77e58","hair_color":"352821"}]
 app.start_household();app.set_process(false);await frames(3)
 app.setup_live([{"id":"table","kind":"dining","x":0,"z":0,"rotation":0},{"id":"near","kind":"chair","x":0,"z":1.0,"rotation":180},{"id":"far","kind":"chair","x":0,"z":-1.0,"rotation":0}])
 app.ui.hide();app.overlay.hide();app.world.set_process(false)
 for wall:Node3D in app.world.walls:wall.hide()
 for id:String in app.world.actors:
  app.world.actors[id].set_selected(false);app.world.actors[id].voice_enabled=false
  if id in ["maya","leo"]:app.world.actors[id].hide()
 await frames(3)
 # Both settings use authored tabletop and chair anchors from the production meal flow.
 await dinner("adults",0.0,false)
 await dinner("rotated_child",PI*.5,true)
 await carry()
 if metrics_only:speech_check()
 var file:=FileAccess.open(out+"/report.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"label":label,"checks":checks,"failures":failures,"metrics":metrics,"samples":samples},"\t"));file.close()
 app.queue_free();await frames(4)
 print("MEAL_GESTURE %s: %d checks, %d failures"%[label,checks,failures.size()]);quit(0 if failures.is_empty() else 1)
func dinner(name:String,yaw:float,child:bool) -> void:
 var table:Dictionary=app._find_item("table")
 table.node.rotation.y=yaw
 var turn:Basis=Basis(Vector3.UP,yaw)
 for i:int in range(2):
  var id:String="player" if i==0 else "housemate_1"
  var a:LifeActor=app.world.actors[id]
  var p:Dictionary=app.household_profiles[i].duplicate(true)
  if child and i==1:p.age_stage="child";p.frame=0;p.hair=1
  p.low_detail=true;a.configure(p);a.voice_enabled=false;a.set_selected(false)
  var chair:Dictionary=app._find_item("near" if i==0 else "far")
  chair.node.position=Vector3(0,.16,0)+turn*Vector3(0,0,1.0 if i==0 else -1.0)
  chair.node.rotation.y=yaw+(PI if i==0 else 0.0)
  a.position=chair.node.position;a.rotation.y=chair.node.rotation.y
  var anchor:Dictionary=app.meal_flow.eating_anchor(id,{"meal_seat":chair.id})
  a.set_activity_anchor(anchor.position,anchor.yaw,anchor.kind,"eat_meal",anchor)
  var plate:Node3D=load("res://assets/models/meal_plate.glb").instantiate();app.world.house.add_child(plate);plate.name="StudyPlate"+str(i)
  plate.position=anchor.plate_position;plate.rotation.y=yaw
  metrics[name+id]={"mouth_min":INF,"food_min":INF,"support_hand_low":INF,"support_hand_high":-INF,"support_elbow_min":INF,"support_elbow_max":-INF,"forearm_table_clearance":INF,"plate_support_error":absf(plate.position.y-_mesh_top(table.node)-.002)}
  check(metrics[name+id].plate_support_error<.0001,name+id+" real plate bottom matches imported tabletop plus 2 mm")
 var dish:Node3D=load("res://assets/models/meal_serving.glb").instantiate();app.world.house.add_child(dish);dish.position=table.node.to_global(Vector3(0,.847,0));dish.rotation.y=yaw
 # Clear authored permanent centerpiece exactly as the meal view synchronizer does.
 for mesh:MeshInstance3D in table.node.find_children("*","MeshInstance3D",true,false):
  if str(mesh.name).begins_with("Fruit"):mesh.hide()
 for i:int in range(348+120):
  for id:String in ["player","housemate_1"]:
   var a:LifeActor=app.world.actors[id]
   a.animate(1.0/60.0,1.0,false,"eat_meal")
   if i>=120:sample(name,id,a)
  if i==137 or i==311:
   app.world.camera_target=Vector3(0,1.0,0);app.world.camera.size=3.6;app.world.camera_angle=yaw+(.7 if i==137 else PI+.7);app.world.camera_elevation=.43;app.world.update_camera()
   await capture(name+("_bite" if i==137 else "_rest"))
 for id:String in ["player","housemate_1"]:
  var m:Dictionary=metrics[name+id]
  check(m.mouth_min<.025,name+id+" actual fork tip reaches mouth")
  check(m.food_min<.045,name+id+" actual fork tip returns to food")
  if metrics_only:
   check(m.support_elbow_max<150.0,name+id+" support elbow avoids locked extension")
   check(m.support_elbow_max-m.support_elbow_min>15.0,name+id+" free hand settles across a bite")
   check(m.forearm_table_clearance>=-.003,name+id+" padded support forearm clears table footprint")
 for node:Node in app.world.house.get_children():
  if str(node.name).begins_with("StudyPlate") or node==dish:node.queue_free()
 await frames(2)
func sample(scene_name:String,id:String,a:LifeActor) -> void:
 var plate:Vector3=a._activity_anchor.plate_position
 var mouth:Vector3=a._joints.Head.to_global(a._mouth_anchor)
 var tip:Vector3=a._meal_fork.find_child("BitePoint",true,false).global_position
 var palm:Vector3=a._joints.Forearm_L.to_global(a._grip_offset("L"))
 var shoulder:Vector3=a._joints.Arm_L.global_position
 var elbow:Vector3=a._joints.Forearm_L.global_position
 var bend:float=rad_to_deg((shoulder-elbow).angle_to(palm-elbow))
 var m:Dictionary=metrics[scene_name+id]
 m.mouth_min=minf(m.mouth_min,tip.distance_to(mouth));m.food_min=minf(m.food_min,tip.distance_to(plate+Vector3(0,.035,0)))
 m.support_hand_low=minf(m.support_hand_low,palm.y);m.support_hand_high=maxf(m.support_hand_high,palm.y)
 m.support_elbow_min=minf(m.support_elbow_min,bend);m.support_elbow_max=maxf(m.support_elbow_max,bend)
 m.forearm_table_clearance=minf(m.forearm_table_clearance,table_clearance(elbow,palm,.022 if a._model_age=="child" else .032))
 samples.append({"scene":scene_name,"id":id,"time":a._action_time,"fork":vec(tip),"mouth":vec(mouth),"plate":vec(plate),"support_palm":vec(palm),"support_elbow":vec(elbow),"support_angle_degrees":bend})
func carry() -> void:
 for id:String in ["near","far","table"]:app._find_item(id).node.hide()
 var dishes:Array=[]
 var carry_metrics:Array=[{"max_grip_error":0.0},{"max_grip_error":0.0}]
 for i:int in range(2):
  var a:LifeActor=app.world.actors["player" if i==0 else "housemate_1"]
  a.clear_activity_anchor();a.position=Vector3(-.7 if i==0 else .7,.16,0);a.rotation.y=.15
  a.meal_presentation={"carrying":true,"platter":i==0}
  var dish:Node3D=load("res://assets/models/meal_serving.glb" if i==0 else "res://assets/models/meal_plate.glb").instantiate();app.world.house.add_child(dish);dishes.append(dish)
 for f:int in range(180):
  for i:int in range(2):
   var a:LifeActor=app.world.actors["player" if i==0 else "housemate_1"]
   a.animate(1.0/60.0,1.0,true,"serve_meal");dishes[i].global_transform=a.meal_carry_transform()
   if f>60:
    for side:String in ["L","R"]:
     var palm:Vector3=a._joints["Forearm_"+side].to_global(a._grip_offset(side))
     var contact:Vector3
     if i==0:contact=dishes[i].find_child("GripLeft" if side=="L" else "GripRight",true,false).global_position
     else:contact=dishes[i].to_global(Vector3(-.12 if side=="L" else .12,.005,0))
     carry_metrics[i].max_grip_error=maxf(carry_metrics[i].max_grip_error,palm.distance_to(contact))
  if f==115:
   app.world.camera_target=Vector3(0,1.0,0);app.world.camera.size=3.3;app.world.camera_angle=.6;app.world.camera_elevation=.18;app.world.update_camera();await capture("carry_adult_child")
 for i:int in range(2):
  var a:LifeActor=app.world.actors["player" if i==0 else "housemate_1"]
  var grips:Dictionary={}
  for side:String in ["L","R"]:
   grips[side]=vec(a._joints["Forearm_"+side].to_global(a._grip_offset(side)))
  metrics["carry_"+str(i)]={"palm_world":grips,"dish_origin":vec(dishes[i].global_position),"proportion":a._proportion,"max_grip_error":carry_metrics[i].max_grip_error}
  if metrics_only:
   check(carry_metrics[i].max_grip_error<.016,"Carrier%d hands remain within16mm of actual handle/plate edge contact"%i)
   var before:Transform3D=a.meal_carry_transform();var arm_before:Transform3D=a._joints.Forearm_L.global_transform
   a.animate(.5,0.0,true,"serve_meal")
   check(a.meal_carry_transform().is_equal_approx(before) and a._joints.Forearm_L.global_transform.is_equal_approx(arm_before),"Carrier%d pause freezes hands and dish"%i)
   check(not a._meal_fork.visible,"Carrier%d does not show an eating fork"%i)
func capture(name:String) -> void:
 if metrics_only:return
 if settled and name!="adults_bite":return
 await frames(90 if settled else 2);await RenderingServer.frame_post_draw
 var image:Image=root.get_texture().get_image();check(image.save_png(out+"/"+name+".png")==OK,"render "+name+" saved")
func _mesh_top(node:Node3D) -> float:
 var top:float=-INF
 for mesh:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
  if not str(mesh.name).begins_with("Dining"):continue
  for i:int in range(8):top=maxf(top,mesh.to_global(mesh.get_aabb().get_endpoint(i)).y)
 return top
func vec(v:Vector3) -> Array:return [v.x,v.y,v.z]

func table_clearance(a:Vector3,b:Vector3,radius:float) -> float:
 var table:Node3D=app._find_item("table").node
 a=table.to_local(a);b=table.to_local(b)
 var first:float=0.0;var last:float=1.0
 for axis:int in [0,2]:
  var edge:float=(.8 if axis==0 else .56)+radius
  var direction:float=b[axis]-a[axis]
  if absf(direction)<.000001:
   if absf(a[axis])>edge:return INF
  else:
   var lo:float=(-edge-a[axis])/direction;var hi:float=(edge-a[axis])/direction
   first=maxf(first,minf(lo,hi));last=minf(last,maxf(lo,hi))
 if first>last:return INF
 return minf(a.lerp(b,first).y,a.lerp(b,last).y)-.845-radius

func speech_check() -> void:
 var a:LifeActor=app.world.actors.player
 a.speech("A little moment of joy.")
 var before:Dictionary=a.speech_presentation()
 check(not before.is_empty(),"Meal actor retains spoken-text presentation")
 a.animate(.5,0.0,true,"serve_meal")
 check(a.speech_presentation()==before,"Paused carrier retains speech lifetime")
 a.animate(4.0,1.0,true,"serve_meal")
 check(a.speech_presentation().is_empty(),"Resumed carrier speech expires normally")
