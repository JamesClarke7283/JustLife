extends RefCounted
## Adding a whole storey: the house goes up one floor. The new storey gets a slab
## over the footprint of the one below, outer walls standing on the line of the
## walls below them, and the roof is lifted from the old top storey to the new one.
## Up to four storeys (levels 0 to Building.MAX_LEVEL). Pure data: no Nodes, wallet
## or save writes; the same validation and whole-house checks as every build tool.
const Building=preload("res://scripts/building_state.gd")
const Edits=preload("res://scripts/building_edits.gd")
const OP:String="add_storey"
const FLOOR_RATE:float=12.0
const WALL_RATE:float=55.0
## The widest gap in an outer wall line that is a doorway or window bay, filled in
## on the storey above rather than copied as a hole in the new wall.
const GAP_FILL:float=3.0
const WALL_THICKNESS:float=.14

static func _error(message:String)->Dictionary:return {"ok":false,"error":message}

## How many storeys the home has: the ground floor plus every storey built above it.
static func storeys(state:Dictionary)->int:
	return Building.top_level(state)+1

## Whether another storey can go on: there are fewer than four.
static func can_add(state:Dictionary)->bool:
	return Building.top_level(state)<Building.MAX_LEVEL

## The floors of a storey that are part of its rooms, not a staircase's own landing.
static func _storey_floors(state:Dictionary,level:int)->Array:
	var result:Array=[]
	for floor:Dictionary in state.floors:
		if int(floor.level)==level and floor.get("landing_for")==null:result.append(floor)
	return result

static func _thin(wall:Dictionary)->bool:
	return minf(float(wall.w),float(wall.d))<=.20

static func _inside(point:Vector2,areas:Array)->bool:
	for area:Rect2 in areas:
		if area.has_point(point):return true
	return false

## The floors of a storey that are inside the house: a slab whose middle (or one of
## its quarters) lies in a room closed by walls. A patio laid against the front
## wall is outside and is not built over. With no closed room at all (a bare slab),
## every floor counts.
static func _house_floors(state:Dictionary,level:int)->Array:
	var floors:Array=_storey_floors(state,level)
	var inside:Array=[]
	for floor:Dictionary in floors:
		var r:Rect2=Building.rect(floor)
		for point:Vector2 in [r.get_center(),r.position+r.size*Vector2(.25,.25),r.position+r.size*Vector2(.75,.25),r.position+r.size*Vector2(.25,.75),r.position+r.size*Vector2(.75,.75)]:
			if not bool(Edits._enclosed_cells(state,level,point).escaped):inside.append(floor);break
	return inside if not inside.is_empty() else floors

## The floors of the storey below, as rectangles: the new storey's slab goes over them.
static func _footprint(state:Dictionary,level:int)->Array:
	var result:Array=[]
	for floor:Dictionary in _house_floors(state,level):
		result.append({"rect":Building.rect(floor),"material":str(floor.material)})
	return result

## Leave the new walls clear of every staircase arriving on the new storey: its
## opening and its landing keep a gap in any wall line that would cross them.
static func _clear_of_stairs(lines:Array,state:Dictionary,level:int)->Array:
	var clear:Array=[]
	for stair:Dictionary in state.stairs:
		if int(stair.upper)!=level:continue
		clear.append(Building.stair_rect(stair).grow(.02));clear.append(Building.landing_rect(stair,true).grow(.02))
	if clear.is_empty():return lines
	var result:Array=[]
	for line:Dictionary in lines:
		var horizontal:bool=bool(line.horizontal)
		var half:float=float(line.thickness)*.5
		var pieces:Array=[Vector2(float(line.low),float(line.high))]
		for area:Rect2 in clear:
			var across_low:float=area.position.y if horizontal else area.position.x
			var across_high:float=area.end.y if horizontal else area.end.x
			if across_high<=float(line.line)-half or across_low>=float(line.line)+half:continue
			var cut_low:float=area.position.x if horizontal else area.position.y
			var cut_high:float=area.end.x if horizontal else area.end.y
			var kept:Array=[]
			for piece:Vector2 in pieces:
				if cut_high<=piece.x or cut_low>=piece.y:kept.append(piece);continue
				if cut_low>piece.x:kept.append(Vector2(piece.x,cut_low))
				if cut_high<piece.y:kept.append(Vector2(cut_high,piece.y))
			pieces=kept
		for piece:Vector2 in pieces:
			var part:Dictionary=line.duplicate();part.low=piece.x;part.high=piece.y
			result.append(part)
	return result

## Whether a point on a wall line is on the outside of the storey: floor on one
## side of it and none on the other.
static func _boundary(point:Vector2,horizontal:bool,areas:Array)->bool:
	var across:=Vector2(0,.3) if horizontal else Vector2(.3,0)
	return _inside(point+across,areas)!=_inside(point-across,areas)

## The outer walls of a storey, joined into whole lines: a doorway or window bay in
## a wall below is no hole in the wall above.
static func _outer_lines(state:Dictionary,level:int)->Array:
	var areas:Array=[]
	for floor:Dictionary in _house_floors(state,level):areas.append(Building.rect(floor))
	var groups:Dictionary={}
	for wall:Dictionary in state.walls:
		if int(wall.level)!=level or not _thin(wall):continue
		var r:Rect2=Building.rect(wall)
		var horizontal:bool=float(wall.w)>float(wall.d)
		if not _boundary(r.get_center(),horizontal,areas):continue
		var line:float=snappedf(r.get_center().y if horizontal else r.get_center().x,.01)
		var thickness:float=minf(r.size.x,r.size.y)
		var key:String="%s:%.2f:%.3f" % ["h" if horizontal else "v",line,thickness]
		if not groups.has(key):groups[key]={"horizontal":horizontal,"line":r.get_center().y if horizontal else r.get_center().x,"thickness":thickness,"material":str(wall.material),"spans":[]}
		groups[key].spans.append(Vector2(r.position.x,r.end.x) if horizontal else Vector2(r.position.y,r.end.y))
	var lines:Array=[]
	for key:String in groups:
		var group:Dictionary=groups[key]
		var spans:Array=group.spans
		spans.sort_custom(func(a:Vector2,b:Vector2)->bool:return a.x<b.x)
		var current:Vector2=spans[0]
		for index:int in range(1,spans.size()+1):
			var next:Vector2=spans[index] if index<spans.size() else Vector2(INF,INF)
			var gap:float=next.x-current.y
			var middle:float=(current.y+next.x)*.5
			var at:=Vector2(middle,float(group.line)) if bool(group.horizontal) else Vector2(float(group.line),middle)
			if index<spans.size() and (gap<=.001 or (gap<=GAP_FILL and _boundary(at,bool(group.horizontal),areas))):
				current.y=maxf(current.y,next.y);continue
			lines.append({"horizontal":group.horizontal,"line":group.line,"thickness":group.thickness,"low":current.x,"high":current.y,"material":group.material})
			current=next
	return lines

## The boundary of a set of rectangles, as wall lines along its edges: used when the
## storey below has no outer walls of its own to raise.
static func _boundary_lines(areas:Array)->Array:
	var lines:Array=[]
	for area:Rect2 in areas:
		for edge:Array in [[true,area.position.y,area.position.x,area.end.x],[true,area.end.y,area.position.x,area.end.x],[false,area.position.x,area.position.y,area.end.y],[false,area.end.x,area.position.y,area.end.y]]:
			var horizontal:bool=edge[0];var line:float=edge[1];var low:float=edge[2];var high:float=edge[3]
			# Split the edge where it runs between two rectangles; keep only outer runs.
			var cuts:Array=[low,high]
			for other:Rect2 in areas:
				for value:float in ([other.position.x,other.end.x] if horizontal else [other.position.y,other.end.y]):
					if value>low and value<high and not cuts.has(value):cuts.append(value)
			cuts.sort()
			var start:float=NAN
			for index:int in cuts.size()-1:
				var middle:float=(cuts[index]+cuts[index+1])*.5
				var at:=Vector2(middle,line) if horizontal else Vector2(line,middle)
				var outer:bool=_boundary(at,horizontal,areas)
				if outer and is_nan(start):start=cuts[index]
				if (not outer or index==cuts.size()-2) and not is_nan(start):
					lines.append({"horizontal":horizontal,"line":line,"thickness":WALL_THICKNESS,"low":start,"high":cuts[index+1] if outer else cuts[index],"material":"eae7d7"})
					start=NAN
	return lines

static func _wall_record(state:Dictionary,level:int,line:Dictionary)->Dictionary:
	var horizontal:bool=bool(line.horizontal)
	var length:float=float(line.high)-float(line.low)
	var middle:float=(float(line.high)+float(line.low))*.5
	return {"id":Building._new_id(state,"walls"),"level":level,
		"x":middle if horizontal else float(line.line),"z":float(line.line) if horizontal else middle,
		"w":length if horizontal else float(line.thickness),"d":float(line.thickness) if horizontal else length,
		"height":2.6,"cut":true,"material":str(line.material)}

static func _overlaps_parallel(state:Dictionary,wall:Dictionary)->bool:
	for other:Dictionary in state.walls:
		if int(other.level)!=int(wall.level) or str(other.id)==str(wall.id):continue
		if (float(wall.w)>float(wall.d))==(float(other.w)>float(other.d)) and Building.rect(wall).grow(-.001).intersects(Building.rect(other).grow(-.001)):return true
	return false

## Two opposite walls of a storey that hold up this roof, or [] when none do.
static func _roof_supports(state:Dictionary,roof:Dictionary,level:int)->Array:
	var trial:Dictionary=roof.duplicate(true)
	for first:Dictionary in state.walls:
		if int(first.level)!=level:continue
		for second:Dictionary in state.walls:
			if int(second.level)!=level or str(first.id)==str(second.id):continue
			trial["supports"]=[str(first.id),str(second.id)]
			if Building._perimeter_support_error(state,trial,level).is_empty():return trial.supports
	return []

static func propose(current:Dictionary,operation:Variant,funds:Variant)->Dictionary:
	var error:String=Building.validate(current)
	if not error.is_empty():return _error(error)
	if not operation is Dictionary or operation.get("op")!=OP or not Building.number(funds,0,1e9,true):return _error("Invalid storey addition.")
	if int(current.revision)>=1000000000:return _error("Building revision limit reached.")
	var below:int=Building.top_level(current)
	if below>=Building.MAX_LEVEL:return _error("This home already has four storeys, the most a home can have.")
	var level:int=below+1
	var footprint:Array=_footprint(current,below)
	if footprint.is_empty():return _error("Lay a floor first: a new storey goes on top of the rooms below it.")
	var after:Dictionary=current.duplicate(true)
	var floor_before:float=Building._union_area(Building._rects(after,"floors",level))
	var areas:Array=[]
	for part:Dictionary in footprint:
		var area:Rect2=part.rect
		if area.size.x<.5 or area.size.y<.5:continue
		areas.append(area)
		after.floors.append({"id":Building._new_id(after,"floors"),"level":level,"x":area.get_center().x,"z":area.get_center().y,"w":area.size.x,"d":area.size.y,"material":"cfa97e"})
	if areas.is_empty():return _error("Lay a floor first: a new storey goes on top of the rooms below it.")
	# The walls go up with the house: the outer walls below are raised on the new
	# storey, on the same lines, as whole walls. The slab is carried out under them,
	# over the walls (and the lintels over their doorways) beneath.
	var lines:Array=_outer_lines(current,below)
	var copied:bool=not lines.is_empty()
	if not copied:lines=_boundary_lines(areas)
	lines=_clear_of_stairs(lines,current,level)
	var wall_length:float=0.0
	for line:Dictionary in lines:
		if float(line.high)-float(line.low)<.3:continue
		var wall:Dictionary=_wall_record(after,level,line)
		if _overlaps_parallel(after,wall):continue
		if copied and not Building._covered(Building.rect(wall),Building._rects(after,"floors",level)):
			after.floors.append({"id":Building._new_id(after,"floors"),"level":level,"x":float(wall.x),"z":float(wall.z),"w":float(wall.w),"d":float(wall.d),"material":"cfa97e"})
		after.walls.append(wall);wall_length+=maxf(float(wall.w),float(wall.d))
	# The roof goes up too: each roof on the old top storey is lifted onto the new
	# one, resting on the walls just raised.
	var lifted:int=0
	for roof:Dictionary in after.roofs:
		if int(roof.level)!=below:continue
		var raised:Dictionary=roof.duplicate(true);raised.level=level
		var supports:Array=_roof_supports(after,raised,level)
		if supports.is_empty() or not Building._covered(Building.rect(raised),Building._rects(after,"floors",level)):continue
		roof.level=level;roof.supports=supports;lifted+=1
	var cost:int=roundi(maxf(0.0,Building._union_area(Building._rects(after,"floors",level))-floor_before)*FLOOR_RATE+wall_length*WALL_RATE)
	if cost<=0:return _error("This storey adds nothing new.")
	if int(funds)<cost:return _error("A new storey costs ℒ%d." % cost)
	after.revision=int(current.revision)+1
	error=Building.validate(after)
	if not error.is_empty():
		if error.contains("roof"):return _error("The roof could not be lifted onto the new storey (%s) Delete or edit that roof first." % error)
		return _error(error)
	return {"ok":true,"operation":operation.duplicate(true),"before":Building.fingerprint(current),"after":after,"cost":cost,"funds_before":int(funds),"funds_after":int(funds)-cost,"level":level,"roofs_lifted":lifted}
