extends SceneTree
var checks:int=0
var failures:Array[String]=[]
var report:Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(value:bool,detail:String) -> void:
	checks+=1
	if not value:failures.append(detail);push_error(detail)
func bounds(node:Node3D) -> AABB:
	var result:AABB;var first:bool=true
	for part:MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		var current:AABB=part.global_transform*part.get_aabb()
		result=current if first else result.merge(current);first=false
	return result
func xyz(v:Vector3) -> Array:return [v.x,v.y,v.z]
func run() -> void:
	for recipe:String in ["herb_pasta","harvest_bake"]:
		for size:String in ["serving","plate"]:
			var id:String=recipe+"_"+size
			var packed:PackedScene=load("res://assets/models/meal_"+id+".glb")
			check(packed!=null,id+" imports as a PackedScene")
			if packed==null:continue
			var model:Node3D=packed.instantiate();root.add_child(model)
			var box:AABB=bounds(model)
			check(box.position.is_finite() and box.size.is_finite(),id+" bounds are finite")
			check(absf(box.position.y)<.0001,id+" actual underside is Godot Y=0")
			check(box.size.x<=(.50 if size=="serving" else .30)+.0001,id+" stays within serving/plate width")
			check(box.size.z<=(.335 if size=="serving" else .30)+.0001,id+" stays within serving/plate depth")
			var food:Node3D=model.find_child("Food",true,false)
			var dish:MeshInstance3D=model.find_child("DishGeometry",true,false)
			check(food!=null and dish!=null,id+" exposes named Food and DishGeometry")
			if food!=null and dish!=null:
				check(not food.is_ancestor_of(dish),id+" ceramic is outside Food subtree")
				var before:Transform3D=dish.global_transform;food.scale.y=.05;food.hide()
				check(dish.is_visible_in_tree() and dish.global_transform==before,id+" consumption leaves ceramic intact")
			var meshes:int=0;var surfaces:int=0;var triangles:int=0
			for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				meshes+=1;surfaces+=mesh.mesh.get_surface_count()
				for index:int in range(mesh.mesh.get_surface_count()):triangles+=mesh.mesh.surface_get_array_index_len(index)/3
			check(meshes==2 and surfaces<=16,id+" is batched into two meshes with bounded materials")
			if size=="serving":
				for side:String in ["Left","Right"]:
					var marker:Node3D=model.find_child("Grip"+side,true,false)
					check(marker!=null and marker.global_position.distance_to(Vector3(-.2395 if side=="Left" else .2395,.046,0))<.0001,id+" preserves "+side+" carrying grip")
			else:
				var marker:Node3D=model.find_child("Grip",true,false)
				check(marker!=null and marker.global_position.distance_to(Vector3(0,.009,0))<.0001,id+" preserves plate grip")
			report[id]={"bounds_min":xyz(box.position),"bounds_size":xyz(box.size),"food_pivot":xyz(food.global_position) if food else [],"meshes":meshes,"surfaces":surfaces,"triangles":triangles}
			model.free()
	report.checks=checks;report.failures=failures
	DirAccess.make_dir_recursive_absolute("res://art/recipes/studio")
	var file:FileAccess=FileAccess.open("res://art/recipes/studio/godot_import_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("RECIPE_IMPORT "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
