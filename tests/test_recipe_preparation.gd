extends SceneTree
## Directed art/contact study. Actual imported stove, actor and recipe props; no public meal-flow claim.
var app:Node
var checks:int=0
var failures:Array[String]=[]
var samples:Array=[]
var metrics:Dictionary={}
var screenshots:bool=true
const CASES=[['garden_skillet',.25,'garden_stir'],['herb_pasta',.25,'pasta_fold'],['herb_pasta',.55,'pasta_season'],['harvest_bake',.30,'bake_season'],['harvest_bake',.80,'bake_ready']]
func _initialize()->void:call_deferred('run')
func check(ok:bool,msg:String)->void:
 checks+=1
 if not ok:failures.append(msg);push_error(msg)
func frames(n:int)->void:
 for i:int in range(n):await process_frame
func run()->void:
 screenshots=not '--metrics-only' in OS.get_cmdline_user_args()
 DirAccess.make_dir_recursive_absolute('user://recipe_preparation')
 app=load('res://scenes/main.tscn').instantiate();root.add_child(app);current_scene=app;await frames(4)
 app.set_process(false);app.set_sound(false)
 app.household_profiles=[{'name':'Mara Vale','age_stage':'adult','frame':0,'hair':1,'outfit':0,'top_color':'7396a9','bottom_color':'e0d5bd','skin_color':'d9a17d','hair_color':'54382a'}]
 app.start_household();app.set_process(false);await frames(3)
 app.setup_live([{'id':'stove','kind':'stove','x':0,'z':0,'rotation':0},{'id':'counter','kind':'counter','x':1.2,'z':0,'rotation':0}]);await frames(3)
 app.ui.hide();app.overlay.hide();app.world.set_process(false)
 for id:String in app.world.actors:
  app.world.actors[id].set_selected(false);app.world.actors[id].voice_enabled=false
  if id!='player':app.world.actors[id].hide()
 var a:LifeActor=app.world.actors.player
 var stove:Dictionary=app._find_item('stove')
 app.world.camera_target=Vector3(0,1.05,.70);app.world.camera.size=2.8;app.world.camera_angle=-1.1;app.world.camera_elevation=.36;app.world.update_camera()
 var variants:Array=[[0,1.0,1.0]] if screenshots else [[0,1.0,1.0],[0,.85,.93],[1,1.15,1.08]]
 for variant:Array in variants:
  for c:Array in CASES:
   a.configure(app.household_profiles[0].merged({'low_detail':true,'frame':variant[0],'body_scale':variant[1],'height_scale':variant[2]},true));a.voice_enabled=false;a.set_selected(false)
   var anchor:Dictionary=app.world.activity_anchor(stove,'cook',a.get_body_landmarks())
   a.position=anchor.position;a.rotation.y=anchor.yaw;a.set_activity_anchor(anchor.position,anchor.yaw,anchor.kind,'cook',anchor)
   a.cooking_presentation={'recipe':c[0],'progress':c[1]}
   var root_before:Transform3D=a.transform
   var m:Dictionary={'spoon_food_error':0.0,'spoon_radius':0.0,'spoon_grip_angle':0.0,'support_gap':0.0,'tray_level':1.0,'jar_food_axis_angle':0.0,'hand_contact_error':0.0,'stove_forearm_clearance':INF,'dish_stove_clearance':INF}
   metrics[c[2]+'_'+str(variant)]=m
   for i:int in range(300):
    a.animate(1.0/60.0,1.0,false,'cook')
    if i>120 and i%6==0:sample(a,c[2],m)
    if i==155 and screenshots:
     await capture(c[2])
     if c[2]=='bake_ready':
      app.world.camera_angle=-2.25;app.world.camera_elevation=.5;app.world.update_camera();await capture('bake_ready_front')
      app.world.camera_angle=-1.1;app.world.camera_elevation=.36;app.world.update_camera()
   check(a.transform.is_equal_approx(root_before),c[2]+': navigation root unchanged')
   check(m.stove_forearm_clearance>=-.003,c[2]+': padded forearms clear the actual stove top')
   check(m.dish_stove_clearance>=-.003,c[2]+': actual dish underside clears stove top')
   if c[0]=='garden_skillet':check(m.spoon_radius<.12,c[2]+': spoon stays inside original bowl rim')
   if c[2]=='pasta_fold':
    check(m.spoon_food_error<.035,c[2]+': spoon follows actual food surface within35mm')
    check(m.spoon_grip_angle<8.0,c[2]+': utensil stays in finger channel')
   if 'season' in c[2]:
    check(a._seasoning_jar.visible and not a._cooking_spoon.visible,c[2]+': shaker replaces spoon')
    check(m.jar_food_axis_angle<12.0,c[2]+': shaker mouth points at actual food')
   if c[0]=='harvest_bake':
    check(a._baking_tray.visible and not a._cooking_bowl.visible,c[2]+': original oven dish is visible')
    check(m.tray_level>.999,c[2]+': full-size oven dish stays level')
    check(m.hand_contact_error<.025,c[2]+': supporting palm reaches underside or real handles')
   var hand_before:Transform3D=a._joints.Forearm_R.global_transform
   var tray_before:Transform3D=a._baking_tray.global_transform
   var clock_before:float=a._action_time
   a.animate(.5,0.0,true,'')
   check(a._action_time==clock_before and a._joints.Forearm_R.global_transform.is_equal_approx(hand_before) and a._baking_tray.global_transform.is_equal_approx(tray_before),c[2]+': pause freezes recipe pose and props')
   for i:int in range(90):a.animate(1.0/60.0,1,true,'')
   check(not a._cooking_bowl.visible and not a._seasoning_jar.visible and not a._baking_tray.visible,c[2]+': preparation props clear on departure')
 transition_check(a)
 for value:Variant in [null,{},'unknown',42]:
  a.cooking_presentation={'recipe':value,'progress':NAN};check(a._cooking_recipe()=='garden_skillet' and a._cooking_progress()==0,'malformed visual metadata safely uses default')
 var file:=FileAccess.open('user://recipe_preparation/'+('render_report.json' if screenshots else 'contact_report.json'),FileAccess.WRITE)
 file.store_string(JSON.stringify({'checks':checks,'failures':failures,'metrics':finite_json(metrics),'samples':samples,'method':'Directed actual actor animation at60Hz; actual stove/props; no public flow claim. Null clearance means segment or point lies wholly outside stove footprint, not measured vertical separation.'},'\t'));file.close()
 app.queue_free();await frames(4)
 print('RECIPE_PREPARATION %d checks, %d failures'%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
func sample(a:LifeActor,name:String,m:Dictionary)->void:
 var palm_l:Vector3=a._joints.Forearm_L.to_global(a._grip_offset('L'))
 var palm_r:Vector3=a._joints.Forearm_R.to_global(a._grip_offset('R'))
 var food:Vector3=a._model.to_global(a._recipe_food_point())
 for side:String in ['L','R']:
  var elbow:Vector3=a._joints['Forearm_'+side].global_position
  var palm:Vector3=a._joints['Forearm_'+side].to_global(a._grip_offset(side))
  m.stove_forearm_clearance=minf(m.stove_forearm_clearance,stove_clearance(elbow,palm,.032))
 if a._baking_tray.visible:m.dish_stove_clearance=minf(m.dish_stove_clearance,stove_clearance(a._baking_tray.global_position,a._baking_tray.global_position,0))
 elif a._cooking_bowl.visible:
  var base:Vector3=a._recipe_bowl.global_position if a._presented_cooking_recipe=='herb_pasta' and is_instance_valid(a._recipe_bowl) else a._bowl_center.to_global(Vector3(0,-.098,0))
  m.dish_stove_clearance=minf(m.dish_stove_clearance,stove_clearance(base,base,0))
 if a._cooking_spoon.visible:
  var point:Vector3=a._spoon_tip.global_position
  var in_bowl:Vector3=a._bowl_center.to_local(point)
  m.spoon_radius=maxf(m.spoon_radius,Vector2(in_bowl.x,in_bowl.z).length())
  m.spoon_food_error=maxf(m.spoon_food_error,point.distance_to(a._model.to_global(a._preparation_tip)))
  var direction:Vector3=(point-a._cooking_spoon.global_position).normalized()
  m.spoon_grip_angle=maxf(m.spoon_grip_angle,rad_to_deg(acos(clampf(absf(a._joints.Forearm_R.global_basis.x.normalized().dot(direction)),0,1))))
 if a._seasoning_jar.visible:
  var jar_axis:Vector3=a._seasoning_jar.global_basis.y.normalized()
  var to_food:Vector3=(food-a._seasoning_jar.global_position).normalized()
  m.jar_food_axis_angle=maxf(m.jar_food_axis_angle,rad_to_deg(jar_axis.angle_to(to_food)))
 if a._baking_tray.visible:
  m.tray_level=minf(m.tray_level,a._baking_tray.global_basis.y.normalized().dot(Vector3.UP))
  var wanted_l:Vector3=a._baking_tray.to_global(Vector3(-.105,-.004,0)) if a._is_seasoning() else a._baking_tray.find_child('GripLeft',true,false).global_position
  m.hand_contact_error=maxf(m.hand_contact_error,palm_l.distance_to(wanted_l))
  if not a._is_seasoning():m.hand_contact_error=maxf(m.hand_contact_error,palm_r.distance_to(a._baking_tray.find_child('GripRight',true,false).global_position))
 samples.append({'case':name,'time':a._action_time,'food':vec(food),'palm_left':vec(palm_l),'palm_right':vec(palm_r),'spoon':vec(a._spoon_tip.global_position),'shaker_mouth':vec(a._seasoning_jar.get_node('SprinkleMouth').global_position)})
func capture(name:String)->void:
 await frames(4);await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png('user://recipe_preparation/'+name+'.png')==OK,'saved '+name)
func vec(v:Vector3)->Array:return [v.x,v.y,v.z]

func stove_clearance(a:Vector3,b:Vector3,radius:float)->float:
 var stove:Node3D=app._find_item('stove').node
 a=stove.to_local(a);b=stove.to_local(b)
 var extent:Vector2=Vector2(.51,.385)
 var top:float=-INF
 for mesh:MeshInstance3D in stove.find_children('*','MeshInstance3D',true,false):
  if not str(mesh.name).begins_with('Cooktop') and not str(mesh.name).begins_with('Burner'):continue
  for i:int in range(8):top=maxf(top,stove.to_local(mesh.to_global(mesh.get_aabb().get_endpoint(i))).y)
 var first:float=0.0;var last:float=1.0
 for axis:int in [0,2]:
  var edge:float=(extent.x if axis==0 else extent.y)+radius
  var d:float=b[axis]-a[axis]
  if absf(d)<.000001:
   if absf(a[axis])>edge:return INF
  else:
   var lo:float=(-edge-a[axis])/d;var hi:float=(edge-a[axis])/d
   first=maxf(first,minf(lo,hi));last=minf(last,maxf(lo,hi))
 if first>last:return INF
 return minf(a.lerp(b,first).y,a.lerp(b,last).y)-top-radius

func transition_check(a:LifeActor)->void:
 for recipe:String in ['herb_pasta','harvest_bake']:
  a.cooking_presentation={'recipe':recipe,'progress':.46 if recipe=='herb_pasta' else .60}
  for i:int in range(90):a.animate(1.0/60.0,1,false,'cook')
  var last:Vector3=a._joints.Forearm_R.to_global(a._grip_offset('R'))
  var maximum:float=0
  a.cooking_presentation.progress=.54 if recipe=='herb_pasta' else .70
  for i:int in range(60):
   a.animate(1.0/60.0,1,false,'cook')
   var hand:Vector3=a._joints.Forearm_R.to_global(a._grip_offset('R'))
   maximum=maxf(maximum,last.distance_to(hand));last=hand
  check(maximum<.085,recipe+': progress transition keeps hand movement below85mm per60Hz step')

func finite_json(value:Variant)->Variant:
 if value is float:return value if is_finite(value) else null
 if value is Dictionary:
  var result:Dictionary={}
  for key:Variant in value:result[key]=finite_json(value[key])
  return result
 if value is Array:
  var result:Array=[]
  for item:Variant in value:result.append(finite_json(item))
  return result
 return value
