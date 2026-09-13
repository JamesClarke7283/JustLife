extends SceneTree
## Throwaway: does a resident home's own serialized layout pass its own validator?
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var world:=LifeWorld.new();root.add_child(world);world.set_process(false)
	await process_frame
	for place:String in LifeNeighborhood.RESIDENT_HOMES:
		world.create_resident_home(place,LifeNeighborhood.layout(place))
		var saved:Array=world.serialize_items()
		var err:String=world.validate_home_layout(saved)
		print(place," saved_size=",saved.size()," validate='",err,"'")
		if not err.is_empty():
			# Name the offending entry.
			var Building=preload("res://scripts/building_state.gd")
			var canonical:Dictionary={}
			for e:Dictionary in saved:
				if str(e.get("kind",""))=="__construction":canonical=Building.migrate(e).state
			for e:Dictionary in saved:
				if str(e.get("kind",""))=="__construction":continue
				var area:Rect2=world.furnishing_rect(e)
				var lvl:int=int(e.get("level",0))
				if not Building.footprint_supported(canonical,lvl,area):print("   UNSUPPORTED ",e.id," ",e.kind," at ",e.x,",",e.z)
				elif not LifeCatalog.passable(str(e.kind)) and Building.blocked_rect(canonical,lvl,area):print("   BLOCKED ",e.id," ",e.kind," at ",e.x,",",e.z," rot=",e.rotation)
	quit(0)
