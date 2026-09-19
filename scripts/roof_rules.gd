extends RefCounted
class_name LifeRoofRules
## Pure conservative clearance rules for separate rectangular gable roofs.
## No Nodes, renderer, clock or wallet access. Attics/junctions are not implied.
const EAVE:float=.28
const SHELL:float=.10
## The navigable lot is the household's own land: the plot it started with plus
## every neighbouring plot it has bought. It is owned by `LifeBuildingState`
## (which derives it from `LifeLand`), so this file reads the one live value
## rather than holding its own copy that could drift from it.
static func lot() -> Rect2:
	return LifeBuildingState.lot()

static func parameters(record:Dictionary)->Dictionary:
	var span:float=float(record.w) if int(record.rotation)==0 else float(record.d)
	var length:float=float(record.d) if int(record.rotation)==0 else float(record.w)
	var pitch:float=float(record.pitch);var sec:float=sqrt(1.0+pitch*pitch)
	return {"span":span,"length":length,"pitch":pitch,"sec":sec,"sn":pitch/sec,"cs":1.0/sec,"height":pitch*span*.5,"x":span*.5+EAVE,"z":length*.5+EAVE}
static func support_rect(record:Dictionary)->Rect2:return Rect2(float(record.x)-float(record.w)*.5,float(record.z)-float(record.d)*.5,float(record.w),float(record.d))
static func envelope(record:Dictionary)->AABB:
	var p:Dictionary=parameters(record)
	var low:float=-p.pitch*EAVE+SHELL*p.sec-.205
	var high:float=p.height+SHELL*p.sec+.065
	return AABB(Vector3(float(record.x)-float(record.w)*.5-EAVE,.16+3.0*int(record.level)+2.6+low,float(record.z)-float(record.d)*.5-EAVE),Vector3(float(record.w)+2*EAVE,high-low,float(record.d)+2*EAVE))
static func _eave_strips(record:Dictionary)->Array[Rect2]:
	# The8cm bearing contact band includes the outer half of a14cm wall.
	# Outside it, existing same-storey walls must leave the eave unobstructed.
	var outer:Rect2=support_rect(record).grow(EAVE);var inner:Rect2=support_rect(record).grow(.08)
	return [Rect2(outer.position,Vector2(inner.position.x-outer.position.x,outer.size.y)),Rect2(Vector2(inner.end.x,outer.position.y),Vector2(outer.end.x-inner.end.x,outer.size.y)),Rect2(Vector2(inner.position.x,outer.position.y),Vector2(inner.size.x,inner.position.y-outer.position.y)),Rect2(Vector2(inner.position.x,inner.end.y),Vector2(inner.size.x,outer.end.y-inner.end.y))]
static func validate(state:Dictionary)->String:
	if state.roofs.size()>16:return "This home already has the maximum16 separate roof pieces."
	for roof:Dictionary in state.roofs:
		if float(roof.w)<1.5 or float(roof.d)<1.5:return "A gable roof must be at least1.5 metres wide and deep."
		if not lot().encloses(support_rect(roof).grow(EAVE)):return "The roof's full28cm eaves must stay inside the lot."
		var volume:AABB=envelope(roof)
		for other:Dictionary in state.roofs:
			if str(roof.id)!=str(other.id) and volume.grow(.005).intersects(envelope(other)):return "Separate roofs need clear eaves. Intersecting roof junctions are not supported yet."
		for floor:Dictionary in state.floors:
			if int(floor.level)<=int(roof.level):continue
			var r:Rect2=support_rect(floor);var slab:=AABB(Vector3(r.position.x,.16+3.0*int(floor.level)-.16,r.position.y),Vector3(r.size.x,.16,r.size.y))
			if volume.intersects(slab):return "An upper floor intersects the roof's full height envelope. Attic floors are not supported yet."
		for wall:Dictionary in state.walls:
			var r:Rect2=support_rect(wall)
			if int(wall.level)==int(roof.level):
				for strip:Rect2 in _eave_strips(roof):
					if strip.intersects(r):return "A wall blocks the roof eave. Leave clear space outside its bearing edge."
			elif int(wall.level)>int(roof.level):
				var box:=AABB(Vector3(r.position.x,.16+3.0*int(wall.level),r.position.y),Vector3(r.size.x,float(wall.height),r.size.y))
				if volume.intersects(box):return "An upper wall intersects the roof's full height envelope."
	return ""
static func obstruction(state:Dictionary,bounds:AABB)->String:
	for roof:Dictionary in state.roofs:
		if not envelope(roof).intersects(bounds):continue
		var p:Dictionary=parameters(roof)
		var transform:=Transform3D(Basis(Vector3.UP,deg_to_rad(float(roof.rotation))),Vector3(float(roof.x),.16+3.0*int(roof.level)+2.6,float(roof.z)))
		var local:AABB=transform.affine_inverse()*bounds
		var plan:=Rect2(local.position.x,local.position.z,local.size.x,local.size.z)
		var support:=Rect2(-p.span*.5,-p.length*.5,p.span,p.length)
		if support.encloses(plan):
			# A tall shower under the ridge is not blocked by the much lower eave
			# elsewhere. Full gable infills still bound the ends above wall top.
			if local.end.y<=0:continue
			var beneath:float=p.height-p.pitch*maxf(absf(local.position.x),absf(local.end.x))
			if local.position.z>-p.length*.5+.085 and local.end.z<p.length*.5-.085 and local.end.y<=beneath-.005:continue
		return "That object needs clear space below the roof and its eaves."
	return ""
