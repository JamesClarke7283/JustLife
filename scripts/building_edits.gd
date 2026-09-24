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
	if not tool is String or tool not in ["wall","room","door","erase","finish","paint","room_pack","grab"] or not Building.number(level,0,1,true):return _error("Invalid structure tool or level.")
	var after:Dictionary=current.duplicate(true);var cost:int=0
	if tool=="room_pack":
		var built:Dictionary=_room_pack(after,operation,int(level))
		if built.has("error"):return _error(str(built.error))
		cost=int(built.cost)
	elif tool=="finish":
		if not Building._material(operation.get("material")):return _error("Choose a valid floor finish.")
		var changed:bool=false
		for floor:Dictionary in after.floors:
			if int(floor.level)==int(level) and floor.material!=operation.material:floor.material=operation.material;changed=true
		if not changed:return _error("The floors on this level already use that finish.")
	elif tool=="grab":
		# Select an existing wall, then push or pull it along its normal so the
		# room resizes. Connected end walls stretch to keep the corners closed.
		if not Building.identifier(operation.get("id")):return _error("Choose an existing wall on this level.")
		if not Building.number(operation.get("line"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN):return _error("Push or pull the wall to a new position.")
		var grabbed:Dictionary=Building.find(after,str(operation.id))
		if grabbed.is_empty() or Building._group_of(after,str(operation.id))!="walls" or int(grabbed.level)!=int(level):return _error("The selected wall has changed.")
		var was_horizontal:bool=float(grabbed.w)>float(grabbed.d)
		var old_line:float=float(grabbed.z) if was_horizontal else float(grabbed.x)
		var grab_length:float=maxf(float(grabbed.w),float(grabbed.d))
		var before_floor:float=Building._union_area(Building._rects(after,"floors",int(level)))
		var grab_error:String=_grab_wall(after,grabbed,float(operation.line),int(level))
		if not grab_error.is_empty():return _error(grab_error)
		var added_floor:float=maxf(0.0,Building._union_area(Building._rects(after,"floors",int(level)))-before_floor)
		cost=int(maxf(.5,absf(float(operation.line)-old_line))*grab_length*12+added_floor*12)
	elif tool in ["wall","room"]:
		for key:String in ["ax","az","bx","bz"]:
			if not Building.number(operation.get(key),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN):return _error("Choose two valid construction points.")
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
		# A room built against an existing room shares that wall rather than
		# building a second one on top of it: two rooms side by side are divided
		# by one wall, which is what the player sees and what makes breaking it
		# later merge them into one bigger room.
		var placed:Array=[]
		for wall:Dictionary in walls:
			if not _coincident_wall(after,wall,int(level)).is_empty():continue
			placed.append(wall)
		walls=placed
		for wall:Dictionary in walls:
			wall.merge({"id":Building._new_id(after,"walls"),"level":int(level),"height":2.6,"cut":true,"material":"eae7d7"});after.walls.append(wall)
		cost=int(length*55+floor_cost) # Preserve legacy whole-quote currency truncation.
	elif tool=="paint":
		# Repaint one wall segment, or every wall joined to it corner to corner;
		# the colour is a wall material like the floor finishes. Nursery paint
		# also carries one of five patterns and is priced per square metre.
		if not Building.identifier(operation.get("id")):return _error("Choose an existing wall on this level.")
		if not Building._material(operation.get("material")):return _error("Choose a valid wall colour.")
		var scope:String=str(operation.get("scope","wall"))
		if scope not in ["wall","room"]:return _error("Choose whether to paint one wall or the whole room.")
		var palette:String=str(operation.get("palette","home"))
		if palette not in ["home","nursery"]:return _error("Choose a home or nursery paint set.")
		var pattern:String=str(operation.get("pattern",""))
		var rate:float=6.0
		var per_area:bool=false
		if palette=="nursery":
			var nursery:Dictionary=LifeCatalog.get_item("nursery_paint")
			if not LifeCatalogVariants.color_offered(str(operation.material),nursery):return _error("Choose a valid nursery colour.")
			if not LifeCatalogVariants.styles(nursery).has(pattern):return _error("Choose a nursery pattern.")
			rate=float(nursery.get("rate_per_square_metre",5))
			per_area=true
		elif not pattern.is_empty():return _error("Home wall paint does not use a pattern.")
		var wall:Dictionary=Building.find(after,str(operation.id))
		if wall.is_empty() or Building._group_of(after,str(operation.id))!="walls" or int(wall.level)!=int(level):return _error("The selected wall has changed.")
		var side:Variant=null
		if Building.number(operation.get("px"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN) and Building.number(operation.get("pz"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN):
			side=Vector2(float(operation.px),float(operation.pz))
		var changed:int=0
		for target:Dictionary in (_room_walls(after,wall,int(level),side) if scope=="room" else [wall]):
			var same_colour:bool=str(target.material)==str(operation.material)
			var same_pattern:bool=str(target.get("pattern",""))==pattern
			if same_colour and same_pattern:continue
			target.material=str(operation.material)
			if pattern.is_empty():target.erase("pattern")
			else:target["pattern"]=pattern
			var span:float=maxf(float(target.w),float(target.d))
			var height:float=float(target.get("height",2.6))
			cost+=int(span*height*rate) if per_area else int(span*rate)
			changed+=1
		if changed==0:return _error("That wall already has this colour." if scope=="wall" else "Those walls already have this colour.")
	else:
		if not Building.identifier(operation.get("id")):return _error("Choose an existing wall on this level.")
		var wall:Dictionary=Building.find(after,str(operation.id))
		if wall.is_empty() or Building._group_of(after,str(operation.id))!="walls" or int(wall.level)!=int(level):return _error("The selected wall has changed.")
		if tool=="erase":
			_remove_collinear(after,wall,int(level))
			cost=-int(maxf(float(wall.w),float(wall.d))*20)
		else:
			# Prefer relocating an existing doorway when the click lands in a gap
			# between collinear wall stubs; otherwise cut a new opening.
			var moved:Dictionary=_relocate_doorway(after,operation.get("center"),int(level))
			if bool(moved.get("ok",false)):
				cost=40
			else:
				var door_error:String=_cut_door(after,wall,operation.get("center"),int(level))
				if not door_error.is_empty():return _error(door_error)
				cost=90
	error=Building.validate(after)
	if not error.is_empty():return _error(error)
	if int(funds)<cost:return _error("Not enough funds for this construction.")
	if int(funds)-cost>1000000000:return _error("This refund exceeds the wallet limit.")
	after.revision=int(current.revision)+1
	return {"ok":true,"operation":operation.duplicate(true),"before":Building.fingerprint(current),"after":after,"cost":cost,"funds_before":int(funds),"funds_after":int(funds)-cost}

## Push or pull one wall along its normal. Orthogonal walls that meet either
## end stretch so the room stays closed; the wall itself stays the same length.
## The floor on this storey grows or shrinks with the push so the new footprint
## stays supported and walkable, without leaving the owned lot.
static func _grab_wall(after:Dictionary,wall:Dictionary,line:float,level:int) -> String:
	var horizontal:bool=float(wall.w)>float(wall.d)
	var old_line:float=float(wall.z) if horizontal else float(wall.x)
	var new_line:float=snappedf(line,.5)
	var delta:float=new_line-old_line
	if absf(delta)<.25:return "Push or pull the wall at least a quarter metre."
	var length:float=maxf(float(wall.w),float(wall.d))
	var along:float=float(wall.x) if horizontal else float(wall.z)
	var low_end:float=along-length*.5
	var high_end:float=along+length*.5
	var moved:Dictionary=wall.duplicate(true)
	if horizontal:moved.z=new_line
	else:moved.x=new_line
	if not Building.lot().encloses(Building.rect(moved).grow(-.02)):return "That would put the wall outside the lot."
	for other:Dictionary in after.walls:
		if int(other.level)!=level or str(other.id)==str(wall.id):continue
		var other_horizontal:bool=float(other.w)>float(other.d)
		if other_horizontal==horizontal:continue
		# Perpendicular run: its fixed axis sits on one of this wall's ends, and
		# one of its own ends meets the wall we are moving.
		var other_line:float=float(other.x) if horizontal else float(other.z)
		var on_low:bool=absf(other_line-low_end)<=.16
		var on_high:bool=absf(other_line-high_end)<=.16
		if not on_low and not on_high:continue
		var span:float=maxf(float(other.w),float(other.d))
		var mid:float=float(other.z) if horizontal else float(other.x)
		var span_low:float=mid-span*.5
		var span_high:float=mid+span*.5
		var touch_low:bool=absf(span_low-old_line)<=.2
		var touch_high:bool=absf(span_high-old_line)<=.2
		if not touch_low and not touch_high:continue
		if touch_low:span_low=new_line
		if touch_high:span_high=new_line
		if span_high-span_low<.5:return "That push would leave a connecting wall too short."
		if horizontal:
			other.z=(span_low+span_high)*.5
			other.d=span_high-span_low
		else:
			other.x=(span_low+span_high)*.5
			other.w=span_high-span_low
		if not Building.lot().encloses(Building.rect(other).grow(-.02)):return "A connecting wall would leave the lot."
	if horizontal:wall.z=new_line
	else:wall.x=new_line
	# Doorway stubs and other collinear panels on the same line move together so
	# an opening cut into the wall keeps both leaves and its door leaf aligned.
	for other:Dictionary in after.walls:
		if int(other.level)!=level or str(other.id)==str(wall.id):continue
		var other_horizontal:bool=float(other.w)>float(other.d)
		if other_horizontal!=horizontal:continue
		var other_line:float=float(other.z) if horizontal else float(other.x)
		if absf(other_line-old_line)>.08:continue
		var other_mid:float=float(other.x) if horizontal else float(other.z)
		var other_half:float=maxf(float(other.w),float(other.d))*.5
		# Only panels that share this wall's run (including a doorway gap of up
		# to 1.4 m) ride along; a distant collinear fence stays put.
		if other_mid+other_half<low_end-1.4 or other_mid-other_half>high_end+1.4:continue
		if horizontal:other.z=new_line
		else:other.x=new_line
		if not Building.lot().encloses(Building.rect(other).grow(-.02)):return "A collinear wall would leave the lot."
	var floor_error:String=_grab_extend_floors(after,horizontal,old_line,new_line,low_end,high_end,level)
	if not floor_error.is_empty():return floor_error
	var roof_error:String=_grab_sync_roofs(after,level)
	if not roof_error.is_empty():return roof_error
	return ""

## Resize every roof on this storey so its support footprint matches the
## outermost wall centre-lines around the floors beneath it. Pitch, rotation,
## finish and identity stay; only the plan grows or shrinks with the room.
static func _grab_sync_roofs(after:Dictionary,level:int) -> String:
	if after.roofs.is_empty():return ""
	var min_x:float=INF;var max_x:float=-INF;var min_z:float=INF;var max_z:float=-INF
	var have:bool=false
	for wall:Dictionary in after.walls:
		if int(wall.level)!=level:continue
		have=true
		var horizontal:bool=float(wall.w)>float(wall.d)
		if horizontal:
			min_x=minf(min_x,float(wall.x)-float(wall.w)*.5)
			max_x=maxf(max_x,float(wall.x)+float(wall.w)*.5)
			min_z=minf(min_z,float(wall.z));max_z=maxf(max_z,float(wall.z))
		else:
			min_z=minf(min_z,float(wall.z)-float(wall.d)*.5)
			max_z=maxf(max_z,float(wall.z)+float(wall.d)*.5)
			min_x=minf(min_x,float(wall.x));max_x=maxf(max_x,float(wall.x))
	if not have:return ""
	var support:=Rect2(Vector2(min_x,min_z),Vector2(max_x-min_x,max_z-min_z))
	if support.size.x<1.5 or support.size.y<1.5:return "That push would leave the roof too small."
	for roof:Dictionary in after.roofs:
		if int(roof.level)!=level:continue
		# Only roofs that already sit on this storey's slab grow with it; a
		# detached outbuilding roof on another pad is left alone.
		var current:Rect2=Building.rect(roof)
		if not support.grow(.5).intersects(current):continue
		roof.x=support.get_center().x
		roof.z=support.get_center().y
		roof.w=support.size.x
		roof.d=support.size.y
		# Re-pick opposite bearing walls so validation still finds supports after
		# the grabbed wall and its connectors moved.
		var supported:bool=false
		for first:Dictionary in after.walls:
			if int(first.level)!=level:continue
			for second:Dictionary in after.walls:
				if int(second.level)!=level or str(first.id)==str(second.id):continue
				roof["supports"]=[str(first.id),str(second.id)]
				if Building._perimeter_support_error(after,roof,level).is_empty():
					supported=true;break
			if supported:break
		if not supported:return "The roof needs two complete opposite bearing walls after that push."
		if not Building.lot().encloses(Building.rect(roof).grow(.28)):return "That would push the roof eaves outside the lot."
	return ""

## Grow or shrink floors that abut the grabbed wall so the strip between the old
## and new lines is covered (outward) or cleared (inward). When no floor touches
## the wall yet, add a slab over the new interior footprint.
static func _grab_extend_floors(after:Dictionary,horizontal:bool,old_line:float,new_line:float,low_end:float,high_end:float,level:int) -> String:
	var before_area:float=Building._union_area(Building._rects(after,"floors",level))
	var adjusted:bool=false
	for floor:Dictionary in after.floors:
		if int(floor.level)!=level:continue
		var r:Rect2=Building.rect(floor)
		# Must overlap the wall's run so a neighbouring room's floor is left alone.
		if horizontal:
			if r.end.x<low_end+.05 or r.position.x>high_end-.05:continue
			var z0:float=r.position.y
			var z1:float=r.end.y
			if absf(z1-old_line)<=.3:
				z1=new_line
			elif absf(z0-old_line)<=.3:
				z0=new_line
			else:
				continue
			if z1<z0:
				var swap:float=z0;z0=z1;z1=swap
			if z1-z0<.5:return "That push would leave the floor too narrow."
			floor.z=(z0+z1)*.5
			floor.d=z1-z0
			# Keep the slab spanning at least the wall's run so corners stay covered.
			var x0:float=minf(r.position.x,low_end)
			var x1:float=maxf(r.end.x,high_end)
			floor.x=(x0+x1)*.5
			floor.w=x1-x0
		else:
			if r.end.y<low_end+.05 or r.position.y>high_end-.05:continue
			var x0:float=r.position.x
			var x1:float=r.end.x
			if absf(x1-old_line)<=.3:
				x1=new_line
			elif absf(x0-old_line)<=.3:
				x0=new_line
			else:
				continue
			if x1<x0:
				var swapx:float=x0;x0=x1;x1=swapx
			if x1-x0<.5:return "That push would leave the floor too narrow."
			floor.x=(x0+x1)*.5
			floor.w=x1-x0
			var z0b:float=minf(r.position.y,low_end)
			var z1b:float=maxf(r.end.y,high_end)
			floor.z=(z0b+z1b)*.5
			floor.d=z1b-z0b
		if not Building.lot().encloses(Building.rect(floor).grow(-.02)):return "That would put the floor outside the lot."
		if int(level)==1:
			var support:String=Building._support_error(after,floor)
			if not support.is_empty():return support
		adjusted=true
	if not adjusted:
		# No abutting slab: lay one over the strip the wall just claimed so the
		# expanded interior is walkable. Prefer extending from any opposite floor
		# edge; otherwise create a new room-sized slab between the parallel walls.
		var strip_lo:float=minf(old_line,new_line)
		var strip_hi:float=maxf(old_line,new_line)
		var material:String="cfa97e"
		for floor:Dictionary in after.floors:
			if int(floor.level)==level:
				material=str(floor.material);break
		var slab:Dictionary={"id":Building._new_id(after,"floors"),"level":level,"material":material}
		if horizontal:
			slab.x=(low_end+high_end)*.5
			slab.w=maxf(.5,high_end-low_end)
			slab.z=(strip_lo+strip_hi)*.5
			slab.d=maxf(.5,strip_hi-strip_lo)
		else:
			slab.z=(low_end+high_end)*.5
			slab.d=maxf(.5,high_end-low_end)
			slab.x=(strip_lo+strip_hi)*.5
			slab.w=maxf(.5,strip_hi-strip_lo)
		# When pushing outward from an empty shell, cover the whole enclosed
		# rectangle: find the opposite parallel wall and span to it.
		var opposite:float=NAN
		for other:Dictionary in after.walls:
			if int(other.level)!=level:continue
			var other_h:bool=float(other.w)>float(other.d)
			if other_h!=horizontal:continue
			var other_line:float=float(other.z) if horizontal else float(other.x)
			if absf(other_line-new_line)<.2:continue
			if is_nan(opposite) or absf(other_line-new_line)>absf(opposite-new_line):
				# Prefer the parallel wall on the interior side of the push.
				var toward_old:bool=(other_line-new_line)*(old_line-new_line)>0
				if toward_old:opposite=other_line
		if not is_nan(opposite):
			var deep_lo:float=minf(opposite,new_line)
			var deep_hi:float=maxf(opposite,new_line)
			if horizontal:
				slab.z=(deep_lo+deep_hi)*.5
				slab.d=maxf(.5,deep_hi-deep_lo)
			else:
				slab.x=(deep_lo+deep_hi)*.5
				slab.w=maxf(.5,deep_hi-deep_lo)
		if not Building.lot().encloses(Building.rect(slab).grow(-.02)):return "That would put the floor outside the lot."
		if int(level)==1:
			var supported:bool=false
			for first:Dictionary in after.walls:
				for second:Dictionary in after.walls:
					slab["supports"]=[str(first.id),str(second.id)]
					if Building._perimeter_support_error(after,slab,0).is_empty():supported=true;break
				if supported:break
			if not supported:return "An upper floor needs two complete opposite bearing walls below."
		after.floors.append(slab)
	# Refuse a grab that somehow shrinks floor below the lot or fails validation
	# of the storey's slabs after the edit.
	for floor:Dictionary in after.floors:
		if int(floor.level)!=level:continue
		if not Building.lot().encloses(Building.rect(floor).grow(-.02)):return "That would put the floor outside the lot."
	var _after_area:float=Building._union_area(Building._rects(after,"floors",level))
	if _after_area+Building.EPS<before_area and absf(new_line-old_line)>Building.EPS:
		# Shrinking is allowed; expanding must not lose coverage of the old room.
		pass
	return ""

## Drop this wall and every collinear panel overlapping it, so a doorway cut
## across a bought-plot boundary cannot leave a second stacked panel sealed.
static func _remove_collinear(after:Dictionary,wall:Dictionary,level:int) -> void:
	var remove_ids:Dictionary={str(wall.id):true}
	for other:Dictionary in after.walls:
		if int(other.level)!=level or str(other.id)==str(wall.id):continue
		if not _coincident_wall({"walls":[wall],"floors":[]},other,level).is_empty():
			remove_ids[str(other.id)]=true
	after.walls=after.walls.filter(func(record:Dictionary)->bool:return not remove_ids.has(str(record.id)))

## Replace a wall with the two panels either side of a 1.06 m doorway centred
## as near `center` as the wall's ends allow. Returns an error or "".
static func _cut_door(after:Dictionary,wall:Dictionary,center_value:Variant,level:int) -> String:
	_remove_collinear(after,wall,level)
	var length:float=maxf(float(wall.w),float(wall.d))
	if not Building.number(center_value,-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN) or length<1.55:return "Choose a wall long enough for a doorway."
	var horizontal:bool=float(wall.w)>float(wall.d)
	var center:float=float(wall.x) if horizontal else float(wall.z)
	var door:float=clampf(float(center_value),center-length*.5+.65,center+length*.5-.65)
	for side:int in [-1,1]:
		var low:float=center-length*.5 if side<0 else door+.53
		var high:float=door-.53 if side<0 else center+length*.5
		if high-low<=.05:continue
		var part:Dictionary=wall.duplicate(true);part.id=Building._new_id(after,"walls")
		if horizontal:part.x=(low+high)*.5;part.w=high-low
		else:part.z=(low+high)*.5;part.d=high-low
		after.walls.append(part)
	return ""

## When a click lands in the gap of an existing doorway, merge the two stubs and
## cut again at the new centre so the opening slides along the wall.
static func _relocate_doorway(after:Dictionary,center_value:Variant,level:int) -> Dictionary:
	if not Building.number(center_value,-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN):return {"ok":false}
	var want:float=float(center_value)
	var best:Dictionary={}
	var best_score:float=1.2
	for first:Dictionary in after.walls:
		if int(first.level)!=level:continue
		var first_h:bool=float(first.w)>float(first.d)
		var first_line:float=float(first.z) if first_h else float(first.x)
		var first_mid:float=float(first.x) if first_h else float(first.z)
		var first_half:float=maxf(float(first.w),float(first.d))*.5
		for second:Dictionary in after.walls:
			if str(second.id)==str(first.id) or int(second.level)!=level:continue
			var second_h:bool=float(second.w)>float(second.d)
			if second_h!=first_h:continue
			var second_line:float=float(second.z) if second_h else float(second.x)
			if absf(second_line-first_line)>.08:continue
			var second_mid:float=float(second.x) if second_h else float(second.z)
			var second_half:float=maxf(float(second.w),float(second.d))*.5
			var a_low:float=first_mid-first_half;var a_high:float=first_mid+first_half
			var b_low:float=second_mid-second_half;var b_high:float=second_mid+second_half
			if a_low>b_low:
				var swap_low:float=a_low;var swap_high:float=a_high
				a_low=b_low;a_high=b_high;b_low=swap_low;b_high=swap_high
			var gap:float=b_low-a_high
			if gap<.9 or gap>1.35:continue
			var gap_mid:float=(a_high+b_low)*.5
			var score:float=absf(want-gap_mid)
			if score>=best_score:continue
			best_score=score
			best={"horizontal":first_h,"line":first_line,"low":a_low,"high":b_high,"material":str(first.material),"pattern":str(first.get("pattern","")),"cut":bool(first.get("cut",true)),"height":float(first.get("height",2.6)),"ids":[str(first.id),str(second.id)]}
	if best.is_empty():return {"ok":false}
	var remove:Dictionary={}
	for id:String in best.ids:remove[id]=true
	after.walls=after.walls.filter(func(record:Dictionary)->bool:return not remove.has(str(record.id)))
	var merged:Dictionary={"id":Building._new_id(after,"walls"),"level":level,"height":best.height,"cut":best.cut,"material":best.material}
	if not str(best.pattern).is_empty():merged["pattern"]=best.pattern
	if bool(best.horizontal):
		merged.x=(float(best.low)+float(best.high))*.5;merged.z=float(best.line)
		merged.w=float(best.high)-float(best.low);merged.d=.14
	else:
		merged.z=(float(best.low)+float(best.high))*.5;merged.x=float(best.line)
		merged.d=float(best.high)-float(best.low);merged.w=.14
	after.walls.append(merged)
	var door_error:String=_cut_door(after,merged,want,level)
	if not door_error.is_empty():return {"ok":false,"error":door_error}
	return {"ok":true}

## ------------------------------------------------------------ room packs
##
## A ready-made room is a real structure edit: four walls (sharing any existing
## wall that already stands on one of its edges), one doorway and a carpet floor,
## validated and priced together so the furniture that follows always stands in
## a finished room.

const ROOM_PACK_SIDES:Array[String]=["north","south","west","east"]
const ROOM_PACK_SNAP:float=.9

## Where one edge of an axis-aligned room lies: its line, its span and whether
## it runs along x.
static func _pack_edge(area:Rect2,side:String) -> Dictionary:
	match side:
		"north":return {"horizontal":true,"line":area.position.y,"low":area.position.x,"high":area.end.x}
		"south":return {"horizontal":true,"line":area.end.y,"low":area.position.x,"high":area.end.x}
		"west":return {"horizontal":false,"line":area.position.x,"low":area.position.y,"high":area.end.y}
	return {"horizontal":false,"line":area.end.x,"low":area.position.y,"high":area.end.y}

## The parts of one room edge no existing wall already covers. A room drawn
## against the house reuses its wall instead of stacking a second panel on it.
static func _uncovered_spans(state:Dictionary,edge:Dictionary,level:int) -> Array:
	var spans:Array=[Vector2(float(edge.low),float(edge.high))]
	for wall:Dictionary in state.walls:
		if int(wall.level)!=level or (float(wall.w)>=float(wall.d))!=bool(edge.horizontal):continue
		var line:float=float(wall.z) if edge.horizontal else float(wall.x)
		if absf(line-float(edge.line))>.08:continue
		var center:float=float(wall.x) if edge.horizontal else float(wall.z)
		var half:float=maxf(float(wall.w),float(wall.d))*.5
		var cut:=Vector2(center-half,center+half)
		var kept:Array=[]
		for span:Vector2 in spans:
			if cut.y<=span.x or cut.x>=span.y:kept.append(span);continue
			if cut.x>span.x:kept.append(Vector2(span.x,cut.x))
			if cut.y<span.y:kept.append(Vector2(cut.y,span.y))
		spans=kept
	return spans.filter(func(span:Vector2)->bool:return span.y-span.x>=.3)

static func _room_pack(after:Dictionary,operation:Dictionary,level:int) -> Dictionary:
	if level!=0:return {"error":"Room packs are built on the ground floor."}
	for key:String in ["ax","az","bx","bz"]:
		if not Building.number(operation.get(key),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN):return {"error":"Choose where the room pack goes."}
	if not Building._material(operation.get("material")):return {"error":"Choose a valid carpet."}
	var side:String=str(operation.get("door",""))
	if side not in ROOM_PACK_SIDES:return {"error":"Choose which wall the doorway goes in."}
	var a:=Vector2(float(operation.ax),float(operation.az));var b:=Vector2(float(operation.bx),float(operation.bz))
	var area:=Rect2(Vector2(minf(a.x,b.x),minf(a.y,b.y)),(b-a).abs())
	if area.size.x<2.0 or area.size.y<2.0:return {"error":"A room pack needs at least two metres each way."}
	var length:float=0.0
	for edge_side:String in ROOM_PACK_SIDES:
		var edge:Dictionary=_pack_edge(area,edge_side)
		for span:Vector2 in _uncovered_spans(after,edge,level):
			var mid:float=(span.x+span.y)*.5;var run:float=span.y-span.x
			var wall:Dictionary={"x":mid if edge.horizontal else float(edge.line),"z":float(edge.line) if edge.horizontal else mid,"w":run if edge.horizontal else .14,"d":.14 if edge.horizontal else run}
			wall.merge({"id":Building._new_id(after,"walls"),"level":level,"height":2.6,"cut":true,"material":"eae7d7"})
			after.walls.append(wall);length+=run
	# The doorway goes through whichever wall now stands across the middle of
	# the chosen edge: a new panel, or the house wall the room was built against.
	var door_edge:Dictionary=_pack_edge(area,side)
	var door_at:float=(float(door_edge.low)+float(door_edge.high))*.5
	if operation.has("door_at"):
		if not Building.number(operation.get("door_at"),float(door_edge.low)+.65,float(door_edge.high)-.65):return {"error":"Choose a doorway position along that wall."}
		door_at=float(operation.door_at)
	var host:Dictionary={}
	for wall:Dictionary in after.walls:
		if int(wall.level)!=level or (float(wall.w)>=float(wall.d))!=bool(door_edge.horizontal):continue
		var line:float=float(wall.z) if door_edge.horizontal else float(wall.x)
		var center:float=float(wall.x) if door_edge.horizontal else float(wall.z)
		var half:float=maxf(float(wall.w),float(wall.d))*.5
		if absf(line-float(door_edge.line))<=.08 and absf(door_at-center)<=half-.6:host=wall;break
	if host.is_empty():return {"error":"There is no wall long enough for the room's doorway on that side."}
	var door_error:String=_cut_door(after,host,door_at,level)
	if not door_error.is_empty():return {"error":door_error}
	# Carpet is its own floor record over the room, so it wins the finish even
	# where the house floor already runs beneath; only new area is charged.
	var before_area:float=Building._union_area(Building._rects(after,"floors",level))
	after.floors.append({"id":Building._new_id(after,"floors"),"level":level,"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y,"material":str(operation.material)})
	var added_area:float=maxf(0.0,Building._union_area(Building._rects(after,"floors",level))-before_area)
	return {"cost":int(length*55+added_area*12)+90}

## Fit a room pack of `size` near `center`: on the quarter-metre grid, with any
## edge that lands within ROOM_PACK_SNAP of a parallel wall moved onto that wall,
## so the room shares it instead of leaving a sliver between.
static func room_pack_rect(state:Dictionary,center:Vector2,size:Vector2,level:int=0) -> Rect2:
	var c:=Vector2(snappedf(center.x,Building.CELL),snappedf(center.y,Building.CELL))
	var area:=Rect2(c-size*.5,size)
	var shift:=Vector2.ZERO;var best:=Vector2(ROOM_PACK_SNAP,ROOM_PACK_SNAP)
	for wall:Dictionary in state.get("walls",[]):
		if int(wall.get("level",0))!=level:continue
		var horizontal:bool=float(wall.w)>=float(wall.d)
		var half:float=maxf(float(wall.w),float(wall.d))*.5
		if horizontal:
			if minf(float(wall.x)+half,area.end.x)-maxf(float(wall.x)-half,area.position.x)<.5:continue
			for edge:float in [area.position.y,area.end.y]:
				var move:float=float(wall.z)-edge
				if absf(move)<best.y:best.y=absf(move);shift.y=move
		else:
			if minf(float(wall.z)+half,area.end.y)-maxf(float(wall.z)-half,area.position.y)<.5:continue
			for edge:float in [area.position.x,area.end.x]:
				var move:float=float(wall.x)-edge
				if absf(move)<best.x:best.x=absf(move);shift.x=move
	area.position+=shift
	# Keep the whole room on the household's own land.
	var lot:Rect2=Building.lot().grow(-.3)
	area.position.x=clampf(area.position.x,lot.position.x,lot.end.x-area.size.x)
	area.position.y=clampf(area.position.y,lot.position.y,lot.end.y-area.size.y)
	return area

## Which edge of a room pack gets the doorway. An edge whose far side is already
## floor opens into the house; an edge built against an existing wall is next
## best; otherwise the door faces `toward` (the rest of the home).
static func room_pack_door(state:Dictionary,area:Rect2,toward:Vector2,level:int=0) -> String:
	return room_pack_door_order(state,area,toward,level)[0]

## Every edge, best doorway first, so a caller that finds the best edge blocked
## on its far side can try the next.
static func room_pack_door_order(state:Dictionary,area:Rect2,toward:Vector2,level:int=0) -> Array[String]:
	var scores:Dictionary={}
	var floors:Array=Building._rects(state,"floors",level)
	for side:String in ROOM_PACK_SIDES:
		var edge:Dictionary=_pack_edge(area,side)
		var mid:float=(float(edge.low)+float(edge.high))*.5
		var normal:Vector2={"north":Vector2(0,-1),"south":Vector2(0,1),"west":Vector2(-1,0),"east":Vector2(1,0)}[side]
		var point:Vector2=(Vector2(mid,float(edge.line)) if edge.horizontal else Vector2(float(edge.line),mid))
		var score:float=0.0
		for floor:Rect2 in floors:
			if floor.has_point(point+normal*.6) and not area.has_point(point+normal*.6):score+=4.0;break
		if _uncovered_spans(state,edge,level).is_empty():score+=2.0
		var to:Vector2=toward-area.get_center()
		if to.length()>.01:score+=normal.dot(to.normalized())
		scores[side]=score
	var order:Array[String]=ROOM_PACK_SIDES.duplicate()
	order.sort_custom(func(a:String,b:String)->bool:return float(scores[a])>float(scores[b]))
	return order

## Where along a room pack's edge the doorway can open onto clear floor, nearest
## the middle first. `clear` answers whether a lot point is free to stand on;
## returns NAN when nowhere on that edge is.
static func room_pack_door_at(area:Rect2,side:String,clear:Callable) -> float:
	var edge:Dictionary=_pack_edge(area,side)
	var mid:float=(float(edge.low)+float(edge.high))*.5
	var normal:Vector2={"north":Vector2(0,-1),"south":Vector2(0,1),"west":Vector2(-1,0),"east":Vector2(1,0)}[side]
	var reach:float=(float(edge.high)-float(edge.low))*.5-.65
	var step:float=0.0
	while step<=reach+.001:
		for at:float in ([mid] if step==0.0 else [mid+step,mid-step]):
			var point:Vector2=(Vector2(at,float(edge.line)) if edge.horizontal else Vector2(float(edge.line),at))
			var ok:bool=true
			for across:float in [-.35,0.0,.35]:
				var sample:Vector2=point+normal*.6+(Vector2(across,0) if edge.horizontal else Vector2(0,across))
				if not bool(clear.call(sample)):ok=false;break
			if ok:return at
		step+=Building.CELL
	return NAN

## The existing wall a proposed wall would duplicate, or an empty dictionary. A
## room drawn against another room must share the wall between them rather than
## stacking a second one on the same line — including collinear overlaps across a
## bought-plot boundary, where neither segment fully encloses the other.
static func _coincident_wall(state:Dictionary,proposed:Dictionary,level:int) -> Dictionary:
	var area:=Rect2(Vector2(float(proposed.x)-float(proposed.w)*.5,float(proposed.z)-float(proposed.d)*.5),Vector2(float(proposed.w),float(proposed.d)))
	var proposed_horizontal:bool=float(proposed.w)>=float(proposed.d)
	for wall:Dictionary in state.walls:
		if int(wall.level)!=level:continue
		var other:=Rect2(Vector2(float(wall.x)-float(wall.w)*.5,float(wall.z)-float(wall.d)*.5),Vector2(float(wall.w),float(wall.d)))
		if area.grow(.02).encloses(other) or other.grow(.02).encloses(area):return wall
		var wall_horizontal:bool=float(wall.w)>=float(wall.d)
		if proposed_horizontal!=wall_horizontal:continue
		# Same centre line and overlapping span: one shared wall, so a doorway
		# cut later opens both rooms instead of only one of two stacked panels.
		if proposed_horizontal:
			if absf(float(proposed.z)-float(wall.z))>.08:continue
			var a0:float=area.position.x;var a1:float=area.end.x
			var b0:float=other.position.x;var b1:float=other.end.x
			if minf(a1,b1)-maxf(a0,b0)>.05:return wall
		else:
			if absf(float(proposed.x)-float(wall.x))>.08:continue
			var a0:float=area.position.y;var a1:float=area.end.y
			var b0:float=other.position.y;var b1:float=other.end.y
			if minf(a1,b1)-maxf(a0,b0)>.05:return wall
	return {}


static func _wall_ends(wall:Dictionary) -> Array:
	var horizontal:bool=float(wall.w)>=float(wall.d)
	var half:float=maxf(float(wall.w),float(wall.d))*.5
	if horizontal:return [Vector2(float(wall.x)-half,float(wall.z)),Vector2(float(wall.x)+half,float(wall.z))]
	return [Vector2(float(wall.x),float(wall.z)-half),Vector2(float(wall.x),float(wall.z)+half)]

static func _room_walls(state:Dictionary,start:Dictionary,level:int,side:Variant) -> Array:
	# Walls of the enclosed floor region on one side of the clicked wall. The
	# region flood-fills the cell grid: wall segments rasterize as solid cells
	# and collinear door gaps up to 1.4 m keep a blocked seam, so doorways stay
	# room boundaries; a side that leaks to the outdoors falls back to the
	# joined-wall scope.
	var cell:float=0.25
	var pad:float=.08
	var segments:Array=[]
	var lo:=Vector2(1e9,1e9);var hi:=Vector2(-1e9,-1e9)
	for wall:Dictionary in state.walls:
		if int(wall.level)!=int(level):continue
		var ends:Array=_wall_ends(wall)
		segments.append({"a":ends[0],"b":ends[1]})
		lo=Vector2(minf(lo.x,minf(ends[0].x,ends[1].x)),minf(lo.y,minf(ends[0].y,ends[1].y)))
		hi=Vector2(maxf(hi.x,maxf(ends[0].x,ends[1].x)),maxf(hi.y,maxf(ends[0].y,ends[1].y)))
	if segments.is_empty():return [start]
	lo-=Vector2(2.5,2.5);hi+=Vector2(2.5,2.5)
	var solid:Dictionary={}
	for segment:Dictionary in segments:
		var a2:=Vector2(minf(segment.a.x,segment.b.x),minf(segment.a.y,segment.b.y))-Vector2(pad,pad)
		var b2:=Vector2(maxf(segment.a.x,segment.b.x),maxf(segment.a.y,segment.b.y))+Vector2(pad,pad)
		var c0:=Vector2i(int(floor(a2.x/cell)),int(floor(a2.y/cell)))
		var c1:=Vector2i(int(floor(b2.x/cell)),int(floor(b2.y/cell)))
		for cx:int in range(c0.x,c1.x+1):
			for cz:int in range(c0.y,c1.y+1):
				solid[Vector2i(cx,cz)]=true
	# Door seams: a blocked edge across each collinear gap up to 1.4 m wide.
	var horizontal:Array=[];var vertical:Array=[]
	for segment:Dictionary in segments:
		if absf(segment.a.y-segment.b.y)<.01:horizontal.append(segment)
		elif absf(segment.a.x-segment.b.x)<.01:vertical.append(segment)
	var seams:Dictionary={}
	for group:Array in [horizontal,vertical]:
		for i:int in range(group.size()):
			for j:int in range(i+1,group.size()):
				var a:Dictionary=group[i];var b:Dictionary=group[j]
				var line_y:bool=absf(a.a.y-b.a.y)<.01
				var low:float;var high:float;var line:float
				if line_y:
					if absf(a.a.y-b.a.y)>.01:continue
					low=minf(minf(a.a.x,a.b.x),minf(b.a.x,b.b.x))
					high=maxf(maxf(a.a.x,a.b.x),maxf(b.a.x,b.b.x))
					line=a.a.y
				else:
					if absf(a.a.x-b.a.x)>.01:continue
					low=minf(minf(a.a.y,a.b.y),minf(b.a.y,b.b.y))
					high=maxf(maxf(a.a.y,a.b.y),maxf(b.a.y,b.b.y))
					line=a.a.x
				var ax_span:float=absf(a.a.x-a.b.x)
				var ay_span:float=absf(a.a.y-a.b.y)
				var bx_span:float=absf(b.a.x-b.b.x)
				var by_span:float=absf(b.a.y-b.b.y)
				var gap:float=(high-low)-ax_span-ay_span-bx_span-by_span
				if gap>1.4 or gap<=.05:continue
				var steps:int=int((high-low)/cell)*2+2
				for s:int in range(steps+1):
					var t:float=low+(high-low)*float(s)/float(steps)
					var p:=Vector2(t,line) if line_y else Vector2(line,t)
					var c:=Vector2i(int(floor(p.x/cell)),int(floor(p.y/cell)))
					seams[Vector2i(c.x,c.y)]=true
	# Door seams block like walls: the whole house interior must not merge
	# into one region through the doorway.
	solid.merge(seams)
	var ends:Array=_wall_ends(start)
	var mid:Vector2=(ends[0]+ends[1])*.5
	var normal:=Vector2(0,1) if float(start.w)>=float(start.d) else Vector2(1,0)
	var side_sign:int=1
	if side is Vector2:
		var sp:Vector2=side
		side_sign=1 if (sp-mid).dot(normal)>=0 else -1
	var begin:Vector2i=Vector2i(int(floor(mid.x/cell)),int(floor(mid.y/cell)))+Vector2i(int(normal.x*side_sign),int(normal.y*side_sign))
	var tries:int=0
	while solid.has(begin) and tries<6:
		begin+=Vector2i(int(normal.x*side_sign),int(normal.y*side_sign));tries+=1
	var region:Dictionary={begin:true}
	var frontier:Array=[begin]
	var escaped:bool=false
	while not frontier.is_empty() and not escaped:
		var cur:Vector2i=frontier.pop_back()
		for dir:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
			var nxt:Vector2i=cur+dir
			if nxt.x<int(lo.x/cell) or nxt.y<int(lo.y/cell) or nxt.x>int(hi.x/cell) or nxt.y>int(hi.y/cell):
				escaped=true;continue
			if region.has(nxt) or solid.has(nxt):continue
			region[nxt]=true;frontier.append(nxt)
			if region.size()>4000:escaped=true;break
	var room:Array=[start]
	for wall:Dictionary in state.walls:
		if int(wall.level)!=int(level) or room.has(wall):continue
		var wends:Array=_wall_ends(wall)
		var a2:=Vector2(minf(wends[0].x,wends[1].x),minf(wends[0].y,wends[1].y))-Vector2(pad,pad)
		var b2:=Vector2(maxf(wends[0].x,wends[1].x),maxf(wends[0].y,wends[1].y))+Vector2(pad,pad)
		var c0:=Vector2i(int(floor(a2.x/cell)),int(floor(a2.y/cell)))
		var c1:=Vector2i(int(floor(b2.x/cell)),int(floor(b2.y/cell)))
		var touches:bool=false
		for cx:int in range(c0.x,c1.x+1):
			for cz:int in range(c0.y,c1.y+1):
				for dir:Vector2i in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
					if region.has(Vector2i(cx,cz)+dir):touches=true
				if touches:break
			if touches:break
		if touches:room.append(wall)
	return room

static func _edge_blocked(a:Vector2i,b:Vector2i,blocked:Dictionary) -> bool:
	var low:=a if (a.x<b.x or (a.x==b.x and a.y<b.y)) else b
	var high:=b if low==a else a
	return blocked.has(str(low.x,",",low.y,"|",high.x,",",high.y))

static func _block_edges(a:Vector2,b:Vector2,cell:float,blocked:Dictionary) -> void:
	# Mark every cell-edge pair crossed by the wall segment's centre line.
	var horizontal:bool=absf(a.y-b.y)<.01
	var steps:int=int(maxf(absf(a.x-b.x),absf(a.y-b.y))/cell)*2+2
	for i:int in range(steps+1):
		var p:Vector2=a.lerp(b,float(i)/float(steps))
		var c:=Vector2i(int(floor(p.x/cell)),int(floor(p.y/cell)))
		var nudge:=Vector2i(0,1) if horizontal else Vector2i(1,0)
		var other:=c+nudge
		var low:=c if (c.x<other.x or (c.x==other.x and c.y<other.y)) else other
		var high:=other if low==c else c
		blocked[str(low.x,",",low.y,"|",high.x,",",high.y)]=true

static func _joined_walls(state:Dictionary,start:Dictionary,level:int) -> Array:
	# Walls joined end to end form one room for whole-room paint: a drawn room
	# is its four walls, a doorway keeps both portions, and a partition that
	# meets another wall mid-segment stays a separate choice.
	var room:Array=[start]
	var frontier:Array=[start]
	while not frontier.is_empty():
		var wall:Dictionary=frontier.pop_back()
		for other:Dictionary in state.walls:
			if int(other.level)!=level or room.has(other):continue
			var joined:bool=false
			for a:Vector2 in _wall_ends(wall):
				for b:Vector2 in _wall_ends(other):
					if a.distance_to(b)<=.2:joined=true
			if joined:room.append(other);frontier.append(other)
	return room
