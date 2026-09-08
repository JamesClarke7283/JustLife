extends SceneTree

var app: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func press(label: String) -> void:
	for control: Node in app.find_children("*", "Button", true, false):
		if control.text == label and control.is_visible_in_tree() and not control.disabled:
			control.pressed.emit(); return
	check(false, "Missing usable button: " + label)
func finish_activity() -> void:
	app.household.set_speed(8)
	for frame: int in range(220):
		app._process(.1)
		await process_frame
		if app.sim.action_queue.is_empty():return
	check(false, "Queued school activity must complete through normal movement/ticking.")

func run() -> void:
	app=load("res://scenes/main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.set_sound(false)
	var child: Dictionary=app.profile.duplicate(true)
	child.name="Alex Rowan";child["age_stage"]="child";child["life_stage"]="minor"
	var adult: Dictionary=app.profile.duplicate(true);adult.name="Bea Rowan"
	app.household_profiles=[child,adult];app.profile=child
	app.start_household();app.sim.autonomy=false
	press("School");await process_frame
	check(app.career_labels.title.text == "Willow School", "Child HUD shows their school instead of an adult career.")
	check(not app.career_labels.work.disabled, "Weekday morning classes are available.")
	press("School record →");await process_frame
	check(app.overlay_open and app.sim.speed == 0, "School record pauses live gameplay.")
	press("Back to life")
	var money: int=app.household.funds
	press("Online classes");await process_frame
	check(app.sim.get_current_action().id == "school", "School button queues lessons at a real desk.")
	await finish_activity()
	check(app.sim.education.attended == 1, "Arriving and completing lessons records attendance once.")
	check(app.household.funds == money, "School completion does not grant wages.")
	check(app.career_labels.work.disabled, "Same-day attendance cannot be repeated through the HUD.")
	press("Homework");await process_frame
	check(app.sim.get_current_action().id == "homework", "Homework button queues a separate assignment.")
	await finish_activity()
	check(app.sim.education.homework == 1, "Finished homework is recorded.")
	check(app.career_labels.details.text.contains("ready"), "The HUD communicates prepared homework.")
	app.household.set_speed(0)
	check(app.save_game(), "Mixed-age household with school records can be saved.")
	var saved_id: String=app.active_save_id
	app.load_game(saved_id);await process_frame
	check(app.sim.education.attended == 1 and app.sim.education.homework == 1, "Named-save load retains school progress.")
	check(app.sim.character.age_stage == "child", "Named-save load preserves childhood.")
	app.sim.celebrate_birthday();await process_frame;await process_frame
	check(app.sim.character.age_stage == "teen" and app.sim.education.records.size() == 1, "Birthday carries childhood school history into the next stage.")
	press("My Lifelet");press("School history");await process_frame
	check(app.overlay_open, "Earlier school history remains reachable after a birthday.")
	check(app.find_children("*", "Label", true, false).any(func(label: Node):return label.text.contains("Coursework incomplete") and label.is_visible_in_tree()), "An unfinished term is described accurately instead of inventing graduation.")
	LifeSaveLibrary.delete_slot(saved_id)
	app.queue_free();await process_frame;await process_frame
	print("School UI: %d checks, %d failures." % [checks,failures])
	quit(0 if failures == 0 else 1)
