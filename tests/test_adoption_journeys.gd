extends "res://tests/test_stair_controller.gd"
# Resolve the real scene with this test's static SaveLibrary dependency. Late
# scene loading after that class leaves script resources retained in Godot 4.7.
const MainScene=preload("res://scenes/main.tscn")
var adoption_observations:Dictionary={}

func _adopt_after_saved_movement()->void:
	_setup(2)
	app.household.set_speed(0);app.overlay_open=true
	check(app.save_game("","Before journey adoption"),"Actual main writes a named V2 save of the initial two-floor household.")
	var saved:Dictionary=LifeSaveLibrary.read_slot(app.active_save_id)
	check(bool(saved.ok) and int(saved.data.household_version)==2,"Named positive control validates the original V2 household.")
	if not bool(saved.ok):return
	var stale:Dictionary=app.household.journeys.duplicate(true)
	app.overlay_open=false;app.household.set_speed(1)
	app.on_ground_clicked(Vector3(2,3.16,4))
	check(_until_transit("player"),"Real controller moves and advances time after saving, reaching an occupied staircase.")
	var live:Dictionary=app.traversal.snapshot()
	check(live!=stale and app.household.minutes>float(saved.data.minutes),"Actual physical facts and clock differ from the earlier named save.")
	app.adoption_flow.show_phone()
	var entry:Button=app.overlay.get_node_or_null("PhoneAdoptChild")
	check(is_instance_valid(entry) and not entry.disabled,"Actual Phone entry allows the at-home adult to review adoption while another household member exists.")
	if not is_instance_valid(entry) or entry.disabled:return
	entry.pressed.emit()
	var candidate:Button=app.overlay.get_node_or_null("AdoptionCandidate_0")
	check(is_instance_valid(candidate),"Actual Phone candidates expose the original named child review.")
	if not is_instance_valid(candidate):return
	candidate.pressed.emit()
	var confirm:Button=app.overlay.get_node_or_null("AdoptionConfirm")
	check(is_instance_valid(confirm) and not confirm.disabled,"Actual review offers a single validated ℒ1,000 confirmation.")
	if not is_instance_valid(confirm) or confirm.disabled:return
	var funds:int=app.household.funds;var minutes:float=app.household.minutes
	var routes:Dictionary=app.traversal.routes.duplicate(true);var locks:Dictionary=app.traversal.stairs.duplicate(true)
	var positions:Dictionary={}
	for id:String in app.world.actors:positions[id]=app.world.actors[id].transform
	confirm.pressed.emit()
	check(app.household.members.size()==3,"Phone confirmation after V2 saving adopts exactly one school-age child.")
	adoption_observations={"saved_clock":saved.data.minutes,"live_clock":minutes,"cached_journeys":stale,"live_journeys":live,"members_after":app.household.members.size(),"funds_before":funds,"funds_after":app.household.funds,"notice":app.notice_label.text if is_instance_valid(app.notice_label) else ""}
	if app.household.members.size()!=3:
		check(app.household.funds==funds and app.household.minutes==minutes and app.traversal.routes==routes and app.traversal.stairs==locks,"Rejected transaction preserves funds, clock, occupied stair owner and queues.")
		check(positions.keys().all(func(id:String)->bool:return app.world.actors[id].transform==positions[id]),"Rejected adoption leaves every actual actor at its current physical location.")
		return
	check(app.household.funds==funds-1000 and app.household.minutes==minutes,"Successful adoption charges exactly once without advancing the household clock.")
	check(app.traversal.routes.player==routes.player and app.traversal.stairs==locks and positions.keys().all(func(id:String)->bool:return app.world.actors[id].transform==positions[id]),"Adding a child preserves existing exact controller routes, FIFO locks and actor transforms.")
	var child:LifeSim=app.household.member_sim("housemate_2")
	check(child!=null and str(child.get_current_action().get("id",""))=="arrive_home","New child starts the actual original arrival action.")
	app.household.set_speed(1)
	for frame:int in 2400:
		_step()
		if child.get_current_action().is_empty():break
	check(child.get_current_action().is_empty() and app.world.point_level(app.world.actors.housemate_2.position)==0,"New child naturally completes its ground-floor arrival through actual controller frames.")

func _run()->void:
	app=MainScene.instantiate();root.add_child(app);app.set_process(false);app.set_sound(false)
	_adopt_after_saved_movement()
	var report:Dictionary={"checks":checks,"failures":failures,"observations":adoption_observations,"scope":"Named V2 save, actual manual50ms movement/time, actual Phone Button callbacks and subsequent arrival. Headless controller evidence; no pointer/rendered/fresh-process claim."}
	var file:=FileAccess.open("user://adoption_journeys.json",FileAccess.WRITE);file.store_string(JSON.stringify(LifeSaveLibrary._json_safe(report),"  ",true,true));file.close()
	print("ADOPTION_JOURNEYS checks=%d failures=%d"%[checks,failures.size()])
	app.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
