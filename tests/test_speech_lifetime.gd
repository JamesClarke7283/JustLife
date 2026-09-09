extends "res://tests/test_playthrough.gd"
## Focused real-frame presentation test. Text is supplied explicitly; this does
## not pretend an activity completed or replace the paired-homework playthrough.
func _run() -> void:
	screenshot_dir="res://art/speech_lifetime"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	await _enter_new_game();await press("Find my home",true);await press("Start living",true);await press("Ⅱ")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	app.world.camera_target=app.player.position+Vector3(0,.5,0);app.world.camera.size=10;app.world.update_camera()
	app.player.speech("A little moment of joy.")
	await frames(4)
	check(app.activity_bubbles.cards.has("player") and app.activity_bubbles.cards.player.visible,"A real rendered speech card appears for the selected Lifelet.")
	var remaining:float=app.player.speech_presentation().remaining
	await create_timer(3.5).timeout
	check(is_equal_approx(app.player.speech_presentation().remaining,remaining),"Paused speech survives longer than its normal real-time lifetime.")
	await press("PauseMenu");await frames(3)
	check(not app.activity_bubbles.visible,"Pause modal hides speech while retaining actor state.")
	await press("Resume");await frames(3)
	check(app.activity_bubbles.cards.has("player") and app.activity_bubbles.cards.player.visible,"Closing the modal restores the still-paused message.")
	await screenshot("01_paused_message",false,false)
	await press("▶")
	await wait_until(func()->bool:return app.player.speech_presentation().is_empty() and app.activity_bubbles.cards.is_empty(),"speech expires naturally through ordinary resumed frame processing",10)
	check(not app.player._speech.visible,"Natural expiry leaves no duplicate world label.")
	await press("Ⅱ");await screenshot("02_expired_message",false,false)
	var report:Dictionary={"assertions":assertions,"failures":failures,"evidence":evidence,"method":"Focused rendered speech presentation. Public new-game, pause/menu/resume controls and real frame time. Test supplies text explicitly; no fabricated activity completion or time advancement."}
	var file:=FileAccess.open(screenshot_dir.path_join("playthrough_results.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	app.queue_free();await frames(3)
	print("SPEECH_LIFETIME assertions=%d failures=%d"%[assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)
