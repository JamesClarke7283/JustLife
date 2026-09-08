extends "res://tests/test_school_playthrough.gd"
## Bounded fresh-household public friendly conversation reward verification.
func _run()->void:
	screenshot_dir="res://art/family_rewards"
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app);current_scene=app
	await frames(4);app.set_sound(false)
	app.household.member_action_finished.connect(func(id:String,action:Dictionary):member_completed.append(id+":"+str(action.id)))
	await _enter_new_game()
	for i:int in range(2):
		if i>0:await press("+ Add Lifelet")
		_set_name("Ari Atlas" if i==0 else "Bea Brook")
		for option:OptionButton in app.find_children("*","OptionButton",true,false):
			if option.item_count==4 and option.get_item_text(0)=="Maker":
				option.select(0);option.item_selected.emit(0);break
		await frames(4)
	await press_member("Ari Atlas");await press("Connections");await _connection(1,1);await press("Back to creating")
	await press("Find my home",true);await press("Willow Cottage");await press("Start living",true);await press("Ⅱ")
	for member:Dictionary in app.household.members:member.sim.autonomy=false
	check(app.sim.funds==2500,"Fresh siblings enter the cottage with the advertised2500 wallet and no unearned family friendship bonus.")
	for member:Dictionary in app.household.members:
		check(not _fresh_friend(member.sim).complete and member.sim.social_history.is_empty(),"Existing family closeness alone does not fulfill a fresh friendship want or invent earned history.")
	await press("Wishes")
	check(_visible_text_contains("Share a friendly chat"),"Visible friendship goal explains the required new interaction.")
	await screenshot("01_new_family_want")
	await press("Back to life")
	await _open_social("housemate_1");await press(str(app.sim.get_action_definition("friendly").label));await press("▶")
	await wait_until(func()->bool:return active_is("friendly",.2),"actual initial sibling conversation",40)
	await press("Ⅱ")
	check(app.sim.funds==2500 and not _fresh_friend(app.sim).complete,"Partial conversation grants no money or premature wish completion.")
	await press("Cancel action");await press("▶");await frames(12);await press("Ⅱ")
	check(app.sim.funds==2500 and not _fresh_friend(app.sim).complete,"Canceling a partial conversation preserves the unfinished reward.")
	await _open_social("housemate_1");await press(str(app.sim.get_action_definition("friendly").label));await press("▶")
	await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"real completed sibling conversation",45)
	await press("Ⅱ");await frames(4)
	check(app.sim.funds==2660,"One completed mutual conversation pays exactly80 for each participant, once.")
	for member:Dictionary in app.household.members:check(_fresh_friend(member.sim).complete and not member.sim.social_history.is_empty(),"Both participants earn the new conversation goal and retain actual social history.")
	await screenshot("02_earned_family_reward",true,false)
	await _open_social("housemate_1");await press(str(app.sim.get_action_definition("friendly").label));await press("▶")
	await wait_until(func()->bool:return app.sim.action_queue.is_empty(),"repeat completed sibling conversation",45)
	await press("Ⅱ")
	check(app.sim.funds==2660,"Repeating the conversation does not pay the same fulfilled goal again.")
	_write_report();app.queue_free();await frames(3)
	print("FAMILY_REWARD_RESULT assertions=%d failures=%d"%[assertions,failures.size()]);quit(0 if failures.is_empty() else 1)

func _fresh_friend(sim:Node)->Dictionary:
	for want:Dictionary in sim.wants:
		if str(want.id)=="friend":return want
	return {"complete":false}
