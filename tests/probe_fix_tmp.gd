extends SceneTree
## Throwaway: relocate invalid/overlapping resident-home furnishings to the
## nearest positions that are supported, clear of every wall, and clear of
## every other non-passable furnishing. Prints the corrected entry arrays.
const Building=preload("res://scripts/building_state.gd")
func _initialize()->void:_run.call_deferred()
func _valid(world:LifeWorld,canonical:Dictionary,e:Dictionary,others:Dictionary)->bool:
	var lvl:int=int(e.get("level",0))
	var a:Rect2=world.furnishing_rect(e)
	if not Building.LOT.encloses(a):return false
	if not Building.footprint_supported(canonical,lvl,a):return false
	if not LifeCatalog.passable(str(e.kind)) and Building.blocked_rect(canonical,lvl,a):return false
	for other:Dictionary in others.values():
		if str(other.id)==str(e.id) or int(other.get("level",0))!=lvl:continue
		if LifeCatalog.passable(str(other.kind)):continue
		if LifeCatalog.passable(str(e.kind)):continue
		if world.furnishing_rect(other).intersects(a):return false
	return true
func _run()->void:
	var world:=LifeWorld.new();root.add_child(world);world.set_process(false)
	await process_frame
	for place:String in ["priya_home","tom_home"]:
		var entries:Array=LifeNeighborhood.layout(place)
		for pass_index in range(8):
			world.create_resident_home(place,entries)
			var saved:Array=world.serialize_items()
			var canonical:Dictionary={}
			for e:Dictionary in saved:
				if str(e.get("kind",""))=="__construction":canonical=e
			var others:Dictionary={}
			for e:Dictionary in saved:
				if str(e.get("kind",""))=="__construction":continue
				others[str(e.id)]=e
			var moved:bool=false
			for e:Dictionary in saved:
				if str(e.get("kind",""))=="__construction":continue
				if _valid(world,canonical,e,others):continue
				var best:Dictionary={};var best_d:float=INF
				for radius:int in range(0,49):
					for dx:int in range(-radius,radius+1):
						for dz:int in range(-radius,radius+1):
							if maxi(absi(dx),absi(dz))!=radius:continue
							var cand:Dictionary=e.duplicate(true)
							cand.x=snappedf(float(e.x)+float(dx)*.25,.25)
							cand.z=snappedf(float(e.z)+float(dz)*.25,.25)
							if not _valid(world,canonical,cand,others):continue
							var d:=Vector2(cand.x-float(e.x),cand.z-float(e.z)).length()
							if d<best_d:best_d=d;best=cand
					if not best.is_empty():break
				if best.is_empty():print("  NOSOLUTION ",e.id," ",e.kind);continue
				# Apply to the authored entries by id index.
				var index:int=int(str(e.id).replace(place+"_",""))
				entries[index][1]=best.x;entries[index][2]=best.z
				others[str(e.id)]=best
				moved=true
				print("  %s %s (%.2f,%.2f)->(%.2f,%.2f)"%[e.id,e.kind,e.x,e.z,best.x,best.z])
			if not moved:break
		world.create_resident_home(place,entries)
		print("FINAL ",place," validate='",world.validate_home_layout(world.serialize_items()),"'")
		var out:Array=[]
		for e:Array in entries:out.append("[%s,%s,%s]"%[str(e[0]),str(e[1]),str(e[2])])
		print("ENTRIES ",place," ",out)
	quit(0)
