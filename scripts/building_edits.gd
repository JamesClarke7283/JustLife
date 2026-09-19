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
		for wall:Dictionary in walls:
			wall.merge({"id":Building._new_id(after,"walls"),"level":int(level),"height":2.6,"cut":true,"material":"eae7d7"});after.walls.append(wall)
		cost=int(length*55+floor_cost) # Preserve legacy whole-quote currency truncation.
	elif tool=="paint":
		# Repaint one wall segment, or every wall joined to it corner to corner;
		# the colour is a wall material like the floor finishes.
		if not Building.identifier(operation.get("id")):return _error("Choose an existing wall on this level.")
		if not Building._material(operation.get("material")):return _error("Choose a valid wall colour.")
		var scope:String=str(operation.get("scope","wall"))
		if scope not in ["wall","room"]:return _error("Choose whether to paint one wall or the whole room.")
		var wall:Dictionary=Building.find(after,str(operation.id))
		if wall.is_empty() or Building._group_of(after,str(operation.id))!="walls" or int(wall.level)!=int(level):return _error("The selected wall has changed.")
		var side:Variant=null
		if Building.number(operation.get("px"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN) and Building.number(operation.get("pz"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN):
			side=Vector2(float(operation.px),float(operation.pz))
		var changed:int=0
		for target:Dictionary in (_room_walls(after,wall,int(level),side) if scope=="room" else [wall]):
			if str(target.material)==str(operation.material):continue
			target.material=str(operation.material)
			cost+=int(maxf(float(target.w),float(target.d))*6);changed+=1
		if changed==0:return _error("That wall already has this colour." if scope=="wall" else "Those walls already have this colour.")
	else:
		if not Building.identifier(operation.get("id")):return _error("Choose an existing wall on this level.")
		var wall:Dictionary=Building.find(after,str(operation.id))
		if wall.is_empty() or Building._group_of(after,str(operation.id))!="walls" or int(wall.level)!=int(level):return _error("The selected wall has changed.")
		after.walls=after.walls.filter(func(record:Dictionary)->bool:return record.id!=wall.id)
		var length:float=maxf(float(wall.w),float(wall.d))
		if tool=="erase":cost=-int(length*20)
		else:
			if not Building.number(operation.get("center"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN) or length<1.55:return _error("Choose a wall long enough for a doorway.")
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
	if escaped:print("ROOMDBG escaped region_size=",region.size())
	print("ROOMDBG west=",region.has(Vector2i(-12,0))," east=",region.has(Vector2i(12,0))," north_gap_seal=",region.has(Vector2i(0,0)),solid.has(Vector2i(0,0)),seams.has(Vector2i(0,0)))
	var room:Array=[start]
	print("ROOMDBG region_size=",region.size()," solid=",solid.size()," seams=",seams.size()," begin=",begin)
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
