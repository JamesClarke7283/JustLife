extends SceneTree
## Geometry/transaction/graph controls only. Does not pretend to render stairs,
## move actors, advance clocks, or exercise public building/save UI.
const Building=preload("res://scripts/building_state.gd")
const Navigation=preload("res://scripts/lot_navigation.gd")
var assertions:int=0
var failures:Array[String]=[]
var receipt:Dictionary={"scope":"Detached building schema/support/transaction and explicit AStar3D graph; no actor/UI integration.","routes":[]}

func _initialize() -> void:_run.call_deferred()
func check(value:bool,message:String) -> void:
	assertions+=1
	print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:failures.append(message);push_error(message)

func _base(upper:bool=true) -> Dictionary:
	var state:Dictionary=Building.fresh()
	state.floors=[{"id":"ground","level":0,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"cfa97e"}]
	state.walls=[{"id":"north","level":0,"x":0.0,"z":-5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"},{"id":"south","level":0,"x":0.0,"z":5.0,"w":8.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"}]
	if upper:state.floors.append({"id":"upper","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"dcd6c6","supports":["north","south"]})
	return state

func _stairs(state:Dictionary,x:float=0.0,z:float=-2.0,rotation:int=0) -> Dictionary:
	var quote:Dictionary=Building.propose(state,{"op":"add","collection":"stairs","record":{"x":x,"z":z,"rotation":rotation}},10000)
	check(bool(quote.ok),"A supported stair proposal validates.")
	if not bool(quote.ok):print(quote);return state
	var result:Dictionary=Building.commit(state,quote,10000)
	check(bool(result.ok),"A supported staircase commits to detached data.")
	return result.state if bool(result.ok) else state

func _run() -> void:
	_test_schema_and_support()
	_test_transactions()
	_test_upper_wall_and_landing_dependencies()
	_test_routes()
	_test_geometry_queries()
	receipt["assertions"]=assertions;receipt["failures"]=failures
	var file:=FileAccess.open("user://building_modules.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(_json_safe(receipt),"  "));file.close()
	print("BUILDING_MODULES assertions=%d failures=%d"%[assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_upper_wall_and_landing_dependencies() -> void:
	var wall:Dictionary={"level":1,"x":0.0,"z":0.0,"w":2.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"}
	var ground:Dictionary=_base(false)
	check(not bool(Building.propose(ground,{"op":"add","collection":"walls","record":wall},1000).ok),"Critic: an unsupported upper wall cannot be purchased over a ground-only house.")
	var placed:Dictionary=Building.propose(_base(),{"op":"add","collection":"walls","record":wall},1000)
	check(bool(placed.ok),"Positive: a fully supported upper interior wall is legal.")
	if bool(placed.ok):check(not bool(Building.propose(placed.after,{"op":"remove","id":"upper"},1000).ok),"Critic: removing the slab cannot leave an upper wall floating.")
	wall.x=0.0;wall.z=-5.0;wall.w=8.0
	var perimeter:Dictionary=Building.propose(_base(),{"op":"add","collection":"walls","record":wall},1000)
	check(bool(perimeter.ok),"A normal 14cm perimeter wall centered on the slab edge gains real bearing support.")
	if bool(perimeter.ok):
		var record:Dictionary=perimeter.after.walls[-1]
		check(Building.footprint_supported(perimeter.after,1,Building.rect(record)),"The complete perimeter wall footprint is covered by slab plus bearing strip.")
		var tiles:Array=Building.surface_tiles(perimeter.after,1);var areas:Array=[]
		for tile:Dictionary in tiles:areas.append(tile.rect)
		check(Building._covered(Building.rect(record),areas),"The rendered slab rectangles actually include the full wall bearing strip.")
	wall.z=-5.08
	check(not bool(Building.propose(_base(),{"op":"add","collection":"walls","record":wall},1000).ok),"Moving a perimeter wall beyond its supported inner half rejects.")
	var first:Dictionary=_stairs(_base(),0,-2,0)
	var second:Dictionary={"op":"add","collection":"stairs","record":{"x":-2.25,"z":-2.75,"rotation":90}}
	check(bool(Building.propose(_base(),second,10000).ok),"Positive: the second rotated stair is valid by itself.")
	check(not bool(Building.propose(first,second,10000).ok),"Critic: a second stair run cannot occupy the first staircase's landing.")
	var narrow:Dictionary=_base();narrow.floors[1].w=1.25
	check(Building.validate(narrow).is_empty(),"Positive guard adversary: a narrow supported upper slab is legal without stairs.")
	var unsupported_guard:Dictionary=Building.propose(narrow,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000)
	check(not bool(unsupported_guard.ok) and str(unsupported_guard.get("error","")).contains("guard"),"Stair cannot create floating guard posts where only its opening and upper landing fit.")
	narrow.floors[1].w=2.0
	check(bool(Building.propose(narrow,{"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}},10000).ok),"Adding actual surrounding slab supports the same stair and perimeter guard.")

func _test_schema_and_support() -> void:
	var base:Dictionary=_base()
	check(Building.validate(base).is_empty(),"Opposite lower walls support a complete upper floor.")
	var original:Dictionary=base.duplicate(true)
	for value:Variant in [null,[],false,"building",{"version":999}]:check(not Building.validate(value).is_empty(),"Malformed building root rejects: "+str(value))
	for levels:Variant in [[false,true],[0,1.5],{},[0],null]:
		var malformed:Dictionary=base.duplicate(true);malformed.levels=levels
		check(not Building.validate(malformed).is_empty(),"Malformed level list rejects: "+str(levels))
	for value:Variant in [null,{},false,"1",1.5,-1,2]:
		var bad:Dictionary=base.duplicate(true);bad.floors[1].level=value
		check(not Building.validate(bad).is_empty(),"Malformed floor level rejects: "+str(value))
	for value:Variant in [NAN,INF,{},"4",0.0,-1.0]:
		var bad:Dictionary=base.duplicate(true);bad.floors[1].w=value
		check(not Building.validate(bad).is_empty(),"Malformed floor dimension rejects: "+str(value))
	var bad:Dictionary=base.duplicate(true);bad.floors[1].id="north"
	check(not Building.validate(bad).is_empty(),"IDs are unique across structural collections.")
	bad=base.duplicate(true);bad.floors[1].supports=["missing","south"]
	check(not Building.validate(bad).is_empty(),"Missing support wall is rejected.")
	bad=base.duplicate(true);bad.floors[1].supports=["north","north"]
	check(not Building.validate(bad).is_empty(),"One wall cannot pretend to support opposite edges.")
	bad=base.duplicate(true);bad.walls[1].level=1
	check(not Building.validate(bad).is_empty(),"A wall on the upper storey cannot support that same slab from below.")
	bad=base.duplicate(true);bad.walls[0].w=7.0
	check(not Building.validate(bad).is_empty(),"A short support wall cannot pass a full-edge support test.")
	bad=base.duplicate(true);bad.floors[1].w=9.0
	check(not Building.validate(bad).is_empty(),"Upper floor cannot overhang the supported lower footprint.")
	bad=base.duplicate(true);var duplicate:Dictionary=bad.walls[0].duplicate(true);duplicate.id="duplicate_north";bad.walls.append(duplicate)
	check(not Building.validate(bad).is_empty(),"A second identity cannot double an existing parallel wall volume.")
	var with_stairs:Dictionary=_stairs(base,2)
	if with_stairs.stairs.is_empty():return
	var hole:Rect2=Building.rect(with_stairs.openings[0])
	var sampled_clear:bool=true
	for x:float in [-4.0,0.0,4.0]:
		for z:float in [-5.0,0.0,5.0]:sampled_clear=sampled_clear and not hole.has_point(Vector2(x,z))
	check(sampled_clear,"Positive adversary: all nine regular samples miss the off-center stair opening.")
	check(not Building.footprint_supported(with_stairs,1,Rect2(-4,-5,8,10)),"Whole upper footprint rejects its internal opening despite nine clear samples.")
	check(Building.footprint_supported(with_stairs,0,Rect2(-4,-5,8,10)),"The matching ground footprint stays supported below the upper opening.")
	check(Building.footprint_supported(with_stairs,1,Rect2(-3,-2,.3,.3)),"A separate upper-floor footprint is still supported.")
	bad=with_stairs.duplicate(true);bad.openings[0].w=.1
	check(not Building.validate(bad).is_empty(),"Opening dimensions must match the actual stair volume.")
	bad=with_stairs.duplicate(true);bad.openings[0].stair="missing"
	check(not Building.validate(bad).is_empty(),"An orphan opening rejects.")
	bad=with_stairs.duplicate(true);bad.stairs[0].upper=0
	check(not Building.validate(bad).is_empty(),"A staircase cannot claim a same-floor vertical connection.")
	bad=with_stairs.duplicate(true);bad.stairs[0].rotation=45
	check(not Building.validate(bad).is_empty(),"Unsupported stair rotation rejects before graph construction.")
	bad=with_stairs.duplicate(true);bad.stairs[0].x={}
	check(not Building.validate(bad).is_empty(),"Stair dictionary coordinate rejects before numeric conversion.")
	var crossed:Dictionary={"id":"crossed","level":0,"x":2.0,"z":0.0,"w":2.0,"d":.14,"height":2.6,"cut":true,"material":"eae7d7"}
	bad=with_stairs.duplicate(true);bad.walls.append(crossed)
	check(not Building.validate(bad).is_empty(),"A lower wall through the stair run rejects.")
	var legacy:Dictionary={"kind":"__construction","walls":[{"id":"saved_wall_17","x":6.5,"z":0.0,"w":.14,"d":3.0,"height":2.6,"color":"eae7d7","cut":false}],"floors":[{"x":0.0,"z":6.0,"w":3.0,"d":2.0,"color":"896953"}]}
	var legacy_before:Dictionary=legacy.duplicate(true)
	var migrated:Dictionary=Building.migrate(legacy)
	check(bool(migrated.ok) and bool(migrated.migrated),"Unversioned current construction migrates to explicit level-0 geometry.")
	if bool(migrated.ok):
		check(migrated.state.walls[0].id=="saved_wall_17" and not migrated.state.walls[0].cut,"Migration preserves existing wall identity and wall-view metadata.")
		check(Building.footprint_supported(migrated.state,0,Rect2(-5,-4,10,8)) and Building.footprint_supported(migrated.state,0,Rect2(-1,5.5,2,1)),"Migration explicitly supports both starter floor and saved ground extension.")
		check(not Building.footprint_supported(migrated.state,1,Rect2(-1,-1,2,2)),"Legacy migration does not fabricate an upper floor.")
		var loaded:Dictionary=Building.migrate(JSON.parse_string(JSON.stringify(migrated.state)))
		check(bool(loaded.ok) and not loaded.migrated,"Version-2 geometry survives an actual JSON roundtrip without migrating again.")
	check(legacy==legacy_before and base==original,"Validation and migration do not modify the supplied originals.")
	bad=legacy.duplicate(true);bad.walls[0].x="bad"
	check(not bool(Building.migrate(bad).ok),"Malformed legacy geometry is rejected rather than silently dropped.")
	bad=legacy.duplicate(true);bad.version=1
	check(bool(Building.migrate(bad).ok),"An explicitly marked version-1 ground record also migrates.")
	bad=legacy.duplicate(true);bad.floors[0].level=1
	check(not bool(Building.migrate(bad).ok),"Legacy ingress cannot silently flatten an injected upper floor.")
	bad=legacy.duplicate(true);bad.openings=[]
	check(not bool(Building.migrate(bad).ok),"Unversioned level geometry requires an explicit new format.")
	var roof_state:Dictionary=with_stairs.duplicate(true)
	for wall:Dictionary in base.walls:
		var elevated:Dictionary=wall.duplicate(true);elevated.id="upper_"+str(wall.id);elevated.level=1;roof_state.walls.append(elevated)
	var roof:Dictionary={"id":"roof","level":1,"x":0.0,"z":0.0,"w":8.0,"d":10.0,"material":"638c86","pitch":.5,"rotation":0,"supports":["upper_north","upper_south"]}
	roof_state.roofs.append(roof)
	check(Building.validate(roof_state).is_empty(),"A perimeter-supported roof bridges the upper stair void without making it walkable.")
	roof_state.roofs[0].supports=["north","south"]
	check(not Building.validate(roof_state).is_empty(),"A roof cannot use distant lower-storey walls as its perimeter support.")

func _test_transactions() -> void:
	var base:Dictionary=_base();var before:Dictionary=base.duplicate(true)
	var operation:Dictionary={"op":"add","collection":"stairs","record":{"x":0.0,"z":-2.0,"rotation":0}}
	var quote:Dictionary=Building.propose(base,operation,1000)
	check(bool(quote.ok) and int(quote.cost)==650 and int(quote.funds_after)==350,"Stair quote includes its matching opening for one original §650 charge.")
	check(base==before and not operation.record.has("id"),"A quote changes no caller-owned building or operation.")
	if not bool(quote.ok):return
	var committed:Dictionary=Building.commit(base,quote,1000)
	check(bool(committed.ok) and committed.state.stairs.size()==1 and committed.state.openings.size()==1 and committed.funds==350,"Commit returns a complete detached state and funds result.")
	if not bool(committed.ok):return
	check(base==before,"Commit leaves the old live-state candidate untouched.")
	check(not bool(Building.commit(committed.state,quote,350).ok),"Duplicate confirmation cannot apply its old quote or charge twice.")
	check(not bool(Building.commit(base,quote,999).ok),"A changed wallet invalidates the quote.")
	var tampered:Dictionary=quote.duplicate(true);tampered.cost=0;tampered.funds_after=1000
	check(not bool(Building.commit(base,tampered,1000).ok),"Caller cannot change the charged price after preview.")
	tampered=quote.duplicate(true);tampered.after.openings.clear()
	check(not bool(Building.commit(base,tampered,1000).ok),"Caller cannot remove the required hole from the detached quoted result.")
	check(not bool(Building.propose(base,operation,649).ok),"Insufficient funds reject before geometry or money changes.")
	var failed:Dictionary=Building.propose(committed.state,{"op":"remove","id":"north"},350)
	check(not bool(failed.ok),"Removing a supporting wall refuses an invalid detached structure.")
	failed=Building.propose(committed.state,{"op":"remove","id":str(committed.state.openings[0].id)},350)
	check(not bool(failed.ok),"An opening cannot be removed separately from its stair.")
	var undo:Dictionary=Building.undo(committed.state,committed.receipt,350)
	check(bool(undo.ok) and undo.funds==1000 and undo.state.stairs.is_empty() and undo.state.openings.is_empty(),"Undo restores both stair and hole together and returns exactly the prior charge.")
	if bool(undo.ok):
		check(not bool(Building.undo(undo.state,committed.receipt,1000).ok),"An undo receipt cannot pay out repeatedly.")
		check(int(undo.state.next_serial)>=int(committed.state.next_serial),"Undo never reuses already allocated structure identities.")
	var forged:Dictionary=committed.receipt.duplicate(true);forged.funds_delta=99999
	check(not bool(Building.undo(committed.state,forged,350).ok),"Undo recomputes the original operation instead of trusting a forged refund.")
	forged=committed.receipt.duplicate(true);forged.before.floors.clear()
	check(not bool(Building.undo(committed.state,forged,350).ok),"Undo cannot restore an unrelated invalid former building.")
	var exhausted:Dictionary=base.duplicate(true);exhausted.revision=1000000000
	check(not bool(Building.propose(exhausted,operation,1000).ok),"A maximum revision cannot produce an invalid overflowed candidate.")
	var sale_base:Dictionary=_base(false)
	var sale:Dictionary=Building.propose(sale_base,{"op":"remove","id":"north"},100)
	check(bool(sale.ok) and sale.cost==-160,"An independent ground wall retains the existing §20-per-metre sale refund.")
	if bool(sale.ok):
		var sold:Dictionary=Building.commit(sale_base,sale,100)
		check(bool(sold.ok) and not bool(Building.undo(sold.state,sold.receipt,0).ok),"Undoing a sale still requires enough current funds.")
	check(not bool(Building.propose(sale_base,{"op":"remove","id":"north"},1000000000).ok),"A wall refund cannot overflow the wallet limit.")
	var floor_op:Dictionary={"op":"add","collection":"floors","record":{"level":0,"x":0.0,"z":5.5,"w":2.0,"d":2.0,"material":"cfa97e"}}
	var extension:Dictionary=Building.propose(base,floor_op,1000)
	check(bool(extension.ok) and extension.cost==36,"An overlapping floor extension charges only its new 3m² union area.")
	floor_op.record.z=0.0
	check(not bool(Building.propose(base,floor_op,1000).ok),"An entirely duplicate floor cannot create a second charged slab.")
	var removed:Dictionary=Building.propose(committed.state,{"op":"remove","id":str(committed.state.stairs[0].id)},350)
	check(bool(removed.ok) and removed.after.openings.is_empty() and Building.footprint_supported(removed.after,1,Rect2(-.5,-1,1,1)),"Removing an unoccupied stair also closes its paired upper-floor hole in pure geometry.")

func _test_routes() -> void:
	var nav=Navigation.new();var base:Dictionary=_base()
	check(bool(nav.rebuild(base).ok),"Supported two-storey floor graphs build without stairs.")
	var lower:Dictionary=Navigation.floor_location(0,Vector3(-2,.16,0))
	var upper:Dictionary=Navigation.floor_location(1,Vector3(-2,3.16,0))
	check(not bool(nav.route(lower,upper).ok),"Same X/Z across levels has no route without an actual stair connection.")
	check(bool(nav.route(lower,Navigation.floor_location(0,Vector3(2,.16,0))).ok),"Ground-floor movement remains available independently.")
	var stairs:Dictionary=_stairs(base)
	check(bool(nav.rebuild(stairs).ok),"A validated staircase connects the explicit 3D graph.")
	var result:Dictionary=nav.route(lower,upper)
	check(bool(result.ok),"Actual graph route goes between two different floor heights.")
	if bool(result.ok):
		receipt.routes.append(result)
		check(result.points[0]==lower.position and result.points[-1]==upper.position,"The route keeps both exact endpoints, without nearest-floor substitution.")
		var rises:int=0;var max_rise:float=0;var vertical_only:bool=false
		for segment:Dictionary in result.segments:
			var rise:float=absf(segment.to.y-segment.from.y)
			if rise>.00001:
				rises+=1;max_rise=maxf(max_rise,rise)
				check(segment.kind=="stair" and segment.stair_id==stairs.stairs[0].id,"Every rising edge belongs to the actual staircase.")
				if Vector2(segment.to.x-segment.from.x,segment.to.z-segment.from.z).length()<.001:vertical_only=true
		check(rises==15 and max_rise<=.20001 and not vertical_only,"Stairs rise over fifteen physical run segments, never one vertical teleport edge.")
		check(result.distance>3.0,"The route cost includes real travel to and along the staircase.")
	var descent:Dictionary=nav.route(upper,lower)
	check(bool(descent.ok) and descent.points[-1]==lower.position,"The same staircase genuinely connects descent.")
	var same:Dictionary=nav.route(upper,upper)
	check(bool(same.ok) and same.already_reached and same.distance==0,"Already at the exact upper endpoint is distinct from no route.")
	check(not bool(nav.route(lower,Navigation.floor_location(1,Vector3(0,3.16,0))).ok),"An endpoint inside the upper stair opening rejects.")
	check(not bool(nav.route(lower,Navigation.floor_location(0,Vector3(-2,3.16,0))).ok),"Conflicting level and Y reject instead of snapping downstairs.")
	var arbitrary:Dictionary=Navigation.floor_location(1,Vector3(-2.08,3.16,.07))
	var off_grid:Dictionary=nav.route(upper,arbitrary)
	check(bool(off_grid.ok) and off_grid.points[-1]==arbitrary.position,"A clear off-grid point retains its exact local connection and endpoint.")
	var blocker:Dictionary={"id":"bed","level":1,"x":-2.0,"z":0.0,"w":1.0,"d":1.0}
	check(bool(nav.rebuild(stairs,[blocker]).ok),"Level-tagged furniture obstacle builds.")
	check(bool(nav.route(lower,lower).ok) and not bool(nav.route(upper,upper).ok),"An upstairs furnishing blocks only its own floor footprint.")
	blocker={"id":"landing_box","level":1,"x":0.0,"z":2.25,"w":.5,"d":.5}
	check(bool(nav.rebuild(stairs,[blocker]).ok),"A later blocked landing keeps the rest of the topology available.")
	check(not bool(nav.route(lower,upper).ok),"A blocked landing disables stair admission without substituting another upper cell.")
	var prior:Dictionary=nav.state_snapshot();var generation:int=nav.generation
	var bad:Dictionary=stairs.duplicate(true);bad.openings.clear()
	check(not bool(nav.rebuild(bad).ok) and nav.state_snapshot()==prior and nav.generation==generation,"Rejected rebuild is atomic and retains the previously valid topology.")
	check(not bool(nav.rebuild(stairs,[{"id":"bad","level":{},"x":0,"z":0,"w":1,"d":1}]).ok),"Malformed obstacle rejects before unsafe numeric conversion.")
	var rotated:Dictionary=_stairs(base,-2,0,90)
	check(bool(nav.rebuild(rotated).ok),"A quarter-turn stair has a complete paired opening and valid landings.")
	# The old common endpoint (-2,0) is the rotated stair's lower run edge,
	# not a floor point. Keep this positive control on supported floor instead.
	var rotated_route:Dictionary=nav.route(Navigation.floor_location(0,Vector3(-2,.16,-2)),Navigation.floor_location(1,Vector3(-2,3.16,-2)))
	check(bool(rotated_route.ok),"Rotating the stair also rotates the only cross-floor graph route.")
	if bool(rotated_route.ok):receipt.routes.append(rotated_route)
	var normalized:Dictionary=JSON.parse_string(JSON.stringify(stairs))
	check(bool(nav.rebuild(normalized).ok) and bool(nav.route(lower,upper).ok),"JSON-loaded geometry rebuilds the same reachable floor/stair connections.")

func _test_geometry_queries() -> void:
	var nav=Navigation.new()
	var at:=Vector3(-2,.16,0)
	check(not nav.point_clear(0,at),"An unbuilt navigation has no supported query point.")
	var base:Dictionary=_base()
	check(bool(nav.rebuild(base).ok) and nav.point_clear(0,at),"Rebuild publishes supported ground geometry with its graph.")
	var obstacle:Dictionary={"id":"query_box","level":0,"x":-2.0,"z":0.0,"w":.5,"d":.5}
	check(bool(nav.rebuild(base,[obstacle]).ok) and not nav.point_clear(0,at),"A valid furniture rebuild updates exact point clearance.")
	var beside:=Vector3(-2.5,.16,0)
	check(nav.point_clear(0,beside) and not nav.point_clear(0,beside,Vector2(.3,.16)) and nav.point_clear(0,beside,Vector2(.16,.3)),"Custom footprints retain their distinct X and Z extent beside an obstacle.")
	var from:=Vector3(-3,.16,0);var to:=Vector3(-1,.16,0)
	check(nav.point_clear(0,from) and nav.point_clear(0,to) and not nav.segment_clear(0,from,to),"Clear public endpoints still reject a segment through furniture.")
	check(nav.segment_clear(1,from+Vector3(0,3,0),to+Vector3(0,3,0)),"The same segment remains supported above a ground-only obstacle.")
	var generation:int=nav.generation
	var malformed:Dictionary=base.duplicate(true);malformed.version=999
	check(not bool(nav.rebuild(malformed).ok) and nav.generation==generation and not nav.point_clear(0,at) and not nav.segment_clear(0,from,to),"Rejected structure retains prior point and segment clearance.")
	check(not bool(nav.rebuild(base,[{"id":"bad"}]).ok) and nav.generation==generation and not nav.point_clear(0,at),"Rejected obstacle retains prior geometry and generation.")
	check(bool(nav.rebuild(base).ok) and nav.point_clear(0,at) and nav.segment_clear(0,from,to),"Removing furniture rebuilds both public query results.")
	check(bool(nav.rebuild(_base(false)).ok) and not nav.point_clear(1,at+Vector3(0,3,0)),"Removing Upper replaces its support geometry without stale clearance.")

func _json_safe(value:Variant) -> Variant:
	if value is Vector3:return [value.x,value.y,value.z]
	if value is PackedVector3Array:value=Array(value)
	if value is Array:
		var result:Array=[]
		for item:Variant in value:result.append(_json_safe(item))
		return result
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:result[str(key)]=_json_safe(value[key])
		return result
	return value
