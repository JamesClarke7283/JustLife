extends SceneTree
## First actual-frame gait study: isolated fixture, not public controller traversal.
var space:Node3D
var camera:Camera3D
var failures:Array[String]=[]
var frames:int=0
var max_contact_error:float=0
var max_support_error:float=0
var evidence:Array=[]
var violations:Dictionary={}
const OUT="user://regression/stair_motion/"

func _initialize()->void:run.call_deferred()
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,900)
	space=Node3D.new();root.add_child(space);stage()
	var pack:PackedScene=load("res://assets/models/juniper_stair.glb")
	var stair:Node3D=pack.instantiate();space.add_child(stair);stair.position.y=.16
	for mesh:MeshInstance3D in stair.find_children("*","MeshInstance3D",true,false):mesh.create_trimesh_collision()
	await physics_frame;await physics_frame
	for age:String in ["young_adult","child"]:
		var actor:=LifeActor.new();space.add_child(actor)
		actor.configure({"name":"Stair study "+age,"age_stage":age,"frame":0,"outfit":0,"hair":0,"body_scale":1.0,"height_scale":1.0})
		actor.voice_enabled=false
		print("SOLE_GEOMETRY ",age," ",actor._leg_rest.L.sole_size)
		for direction:int in [1,-1]:
			var plan:Dictionary=LifeStairGait.plan(stair.global_transform,direction,actor.stair_rear_extent(direction))
			var distance:float=0
			var captured:bool=false
			while distance<float(plan.length):
				await process_frame
				var delta:float=minf(.05,root.get_process_delta_time())
				distance=minf(float(plan.length),distance+delta*LifeStairGait.SPEED)
				var sample:Dictionary=LifeStairGait.sample(plan,distance)
				actor.position=sample.root;actor.rotation.y=sample.yaw
				actor.present_stair(sample);actor.animate(delta,1,true,"")
				frames+=1
				measure(actor,sample,age,direction)
				if not captured and distance>float(plan.length)*.49:
					captured=true
					camera.position=Vector3(5,3,1.85);camera.look_at(actor.position+Vector3(0,.9,0));camera.size=3.5
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUT+age+("_up" if direction==1 else "_down")+".png")
					camera.position=actor.position+Vector3(.65,.80,-1.8)
					camera.look_at(actor.position+Vector3(0,.38,0));camera.size=1.65
					await process_frame;await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUT+age+("_up_feet" if direction==1 else "_down_feet")+".png")
			# Same-distance zero-time reconstruction must leave joints and sole transforms exact.
			var sample:Dictionary=LifeStairGait.sample(plan,distance*.53)
			actor.position=sample.root;actor.rotation.y=sample.yaw;actor.present_stair(sample);actor.animate(1.0/60,1,true,"")
			var feet:Dictionary={"L":actor._leg_rest.L.shoe.global_transform,"R":actor._leg_rest.R.shoe.global_transform}
			var before:float=actor._time
			actor.present_stair(sample,true)
			if actor._time!=before or not feet.L.is_equal_approx(actor._leg_rest.L.shoe.global_transform) or not feet.R.is_equal_approx(actor._leg_rest.R.shoe.global_transform):failures.append(age+" reconstruction changed time or shoe pose")
		actor.queue_free();await process_frame
	var f:=FileAccess.open(OUT+"motion.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"frames":frames,"max_contact_error":max_contact_error,"max_support_error":max_support_error,"failures":failures,"samples":evidence,"violation_counts":violations,"scope":"Actual-frame isolated adult/child ascent/descent; imported real soles/treads, deterministic zero-time pose. No controller routing/FIFO/cancel/save/public game evidence."},"  "));f.close()
	space.queue_free();await process_frame
	print("STAIR_MOTION frames=%d contact_error=%.6f support_error=%.6f failures=%d"%[frames,max_contact_error,max_support_error,failures.size()])
	quit(0 if failures.is_empty() else 1)

func measure(actor:LifeActor,sample:Dictionary,age:String,direction:int)->void:
	for side:String in actor._leg_rest:
		var rest:Dictionary=actor._leg_rest[side]
		var minimum:Vector3=Vector3.INF;var maximum:Vector3=-Vector3.INF
		for mesh:MeshInstance3D in rest.shoe.find_children("Shoes_Sole*","MeshInstance3D",true,false):
			for corner:int in range(8):
				var p:Vector3=mesh.to_global(mesh.get_aabb().get_endpoint(corner));minimum=minimum.min(p);maximum=maximum.max(p)
		var center:=Vector3((minimum.x+maximum.x)*.5,minimum.y,(minimum.z+maximum.z)*.5)
		var target:Vector3=sample.feet[side]+Basis(Vector3.UP,sample.yaw)*Vector3(rest.foot.x*actor.visual.scale.x,0,0)
		var error:float=center.distance_to(target);max_contact_error=maxf(max_contact_error,error)
		if error>.006:violation("target",age,direction,"%s direction%d phase%.3f %s sole target error%.5f"%[age,direction,sample.phase,side,error])
		if bool(sample.planted[side]):
			var ray:=PhysicsRayQueryParameters3D.create(center+Vector3.UP*.05,center-Vector3.UP*.25)
			var hit:Dictionary=space.get_world_3d().direct_space_state.intersect_ray(ray)
			var gap:float=absf(center.y-hit.position.y) if not hit.is_empty() else 1
			max_support_error=maxf(max_support_error,gap)
			if gap>.008:violation("support",age,direction,"%s direction%d phase%.3f %s real surface support gap%.5f"%[age,direction,sample.phase,side,gap])
		if frames%30==0:evidence.append({"age":age,"direction":direction,"phase":sample.phase,"side":side,"planted":sample.planted[side],"target_error":error,"center":[center.x,center.y,center.z]})

func box(at:Vector3,size:Vector3,color:String)->void:
	var mesh:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=size
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(color);mat.roughness=.8
	mesh.mesh=shape;mesh.material_override=mat;space.add_child(mesh);mesh.position=at;mesh.create_trimesh_collision()

func stage()->void:
	camera=Camera3D.new();space.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true
	camera.position=Vector3(6,5,-5);camera.look_at(Vector3(0,1.9,2));camera.size=7
	var we:=WorldEnvironment.new();var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR;environment.background_color=Color("cddfd6")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("e4ede4");environment.ambient_light_energy=.35
	environment.tonemap_mode=Environment.TONE_MAPPER_REINHARDT;we.environment=environment;space.add_child(we)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-52,-35,0);sun.light_color=Color("fff0d7");sun.light_energy=.8;sun.shadow_enabled=true;space.add_child(sun)
	box(Vector3(0,.12,1.5),Vector3(8,.08,9),"d8d9cf")
	box(Vector3(0,3.08,4.4),Vector3(3,.16,1.3),"efe9da")


func violation(kind:String,age:String,direction:int,message:String)->void:
	var key:String=age+":"+str(direction)+":"+kind
	violations[key]=int(violations.get(key,0))+1
	if failures.size()<20:failures.append(message)
