extends SceneTree
var app: Node
func _initialize() -> void: _run.call_deferred()
func _press(text: String) -> bool:
	for b: Node in app.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit(); return true
	return false
func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await process_frame; await process_frame
	app.new_game(); await process_frame
	app.household_profiles[0]["age_stage"] = "adult"
	await process_frame
	for i in 3:
		app.add_creator_member()
		app.household_profiles[app.household_profiles.size()-1]["age_stage"] = "adult"
	await process_frame
	app.start_household()
	for i in 10: await process_frame
	app.set_game_speed(0)
	app.residents.begin_trip("park", ["player","housemate_1"])
	print("PARTY=", app.residents.trip.get("party"))
	for i in 300:
		if app.residents.trip.is_empty(): break
		app.residents.tick_trip(0.05)
		await process_frame
	var vis := 0
	for m in app.household.members:
		var a = app.world.actors[str(m.id)]
		print("  member ", m.id, " visible=", a.visible, " pos=", a.position.rounded())
		if a.visible: vis += 1
	print("FINAL venue=", app.current_venue, " VIS=", vis)
	app.queue_free(); await process_frame
	quit(0)
