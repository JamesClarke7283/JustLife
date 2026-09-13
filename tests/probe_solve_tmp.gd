extends SceneTree
## Throwaway: deterministic nearest-valid placement for every resident-home
## furnishing, resolved in one ordered pass against the built home geometry.
const Building=preload("res://scripts/building_state.gd")
func _initialize()->void:_run.call_deferred()
func _place(world:LifeWorld,canonical:Dictionary,placed:Array,e:Dictionary)->Dictionary:
	# Preserve kind/rotation/id; move x/z only.
	var lvl:int=int(e.get("level",0))
	var base:Dictionary={"id":str(e.id),"kind":str(e.kind),"x":float(e.x),"z":float(e.z),"rotation":float(e.rotation),"level":lvl}
	var passable:bool=LifeCatalog.passable(str(e.kind))
	for radius:int in range(0,61):
		var found:Array=[]
		for dx:int in range(-radius,radius+1):
			for dz:int in range(-radius,radius+1):
				if maxi(absi(dx),absi(dz))!=radius:continue
				var cand:Dictionary=base.duplicate(true)
				cand.x=base.x+float(dx)*.25;cand.z=base.z+float(dz)*.25
				var a:Rect2=world.furnishing_rect(cand)
				if not Building.LOT.encloses(a):continue
				if not Building.footprint_supported(canonical,lvl,a):continue
				if not passable and Building.blocked_rect(canonical,lvl,a):continue
				if not passable:
					var clash:bool=false
					for other:Dictionary in placed:
						if int(other.level)!=lvl or LifeCatalog.passable(str(other.kind)):continue
						if world.furnishing_rect(other).intersects(a):clash=true;break
					if clash:continue
				cand["d"]=Vector2(float(dx),float(dz)).length()
				found.append(cand)
		if not found.is_empty():
			found.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
				if absf(float(a.d)-float(b.d))>.0001:return float(a.d)<float(b.d)
				if a.x!=b.x:return a.x<b.x
				return a.z<b.z)
			var pick:Dictionary=found[0];pick.erase("d")
			return pick
	return {}
func _run()->void:
	var world:=LifeWorld.new();root.add_child(world);world.set_process(false)
	await process_frame
	for place:String in ["maya_home","leo_home","priya_home","tom_home"]:
		var authored:Array=LifeNeighborhood.layout(place)
		world.create_resident_home(place,authored)
		var saved:Array=world.serialize_items()
		var canonical:Dictionary={}
		for e:Dictionary in saved:
			if str(e.get("kind",""))=="__construction":canonical=e
		var placed:Array=[]
		var changed:Array=[]
		for e:Dictionary in saved:
			if str(e.get("kind",""))=="__construction":continue
			var fixed:Dictionary=_place(world,canonical,placed,e)
			if fixed.is_empty():print("NOSOLUTION ",e.id," ",e.kind);continue
			if absf(fixed.x-float(e.x))>.001 or absf(fixed.z-float(e.z))>.001:
				changed.append([str(e.id),str(e.kind),float(e.x),float(e.z),fixed.x,fixed.z])
			placed.append(fixed)
		# Rebuild from the corrected placements and re-validate.
		var corrected:Array=[]
		for e:Array in authored:corrected.append(e.duplicate())
		for e:Dictionary in saved:
			if str(e.get("kind",""))=="__construction":continue
			var index:int=int(str(e.id).replace(place+"_",""))
			for p:Dictionary in placed:
				if str(p.id)==str(e.id):corrected[index][1]=p.x;corrected[index][2]=p.z
		world.create_resident_home(place,corrected)
		print(place," validate='",world.validate_home_layout(world.serialize_items()),"' changes=",changed.size())
		for c:Array in changed:print("   %s %s (%.2f,%.2f)->(%.2f,%.2f)"%c)
	quit(0)
