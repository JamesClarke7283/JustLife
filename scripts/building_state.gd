extends RefCounted
class_name LifeBuildingState
## Detached building data, support and transactions. No Nodes, wallet or save writes.
const RoofRules=preload("res://scripts/roof_rules.gd")
const Land=preload("res://scripts/land.gd")
const VERSION:int=2
const GROUND_Y:float=.16
const RISE:float=3.0
## The highest storey: the ground floor is level 0, so a home has up to four storeys.
const MAX_LEVEL:int=3
const CELL:float=.25
const STAIR_WIDTH:float=1.25
const STAIR_RUN:float=3.75
const STAIR_STEPS:int=15
const GUARD_EDGE:float=.68
const GUARD_HALF:float=.043
const EPS:float=.000001
const REFUND_RATES:Dictionary={"walls":20.0,"floors":4.0,"roofs":6.0}
## The navigable lot: the household's own land, which is the starting plot plus
## every neighbouring plot it has bought. `LifeLand` owns the arithmetic; this is
## the one live copy the building rules, the navigation graph, the compatibility
## grid and the camera pan all read, so buying a plot moves the boundary for all
## of them at once.
##
## The land is set by the world when a household's layout is restored, and is not
## part of the construction record: it belongs to the household, not to the house
## standing on it.
static var land: Dictionary = Land.fresh()

## Set the household's land. Everything derived from the lot is rebuilt by the
## caller after this, because the navigation region and the grid both change.
static func set_land(value: Variant) -> void:
	land = Land.from_save(value)

## The whole lot as a rectangle.
static func lot() -> Rect2:
	return Land.rect(land)

## Half a navigation cell, so a derived grid always contains the whole lot.
const LOT_MARGIN:float=.25
const GROUPS:Array[String]=["walls","floors","stairs","openings","roofs"]
const MAX_RECORDS:int=512

static func fresh() -> Dictionary:
	return {"kind":"__construction","version":VERSION,"revision":0,"next_serial":1,"levels":range(MAX_LEVEL+1),"walls":[],"floors":[],"stairs":[],"openings":[],"roofs":[]}

static func number(value:Variant,low:float,high:float,whole:bool=false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high and (not whole or float(value)==floorf(float(value)))

static func identifier(value:Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>100:return false
	for character:String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":return false
	return true

static func level_y(level:int) -> float:return GROUND_Y+RISE*level
## The whole lot in navigation cells, derived from the live land so a larger lot
## is never half-covered by the graph, the compatibility grid or a pan clamp.
static func cell_range() -> Rect2i:
	var bounds:Rect2=lot()
	var low:=Vector2i(floori(bounds.position.x/CELL)-1,floori(bounds.position.y/CELL)-1)
	var high:=Vector2i(ceili(bounds.end.x/CELL)+1,ceili(bounds.end.y/CELL)+1)
	return Rect2i(low,high-low)
static func rect(record:Dictionary) -> Rect2:return Rect2(float(record.x)-float(record.w)/2,float(record.z)-float(record.d)/2,float(record.w),float(record.d))
static func _error(message:String) -> Dictionary:return {"ok":false,"error":message}
static func fingerprint(state:Dictionary) -> String:return JSON.stringify(state).sha256_text()

static func _rect_error(record:Dictionary) -> String:
	# The real bound is the household's own lot, which grows as plots are bought;
	# the numeric guard only keeps a hostile value out of the arithmetic, so it
	# must not be tighter than the largest lot a household can own.
	for key:String in ["x","z","w","d"]:
		if not number(record.get(key),-Land.MAX_SPAN,Land.MAX_SPAN):return "A building rectangle has invalid numbers."
	if float(record.w)<=0 or float(record.d)<=0 or not lot().encloses(rect(record)):return "A building rectangle is outside the lot."
	return ""

static func _material(value:Variant) -> bool:
	if not value is String or value.length()!=6:return false
	for character:String in value.to_lower():
		if not character in "0123456789abcdef":return false
	return true

static func find(state:Dictionary,id:String) -> Dictionary:
	for group:String in GROUPS:
		for record:Dictionary in state[group]:
			if str(record.id)==id:return record
	return {}

static func _group_of(state:Dictionary,id:String) -> String:
	for group:String in GROUPS:
		for record:Dictionary in state[group]:
			if str(record.id)==id:return group
	return ""

static func stair_point(stair:Dictionary,along:float,height:float=0.0) -> Vector3:
	var local:=Vector3(0,height,along)
	return Vector3(float(stair.x),level_y(int(stair.lower)),float(stair.z))+Basis(Vector3.UP,deg_to_rad(float(stair.rotation)))*local

static func stair_rect(stair:Dictionary) -> Rect2:
	var center:Vector3=stair_point(stair,STAIR_RUN*.5)
	var size:=Vector2(STAIR_WIDTH,STAIR_RUN)
	if int(stair.rotation)%180!=0:size=Vector2(size.y,size.x)
	return Rect2(Vector2(center.x,center.z)-size*.5,size)

static func landing_rect(stair:Dictionary,upper:bool) -> Rect2:
	var center:Vector3=stair_point(stair,STAIR_RUN+.5 if upper else -.5)
	var size:=Vector2(STAIR_WIDTH,1.0)
	if int(stair.rotation)%180!=0:size=Vector2(size.y,size.x)
	return Rect2(Vector2(center.x,center.z)-size*.5,size)

static func guard_runs(stair:Dictionary) -> Array:
	# Authored span/post kit sits outside the exact opening. Upper landing exit
	# stays open; this is derived geometry owned by the stair, not separate IDs.
	var origin:Vector3=stair_point(stair,0,RISE)
	var basis:=Basis(Vector3.UP,deg_to_rad(float(stair.rotation)))
	var left:Vector3=origin+basis*Vector3(-GUARD_EDGE,0,-.055)
	var right:Vector3=origin+basis*Vector3(GUARD_EDGE,0,-.055)
	return [[left,origin+basis*Vector3(-GUARD_EDGE,0,STAIR_RUN)],[right,origin+basis*Vector3(GUARD_EDGE,0,STAIR_RUN)],[left,right]]

static func guard_footprints(stair:Dictionary) -> Array:
	var result:Array=[]
	for run:Array in guard_runs(stair):
		var first:Vector3=run[0];var last:Vector3=run[1]
		var low:=Vector2(minf(first.x,last.x)-GUARD_HALF,minf(first.z,last.z)-GUARD_HALF)
		var high:=Vector2(maxf(first.x,last.x)+GUARD_HALF,maxf(first.z,last.z)+GUARD_HALF)
		result.append(Rect2(low,high-low))
	return result

static func _rects(state:Dictionary,group:String,level:int) -> Array:
	var result:Array=[]
	for record:Dictionary in state[group]:
		if int(record.level)==level:result.append(rect(record))
	return result

static func _covered(bounds:Rect2,surfaces:Array,holes:Array=[]) -> bool:
	# Exact axis-aligned arrangement cells: catches holes/gaps between all sampled
	# corners or centers. Geometry is constant within each partition cell.
	var xs:Array[float]=[bounds.position.x,bounds.end.x]
	var zs:Array[float]=[bounds.position.y,bounds.end.y]
	for area:Rect2 in surfaces+holes:
		if not area.intersects(bounds):continue
		for x:float in [area.position.x,area.end.x]:
			if x>bounds.position.x and x<bounds.end.x and not xs.has(x):xs.append(x)
		for z:float in [area.position.y,area.end.y]:
			if z>bounds.position.y and z<bounds.end.y and not zs.has(z):zs.append(z)
	xs.sort();zs.sort()
	for i:int in range(xs.size()-1):
		for j:int in range(zs.size()-1):
			var at:=Vector2((xs[i]+xs[i+1])*.5,(zs[j]+zs[j+1])*.5)
			var supported:bool=false
			for area:Rect2 in surfaces:
				if area.has_point(at):supported=true;break
			if not supported:return false
			for area:Rect2 in holes:
				if area.has_point(at):return false
	return bounds.size.x>0 and bounds.size.y>0

static func footprint_supported(state:Dictionary,level:int,bounds:Rect2,include_terrain:bool=false) -> bool:
	if level<0 or level>MAX_LEVEL or not lot().encloses(bounds):return false
	var surfaces:Array=_rects(state,"floors",level)
	surfaces.append_array(_wall_bearing_rects(state,level))
	if level==0 and include_terrain:surfaces.append(lot())
	return _covered(bounds,surfaces,_rects(state,"openings",level))

static func _wall_bearing_rects(state:Dictionary,level:int) -> Array:
	var result:Array=[]
	if level<1:return result
	var floors:Array=_rects(state,"floors",level);var holes:Array=_rects(state,"openings",level)
	for wall:Dictionary in state.walls:
		if int(wall.level)!=level:continue
		var full:Rect2=rect(wall)
		if _covered(full,floors,holes):continue
		var crosses_hole:bool=false
		for hole:Rect2 in holes:
			if full.intersects(hole):crosses_hole=true;break
		if crosses_hole:continue
		# The actual slab gains a bearing strip under a normal edge-centered
		# wall, only when one continuous full-length inner half is supported.
		var horizontal:bool=full.size.x>=full.size.y
		if minf(full.size.x,full.size.y)>.20:continue
		var half:Rect2=full
		if horizontal:half.size.y*=.5
		else:half.size.x*=.5
		var opposite:Rect2=half
		if horizontal:opposite.position.y+=half.size.y
		else:opposite.position.x+=half.size.x
		if _covered(half,floors,holes) or _covered(opposite,floors,holes):result.append(full)
	return result

static func surface_tiles(state:Dictionary,level:int) -> Array:
	# Non-overlapping visual/support rectangles, with exact stair voids cut out.
	# Material follows the last covering floor record, matching finish overlays.
	var surfaces:Array=_rects(state,"floors",level)
	var bearings:Array=_wall_bearing_rects(state,level)
	surfaces.append_array(bearings)
	var holes:Array=_rects(state,"openings",level)
	var xs:Array[float]=[];var zs:Array[float]=[];var result:Array=[]
	var finish_bounds:Array=[]
	for floor:Dictionary in state.floors:
		if int(floor.level)==level:
			for finish:Dictionary in floor.get("finish_regions",[]):finish_bounds.append(rect(finish))
	for area:Rect2 in surfaces+holes+finish_bounds:
		for x:float in [area.position.x,area.end.x]:
			if not xs.has(x):xs.append(x)
		for z:float in [area.position.y,area.end.y]:
			if not zs.has(z):zs.append(z)
	xs.sort();zs.sort()
	for i:int in range(xs.size()-1):
		for j:int in range(zs.size()-1):
			var tile:=Rect2(xs[i],zs[j],xs[i+1]-xs[i],zs[j+1]-zs[j])
			if not _covered(tile,surfaces,holes):continue
			var owner:Dictionary={"id":"wall_bearing","material":"cfa97e"}
			for floor:Dictionary in state.floors:
				if int(floor.level)==level and rect(floor).has_point(tile.get_center()):
					owner=floor.duplicate()
					for finish:Dictionary in floor.get("finish_regions",[]):
						if rect(finish).has_point(tile.get_center()):owner.merge(finish,true)
			result.append({"rect":tile,"level":level,"source_id":str(owner.id),"material":str(owner.material),"carpet":str(owner.get("carpet",""))})
	return result

static func blocked_rect(state:Dictionary,level:int,bounds:Rect2,include_stairs:bool=true) -> bool:
	for wall:Dictionary in state.walls:
		if int(wall.level)==level and rect(wall).intersects(bounds):return true
	if include_stairs:
		for stair:Dictionary in state.stairs:
			if level==int(stair.lower) and stair_rect(stair).intersects(bounds):return true
			if level==int(stair.upper):
				for guard:Rect2 in guard_footprints(stair):
					if guard.intersects(bounds):return true
	return false

## Whether an upper floor stands over the storey below it: that storey's floors or
## the walls standing on them. An upper floor needs no bearing walls of its own.
static func _footing(state:Dictionary,lower:int,bounds:Rect2) -> bool:
	if lower<0 or lower>MAX_LEVEL or not lot().encloses(bounds):return false
	# A staircase's landing holds up only the people on it, not a floor above.
	var surfaces:Array=[]
	for floor:Dictionary in state.floors:
		if int(floor.level)==lower and floor.get("landing_for")==null:surfaces.append(rect(floor))
	surfaces.append_array(_rects(state,"walls",lower))
	surfaces.append_array(_lintels(state,lower))
	return _covered(bounds,surfaces)

## The widest doorway or window bay a wall line spans with a lintel.
const LINTEL_SPAN:float=3.0

## The lintels over the doorways in a storey's walls: the gap between two lengths
## of the same wall line, up to LINTEL_SPAN wide, carries the floor above like the
## wall either side of it.
static func _lintels(state:Dictionary,level:int) -> Array:
	var lines:Dictionary={}
	for wall:Dictionary in state.walls:
		if int(wall.level)!=level or minf(float(wall.w),float(wall.d))>.20:continue
		var r:Rect2=rect(wall)
		var horizontal:bool=float(wall.w)>float(wall.d)
		var key:String="%s:%.2f:%.3f" % ["h" if horizontal else "v",r.get_center().y if horizontal else r.get_center().x,minf(r.size.x,r.size.y)]
		if not lines.has(key):lines[key]={"horizontal":horizontal,"rects":[]}
		lines[key].rects.append(r)
	var result:Array=[]
	for key:String in lines:
		var horizontal:bool=lines[key].horizontal
		var spans:Array=lines[key].rects
		spans.sort_custom(func(a:Rect2,b:Rect2)->bool:return (a.position.x if horizontal else a.position.y)<(b.position.x if horizontal else b.position.y))
		for index:int in range(1,spans.size()):
			var before:Rect2=spans[index-1];var after:Rect2=spans[index]
			var start:float=before.end.x if horizontal else before.end.y
			var end:float=after.position.x if horizontal else after.position.y
			if end-start<=EPS or end-start>LINTEL_SPAN:continue
			result.append(Rect2(start,before.position.y,end-start,before.size.y) if horizontal else Rect2(before.position.x,start,before.size.x,end-start))
	return result

static func _support_error(state:Dictionary,record:Dictionary) -> String:
	var lower:int=int(record.level)-1
	if lower<0:return ""
	# A staircase's own landing is held up by the stair, wherever it climbs from.
	if record.get("landing_for")!=null:return ""
	if not _footing(state,lower,rect(record)):return "An upper floor must stand over the floor of the storey below it."
	return ""

## The top storey a home has really built: the highest level with a floor that is
## not just a staircase's landing. 0 for a ground-floor home.
static func top_level(state:Dictionary) -> int:
	var top:int=0
	for floor:Dictionary in state.get("floors",[]):
		if floor.get("landing_for")==null:top=maxi(top,int(floor.level))
	return top

## The highest level anything stands on, landings included.
static func highest_level(state:Dictionary) -> int:
	var top:int=0
	for floor:Dictionary in state.get("floors",[]):top=maxi(top,int(floor.level))
	return top

## The floor a staircase brings with it at its top: the opening, the upper landing
## and the rail around the opening, snapped out to the quarter-metre grid so the
## slab meets the walls and floors laid on that grid.
static func stair_top_area(stair:Dictionary) -> Rect2:
	var area:Rect2=stair_rect(stair).merge(landing_rect(stair,true))
	for guard:Rect2 in guard_footprints(stair):area=area.merge(guard)
	area=area.grow(.05)
	var low:=Vector2(floorf(area.position.x/CELL)*CELL,floorf(area.position.y/CELL)*CELL)
	var high:=Vector2(ceilf(area.end.x/CELL)*CELL,ceilf(area.end.y/CELL)*CELL)
	return Rect2(low,high-low).intersection(lot())

static func _perimeter_support_error(state:Dictionary,record:Dictionary,support_level:int) -> String:
	var supports:Variant=record.get("supports")
	if not supports is Array or supports.size()!=2 or supports[0]==supports[1]:return "A slab or roof needs two distinct opposite support walls."
	var walls:Array=[]
	for id:Variant in supports:
		if not identifier(id) or _group_of(state,id)!="walls":return "A slab or roof refers to a missing support wall."
		var wall:Dictionary=find(state,id)
		if int(wall.level)!=support_level or float(wall.height)<2.6:return "A support wall is on the wrong level or too short."
		walls.append(rect(wall).grow(.001))
	var area:Rect2=rect(record)
	for axis:int in [0,1]:
		var good:bool=true
		for index:int in range(2):
			var a:Vector2=area.position
			var b:Vector2=Vector2(area.end.x,area.position.y) if axis==0 else Vector2(area.position.x,area.end.y)
			if index==1:
				if axis==0:a.y=area.end.y;b.y=area.end.y
				else:a.x=area.end.x;b.x=area.end.x
			if not (walls[index].has_point(a) and walls[index].has_point(b)):good=false
		if good:return ""
	# Ordering of the two physical walls is immaterial.
	walls.reverse()
	for axis:int in [0,1]:
		var good:bool=true
		for index:int in range(2):
			var a:Vector2=area.position
			var b:Vector2=Vector2(area.end.x,area.position.y) if axis==0 else Vector2(area.position.x,area.end.y)
			if index==1:
				if axis==0:a.y=area.end.y;b.y=area.end.y
				else:a.x=area.end.x;b.x=area.end.x
			if not (walls[index].has_point(a) and walls[index].has_point(b)):good=false
		if good:return ""
	return "Support walls must cover two opposite floor edges."

static func validate(state:Variant) -> String:
	if not state is Dictionary or state.get("kind")!="__construction" or state.get("version")!=VERSION:return "Unsupported building format."
	if not number(state.get("revision"),0,1e9,true) or not number(state.get("next_serial"),1,1e9,true):return "Invalid building revision."
	var levels:Variant=state.get("levels")
	if not levels is Array or levels.size()<2 or levels.size()>MAX_LEVEL+1:return "Invalid building levels."
	for index:int in levels.size():
		if not number(levels[index],index,index,true):return "Invalid building levels."
	var cleared:Variant=state.get("cleared_vegetation",[])
	if not cleared is Array or cleared.size()>4096:return "Invalid cleared garden plants."
	var seen_plants:Dictionary={}
	for plant_id:Variant in cleared:
		if not identifier(plant_id) or seen_plants.has(plant_id):return "Invalid cleared garden plant identity."
		seen_plants[plant_id]=true
	var ids:Dictionary={};var count:int=0
	for group:String in GROUPS:
		if not state.get(group) is Array:return "Invalid building collection: "+group
		count+=state[group].size()
		if count>MAX_RECORDS:return "Too many building records."
		for value:Variant in state[group]:
			if not value is Dictionary or not identifier(value.get("id")) or ids.has(value.id):return "Duplicate or invalid building identity."
			ids[value.id]=group
			if value.has("refund_rate") and (not REFUND_RATES.has(group) or not number(value.refund_rate,0,float(REFUND_RATES.get(group,0)))):return "Invalid construction refund rate."
			if value.has("refund_value") and (group!="stairs" or not number(value.refund_value,0,250,true)):return "Invalid staircase refund value."
			if group=="stairs":
				if not number(value.get("lower"),0,MAX_LEVEL-1,true) or not number(value.get("upper"),1,MAX_LEVEL,true) or int(value.upper)!=int(value.lower)+1 or not number(value.get("rotation"),0,270,true) or int(value.rotation)%90!=0:return "A stair must join adjacent supported levels with a right-angle rotation."
				for key:String in ["x","z"]:
					if not number(value.get(key),-Land.MAX_SPAN,Land.MAX_SPAN) or not is_equal_approx(snappedf(float(value[key]),CELL),float(value[key])):return "A stair has an invalid grid position."
				if not identifier(value.get("opening")) or not lot().encloses(stair_rect(value)) or not lot().encloses(landing_rect(value,false)) or not lot().encloses(landing_rect(value,true)):return "A stair or landing extends beyond the lot."
			else:
				if not number(value.get("level"),0,MAX_LEVEL,true):return "A record has an invalid level."
				var error:String=_rect_error(value)
				if not error.is_empty():return error
				if group in ["walls","floors","roofs"] and not _material(value.get("material")):return "A building material is invalid."
				if group=="walls" and (not number(value.get("height"),2.6,2.6) or not value.get("cut") is bool):return "A wall has invalid height or cutaway data."
				if group=="openings" and (not number(value.level,1,MAX_LEVEL,true) or not identifier(value.get("stair"))):return "An opening has no valid owning staircase."
				if group=="floors" and value.get("landing_for")!=null and not identifier(value.landing_for):return "A staircase landing names an invalid staircase."
				if group=="roofs" and (not number(value.get("pitch"),.05,1.0) or not number(value.get("rotation"),0,90,true) or int(value.rotation)%90!=0):return "Invalid roof parameters."
				if group=="roofs":
					var style:String=LifeRoofGeometry.normalize_style(value.get("style","gabled"))
					if style not in LifeRoofGeometry.STYLES:return "Choose a valid roof style."
					if style!="flat" and float(value.pitch)<.2:return "Invalid roof pitch for that style."
	for floor:Dictionary in state.floors:
		var finishes:Variant=floor.get("finish_regions",[])
		if not finishes is Array or finishes.size()>512:return "Invalid floor finish regions."
		for finish:Variant in finishes:
			if not finish is Dictionary or not _rect_error(finish).is_empty() or not rect(floor).encloses(rect(finish)) or not _material(finish.get("material")):return "A floor finish must stay inside its slab."
			if str(finish.get("carpet","")) not in ["","plain","geometric","loop","striped","vintage"]:return "Invalid carpet style."
		if floor.get("landing_for")!=null:
			# Only a real staircase arriving on that storey holds a landing up, and
			# only the landing it brought: its opening, landing and rail.
			if _group_of(state,str(floor.landing_for))!="stairs" or int(find(state,str(floor.landing_for)).upper)!=int(floor.level):return "A staircase landing has no staircase beneath it."
			if not stair_top_area(find(state,str(floor.landing_for))).grow(.01).encloses(rect(floor)):return "A staircase landing is larger than the stairs' own landing."
		var error:String=_support_error(state,floor)
		if not error.is_empty():return error
	for wall:Dictionary in state.walls:
		if int(wall.level)>=1 and not footprint_supported(state,int(wall.level),rect(wall)):return "An upper wall needs continuous floor beneath its whole footprint."
		for other:Dictionary in state.walls:
			if wall.id==other.id or wall.level!=other.level:continue
			if (float(wall.w)>float(wall.d))==(float(other.w)>float(other.d)) and rect(wall).grow(-.001).intersects(rect(other).grow(-.001)):return "Parallel wall interiors overlap."
	for opening:Dictionary in state.openings:
		if _group_of(state,str(opening.stair))!="stairs":return "An opening refers to a missing stair."
		var stair:Dictionary=find(state,str(opening.stair))
		if str(stair.opening)!=str(opening.id) or int(opening.level)!=int(stair.upper) or not rect(opening).is_equal_approx(stair_rect(stair)):return "The stair opening does not match its stair footprint."
		if not _covered(rect(opening),_rects(state,"floors",int(stair.upper))):return "A stair opening is outside an upper slab."
	for stair:Dictionary in state.stairs:
		if _group_of(state,str(stair.opening))!="openings" or str(find(state,str(stair.opening)).stair)!=str(stair.id):return "A stair lacks its unique matching opening."
		var low:int=int(stair.lower);var high:int=int(stair.upper)
		# A ground-floor staircase may stand on the garden as well as on a floor.
		if not footprint_supported(state,low,stair_rect(stair),low==0) or not footprint_supported(state,low,landing_rect(stair,false),low==0) or not footprint_supported(state,high,landing_rect(stair,true)):return "A stair or landing has no continuous floor support."
		for guard:Rect2 in guard_footprints(stair):
			if not footprint_supported(state,high,guard):return "The stair opening needs surrounding slab beneath its full guard and post footprints."
			# A wall standing in the guard's own band is itself the barrier at that
			# edge, so it does not refuse the staircase: the run and landing checks
			# below still keep the whole staircase body clear of every wall.
		for level:int in [low,high]:
			if blocked_rect(state,level,stair_rect(stair),false) or blocked_rect(state,level,landing_rect(stair,level==high),false):return "A wall blocks a stair or landing."
		for other:Dictionary in state.stairs:
			if stair.id==other.id:continue
			if int(other.lower)==low:
				if stair_rect(stair).grow(.01).intersects(stair_rect(other)):return "Stair volumes overlap."
				if landing_rect(stair,false).intersects(stair_rect(other)) or landing_rect(stair,true).intersects(stair_rect(other)):return "A stair run blocks another stair's landing."
			elif int(other.upper)==low:
				# A flight starting on the floor another one arrives at keeps clear of
				# that one's landing and the rail round its opening.
				var foot:Rect2=stair_rect(stair).merge(landing_rect(stair,false))
				if foot.intersects(landing_rect(other,true)):return "A stair run blocks another stair's landing."
				for guard:Rect2 in guard_footprints(other):
					if guard.intersects(foot):return "A stair run blocks another stair's rail."
	for roof:Dictionary in state.roofs:
		# A roof spans above the stair opening; it is not a walkable floor.
		if not _covered(rect(roof),_rects(state,"floors",int(roof.level))):return "A roof is outside its storey footprint."
		var error:String=_perimeter_support_error(state,roof,int(roof.level))
		if not error.is_empty():return error
	return RoofRules.validate(state)

static func migrate(legacy:Variant) -> Dictionary:
	if not legacy is Dictionary:return _error("Building data must be an object.")
	if legacy.has("version") and legacy.version!=1:
		var error:String=validate(legacy)
		return {"ok":true,"state":legacy.duplicate(true),"migrated":false} if error.is_empty() else _error(error)
	if legacy.get("kind")!="__construction" or not legacy.get("walls") is Array or not legacy.get("floors") is Array:return _error("Malformed legacy construction.")
	if legacy.walls.size()+legacy.floors.size()>MAX_RECORDS-1:return _error("Too many legacy building records.")
	for field:String in ["stairs","openings","roofs","levels"]:
		if legacy.has(field):return _error("Legacy construction cannot contain unversioned level geometry.")
	var state:Dictionary=fresh()
	if legacy.has("cleared_vegetation"):state["cleared_vegetation"]=legacy.cleared_vegetation.duplicate() if legacy.cleared_vegetation is Array else legacy.cleared_vegetation
	state.floors.append({"id":"legacy_starter_floor","level":0,"x":0.0,"z":0.0,"w":12.0,"d":10.0,"material":"cfa97e"})
	for group:String in ["walls","floors"]:
		for index:int in range(legacy[group].size()):
			var record:Variant=legacy[group][index]
			if not record is Dictionary:return _error("Malformed legacy rectangle.")
			if record.has("level") and not number(record.level,0,0,true):return _error("Legacy construction cannot flatten an upper level.")
			var error:String=_rect_error(record)
			if not error.is_empty():return _error(error)
			var entry:Dictionary={"id":record.get("id","legacy_"+group+"_"+str(index)),"level":0,"x":record.x,"z":record.z,"w":record.w,"d":record.d,"material":record.get("color","eae7d7" if group=="walls" else "cfa97e")}
			if group=="walls":entry.merge({"height":record.get("height",2.6),"cut":record.get("cut",true)})
			state[group].append(entry)
	var error:String=validate(state)
	return {"ok":true,"state":state,"migrated":true} if error.is_empty() else _error(error)

static func _new_id(state:Dictionary,group:String) -> String:
	var id:String=group+"_"+str(state.next_serial)
	while not find(state,id).is_empty():state.next_serial+=1;id=group+"_"+str(state.next_serial)
	state.next_serial+=1
	return id

static func _union_area(rectangles:Array) -> float:
	var xs:Array[float]=[]
	for area:Rect2 in rectangles:
		for x:float in [area.position.x,area.end.x]:
			if not xs.has(x):xs.append(x)
	xs.sort();var total:float=0.0
	for i:int in range(xs.size()-1):
		var intervals:Array=[]
		for area:Rect2 in rectangles:
			if area.position.x<xs[i+1] and area.end.x>xs[i]:intervals.append(Vector2(area.position.y,area.end.y))
		intervals.sort_custom(func(a:Vector2,b:Vector2)->bool:return a.x<b.x)
		var start:float=0;var end:float=0;var first:bool=true;var span:float=0
		for interval:Vector2 in intervals:
			if first:start=interval.x;end=interval.y;first=false
			elif interval.x>end:span+=end-start;start=interval.x;end=interval.y
			else:end=maxf(end,interval.y)
		if not first:span+=end-start
		total+=(xs[i+1]-xs[i])*span
	return total

static func propose(current:Dictionary,operation:Variant,funds:Variant) -> Dictionary:
	var error:String=validate(current)
	if not error.is_empty():return _error(error)
	if not number(funds,0,1e9,true) or not operation is Dictionary:return _error("Invalid building transaction.")
	if int(current.revision)>=1000000000:return _error("Building revision limit reached.")
	var after:Dictionary=current.duplicate(true)
	var cost:int=0
	var op:String=str(operation.get("op",""))
	if op=="add":
		var group:Variant=operation.get("collection")
		if not group is String or group not in ["walls","floors","stairs","roofs"] or not operation.get("record") is Dictionary:return _error("Invalid construction operation.")
		var record:Dictionary=operation.record.duplicate(true)
		if record.has("id") or record.has("opening") or record.has("landing_for"):return _error("New structural identities are allocated by the transaction.")
		record["id"]=_new_id(after,group)
		var landing_area:float=0.0
		if group=="stairs":
			for key:String in ["x","z","rotation"]:
				if not number(record.get(key),-Land.MAX_SPAN if key!="rotation" else 0,Land.MAX_SPAN if key!="rotation" else 270):return _error("Invalid new stair position.")
			if not number(record.get("lower",0),0,MAX_LEVEL-1,true):return _error("A staircase climbs from the ground floor or a storey with one above it.")
			var lower:int=int(record.get("lower",0))
			record["lower"]=lower;record["upper"]=lower+1;record["opening"]=_new_id(after,"openings")
			var hole:Rect2=stair_rect(record)
			# A staircase needs no floor waiting for it upstairs: where there is
			# none round its top, it brings its own landing slab with it.
			var top:Rect2=stair_top_area(record)
			var before_area:float=_union_area(_rects(after,"floors",lower+1))
			if top.has_area() and not _covered(top,_rects(after,"floors",lower+1)):
				after.floors.append({"id":_new_id(after,"floors"),"level":lower+1,"x":top.get_center().x,"z":top.get_center().y,"w":top.size.x,"d":top.size.y,"material":"cfa97e","landing_for":record.id})
				landing_area=maxf(0.0,_union_area(_rects(after,"floors",lower+1))-before_area)
			after.openings.append({"id":record.opening,"stair":record.id,"level":lower+1,"x":hole.get_center().x,"z":hole.get_center().y,"w":hole.size.x,"d":hole.size.y})
		after[group].append(record)
		error=validate(after)
		if not error.is_empty():return _error(error)
		match group:
			"walls":cost=roundi(maxf(float(record.w),float(record.d))*55)
			"floors":cost=roundi((_union_area(_rects(after,"floors",int(record.level)))-_union_area(_rects(current,"floors",int(record.level))))*12)
			"stairs":cost=650+roundi(landing_area*12)
			"roofs":cost=roundi(float(record.w)*float(record.d)*18)
		if cost<=0:return _error("This construction adds no new priced geometry.")
	elif op=="remove":
		if not identifier(operation.get("id")):return _error("Invalid removal identity.")
		var group:String=_group_of(after,operation.id)
		if group.is_empty() or group=="openings":return _error("Remove the owning structural object.")
		var old:Dictionary=find(after,operation.id)
		after[group]=after[group].filter(func(record:Dictionary)->bool:return record.id!=operation.id)
		var landing_refund:int=0
		if group=="stairs":
			after.openings=after.openings.filter(func(record:Dictionary)->bool:return record.stair!=old.id)
			# The landing slab a staircase brought goes with it, unless something
			# now stands on it: then it stays as an ordinary floor.
			var bare:Dictionary=after.duplicate(true)
			bare.floors=bare.floors.filter(func(record:Dictionary)->bool:return str(record.get("landing_for",""))!=str(old.id))
			if bare.floors.size()<after.floors.size() and validate(bare).is_empty():
				landing_refund=floori(maxf(0.0,_union_area(_rects(after,"floors",int(old.upper)))-_union_area(_rects(bare,"floors",int(old.upper))))*4)
				after=bare
			else:
				for floor:Dictionary in after.floors:
					if str(floor.get("landing_for",""))==str(old.id):floor.erase("landing_for")
		if group=="walls":cost=-floori(maxf(float(old.w),float(old.d))*float(old.get("refund_rate",20.0)))
		elif group=="floors":
			var area:float=maxf(0.0,_union_area(_rects(current,"floors",int(old.level)))-_union_area(_rects(after,"floors",int(old.level))))
			cost=-floori(area*float(old.refund_rate)) if old.has("refund_rate") else -roundi(area*4)
		elif group=="stairs":cost=-int(old.get("refund_value",250))-landing_refund
		elif group=="roofs":cost=-floori(float(old.w)*float(old.d)*float(old.refund_rate)) if old.has("refund_rate") else -roundi(float(old.w)*float(old.d)*6)
		error=validate(after)
		if not error.is_empty():return _error(error)
	else:return _error("Unsupported construction operation.")
	if int(funds)<cost:return _error("Not enough funds for this construction.")
	if int(funds)-cost>1000000000:return _error("This refund exceeds the wallet limit.")
	after.revision=int(current.revision)+1
	return {"ok":true,"operation":operation.duplicate(true),"before":fingerprint(current),"after":after,"cost":cost,"funds_before":int(funds),"funds_after":int(funds)-cost}

static func commit(current:Dictionary,proposal:Variant,funds:Variant) -> Dictionary:
	if not proposal is Dictionary or proposal.get("ok")!=true or proposal.get("before")!=fingerprint(current) or proposal.get("funds_before")!=funds:return _error("The quote is stale; request a new preview.")
	var recalculated:Dictionary=propose(current,proposal.get("operation"),funds)
	if not bool(recalculated.ok):return recalculated
	if proposal.get("cost")!=recalculated.cost or proposal.get("funds_after")!=recalculated.funds_after or proposal.get("after")!=recalculated.after:return _error("The quote does not match the validated transaction.")
	return {"ok":true,"state":recalculated.after,"funds":recalculated.funds_after,"receipt":{"before":current.duplicate(true),"after":fingerprint(recalculated.after),"funds_delta":recalculated.cost,"operation":recalculated.operation.duplicate(true),"funds_before":recalculated.funds_before}}

static func undo(current:Dictionary,receipt:Variant,funds:Variant) -> Dictionary:
	if not receipt is Dictionary or receipt.get("after")!=fingerprint(current) or not number(funds,0,1e9,true) or not number(receipt.get("funds_delta"),-1e9,1e9,true):return _error("This undo receipt does not match the current building.")
	var error:String=validate(receipt.get("before"))
	if not error.is_empty():return _error(error)
	var transaction:Dictionary=propose(receipt.before,receipt.get("operation"),receipt.get("funds_before"))
	if not bool(transaction.ok) or transaction.cost!=receipt.funds_delta or fingerprint(transaction.after)!=receipt.after:return _error("The undo receipt does not match a validated purchase or sale.")
	var restored_funds:int=int(funds)+int(receipt.funds_delta)
	if restored_funds<0 or restored_funds>1000000000 or int(current.revision)>=1000000000:return _error("Undo exceeds the wallet or revision limits.")
	var restored:Dictionary=receipt.before.duplicate(true)
	restored.revision=int(current.revision)+1
	restored.next_serial=maxi(int(restored.next_serial),int(current.next_serial))
	return {"ok":true,"state":restored,"funds":restored_funds}
