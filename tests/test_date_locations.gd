extends "res://tests/test_dating_marriage.gd"
## One date across town, then the public invitation for a dedicated home date.

func travel(destination:String)->bool:
	app.travel_to(destination)
	if app.mode!="travel":return false
	return await drive(func():return app.mode=="live" and app.current_venue==destination,3000,"travel to "+destination)

func run()->void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await process_frame
	app.set_process(false);app.set_sound(false)
	app.household_profiles=[{"name":"Robin Vale","age_stage":"adult","gender":"female","traits":[]}]
	app.start_household();app.world.set_process(false)
	app.sim.autonomy=false;app.sim.set_aging("normal",false)
	for key:String in app.sim.needs:app.sim.needs[key]=90.0
	app.sim.relationships.maya.merge({"friendship":70.0,"romance":65.0,"successful_flirts":3,"completed_dates":0,"bond":"partners"},true)
	app.sim.romantic_partner="maya";app.household.adopt_selected_changes()
	app.household.set_speed(8)
	var arrived:bool=await travel("maya_home")
	check(arrived,"Partners travel to a real off-lot meeting location")
	if not arrived:finish();return
	check(await perform("go_on_date"),"The same date interaction completes at the partner's home")
	check(int(app.sim.relationships.maya.completed_dates)==1,"Off-lot date earns one completed date")
	arrived=await travel("home")
	check(arrived,"The host returns home after the off-lot date")
	if not arrived:finish();return
	app.show_relationships();await process_frame
	var invite:Button=app.overlay.find_child("InviteDate_maya",true,false)
	check(is_instance_valid(invite) and not invite.disabled,"Partner panel offers an enabled dedicated home-date invitation")
	if not is_instance_valid(invite) or invite.disabled:finish();return
	invite.pressed.emit()
	check(not app.household.date_invitation.is_empty() and app.residents.home_visit.active(),"Date invitation creates a real arriving home visit")
	app.household.set_speed(0)
	var pending:Dictionary=app.household.date_invitation.duplicate(true)
	check(app.save_game("","Partner arriving for date"),"Pending date invitation can be saved")
	var slot:String=app.active_save_id
	var epoch:int=app.load_epoch
	app.load_game(slot);await process_frame
	check(app.load_epoch==epoch+1 and app.household.date_invitation==pending,"Loading preserves the exact pending date invitation: "+str({"before":epoch,"after":app.load_epoch,"invitation":app.household.date_invitation,"expected":pending,"notice":app.notice_label.text}))
	app.household.set_speed(8)
	arrived=await drive(func():return str(app.residents.home_visit.state.get("phase",""))=="waiting",3000,"date arrival")
	check(arrived,"Invited date walks to the front door after loading")
	if not arrived:finish();return
	var welcomed:bool=app.residents.home_visit.welcome("player")
	check(welcomed,"Host welcomes the dedicated date inside")
	if not welcomed:finish();return
	app.household.set_speed(8)
	var dating:bool=await drive(func():return str(app.sim.get_current_action().get("id",""))=="go_on_date" and str(app.sim.get_current_action().get("phase",""))=="active",3000,"automatic home date")
	check(dating,"The invitation starts a physical date after the welcome and door sequence")
	check(app.household.date_invitation.is_empty(),"Consumed invitation cannot start a second date on another tick")
	if dating:
		check(await drive(func():return app.sim.action_queue.is_empty(),2600,"home date completion"),"Dedicated home date finishes")
		check(int(app.sim.relationships.maya.completed_dates)==2,"Off-lot and home dates share the two-date marriage gate")
		check(bool(app.sim.get_action_availability("commit","maya").available),"Marriage unlocks after one off-lot date and one invited home date")
	finish()
