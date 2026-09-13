extends SceneTree
## Throwaway: validate each resident home layout exactly as the world does.
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var world:=LifeWorld.new();root.add_child(world);world.set_process(false)
	await process_frame
	for place:String in LifeNeighborhood.RESIDENT_HOMES:
		var layout:Array=LifeNeighborhood.layout(place)
		world.create_resident_home(place,layout)
		print(place," last_error='",world.last_layout_error,"'")
		# Re-validate through the same public entry the cache uses.
		var err:String=world.validate_home_layout(layout)
		print("   validate='",err,"'")
	quit(0)
