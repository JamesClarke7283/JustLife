extends Node3D
class_name LifeConstruction
## Editable axis-aligned rooms, walls and door openings on the household lot.

var world: Node3D
var records: Array = []
var floor_records: Array = []
var wall_nodes: Dictionary = {}
var floor_nodes: Array = []
var tool: String = ""
var anchored: bool = false
var anchor: Vector3 = Vector3.ZERO
var preview: Node3D
var proposal: Dictionary = {}
var valid: bool = false
var cutaway: bool = true

func initialize(owner_world: Node3D) -> void:
	world=owner_world

func add_wall(entry: Dictionary) -> void:
	var e=entry.duplicate(true)
	if not e.has("id"):e["id"]="wall_%d_%d" % [Time.get_ticks_usec(),records.size()]
	if not e.has("color"):e["color"]="eae7d7"
	if not e.has("cut"):e["cut"]=true
	if not e.has("height"):e["height"]=2.6
	var node=Node3D.new()
	add_child(node)
	node.position=Vector3(float(e.x),.16,float(e.z))
	var h:float=.65 if bool(e.cut) and cutaway else float(e.height)
	world.box(node,Vector3(0,h/2,0),Vector3(float(e.w),h,float(e.d)),str(e.color))
	world.box(node,Vector3(0,h+.025,0),Vector3(float(e.w)+.025,.05,float(e.d)+.025),"f5efdf")
	world.box(node,Vector3(0,.055,0),Vector3(float(e.w)+.015,.11,float(e.d)+.015),"f5efdf")
	records.append(e)
	wall_nodes[e.id]=node

func add_floor(entry: Dictionary) -> void:
	var e=entry.duplicate(true)
	var node=world.box(self,Vector3(float(e.x),.125,float(e.z)),Vector3(float(e.w),.075,float(e.d)),str(e.get("color","cfa97e")))
	floor_records.append(e)
	floor_nodes.append(node)

func remove_wall(id: String) -> void:
	if wall_nodes.has(id):
		wall_nodes[id].queue_free()
		wall_nodes.erase(id)
	for i in range(records.size()-1,-1,-1):
		if records[i].id==id:records.remove_at(i)

func snapshot() -> Dictionary:
	return {"kind":"__construction","walls":records.duplicate(true),"floors":floor_records.duplicate(true)}

func restore(data: Dictionary) -> void:
	for n in wall_nodes.values():n.queue_free()
	for n in floor_nodes:
		if is_instance_valid(n):n.queue_free()
	wall_nodes.clear();floor_nodes.clear();records.clear();floor_records.clear()
	for e in data.get("walls",[]):
		if valid_record(e):add_wall(e)
	for e in data.get("floors",[]):
		if valid_record(e):add_floor(e)

func valid_record(e: Variant) -> bool:
	if not e is Dictionary:return false
	for key in ["x","z","w","d"]:
		if not e.has(key) or not (e[key] is float or e[key] is int):return false
	return absf(float(e.x))<9 and absf(float(e.z))<8 and float(e.w)>0 and float(e.d)>0 and float(e.w)<=18 and float(e.d)<=16

func update_cutaway(value: bool) -> void:
	cutaway=value
	var data=snapshot()
	restore(data)

func point_blocked(p: Vector2) -> bool:
	for e in records:
		if wall_rect(e).grow(.15).has_point(p):return true
	return false

func rect_blocked(r: Rect2) -> bool:
	for e in records:
		if wall_rect(e).grow(.03).intersects(r):return true
	return false

func wall_rect(e: Dictionary) -> Rect2:
	return Rect2(Vector2(float(e.x)-float(e.w)/2,float(e.z)-float(e.d)/2),Vector2(float(e.w),float(e.d)))

func floor_contains(p: Vector2) -> bool:
	if Rect2(-5.87,-4.87,11.74,9.74).has_point(p):return true
	for e in floor_records:
		if wall_rect(e).grow(-.13).has_point(p):return true
	return false

func begin(name: String) -> void:
	cancel()
	tool=name
	preview=Node3D.new()
	add_child(preview)

func cancel() -> void:
	tool="";anchored=false;proposal.clear()
	if is_instance_valid(preview):preview.queue_free()
	preview=null

func snap(p: Vector3) -> Vector3:
	return Vector3(clampf(snappedf(p.x,.5),-8,8),.16,clampf(snappedf(p.z,.5),-6.5,7))

func update_preview(p: Vector3) -> void:
	if tool.is_empty() or not is_instance_valid(preview):return
	for n in preview.get_children():n.queue_free()
	var point=snap(p)
	proposal=make_proposal(point)
	valid=not proposal.is_empty() and bool(proposal.get("valid",false))
	var color:Color=Color(.36,.74,.56,.55) if valid else Color(.86,.29,.24,.45)
	var preview_mat=StandardMaterial3D.new()
	preview_mat.albedo_color=color
	preview_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	if not anchored and tool in ["wall","room"]:
		var marker=world.box(preview,point+Vector3(0,.04,0),Vector3(.32,.08,.32),"397e70")
		marker.material_override=preview_mat
	for e in proposal.get("walls",[]):
		var mesh=world.box(preview,Vector3(e.x,.7,e.z),Vector3(e.w,1.08,e.d),"397e70")
		mesh.material_override=preview_mat
	if proposal.has("remove_id"):
		for e in records:
			if e.id==proposal.remove_id:
				var mesh=world.box(preview,Vector3(e.x,.7,e.z),Vector3(e.w+.04,1.10,e.d+.04),"397e70")
				mesh.material_override=preview_mat
	for e in proposal.get("floors",[]):
		var mesh=world.box(preview,Vector3(e.x,.18,e.z),Vector3(e.w,.03,e.d),"397e70")
		mesh.material_override=preview_mat

func click(p: Vector3) -> Dictionary:
	if tool.is_empty():return {}
	if tool in ["wall","room"] and not anchored:
		anchor=snap(p);anchored=true;return {}
	var data=make_proposal(snap(p))
	if data.is_empty() or not bool(data.get("valid",false)):return {"error":"That construction overlaps a furnishing, wall, or the edge of the lot."}
	return data

func make_proposal(p: Vector3) -> Dictionary:
	if tool in ["door","erase"]:
		var nearest:Dictionary={}
		var best:float=.55
		for e in records:
			var r=wall_rect(e)
			var q=Vector2(clampf(p.x,r.position.x,r.end.x),clampf(p.z,r.position.y,r.end.y))
			var distance=q.distance_to(Vector2(p.x,p.z))
			if distance<best:best=distance;nearest=e
		if nearest.is_empty():return {}
		if tool=="erase":return {"op":"erase","remove_id":nearest.id,"walls":[],"cost":-int(maxf(nearest.w,nearest.d)*20),"valid":true}
		var horizontal:bool=float(nearest.w)>float(nearest.d)
		var length:float=maxf(nearest.w,nearest.d)
		if length<1.55:return {}
		var center:float=float(nearest.x) if horizontal else float(nearest.z)
		var door_center:float=clampf(p.x if horizontal else p.z,center-length/2+.65,center+length/2-.65)
		var split:Array=[]
		for side in [-1,1]:
			var a:float=center-length/2 if side==-1 else door_center+.53
			var b:float=door_center-.53 if side==-1 else center+length/2
			if b-a>.05:
				var e=nearest.duplicate(true);e.erase("id")
				if horizontal:e.x=(a+b)/2;e.w=b-a
				else:e.z=(a+b)/2;e.d=b-a
				split.append(e)
		return {"op":"door","remove_id":nearest.id,"walls":split,"cost":90,"valid":true}
	if not anchored:return {}
	var out:Array=[]
	var floors:Array=[]
	var length:float=0
	if tool=="wall":
		var horizontal:bool=absf(p.x-anchor.x)>absf(p.z-anchor.z)
		if horizontal:p.z=anchor.z
		else:p.x=anchor.x
		length=anchor.distance_to(p)
		if length<.5:return {}
		out.append({"x":(p.x+anchor.x)/2,"z":(p.z+anchor.z)/2,"w":length if horizontal else .14,"d":.14 if horizontal else length,"cut":true})
	elif tool=="room":
		var w:float=absf(p.x-anchor.x)
		var d:float=absf(p.z-anchor.z)
		if w<1.5 or d<1.5:return {}
		var cx:float=(p.x+anchor.x)/2
		var cz:float=(p.z+anchor.z)/2
		out.append({"x":cx,"z":anchor.z,"w":w,"d":.14,"cut":true})
		out.append({"x":cx,"z":p.z,"w":w,"d":.14,"cut":true})
		out.append({"x":anchor.x,"z":cz,"w":.14,"d":d,"cut":true})
		out.append({"x":p.x,"z":cz,"w":.14,"d":d,"cut":true})
		floors.append({"x":cx,"z":cz,"w":w,"d":d,"color":"cfa97e"})
		length=(w+d)*2
	var is_valid:bool=true
	for e in out:
		var r=wall_rect(e)
		for item in world.items:
			if item.kind in ["rug","painting"]:continue
			var s:Vector2=item.size
			if int(roundf(item.node.rotation_degrees.y/90))%2:s=Vector2(s.y,s.x)
			if r.intersects(Rect2(Vector2(item.node.position.x,item.node.position.z)-s/2,s)):is_valid=false
		for old in records:
			var existing=wall_rect(old)
			# Joining at endpoints is allowed; overlapping parallel walls is not.
			if existing.grow(-.03).intersects(r.grow(-.03)) and ((float(old.w)>.2)==(float(e.w)>.2)):is_valid=false
	return {"op":tool,"walls":out,"floors":floors,"cost":int(length*55+floor_area(floors)*12),"valid":is_valid}

func floor_area(entries:Array) -> float:
	var total:float=0
	for e in entries:total+=float(e.w)*float(e.d)
	return total

func commit(data: Dictionary) -> void:
	if data.has("remove_id"):remove_wall(data.remove_id)
	for e in data.get("walls",[]):add_wall(e)
	for e in data.get("floors",[]):add_floor(e)
	anchored=false
	proposal.clear()
	world.rebuild_navigation()
	refresh_decorations()

func refresh_decorations() -> void:
	for n in world.house.get_children():
		if n.has_meta("wall_decoration"):
			var supported:bool=false
			for e in records:
				if wall_rect(e).grow(.25).has_point(Vector2(n.position.x,n.position.z)):supported=true;break
			n.visible=supported
		elif n.has_meta("garden_decoration"):
			n.visible=true
			for floor:Dictionary in floor_records:
				if wall_rect(floor).grow(.15).has_point(Vector2(n.position.x,n.position.z)):n.visible=false;break
