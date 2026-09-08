extends SceneTree
const Actor = preload("res://scripts/actor.gd")
var camera:Camera3D
var actor:LifeActor
var world:Node3D
var label:Label
var label_prefix:String="birthday"
func _initialize()->void:call_deferred("run")
func block(pos:Vector3,size:Vector3,color:Color)->void:
 var n:MeshInstance3D=MeshInstance3D.new();var mesh:BoxMesh=BoxMesh.new();mesh.size=size;n.mesh=mesh;n.position=pos
 var mat:StandardMaterial3D=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.8;n.material_override=mat;world.add_child(n)
func capture(action:String,seconds:float,side:bool=false)->void:
 actor.configure(actor.profile)
 actor.clear_activity_anchor()
 actor._time=0;actor._phase_offset=0
 for i:int in range(int(seconds*60.0)):
  actor.animate(1.0/60.0,1,false,action)
  await process_frame
 camera.position=Vector3(2.25,2.05,3.4) if not side else Vector3(3.8,1.9,.65)
 camera.look_at(Vector3(0,1.08,.15))
 label.text="JustLife • %s • %s%s"%[label_prefix.capitalize(),action.capitalize()," / side view" if side else ""]
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://art/%s_%s%s.png"%[label_prefix,action,"_side" if side else ""])
func run()->void:
 var args:PackedStringArray=OS.get_cmdline_user_args();if args.size()>0:label_prefix=args[0]
 world=Node3D.new();root.add_child(world)
 var env:WorldEnvironment=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("e5e3dc");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("fff7e9");env.environment.ambient_light_energy=.25;env.environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;world.add_child(env)
 var sun:DirectionalLight3D=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=.65;sun.shadow_enabled=true;world.add_child(sun)
 var fill:DirectionalLight3D=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,130,0);fill.light_energy=.22;world.add_child(fill)
 block(Vector3(0,-.055,0),Vector3(20,.10,20),Color("bfc6b5"))
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.60;world.add_child(camera);camera.current=true
 var canvas:CanvasLayer=CanvasLayer.new();root.add_child(canvas);label=Label.new();canvas.add_child(label);label.position=Vector2(28,24);label.add_theme_font_size_override("font_size",26);label.add_theme_color_override("font_color",Color("253d35"))
 actor=Actor.new();world.add_child(actor);actor.configure({"name":"Activity study","low_detail":true,"outfit":0,"hair":0,"skin_color":"c18b69","hair_color":"4c3428","top_color":"5d837f","bottom_color":"4f6262"});actor.voice_enabled=false
 await capture("birthday",2.7)
 root.get_texture().get_image().save_png("res://art/birthday_blow.png")
 await capture("birthday",3.4,true)
 root.get_texture().get_image().save_png("res://art/birthday_candles_out.png")
 await capture("birthday",4.8)
 root.get_texture().get_image().save_png("res://art/birthday_clap.png")
 print("Activity gallery saved: ",label_prefix)
 world.queue_free();canvas.queue_free();await process_frame;await create_timer(.2).timeout;quit()
