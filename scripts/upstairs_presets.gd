extends RefCounted
## Complete upper-storey layouts. All geometry goes through the same support,
## stair, roof and whole-house transaction validation as individual build tools.
const Building=preload("res://scripts/building_state.gd")
const PRICES:Array[int]=[1000,2000,3000]
const LABELS:Array[String]=["3 bedrooms · 1 bathroom","3 bedrooms · 1 en-suite · main bathroom","4 bedrooms · 2 en-suites · main bathroom"]
const SIDES:Array[String]=["front","back","east","west"]
const SIDE_LABELS:Dictionary={"front":"Front / South","back":"Back / North","east":"East","west":"West"}
static func _error(message:String)->Dictionary:return {"ok":false,"error":message}

static func supported_floor(state:Dictionary)->Dictionary:
	var areas:Array=[]
	var merged:Rect2;var have:bool=false
	for floor:Dictionary in state.floors:
		if int(floor.level)!=0:continue
		var area:Rect2=Building.rect(floor);areas.append(area)
		merged=merged.merge(area) if have else area;have=true
	if have:areas.push_front(merged)
	for area:Rect2 in areas:
		if area.size.x<9.0 or area.size.y<8.5:continue
		var floor:Dictionary={"level":1,"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y,"material":"cfa97e"}
		for first:Dictionary in state.walls:
			if int(first.level)!=0:continue
			for second:Dictionary in state.walls:
				if int(second.level)!=0 or first.id==second.id:continue
				floor["supports"]=[str(first.id),str(second.id)]
				if Building._support_error(state,floor).is_empty():return floor
	return {}

static func candidates(state:Dictionary,choices:Dictionary)->Array:
	var floor:Dictionary=supported_floor(state)
	if floor.is_empty():return []
	var operations:Array=[]
	var center:=Vector2(float(floor.x),float(floor.z))
	for offset:float in [-1.5,0.0,1.5,-.75,.75]:
		for rotation:int in [0,180]:
			for shift:float in [0.,-.5,.5]:
				var operation:Dictionary=choices.duplicate(true)
				operation.merge({"op":"upstairs_preset","hall_x":snappedf(center.x+offset,.25),"stair_z":snappedf(center.y+(-2.0 if rotation==0 else 2.0)+shift,.25),"rotation":rotation},true)
				operations.append(operation)
	return operations

static func propose(current:Dictionary,operation:Variant,funds:Variant)->Dictionary:
	var error:String=Building.validate(current)
	if not error.is_empty():return _error(error)
	if not operation is Dictionary or operation.get("op")!="upstairs_preset" or not Building.number(operation.get("choice"),0,2,true):return _error("Choose an upstairs layout.")
	if not Building.number(funds,0,1e9,true):return _error("Invalid household funds.")
	for floor:Dictionary in current.floors:
		# A staircase's own landing is not an upstairs yet.
		if int(floor.level)==1 and floor.get("landing_for")==null:return _error("These presets add a new upper storey. Edit the existing upstairs with the individual build tools.")
	var index:int=int(operation.choice);var cost:int=PRICES[index]
	if int(funds)<cost:return _error("This upstairs layout needs ℒ%d." % cost)
	for key:String in ["wall_color","floor_color","roof_color"]:
		if not Building._material(operation.get(key)):return _error("Choose valid wall, floor and roof colours.")
	var roof_style:String=str(operation.get("roof_style","gabled"))
	if roof_style not in ["gabled","hipped","flat","mansard","a_frame"]:return _error("Choose a roof style.")
	var window_style:String=str(operation.get("window_style","a"));var door_style:String=str(operation.get("door_style","a"))
	if window_style not in ["a","b","c","d","e"] or door_style not in ["a","b","c","d","e"]:return _error("Choose a window and door style.")
	var sides:Variant=operation.get("window_sides",SIDES)
	if not sides is Array:return _error("Choose the exterior window sides.")
	for side:Variant in sides:
		if side not in SIDES:return _error("Choose a valid window side.")
	if not Building.number(operation.get("hall_x"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN) or not Building.number(operation.get("stair_z"),-Building.Land.MAX_SPAN,Building.Land.MAX_SPAN) or operation.get("rotation") not in [0,180]:return _error("Choose a clear stair position.")
	var floor:Dictionary=supported_floor(current)
	if floor.is_empty():return _error("An upstairs preset needs a supported ground footprint at least 9 × 8.5 metres, with opposite bearing walls.")
	var after:Dictionary=current.duplicate(true)
	var prefix:String="preset_"+str(after.next_serial)+"_"
	floor.id=Building._new_id(after,"floors");floor.material=str(operation.floor_color);after.floors.append(floor)
	var area:Rect2=Building.rect(floor)
	var cx:float=float(operation.hall_x);var left:float=cx-1.75;var right:float=cx+1.75
	if left-area.position.x<2.7 or area.end.x-right<2.7:return _error("Leave room for bedrooms on both sides of the stairs.")
	var middle:float=area.get_center().y
	var rooms:Array=[
		{"name":"Bedroom 1","kind":"bedroom","rect":Rect2(area.position,Vector2(left-area.position.x,middle-area.position.y))},
		{"name":"Bedroom 2","kind":"bedroom","rect":Rect2(area.position.x,middle,left-area.position.x,area.end.y-middle)},
		{"name":"Bedroom 3" if index==2 else "Main bathroom","kind":"bedroom" if index==2 else "bathroom","rect":Rect2(right,area.position.y,area.end.x-right,middle-area.position.y)},
		{"name":"Bedroom 4" if index==2 else "Bedroom 3","kind":"bedroom","rect":Rect2(right,middle,area.end.x-right,area.end.y-middle)}]
	var added:Array=[]
	var wall_color:String=str(operation.wall_color)
	var west:Dictionary=_wall(after,Vector2(area.position.x,area.position.y),Vector2(area.position.x,area.end.y),wall_color)
	var east:Dictionary=_wall(after,Vector2(area.end.x,area.position.y),Vector2(area.end.x,area.end.y),wall_color)
	_wall(after,area.position,Vector2(area.end.x,area.position.y),wall_color)
	_wall(after,Vector2(area.position.x,area.end.y),area.end,wall_color)
	var door_zs:Array[float]=[middle-2.0,middle+1.8]
	_door_wall(after,added,prefix,Vector2(left,area.position.y),Vector2(left,area.end.y),door_zs,90,operation)
	_door_wall(after,added,prefix,Vector2(right,area.position.y),Vector2(right,area.end.y),door_zs,270,operation)
	_wall(after,Vector2(area.position.x,middle),Vector2(left,middle),wall_color)
	_wall(after,Vector2(right,middle),Vector2(area.end.x,middle),wall_color)
	if index==2:
		var bath_start:float=area.end.y-2.0
		_door_wall(after,added,prefix,Vector2(left,bath_start),Vector2(right,bath_start),[cx],180,operation)
		rooms.append({"name":"Main bathroom","kind":"bathroom","rect":Rect2(left,bath_start,right-left,2.0)})
	for room_index:int in ([1] if index==1 else ([0,3] if index==2 else [])):
		var bedroom:Dictionary=rooms[room_index];var bounds:Rect2=bedroom.rect
		var on_left:bool=room_index<2
		var bath:=Rect2(bounds.position.x if on_left else bounds.end.x-1.8,bounds.position.y if room_index%2==0 else bounds.end.y-2.0,1.8,2.0)
		var vertical:float=bath.end.x if on_left else bath.position.x
		var horizontal:float=bath.end.y if room_index%2==0 else bath.position.y
		_door_wall(after,added,prefix,Vector2(vertical,bath.position.y),Vector2(vertical,bath.end.y),[bath.get_center().y],90 if on_left else 270,operation)
		_wall(after,Vector2(bath.position.x,horizontal),Vector2(bath.end.x,horizontal),wall_color)
		rooms.append({"name":str(bedroom.name)+" en-suite","kind":"ensuite","rect":bath})
	for room:Dictionary in rooms.slice(0,4):
		var bounds:Rect2=room.rect
		for side:String in SIDES:
			if side not in sides:continue
			var at:Vector2;var rotation:int
			if side=="west" and is_equal_approx(bounds.position.x,area.position.x):at=Vector2(area.position.x+.13,bounds.get_center().y);rotation=90
			elif side=="east" and is_equal_approx(bounds.end.x,area.end.x):at=Vector2(area.end.x-.13,bounds.get_center().y);rotation=270
			elif side=="back" and is_equal_approx(bounds.position.y,area.position.y):at=Vector2(bounds.get_center().x,area.position.y+.13);rotation=0
			elif side=="front" and is_equal_approx(bounds.end.y,area.end.y):at=Vector2(bounds.get_center().x,area.end.y-.13);rotation=180
			else:continue
			# Keep the frame on one room's wall face; an en-suite partition must
			# never terminate in the middle of a bedroom window.
			for enclosed:Dictionary in rooms:
				if enclosed.kind!="ensuite" or not bounds.encloses(enclosed.rect):continue
				var bath:Rect2=enclosed.rect
				if side in ["west","east"]:
					var divider:float=bath.end.y if is_equal_approx(bath.position.y,bounds.position.y) else bath.position.y
					if absf(at.y-divider)<1.08:
						at.y=(bath.end.y+bounds.end.y)*.5 if is_equal_approx(bath.position.y,bounds.position.y) else (bounds.position.y+bath.position.y)*.5
				else:
					var divider:float=bath.end.x if is_equal_approx(bath.position.x,bounds.position.x) else bath.position.x
					var touches:bool=is_equal_approx(bath.position.y,area.position.y) if side=="back" else is_equal_approx(bath.end.y,area.end.y)
					if touches and absf(at.x-divider)<1.08:at.x=cx
			added.append({"id":prefix+"window_"+str(added.size()),"kind":"house_window","level":1,"x":at.x,"z":at.y,"rotation":rotation,"style":window_style,"color":"efeadb"})
	var stair:Dictionary={"id":Building._new_id(after,"stairs"),"lower":0,"upper":1,"x":cx,"z":float(operation.stair_z),"rotation":int(operation.rotation),"opening":Building._new_id(after,"openings")}
	var hole:Rect2=Building.stair_rect(stair)
	after.stairs.append(stair);after.openings.append({"id":stair.opening,"stair":stair.id,"level":1,"x":hole.get_center().x,"z":hole.get_center().y,"w":hole.size.x,"d":hole.size.y})
	after.roofs=after.roofs.filter(func(roof:Dictionary)->bool:return int(roof.level)!=0 or not Building.rect(roof).intersects(area))
	after.roofs.append({"id":Building._new_id(after,"roofs"),"level":1,"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y,"supports":[str(west.id),str(east.id)],"rotation":0,"pitch":.5,"style":roof_style,"material":str(operation.roof_color)})
	var saved_rooms:Array=[]
	for room:Dictionary in rooms:
		var bounds:Rect2=room.rect
		saved_rooms.append({"name":room.name,"kind":room.kind,"x":bounds.get_center().x,"z":bounds.get_center().y,"w":bounds.size.x,"d":bounds.size.y})
	after["upstairs_preset"]={"choice":index,"rooms":saved_rooms,"window_sides":sides.duplicate()}
	_allocate_refunds(current,after,added,cost)
	after.revision=int(current.revision)+1
	error=Building.validate(after)
	if not error.is_empty():return _error(error)
	return {"ok":true,"operation":operation.duplicate(true),"before":Building.fingerprint(current),"after":after,"cost":cost,"funds_before":int(funds),"funds_after":int(funds)-cost,"added_furnishings":added}

static func _wall(state:Dictionary,a:Vector2,b:Vector2,color:String)->Dictionary:
	var horizontal:bool=is_equal_approx(a.y,b.y)
	var wall:Dictionary={"id":Building._new_id(state,"walls"),"level":1,"x":(a.x+b.x)*.5,"z":(a.y+b.y)*.5,"w":absf(b.x-a.x) if horizontal else .14,"d":.14 if horizontal else absf(b.y-a.y),"height":2.6,"cut":true,"material":color}
	state.walls.append(wall);return wall

static func _door_wall(state:Dictionary,items:Array,prefix:String,a:Vector2,b:Vector2,centers:Array,rotation:int,choices:Dictionary)->void:
	var horizontal:bool=is_equal_approx(a.y,b.y)
	var low:float=a.x if horizontal else a.y;var high:float=b.x if horizontal else b.y
	var cursor:float=low
	for center:float in centers:
		var before:float=center-.53;var after:float=center+.53
		if before>cursor+.02:_wall(state,Vector2(cursor,a.y) if horizontal else Vector2(a.x,cursor),Vector2(before,a.y) if horizontal else Vector2(a.x,before),str(choices.wall_color))
		cursor=after
		var normal:Vector3=Basis(Vector3.UP,deg_to_rad(rotation))*Vector3.BACK
		var at:Vector2=Vector2(center,a.y) if horizontal else Vector2(a.x,center)
		at+=Vector2(normal.x,normal.z)*.16
		items.append({"id":prefix+"door_"+str(items.size()),"kind":"house_door","level":1,"x":at.x,"z":at.y,"rotation":rotation,"style":str(choices.get("door_style","a")),"color":str(choices.wall_color)})
	if high>cursor+.02:_wall(state,Vector2(cursor,a.y) if horizontal else Vector2(a.x,cursor),b,str(choices.wall_color))

## A preset sells as a discounted bundle. Spread half its paid price across all
## parts, keeping a per-unit rate on splittable geometry so edits cannot duplicate
## a lump-sum refund. Ordinary individually purchased pieces keep normal rates.
static func _allocate_refunds(before:Dictionary,after:Dictionary,items:Array,price:int)->void:
	var pieces:Array=[];var total:float=0.0
	for group:String in ["walls","floors","roofs","stairs"]:
		for piece:Dictionary in after[group]:
			if not Building.find(before,str(piece.id)).is_empty():continue
			var standard:float=250.0 if group=="stairs" else float(Building.REFUND_RATES[group])*(maxf(float(piece.w),float(piece.d)) if group=="walls" else float(piece.w)*float(piece.d))
			pieces.append({"record":piece,"group":group,"standard":standard});total+=standard
	for item:Dictionary in items:total+=LifeCatalogVariants.resale_value(item)
	var ratio:float=minf(1.0,float(price)*.5/maxf(total,1.0))
	for piece:Dictionary in pieces:
		if piece.group=="stairs":piece.record["refund_value"]=floori(float(piece.standard)*ratio)
		else:piece.record["refund_rate"]=float(Building.REFUND_RATES[piece.group])*ratio
	for item:Dictionary in items:item["refund_value"]=floori(LifeCatalogVariants.resale_value(item)*ratio)
