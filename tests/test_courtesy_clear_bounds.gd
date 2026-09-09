extends "res://tests/test_courtesy_clear_phases.gd"

func _run()->void:
	phase_tag="clear_bounds";root.size=Vector2i(1440,900);screenshot_dir="res://evidence"
	audit={"events":[],"scope":"Public unrelated Build entry/return from actual hold. Separately, a declared geometric no-anchor component temporarily places one actual actor on supported upper floor and feeds the normal block collector; no simulation clock or needs advance."}
	app=MainScene.instantiate();root.add_child(app);current_scene=app;app.set_process(false);await frames(4);app.set_sound(false)
	var entries:Array=JSON.parse_string(FileAccess.get_file_as_string(screenshot_dir.path_join("phase_slots.json")))
	await _load_exact(str(entries.filter(func(e:Dictionary):return e.phase=="hold")[0].slot))
	# Build normally performs this existing typed geometry reconciliation.
	app.meal_flow.sync_world(true)
	var before:Dictionary=_physical_facts();var protected:Dictionary=app.traversal.routes.player.duplicate(true)
	await press("Build & buy")
	check(app.mode=="build" and _physical_facts()==before and app.traversal.routes.player==protected,"Unrelated public Build entry preserves exact paused queues/food/bodies/courtesy and the actual protected route.")
	await press("Live")
	check(app.mode=="live" and _physical_facts()==before and app.traversal.routes.player==protected,"Public return from unchanged Build preserves original protected/courtesy ownership and deadlines.")
	await _load_exact(LANDING_SLOT)
	await press("▶");app.household.adopt_selected_changes()
	var t:LifeTraversal=app.traversal;var helper=t.courtesy
	before=_physical_facts();protected=t.routes.player.duplicate(true)
	var other:LifeActor=app.world.actors.housemate_2;var original:Vector3=other.position
	other.position=Vector3(-.05,3.16,2.45)
	check(app.world.lot_navigation.point_clear(1,other.position) and other.position.distance_to(app.world.actors.housemate_3.position)>=.72 and other.position.distance_to(app.world.actors.player.position)>=.72,"Declared third-body obstruction is supported and does not overlap either participant.")
	helper.note_block(t,"player",.3,false);helper.note_block(t,"housemate_3",.3,false)
	helper.consider(t)
	check(helper.trace.size()==1 and helper.owner(t).is_empty() and helper.trace[0].selected.is_empty(),"Normal bounded selection refuses the declared crowd when no usable donor retreat opens the protected exit.")
	check(helper.queries<=24,"Unsuccessful complete selection obeys its shared24-query ceiling.")
	check(t.routes.player==protected,"Failed courtesy selection never rewrites the protected path/phase/ticket/lock.")
	audit["no_anchor"]={"obstacle":other.position,"trace":helper.trace.duplicate(true),"queries":helper.queries,"bodies":_record_clear().bodies}
	other.position=original;helper.reset()
	check(_physical_facts()==before,"No-anchor component restores exact physical/food/queue/clock facts with no simulation advance.")
	await press("Ⅱ");app.household.adopt_selected_changes()
	await _finish()
