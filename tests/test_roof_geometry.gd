extends SceneTree
const Roof=preload("res://scripts/roof_geometry.gd")
var checks:int=0
var failures:Array[String]=[]
var records:Array=[]
func _initialize()->void:_run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func points(model:Node)->Array[Vector3]:
	var out:Array[Vector3]=[]
	for node:Node in model.find_children("*","GeometryInstance3D",true,false):
		if node is MeshInstance3D:
			for surface:int in range(node.mesh.get_surface_count()):
				for point:Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:out.append(node.global_transform*point)
		elif node is MultiMeshInstance3D:
			for instance:int in range(node.multimesh.instance_count):
				var transform:Transform3D=node.global_transform*node.multimesh.get_instance_transform(instance)
				for surface:int in range(node.multimesh.mesh.get_surface_count()):
					for point:Vector3 in node.multimesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:out.append(transform*point)
	return out
func _run()->void:
	var fixtures:Array=[{"w":8.0,"d":10.0,"pitch":.5,"rotation":0},{"w":4.0,"d":6.0,"pitch":.75,"rotation":90},{"w":3.5,"d":5.5,"pitch":.2,"rotation":0},{"w":7.5,"d":3.5,"pitch":1.0,"rotation":90}]
	for index:int in range(fixtures.size()):
		var record:Dictionary=fixtures[index].duplicate(true);record.merge({"id":"roof_%d"%index,"level":index%2,"x":.5,"z":-.5,"material":"57736a"})
		var roof:Node3D=Roof.create(record);root.add_child(roof)
		var p:Array[Vector3]=points(roof);check(p.size()>500,"Parameterized roof produces actual geometry.")
		if p.is_empty():roof.free();continue
		var bounds:=AABB(p[0],Vector3.ZERO)
		for point:Vector3 in p:bounds=bounds.expand(point)
		var expected:AABB=Roof.envelope(record)
		for axis:int in range(3):check(absf(bounds.position[axis]-expected.position[axis])<.0001 and absf(bounds.end[axis]-expected.end[axis])<.0001,"Actual full-mesh roof matches fixed eave/vertical envelope on axis%d fixture%d."%[axis,index])
		check(int(roof.get_meta("native_tile_count"))>50 and int(roof.get_meta("tile_count"))>int(roof.get_meta("native_tile_count")),"Interior uses native imported tile geometry and edge pieces are separately cropped.")
		var params:Dictionary=Roof.parameters(record)
		for name:String in ["RoofDeck_Left","RoofDeck_Right"]:
			var deck:MeshInstance3D=roof.get_node(name);var side:int=-1 if name.ends_with("Left") else 1
			var normal:=Vector3(side*params.sn,params.cs,0);var low:float=INF;var high:float=-INF
			for point:Vector3 in deck.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:low=minf(low,normal.dot(point));high=maxf(high,normal.dot(point))
			check(absf(high-low-.10)<.00005,"Parameterized deck retains true10cm normal thickness.")
			var arrays:Array=deck.mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for triangle:int in range(0,vertices.size(),3):check((vertices[triangle+2]-vertices[triangle]).cross(vertices[triangle+1]-vertices[triangle]).dot(normals[triangle])>0,"Generated deck winding matches its actual outward front normal.")
		for end:int in [-1,1]:
			var gable:MeshInstance3D=roof.get_node("GableInfill_%d"%end);var low:float=INF;var high:float=-INF
			for point:Vector3 in gable.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:low=minf(low,point.y);high=maxf(high,point.y)
			check(absf(low)<.00001 and absf(high-params.height)<.00001,"Full triangular gable closes wall top to ridge at actual dimensions.")
		var ridge:Vector3=(roof.get_node("RidgeEnd").global_position-roof.get_node("RidgeStart").global_position).normalized()
		check(ridge.distance_to(Vector3.BACK if int(record.rotation)==0 else Vector3.RIGHT)<.00001,"Record rotation applies once to the actual generated ridge.")
		records.append({"fixture":record,"mesh_vertices":p.size(),"native_tiles":roof.get_meta("native_tile_count"),"total_tiles":roof.get_meta("tile_count"),"actual_min":[bounds.position.x,bounds.position.y,bounds.position.z],"actual_max":[bounds.end.x,bounds.end.y,bounds.end.z]});roof.free()
	var file:=FileAccess.open("user://roof_geometry.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"  "));file.close();print("ROOF_GEOMETRY checks=%d failures=%d"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
