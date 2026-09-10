extends RefCounted
class_name LifeBuildingEdits
## Detached UI operations for walls, rooms, doorways and floor finishes. A whole
## room/door edit is validated together before a single quote reaches the world.
const Building=preload("res://scripts/building_state.gd")

static func _error(message:String)->Dictionary:return {"ok":false,"error":message}

static func propose(current:Dictionary,operation:Variant,funds:Variant)->Dictionary:
	var error:String=Building.validate(current)
	if not error.is_empty():return _error(error)
	if not operation is Dictionary or operation.get("op")!="structure" or not Building.number(funds,0,1e9,true):return _error("Invalid structure edit.")
	if int(current.revision)>=1000000000:return _error("Building revision limit reached.")
	var tool:Variant=operation.get("tool");var level:Variant=operation.get("level")
	if not tool is String or tool not in ["wall","room","door","erase","finish","paint"] or not Building.number(level,0,1,true):return _error("Invalid structure tool or level.")
	var after:Dictionary=current.duplicate(true);var cost:int=0
	if tool=="finish":
		if not Building._material(operation.get("material")):return _error("Choose a valid floor finish.")
		var changed:bool=false
		for floor:Dictionary in after.floors:
			if int(floor.level)==int(level) and floor.material!=operation.material:floor.material=operation.material;changed=true
		if not changed:return _error("The floors on this level already use that finish.")
	elif tool in ["wall","room"]:
		for key:String in ["ax","az","bx","bz"]:
			if not Building.number(operation.get(key),-18,18):return _error("Choose two valid construction points.")
		var a:=Vector2(float(operation.ax),float(operation.az));var b:=Vector2(float(operation.bx),float(operation.bz))
		var walls:Array=[];var length:float=0.0;var floor_cost:float=0.0
		if tool=="wall":
			var horizontal:bool=absf(b.x-a.x)>absf(b.y-a.y)
			if horizontal:b.y=a.y
			else:b.x=a.x
			length=a.distance_to(b)
			if length<.5:return _error("Choose a wall at least half a metre long.")
			walls.append({"x":(a.x+b.x)*.5,"z":(a.y+b.y)*.5,"w":length if horizontal else .14,"d":.14 if horizontal else length})
		else:
			var size:Vector2=(b-a).abs();var center:Vector2=(a+b)*.5
			if size.x<1.5 or size.y<1.5:return _error("Choose a room at least one and a half metres wide and deep.")
			walls=[{"x":center.x,"z":a.y,"w":size.x,"d":.14},{"x":center.x,"z":b.y,"w":size.x,"d":.14},{"x":a.x,"z":center.y,"w":.14,"d":size.y},{"x":b.x,"z":center.y,"w":.14,"d":size.y}]
			length=(size.x+size.y)*2.0
			var floor:Dictionary={"id":Building._new_id(after,"floors"),"level":int(level),"x":center.x,"z":center.y,"w":size.x,"d":size.y,"material":"cfa97e"}
			var before_area:float=Building._union_area(Building._rects(current,"floors",int(level)))
			after.floors.append(floor)
			var added_area:float=Building._union_area(Building._rects(after,"floors",int(level)))-before_area
			if added_area<=Building.EPS:after.floors.pop_back()
			elif int(level)==1:
				var supported:bool=false
				for first:Dictionary in after.walls:
					for second:Dictionary in after.walls:
						floor["supports"]=[str(first.id),str(second.id)]
						if Building._perimeter_support_error(after,floor,0).is_empty():supported=true;break
					if supported:break
				if not supported:return _error("An upper room needs a supported floor or two complete opposite bearing walls below.")
			floor_cost=maxf(0.0,added_area)*12
		for wall:Dictionary in walls:
			wall.merge({"id":Building._new_id(after,"walls"),"level":int(level),"height":2.6,"cut":true,"material":"eae7d7"});after.walls.append(wall)
		cost=int(length*55+floor_cost) # Preserve legacy whole-quote currency truncation.
	elif tool=="paint":
		# Repaint one wall segment; the colour is a wall material like the floor finishes.
		if not Building.identifier(operation.get("id")):return _error("Choose an existing wall on this level.")
		if not Building._material(operation.get("material")):return _error("Choose a valid wall colour.")
		var wall:Dictionary=Building.find(after,str(operation.id))
		if wall.is_empty() or Building._group_of(after,str(operation.id))!="walls" or int(wall.level)!=int(level):return _error("The selected wall has changed.")
		if str(wall.material)==str(operation.material):return _error("That wall already has this colour.")
		wall.material=str(operation.material)
		cost=int(maxf(float(wall.w),float(wall.d))*6)
	else:
		if not Building.identifier(operation.get("id")):return _error("Choose an existing wall on this level.")
		var wall:Dictionary=Building.find(after,str(operation.id))
		if wall.is_empty() or Building._group_of(after,str(operation.id))!="walls" or int(wall.level)!=int(level):return _error("The selected wall has changed.")
		after.walls=after.walls.filter(func(record:Dictionary)->bool:return record.id!=wall.id)
		var length:float=maxf(float(wall.w),float(wall.d))
		if tool=="erase":cost=-int(length*20)
		else:
			if not Building.number(operation.get("center"),-18,18) or length<1.55:return _error("Choose a wall long enough for a doorway.")
			var horizontal:bool=float(wall.w)>float(wall.d)
			var center:float=float(wall.x) if horizontal else float(wall.z)
			var door:float=clampf(float(operation.center),center-length*.5+.65,center+length*.5-.65)
			for side:int in [-1,1]:
				var low:float=center-length*.5 if side<0 else door+.53
				var high:float=door-.53 if side<0 else center+length*.5
				if high-low<=.05:continue
				var part:Dictionary=wall.duplicate(true);part.id=Building._new_id(after,"walls")
				if horizontal:part.x=(low+high)*.5;part.w=high-low
				else:part.z=(low+high)*.5;part.d=high-low
				after.walls.append(part)
			cost=90
	error=Building.validate(after)
	if not error.is_empty():return _error(error)
	if int(funds)<cost:return _error("Not enough funds for this construction.")
	if int(funds)-cost>1000000000:return _error("This refund exceeds the wallet limit.")
	after.revision=int(current.revision)+1
	return {"ok":true,"operation":operation.duplicate(true),"before":Building.fingerprint(current),"after":after,"cost":cost,"funds_before":int(funds),"funds_after":int(funds)-cost}
