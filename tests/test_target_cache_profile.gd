extends "res://tests/test_home_visit.gd"
func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false);_setup()
	var layout:Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/canonical_target_fixture.json"))
	app.loading_game=true;app.setup_live(layout);app.loading_game=false
	check(not app.world.construction.building_state.is_empty(),"Matched fixture is canonical")
	_step(3)
	var measurements:Array=[]
	var facts:Array=[]
	for index:int in 20:
		var begun:int=Time.get_ticks_usec();_step();measurements.append((Time.get_ticks_usec()-begun)/1000.0)
		facts.append({"targets":app.world.simulation_targets(),"household":app.household.get_state(app.world.serialize_items()),"physical":app._physical_snapshot_context(),"residents":app.residents.snapshot()})
	var file:=FileAccess.open("user://target_cache_profile.json",FileAccess.WRITE);file.store_string(JSON.stringify({"steps_ms":measurements,"frames":LifeSaveLibrary._json_safe(facts)},"",true,true));file.close()
	await _finish()
