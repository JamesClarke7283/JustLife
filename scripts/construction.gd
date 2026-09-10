extends Node3D
class_name LifeConstruction
const Building=preload("res://scripts/building_state.gd")
const Roof=preload("res://scripts/roof_geometry.gd")
const WindowGeometry=preload("res://scripts/window_geometry.gd")
const WoodFloorShader=preload("res://assets/shaders/wood_floor.gdshader")
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
var building_state:Dictionary={}
var stair_nodes:Dictionary={}
var guard_nodes:Dictionary={}
var roof_nodes:Dictionary={}
var roofs_visible:bool=false
var roof_pitch:float=.5
var roof_material:String="57736a"
var roof_edit_id:String=""
var build_level:int=0
var last_error:String=""
var quote_provider:Callable
var _preview_signature:String=""
var _wood_floor_materials:Dictionary={}

func initialize(owner_world: Node3D) -> void:
	world=owner_world
	cutaway=bool(world.cutaway)

func add_wall(entry: Dictionary) -> void:
	var e=entry.duplicate(true)
	if not e.has("id"):e["id"]="wall_%d_%d" % [Time.get_ticks_usec(),records.size()]
	if not e.has("color"):e["color"]="eae7d7"
	if not e.has("cut"):e["cut"]=true
	if not e.has("height"):e["height"]=2.6
	var node=Node3D.new()
	add_child(node)
	var level:int=int(e.get("level",0))
	node.position=Vector3(float(e.x),Building.level_y(level),float(e.z))
	records.append(e)
	wall_nodes[e.id]=node
	_rebuild_wall(e,{})

func _window_supports()->Dictionary:
	var descriptors:Array=[]
	for entry:Dictionary in records:
		var d:Dictionary=entry.duplicate(true)
		d["base_y"]=Building.level_y(int(entry.get("level",0)))
		d["display_height"]=_visible_wall_height(entry)
		descriptors.append(d)
	var out:Dictionary={}
	for window:Node3D in world.house.get_children():
		if window.has_meta("window_aperture"):out[window]=WindowGeometry.supported_wall_ids(window,descriptors)
	return out

func _rebuild_wall(e:Dictionary, supports:Dictionary)->void:
	var node:Node3D=wall_nodes[e.id]
	for child:Node in node.get_children():child.free()
	var level:int=int(e.get("level",0))
	var h:float=_visible_wall_height(e)
	var horizontal:bool=float(e.w)>float(e.d)
	var length:float=float(e.w) if horizontal else float(e.d)
	var pieces:Array[Rect2]=[Rect2(-length*.5,0,length,h)]
	for window:Node3D in supports:
		if not supports[window].has(str(e.id)):continue
		var aperture:Rect2=WindowGeometry.opening(window,e,h,Building.level_y(level),false)
		if aperture.has_area():pieces=WindowGeometry.subtract(pieces,aperture)
	for piece:Rect2 in pieces:
		var c:Vector2=piece.get_center()
		var pos:Vector3=Vector3(c.x,c.y,0) if horizontal else Vector3(0,c.y,c.x)
		var size:Vector3=Vector3(piece.size.x,piece.size.y,float(e.d)) if horizontal else Vector3(float(e.w),piece.size.y,piece.size.x)
		world.box(node,pos,size,str(e.color))
	world.box(node,Vector3(0,h+.025,0),Vector3(float(e.w)+.025,.05,float(e.d)+.025),"f5efdf")
	world.box(node,Vector3(0,.055,0),Vector3(float(e.w)+.015,.11,float(e.d)+.015),"f5efdf")
	if not building_state.is_empty() and not (bool(e.cut) and cutaway):
		var supports_upper:bool=false
		for floor:Dictionary in building_state.floors:
			if int(floor.level)==level+1 and floor.get("supports",[]).has(str(e.id)):supports_upper=true
		if supports_upper:
			# The 3m storey includes the 16cm slab and a 24cm structural rim over
			# the declared 2.6m bearing wall. Cutaway hides this with that wall.
			var rim_height:float=Building.RISE-.16-float(e.height)
			var rim:MeshInstance3D=world.box(node,Vector3(0,float(e.height)+rim_height*.5,0),Vector3(float(e.w),rim_height,float(e.d)),"ae9169")
			rim.set_meta("floor_support_rim",true)
	world.assign_structure_layer(node,level)

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
	refresh_decorations()

func snapshot() -> Dictionary:
	if not building_state.is_empty():return building_state.duplicate(true)
	return {"kind":"__construction","walls":records.duplicate(true),"floors":floor_records.duplicate(true)}

func restore(data: Dictionary) -> void:
	last_error=""
	var canonical:Dictionary={}
	# Validate legacy arrays and every record before freeing any live geometry.
	# Unversioned valid data retains its original ground rendering mode.
	var result:Dictionary=Building.migrate(data)
	if not bool(result.ok):last_error=str(result.error);return
	if data.has("version"):canonical=result.state
	for n in wall_nodes.values():n.queue_free()
	for n in floor_nodes:
		if is_instance_valid(n):n.queue_free()
	wall_nodes.clear();floor_nodes.clear();records.clear();floor_records.clear()
	for node:Node3D in stair_nodes.values():node.queue_free()
	stair_nodes.clear()
	for node:Node3D in guard_nodes.values():node.queue_free()
	guard_nodes.clear()
	for node:Node3D in roof_nodes.values():node.queue_free()
	roof_nodes.clear()
	building_state=canonical
	if not canonical.is_empty():
		_render_building()
		refresh_decorations()
		return
	world.set_starter_floor_visible(true)
	for e in data.get("walls",[]):
		if valid_record(e):add_wall(e)
	for e in data.get("floors",[]):
		if valid_record(e):add_floor(e)
	refresh_decorations()

func _render_building() -> void:
	var legacy_floor:Dictionary=Building.find(building_state,"legacy_starter_floor")
	world.set_starter_floor_visible(not legacy_floor.is_empty())
	if not legacy_floor.is_empty():world.apply_starter_floor_finish(str(legacy_floor.material))
	for wall:Dictionary in building_state.walls:
		var entry:Dictionary=wall.duplicate(true);entry["color"]=entry.material
		add_wall(entry)
	for floor:Dictionary in building_state.floors:
		var entry:Dictionary=floor.duplicate(true);entry["color"]=entry.material
		floor_records.append(entry)
	for level:int in [0,1]:
		for tile:Dictionary in Building.surface_tiles(building_state,level):
			var area:Rect2=tile.rect
			# Keep the authored ground boards/tiles when migrating the starter.
			if level==0 and not legacy_floor.is_empty() and Building.rect(legacy_floor).encloses(area):continue
			var node:MeshInstance3D=world.box(self,Vector3(area.get_center().x,Building.level_y(level)-.08,area.get_center().y),Vector3(area.size.x,.16,area.size.y),str(tile.material))
			node.material_override=_floor_material(str(tile.material))
			node.set_meta("building_level",level);node.set_meta("floor_surface",true);node.set_meta("source_floor",str(tile.source_id))
			world.assign_structure_layer(node,level);floor_nodes.append(node)
	for stair:Dictionary in building_state.stairs:
		var node:Node3D=load("res://assets/models/juniper_stair.glb").instantiate()
		node.name=str(stair.id);add_child(node)
		node.position=Vector3(float(stair.x),Building.level_y(int(stair.lower)),float(stair.z))
		node.rotation_degrees.y=float(stair.rotation)
		node.set_meta("stair_id",str(stair.id));node.set_meta("building_level",int(stair.lower))
		world.assign_stair_layer(node);stair_nodes[str(stair.id)]=node
		_render_guard(stair)
	for record:Dictionary in building_state.roofs:
		var node:Node3D=Roof.create(record);add_child(node);roof_nodes[str(record.id)]=node
		world.assign_structure_layer(node,int(record.level));node.visible=roofs_visible and int(record.level)<=world.view_level

func _floor_material(finish:String)->Material:
	# Only the two existing wood choices use boards. Stone, custom finishes and
	# the separately authored starter timber retain their original materials.
	var key:String=finish.to_lower().trim_prefix("#")
	if key not in ["cfa97e","896953"]:return world.material(finish)
	if not _wood_floor_materials.has(key):
		var surface:=ShaderMaterial.new()
		surface.shader=WoodFloorShader
		surface.resource_local_to_scene=true
		surface.set_shader_parameter("wood_color",Color(key))
		_wood_floor_materials[key]=surface
	return _wood_floor_materials[key]

func set_roof_visibility(value:bool)->void:
	roofs_visible=value
	for id:String in roof_nodes:
		var node:Node3D=roof_nodes[id];node.visible=value and int(node.get_meta("building_level",0))<=world.view_level

func _render_guard(stair:Dictionary) -> void:
	var parent:=Node3D.new();parent.name="Guard_"+str(stair.id);add_child(parent)
	parent.set_meta("stair_guard",str(stair.id));guard_nodes[str(stair.id)]=parent
	var span_pack:PackedScene=load("res://assets/models/juniper_guard_span.glb")
	var post_pack:PackedScene=load("res://assets/models/juniper_guard_post.glb")
	var positions:Array[Vector3]=[]
	for run:Array in Building.guard_runs(stair):
		var first:Vector3=run[0];var last:Vector3=run[1]
		var count:int=ceili(first.distance_to(last))
		for index:int in range(count+1):
			var at:Vector3=first.lerp(last,float(index)/count)
			if not positions.any(func(previous:Vector3)->bool:return previous.is_equal_approx(at)):
				var post:Node3D=post_pack.instantiate();parent.add_child(post);post.position=at
				post.set_meta("guard_post",true);positions.append(at)
			if index==count:continue
			var end:Vector3=first.lerp(last,float(index+1)/count)
			var span:Node3D=span_pack.instantiate();parent.add_child(span);span.position=at
			span.rotation.y=-atan2(end.z-at.z,end.x-at.x);span.scale.x=at.distance_to(end)
			span.set_meta("guard_span",true)
		# Fascia stays on supported slab, flush with its top, never bridging the hole.
		var trim:MeshInstance3D=world.box(parent,(first+last)*.5-Vector3(0,.08,0),Vector3(first.distance_to(last),.16,.055),"ae9169")
		trim.rotation.y=-atan2(last.z-first.z,last.x-first.x);trim.set_meta("guard_trim",true)
	world.assign_structure_layer(parent,1)

func validated_state() -> Dictionary:
	if not building_state.is_empty():return {"ok":true,"state":building_state.duplicate(true)}
	return Building.migrate(snapshot())

func valid_record(e: Variant) -> bool:
	if not e is Dictionary:return false
	for key in ["x","z","w","d"]:
		if not e.has(key) or not (e[key] is float or e[key] is int):return false
	return absf(float(e.x))<9 and absf(float(e.z))<8 and float(e.w)>0 and float(e.d)>0 and float(e.w)<=18 and float(e.d)<=16

func update_cutaway(value: bool) -> void:
	cutaway=value
	var data=snapshot()
	restore(data)

func point_blocked(p: Vector2,level:int=0) -> bool:
	for e in records:
		if int(e.get("level",0))!=level:continue
		if wall_rect(e).grow(.15).has_point(p):return true
	return false

func rect_blocked(r: Rect2,level:int=0) -> bool:
	for e in records:
		if int(e.get("level",0))!=level:continue
		if wall_rect(e).grow(.03).intersects(r):return true
	return false

func wall_rect(e: Dictionary) -> Rect2:
	return Rect2(Vector2(float(e.x)-float(e.w)/2,float(e.z)-float(e.d)/2),Vector2(float(e.w),float(e.d)))

func floor_contains(p: Vector2,level:int=0) -> bool:
	if not building_state.is_empty():return Building.footprint_supported(building_state,level,Rect2(p-Vector2(.00001,.00001),Vector2(.00002,.00002)))
	if level!=0:return false
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
	tool="";anchored=false;proposal.clear();roof_edit_id=""
	set_roof_visibility(roofs_visible)
	_preview_signature=""
	if is_instance_valid(preview):preview.queue_free()
	preview=null

func snap(p: Vector3) -> Vector3:
	return Vector3(clampf(snappedf(p.x,.5),-8,8),Building.level_y(build_level),clampf(snappedf(p.z,.5),-6.5,7))

func update_preview(p: Vector3) -> void:
	if tool.is_empty() or not is_instance_valid(preview):return
	if not p.is_finite():return
	var point=snap(p)
	proposal=make_proposal(point)
	var signature:String=var_to_str([tool,point,anchor,anchored,proposal]).sha256_text()
	if signature==_preview_signature:return
	_preview_signature=signature
	for n in preview.get_children():n.queue_free()
	valid=not proposal.is_empty() and bool(proposal.get("valid",false))
	var color:Color=Color(.36,.74,.56,.55) if valid else Color(.86,.29,.24,.45)
	var preview_mat=StandardMaterial3D.new()
	preview_mat.albedo_color=color
	preview_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	if not anchored and tool in ["wall","room","floor","roof","roof_edit"]:
		var marker=world.box(preview,point+Vector3(0,.04,0),Vector3(.32,.08,.32),"397e70")
		marker.material_override=preview_mat
	for e in proposal.get("walls",[]):
		var mesh=world.box(preview,Vector3(e.x,.7+Building.RISE*build_level,e.z),Vector3(e.w,1.08,e.d),"397e70")
		mesh.material_override=preview_mat
	if proposal.has("remove_id"):
		for e in records:
			if e.id==proposal.remove_id:
				var mesh=world.box(preview,Vector3(e.x,.7+Building.RISE*build_level,e.z),Vector3(e.w+.04,1.10,e.d+.04),"397e70")
				mesh.material_override=preview_mat
	for e in proposal.get("floors",[]):
		var mesh=world.box(preview,Vector3(e.x,.18+Building.RISE*build_level,e.z),Vector3(e.w,.03,e.d),"397e70")
		mesh.material_override=preview_mat
	if proposal.has("stair_preview"):
		var stair:Dictionary=proposal.stair_preview
		var model:Node3D=load("res://assets/models/juniper_stair.glb").instantiate();preview.add_child(model)
		model.position=Vector3(float(stair.x),Building.GROUND_Y,float(stair.z));model.rotation_degrees.y=float(stair.rotation)
		for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):mesh.material_override=preview_mat
		var footprint:Rect2=Building.stair_rect({"x":stair.x,"z":stair.z,"rotation":stair.rotation,"lower":0})
		var outline:MeshInstance3D=world.box(preview,Vector3(footprint.get_center().x,3.175,footprint.get_center().y),Vector3(footprint.size.x,.025,footprint.size.y),"397e70")
		outline.material_override=preview_mat

	if proposal.has("roof_preview"):
		var roof:Node3D=Roof.create(proposal.roof_preview);preview.add_child(roof);roof.position.y+=.015
		for geometry:GeometryInstance3D in roof.find_children("*","GeometryInstance3D",true,false):geometry.material_override=preview_mat
		if not roof_edit_id.is_empty() and roof_nodes.has(roof_edit_id):roof_nodes[roof_edit_id].visible=false

func click(p: Vector3) -> Dictionary:
	if tool.is_empty():return {}
	if not p.is_finite():return {"error":"Point inside the lot."}
	if tool=="roof_edit" and roof_edit_id.is_empty():
		var state:Dictionary=validated_state()
		if not bool(state.ok):return {"error":str(state.error)}
		for roof:Dictionary in state.state.roofs:
			if int(roof.level)==build_level and Building.rect(roof).has_point(Vector2(p.x,p.z)):
				roof_edit_id=str(roof.id);roof_pitch=float(roof.pitch);roof_material=str(roof.material);world.placement_angle=int(roof.rotation);return {}
		return {"error":"Select an existing roof on this level."}
	if tool in ["wall","room","floor","roof","roof_edit"] and not anchored:
		anchor=snap(p);anchored=true;return {}
	var data=make_proposal(snap(p))
	if data.is_empty() or not bool(data.get("valid",false)):return {"error":str(data.get("error","That construction overlaps a furnishing, wall, or the edge of the lot."))}
	return data

func make_proposal(p: Vector3) -> Dictionary:
	if tool in ["roof","roof_edit","roof_remove"]:return _make_roof_proposal(p)
	if tool in ["floor","stairs","remove_structure"]:return _make_level_proposal(p)
	var data:Dictionary=_make_legacy_proposal(p)
	if quote_provider.is_valid():
		var operation:Dictionary={"op":"structure","tool":tool,"level":build_level}
		if tool in ["wall","room"]:
			if not anchored:return {}
			operation.merge({"ax":anchor.x,"az":anchor.z,"bx":p.x,"bz":p.z})
		elif tool in ["door","erase"]:
			if not data.has("remove_id"):return {"valid":false,"error":"Point at a wall on this level."}
			operation["id"]=str(data.remove_id)
			if tool=="door":
				var wall:Dictionary={}
				for record:Dictionary in records:
					if str(record.id)==str(data.remove_id):wall=record;break
				operation["center"]=p.x if float(wall.w)>float(wall.d) else p.z
		var quote:Dictionary=quote_provider.call(operation)
		data["valid"]=bool(quote.ok)
		if bool(quote.ok):data["build_quote"]=quote;data["cost"]=int(quote.cost)
		else:data["error"]=str(quote.error)
		return data
	if data.is_empty() or building_state.is_empty():return data
	var converted:Dictionary=_convert_proposal(data)
	if not bool(converted.ok):data["valid"]=false;data["error"]=str(converted.error)
	else:data["building_state"]=converted.state
	return data

func _make_roof_proposal(p:Vector3)->Dictionary:
	var result:Dictionary=validated_state()
	if not bool(result.ok):return {"valid":false,"error":str(result.error)}
	var state:Dictionary=result.state;var operation:Dictionary={};var view:Dictionary={"valid":false}
	if tool=="roof_remove":
		for roof:Dictionary in state.roofs:
			if int(roof.level)==build_level and Building.rect(roof).has_point(Vector2(p.x,p.z)):operation={"op":"remove","id":str(roof.id)};view["roof_preview"]=roof;break
		if operation.is_empty():return {"valid":false,"error":"Point at a roof on this level."}
	else:
		if tool=="roof_edit" and roof_edit_id.is_empty():return {"valid":false,"error":"Select a roof, then choose its two new corners."}
		if not anchored:return {}
		var width:float=absf(p.x-anchor.x);var depth:float=absf(p.z-anchor.z)
		if width<1.5 or depth<1.5:return {"valid":false,"error":"Choose a roof at least1.5 metres wide and deep."}
		var record:Dictionary={"level":build_level,"x":(p.x+anchor.x)*.5,"z":(p.z+anchor.z)*.5,"w":width,"d":depth,"pitch":roof_pitch,"rotation":posmod(roundi(world.placement_angle),180),"material":roof_material}
		var preview_record:Dictionary=record.duplicate(true);preview_record["id"]="preview" if roof_edit_id.is_empty() else roof_edit_id;view["roof_preview"]=preview_record
		var supported:bool=false
		for first:Dictionary in state.walls:
			for second:Dictionary in state.walls:
				record["supports"]=[str(first.id),str(second.id)]
				if Building._perimeter_support_error(state,record,build_level).is_empty():supported=true;break
			if supported:break
		if not supported:view["error"]="The roof needs two complete opposite bearing walls on this level.";return view
		operation={"op":"add","collection":"roofs","record":record} if tool=="roof" else {"op":"roof_edit","id":roof_edit_id,"record":record}
	if not quote_provider.is_valid():view["error"]="The building transaction service is unavailable.";return view
	var quote:Dictionary=quote_provider.call(operation);view["valid"]=bool(quote.ok)
	if bool(quote.ok):view["build_quote"]=quote;view["cost"]=int(quote.cost)
	else:view["error"]=str(quote.error)
	return view

func _make_level_proposal(p:Vector3)->Dictionary:
	var state_result:Dictionary=validated_state()
	if not bool(state_result.ok):return {"valid":false,"error":str(state_result.error)}
	var state:Dictionary=state_result.state
	var operation:Dictionary={};var view:Dictionary={"valid":false}
	if tool=="stairs":
		var record:Dictionary={"x":p.x,"z":p.z,"rotation":posmod(roundi(world.placement_angle),360)}
		operation={"op":"add","collection":"stairs","record":record};view["stair_preview"]=record
	elif tool=="floor":
		if not anchored:return {}
		var width:float=absf(p.x-anchor.x);var depth:float=absf(p.z-anchor.z)
		if width<.5 or depth<.5:return {"valid":false,"error":"Choose a floor rectangle at least half a metre wide and deep."}
		var record:Dictionary={"level":build_level,"x":(p.x+anchor.x)*.5,"z":(p.z+anchor.z)*.5,"w":width,"d":depth,"material":"cfa97e"}
		view["floors"]=[record]
		if build_level==1:
			var found:bool=false
			for first:Dictionary in state.walls:
				for second:Dictionary in state.walls:
					record["supports"]=[str(first.id),str(second.id)]
					if Building._perimeter_support_error(state,record,0).is_empty():found=true;break
				if found:break
			if not found:view["error"]="An upper floor needs two complete opposite bearing walls below.";return view
		operation={"op":"add","collection":"floors","record":record}
	else:
		var selected:Dictionary={}
		for stair:Dictionary in state.stairs:
			if Building.stair_rect(stair).grow(.1).has_point(Vector2(p.x,p.z)):selected=stair;view["stair_preview"]=stair;break
		if selected.is_empty():
			for index:int in range(state.floors.size()-1,-1,-1):
				var floor:Dictionary=state.floors[index]
				if int(floor.level)==build_level and Building.rect(floor).has_point(Vector2(p.x,p.z)):selected=floor;view["floors"]=[floor];break
		if selected.is_empty():return {"valid":false,"error":"Point at a staircase or a floor on this level."}
		operation={"op":"remove","id":str(selected.id)}
	if not quote_provider.is_valid():view["error"]="The building transaction service is unavailable.";return view
	var quote:Dictionary=quote_provider.call(operation)
	view["valid"]=bool(quote.ok)
	if not bool(quote.ok):view["error"]=str(quote.error)
	else:view["cost"]=int(quote.cost);view["build_quote"]=quote
	return view

func _convert_proposal(data:Dictionary) -> Dictionary:
	var state:Dictionary=building_state.duplicate(true)
	if data.has("remove_id"):state.walls=state.walls.filter(func(record:Dictionary)->bool:return str(record.id)!=str(data.remove_id))
	for wall:Dictionary in data.get("walls",[]):
		var record:Dictionary=wall.duplicate(true)
		record["id"]=Building._new_id(state,"walls");record["level"]=build_level
		record["material"]=record.get("color","eae7d7");record["height"]=2.6;record["cut"]=record.get("cut",true)
		record.erase("color");state.walls.append(record)
	for floor:Dictionary in data.get("floors",[]):
		var record:Dictionary=floor.duplicate(true)
		record["id"]=Building._new_id(state,"floors");record["level"]=build_level;record["material"]=record.get("color","cfa97e");record.erase("color")
		if build_level==1:
			for first:Dictionary in state.walls:
				for second:Dictionary in state.walls:
					record["supports"]=[str(first.id),str(second.id)]
					if Building._perimeter_support_error(state,record,0).is_empty():break
				if Building._perimeter_support_error(state,record,0).is_empty():break
		state.floors.append(record)
	state.revision=int(state.revision)+1
	var error:String=Building.validate(state)
	return {"ok":true,"state":state} if error.is_empty() else {"ok":false,"error":error}

func _make_legacy_proposal(p: Vector3) -> Dictionary:
	if tool in ["door","erase"]:
		var nearest:Dictionary={}
		var best:float=.55
		for e in records:
			if int(e.get("level",0))!=build_level:continue
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
			if world.item_level(item)!=build_level:continue
			if LifeCatalog.passable(str(item.kind)):continue
			var s:Vector2=item.size
			if int(roundf(item.node.rotation_degrees.y/90))%2:s=Vector2(s.y,s.x)
			if r.intersects(Rect2(Vector2(item.node.position.x,item.node.position.z)-s/2,s)):is_valid=false
		for old in records:
			if int(old.get("level",0))!=build_level:continue
			var existing=wall_rect(old)
			# Joining at endpoints is allowed; overlapping parallel walls is not.
			if existing.grow(-.03).intersects(r.grow(-.03)) and ((float(old.w)>.2)==(float(e.w)>.2)):is_valid=false
	return {"op":tool,"walls":out,"floors":floors,"cost":int(length*55+floor_area(floors)*12),"valid":is_valid}

func floor_area(entries:Array) -> float:
	var total:float=0
	for e in entries:total+=float(e.w)*float(e.d)
	return total

func commit(data: Dictionary) -> void:
	if data.get("building_state") is Dictionary:
		restore(data.building_state)
		if not last_error.is_empty():return
		anchored=false;proposal.clear();world.rebuild_navigation();refresh_decorations();return
	if data.has("remove_id"):remove_wall(data.remove_id)
	for e in data.get("walls",[]):add_wall(e)
	for e in data.get("floors",[]):add_floor(e)
	anchored=false
	proposal.clear()
	world.rebuild_navigation()
	refresh_decorations()

func _visible_wall_height(entry:Dictionary)->float:
	var height:float=float(entry.height)
	return minf(.65,height) if bool(entry.cut) and cutaway else height

func _decoration_bounds(node:Node3D)->AABB:
	# Include hidden children so a cutaway toggle can restore the same artwork.
	var meshes:Array= node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D:meshes.append(node)
	var bounds:AABB
	var found:bool=false
	var to_house:Transform3D=world.house.global_transform.affine_inverse()
	for mesh:MeshInstance3D in meshes:
		if mesh.mesh==null:continue
		var local:AABB=(to_house*mesh.global_transform)*mesh.mesh.get_aabb()
		bounds=bounds.merge(local) if found else local
		found=true
	return bounds

func _decoration_supported(node:Node3D)->bool:
	var bounds:AABB=_decoration_bounds(node)
	if bounds.size.is_zero_approx():return false
	var direction:Vector3=node.get_meta("wall_support_normal",Vector3.ZERO)
	if direction.is_zero_approx():return false
	var to_house:Transform3D=world.house.global_transform.affine_inverse()*node.global_transform
	direction=(to_house.basis*direction).normalized()
	var along_x:bool=absf(direction.z)>.999
	if not along_x and absf(direction.x)<.999:return false
	var start:float=bounds.position.x if along_x else bounds.position.z
	var end:float=bounds.end.x if along_x else bounds.end.z
	# Use the wall-facing bounds, including the sill's actual rear reach.
	var plane:float=(bounds.position.z if direction.z<0 else bounds.end.z) if along_x else (bounds.position.x if direction.x<0 else bounds.end.x)
	var groups:Array[Dictionary]=[]
	for entry:Dictionary in records:
		if (float(entry.w)>=float(entry.d))!=along_x:continue
		var wall_plane:float=float(entry.z) if along_x else float(entry.x)
		var thickness:float=float(entry.d) if along_x else float(entry.w)
		if absf(wall_plane-plane)>thickness*.5+.005:continue
		var base:float=Building.level_y(int(entry.get("level",0)))
		# A millimetre of numerical tolerance; the low starter trim extends 1cm
		# below the finished floor, so its lower edge has a separate allowance.
		if bounds.position.y<base-.02 or bounds.end.y>base+_visible_wall_height(entry)+.001:continue
		var center:float=float(entry.x) if along_x else float(entry.z)
		var length:float=float(entry.w) if along_x else float(entry.d)
		var group_index:int=-1
		for index:int in groups.size():
			if absf(float(groups[index].plane)-wall_plane)<.001:group_index=index;break
		if group_index<0:
			group_index=groups.size();groups.append({"plane":wall_plane,"spans":[]})
		groups[group_index].spans.append(Vector2(center-length*.5,center+length*.5))
	for group:Dictionary in groups:
		group.spans.sort_custom(func(a:Vector2,b:Vector2)->bool:return a.x<b.x)
		var covered:float=start
		for span:Vector2 in group.spans:
			if span.y<covered-.001:continue
			if span.x>covered+.001:break
			covered=maxf(covered,span.y)
			if covered>=end-.001:return true
	return false

func refresh_decorations() -> void:
	var supports:Dictionary=_window_supports()
	for e:Dictionary in records:_rebuild_wall(e,supports)
	for n in world.house.get_children():
		if n.has_meta("wall_decoration"):
			n.visible=not supports.get(n,[]).is_empty() if n.has_meta("window_aperture") else _decoration_supported(n)
		elif n.has_meta("garden_decoration"):
			n.visible=true
			for floor:Dictionary in floor_records:
				if int(floor.get("level",0))!=0:continue
				if wall_rect(floor).grow(.15).has_point(Vector2(n.position.x,n.position.z)):n.visible=false;break
