extends SceneTree
const Building=preload("res://scripts/building_state.gd")
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var world:=LifeWorld.new();root.add_child(world);world.set_process(false)
	await process_frame
	for place:String in ["priya_home","tom_home"]:
		world.create_resident_home(place,LifeNeighborhood.layout(place))
		var saved:Array=world.serialize_items()
		var canonical:Dictionary={}
		for e:Dictionary in saved:
			if str(e.get("kind",""))=="__construction":canonical=e
		for e:Dictionary in saved:
			if str(e.get("kind",""))=="__construction":continue
			var area:Rect2=world.furnishing_rect(e)
			var lvl:int=int(e.get("level",0))
			var bad:Array=[]
			for w:Dictionary in canonical.walls:
				if int(w.level)==lvl and Building.rect(w).intersects(area):bad.append("%s(w%s d%s at %s,%s)"%[w.id,w.w,w.d,w.x,w.z])
			print(place," ",e.id," ",e.kind," rect=",area," supported=",Building.footprint_supported(canonical,lvl,area)," walls=",bad)
		# floor + walls summary
		print("  FLOORS:",canonical.floors)
	quit(0)
