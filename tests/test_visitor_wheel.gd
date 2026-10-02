extends "res://tests/test_guest_activity.gd"
## Clicking the visitor opens the wheel at every stage of the visit, with their own
## choices greyed until they are inside; a stay over is asked of a real friend.
func wheel_for(id: String) -> void:
	app.show_interactions({"id": id, "kind": "neighbor", "label": "Maya Chen"}, Vector2(700, 420))
	await process_frame
	await process_frame
func open_ring(name: String) -> void:
	var button: Button = app.overlay.find_child("WheelCategory_" + name, true, false)
	if is_instance_valid(button):
		button.pressed.emit()
		await process_frame
		await process_frame
func entry(id: String) -> Button:
	return app.overlay.find_child("WheelAction_" + id, true, false)

func _run() -> void:
	app = MainScene.instantiate(); root.add_child(app); app.set_process(false); app.set_sound(false)
	_setup()
	app.household.groceries.stock = 12
	check(visit().invite("maya"), "A friend is invited")
	# ---- arriving: the wheel is already there, and the visitor's choices wait
	await wheel_for("maya")
	check(app.overlay.find_child("InteractionWheel", true, false) != null, "The visitor can be clicked as soon as they are on their way")
	await open_ring("social")
	check(entry("ask_to_stay_over") != null and entry("ask_to_stay_over").disabled, "Ask to Stay Over is on the wheel but waits for them to be inside")
	check("inside" in str(entry("ask_to_stay_over").tooltip_text), "It says why (%s)" % entry("ask_to_stay_over").tooltip_text)
	app.close_overlay()
	app.household.set_speed(8)
	check(await frames_until(func() -> bool: return _phase() == "waiting"), "The visitor reaches the front door")
	await wheel_for("maya")
	await open_ring("fun")
	check(entry("guest_join") != null and entry("guest_join").disabled, "Come Join Me waits on the doorstep")
	app.close_overlay()
	check(visit().welcome("player"), "The host welcomes them in")
	await wheel_for("maya")
	check(app.overlay.find_child("InteractionWheel", true, false) != null, "The visitor can be clicked while they are coming in")
	app.close_overlay()
	app.household.set_speed(8)
	check(await frames_until(func() -> bool: return _phase() == "inside"), "The visitor is inside")
	app.household.set_speed(0)
	# ---- inside: their choices open
	await wheel_for("maya")
	await open_ring("fun")
	check(entry("guest_join") != null and not entry("guest_join").disabled, "Come Join Me is open once they are inside")
	check(entry("guest_activity") != null and not entry("guest_activity").disabled, "Suggest an activity is open once they are inside")
	app.overlay.find_child("WheelBack", true, false).pressed.emit(); await process_frame
	await open_ring("social")
	check(entry("ask_to_stay_over") != null and not entry("ask_to_stay_over").disabled, "Ask to Stay Over is open once they are inside")
	app.overlay.find_child("WheelBack", true, false).pressed.emit(); await process_frame
	await open_ring("romantic")
	check(entry("flirt") != null and entry("ask_partner") != null and entry("go_on_date") != null and entry("commit") != null, "The romantic ring carries the whole path to marriage")
	app.close_overlay()

	# ---- someone who is only an acquaintance says no to staying the night
	var friendship: float = app.sim.relationships.maya.friendship
	app.sim.relationships.maya.friendship = 20.0
	for member: Dictionary in app.household.members: member.sim.relationships.maya.friendship = 20.0
	check(not visit().stay_over_refusal().is_empty(), "A friendship of 20 is not enough to stay the night")
	check(not visit().ask_to_stay_over(), "An acquaintance declines to stay over")
	check(not bool(visit().state.get("stay_over", false)), "Declining changes nothing about the visit")
	check("head home" in app.notice_text, "They say so (%s)" % app.notice_text)
	for member: Dictionary in app.household.members: member.sim.relationships.maya.friendship = 50.0
	check(visit().stay_over_refusal().is_empty(), "A good friend will stay")
	check(visit().ask_to_stay_over() and bool(visit().state.get("stay_over", false)), "A friend accepts and the visit is extended")
	check(str(guest().current_action().get("id", "")) == "sleep" or bool(guest().data.bed_requested), "Accepting sends them looking for a bed")
	app.sim.relationships.maya.friendship = friendship
	await _finish()
