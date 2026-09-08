extends "res://tests/test_stair_motion.gd"
## Dense pose sampling of actual rigid shoes, independently of frame-rate motion.
func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1280,900)
	space=Node3D.new();root.add_child(space);stage()
	var fixture:=Node3D.new();space.add_child(fixture)
	for mesh:Node in space.get_children():
		if mesh is MeshInstance3D and mesh.position.y>2.9:mesh.reparent(fixture,true)
	var stair:Node3D=load("res://assets/models/juniper_stair.glb").instantiate();fixture.add_child(stair);stair.position.y=.16
	for mesh:MeshInstance3D in stair.find_children("*","MeshInstance3D",true,false):mesh.create_trimesh_collision()
	await physics_frame;await physics_frame
	var totals:Dictionary={};var examples:Array=[];var samples:int=0;var positive:bool=false
	var cases:Array=[]
	for angle:int in [0,90]:
		for variant:Dictionary in [{"age":"young_adult","frame":0,"body":1.0,"height":1.0},{"age":"child","frame":0,"body":1.0,"height":1.0},{"age":"elder","frame":1,"body":1.15,"height":1.08},{"age":"teen","frame":0,"body":.85,"height":.93}]:
			var spec:Dictionary=variant.duplicate();spec["angle"]=angle;cases.append(spec)
	for spec:Dictionary in cases:
		var age:String=str(spec.age)
		fixture.rotation_degrees.y=int(spec.angle)
		await physics_frame;await physics_frame
		var actor:=LifeActor.new();space.add_child(actor)
		actor.configure({"name":"Shoe clearance "+age,"age_stage":age,"frame":spec.frame,"outfit":0,"hair":0,"body_scale":spec.body,"height_scale":spec.height});actor.voice_enabled=false
		var shapes:Array=[]
		for side:String in actor._leg_rest:
			for mesh:MeshInstance3D in actor._leg_rest[side].shoe.find_children("*","MeshInstance3D",true,false):
				var hull:ConvexPolygonShape3D=mesh.mesh.create_convex_shape(true,false)
				var vertices:PackedVector3Array=hull.points
				var scale:Vector3=mesh.global_basis.get_scale()
				for i:int in vertices.size():vertices[i]*=scale
				hull.points=vertices
				shapes.append({"side":side,"mesh":mesh,"shape":hull})
		for direction:int in [1,-1]:
			var plan:Dictionary=LifeStairGait.plan(stair.global_transform,direction,actor.stair_rear_extent(direction))
			for index:int in range(1141):
				var sample:Dictionary=LifeStairGait.sample(plan,float(plan.length)*index/1140)
				actor.position=sample.root;actor.rotation.y=sample.yaw;actor.present_stair(sample,true)
				samples+=1
				for entry:Dictionary in shapes:
					var query:=PhysicsShapeQueryParameters3D.new();query.shape=entry.shape;query.margin=0
					# Query transforms must not carry unsupported nonuniform body scale.
					# Bake the actual mesh scale into unique hull vertices above.
					query.transform=Transform3D(entry.mesh.global_basis.orthonormalized(),entry.mesh.global_position)
					# One millimetre vertical contact skin removes intended floor tangency.
					query.transform.origin.y+=.001
					var hits:Array=space.get_world_3d().direct_space_state.intersect_shape(query)
					if not positive and age=="young_adult" and direction==1 and index==0:
						query.transform.origin.y-=.05
						positive=not space.get_world_3d().direct_space_state.intersect_shape(query).is_empty()
					if hits.is_empty():continue
					var key:String=age+":"+str(spec.angle)+":"+str(direction)+":"+str(entry.mesh.name)
					totals[key]=int(totals.get(key,0))+1
					if totals[key]<=2:
						var bodies:Array=[]
						for hit:Dictionary in hits:bodies.append(str(hit.collider.get_parent().name))
						examples.append({"age":age,"angle":spec.angle,"direction":direction,"phase":sample.phase,"mesh":str(entry.mesh.name),"planted":sample.planted[entry.side],"hit":bodies})
					if examples.size()==1:
						camera.position=Vector3(5,3,1.85);camera.look_at(actor.position+Vector3(0,.7,0));camera.size=2.6
						await process_frame;await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(OUT+"first_shoe_collision.png")
		actor.queue_free();await process_frame
	var f:=FileAccess.open(OUT+"shoe_collision.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"pose_samples":samples,"collisions":totals,"examples":examples,"positive_control":positive,"contact_skin_m":.001,"scope":"1141 deterministic poses per adult/child/broad-tall-elder/short-teen direction at0/90degrees, real convex hulls of each rigid shoe part vs actual stair/floor triangles. Discrete dense sampling, not continuous sweep or clothing/body clearance."},"  "));f.close()
	space.queue_free();await process_frame
	print("STAIR_SHOE_COLLISION samples=%d collision_groups=%d positive=%s"%[samples,totals.size(),positive])
	quit(0 if totals.is_empty() and positive else 1)
