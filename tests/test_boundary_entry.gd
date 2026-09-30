extends SceneTree
## Narrow legacy lot-margin recovery; ordinary navigation remains strict.
const Building=preload("res://scripts/building_state.gd")
const Navigation=preload("res://scripts/lot_navigation.gd")
var checks:int=0
var failures:int=0
func check(ok:bool,message:String)->void:
	checks+=1;print("CHECK ","PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize()->void:
	var old_land:Dictionary=Building.land
	Building.set_land({})
	var nav:=Navigation.new()
	check(bool(nav.rebuild(Building.fresh()).ok),"The ground graph builds normally")
	for start:Vector3 in [Vector3(-9.25,.16,9),Vector3(-18,.16,0),Vector3(18,.16,0),Vector3(0,.16,-12),Vector3(18,.16,9)]:
		var entry:Vector3=nav.boundary_entry(start)
		check(entry.is_finite() and nav.point_clear(0,entry) and start.distance_to(entry)<=.36 and nav.boundary_entry_step(start,entry),"Each supported lot margin has a nearby checked inward prefix: "+str(start))
		check(not nav.segment_clear(0,start,entry) and not nav.point_clear(0,start),"Ordinary full-body navigation remains strict at the original margin: "+str(start))
	var start:=Vector3(-9.25,.16,9)
	check(nav.boundary_entry(start)==Vector3(-9.25,.16,8.75),"The observed saved pose resolves to the closest inward graph point")
	check(nav.boundary_entry_step(start,Vector3(-9.25,.16,8.92)) and nav.boundary_entry_step(Vector3(-9.25,.16,8.92),Vector3(-9.25,.16,8.84)),"Short physical substeps monotonically remove the boundary overhang")
	for end:Vector3 in [start,Vector3(-9,.16,9),Vector3(-9.25,.16,9.08),Vector3(-9.25,.16,8),Vector3(-9.25,3.16,8.75)]:
		check(not nav.boundary_entry_step(start,end),"No stationary, tangent, outward, long or cross-floor boundary shortcut: "+str(end))
	check(not nav.boundary_entry(Vector3(-9.25,.16,9.1)).is_finite() and not nav.boundary_entry(Vector3.INF).is_finite(),"An outside centre or nonfinite pose is never repaired")
	check(not nav.boundary_entry(Vector3(-9.25,.16,8.75)).is_finite(),"Already supported actors use ordinary navigation")
	var obstacle:Array=[{"id":"boundary_wall","level":0,"x":-9.25,"z":8.58,"w":1.0,"d":.2}]
	check(bool(nav.rebuild(Building.fresh(),obstacle).ok),"A real solid spans the inward prefix")
	check(not nav.boundary_entry_step(start,Vector3(-9.25,.16,8.75)) and not nav.boundary_entry(start).is_finite(),"Boundary recovery cannot pass through a wall or furnishing")
	nav.rebuild(Building.fresh())
	nav._support_holes[0].append(Rect2(-9.75,8.6,1.0,.2))
	check(not nav.boundary_entry(start).is_finite(),"Boundary recovery cannot cross an unsupported hole")
	Building.land=old_land
	print("BOUNDARY_ENTRY %d checks, %d failures"%[checks,failures]);quit(0 if failures==0 else 1)
