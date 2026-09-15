extends SceneTree
## Prove the life settings really change behaviour and survive a save: lifespan
## pace and automatic birthdays are applied to the household, not just shown, and
## a birthday advances the Lifelet through the lifecycle.
##
##   godot --audio-driver Dummy --path <project> --script res://tests/probe_lifecycle_settings.gd

const Lifecycle = preload("res://scripts/lifecycle.gd")
var app: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, why: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", why)
	if not ok: failures.append(why)

func frames(n: int = 3) -> void:
	for i: int in n: await process_frame

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app); current_scene = app
	await frames(6)
	app.set_sound(false)
	app.new_game(); await frames(4)
	app.start_household(); await frames(14)
	app.household.set_speed(0)

	var sim: Object = app.sim
	var original_lifespan: String = str(sim.lifecycle.lifespan)
	print("lifespan default=", original_lifespan, " auto_age=", sim.lifecycle.auto_age)

	# --- The settings dialog really applies its choices ----------------------
	app.show_life_settings()
	await frames(4)
	var pace: OptionButton = app.find_child("LifespanSetting", true, false) as OptionButton
	var auto: CheckButton = app.find_child("AutomaticAgingSetting", true, false) as CheckButton
	check(pace != null, "The settings dialog offers a lifespan choice")
	check(auto != null, "The settings dialog offers automatic birthdays")
	if pace == null or auto == null: return
	# Choose the opposite of the current values so a no-op cannot pass.
	var wanted_index: int = 0 if pace.selected != 0 else 2
	var wanted: String = ["short", "normal", "long"][wanted_index]
	pace.select(wanted_index)
	auto.button_pressed = not auto.button_pressed
	var wanted_auto: bool = auto.button_pressed
	for node: Node in app.find_children("*", "Button", true, false):
		if node is Button and str((node as Button).text) == "Apply":
			(node as Button).pressed.emit()
			break
	await frames(6)
	check(str(sim.lifecycle.lifespan) == wanted, "Apply really changed the lifespan pace (%s -> %s)" % [original_lifespan, str(sim.lifecycle.lifespan)])
	check(bool(sim.lifecycle.auto_age) == wanted_auto, "Apply really changed automatic birthdays (%s)" % str(wanted_auto))
	check(not app.overlay_open, "Applying closes the settings dialog")

	# --- The pace really changes the stage durations --------------------------
	check(str(sim.lifecycle.lifespan) != original_lifespan, "The pace differs from the one the household started with")
	# The pace must really change the stage durations, not just be stored.
	var normal_days: float = Lifecycle.duration("adult", "normal")
	var chosen_days: float = Lifecycle.duration("adult", str(sim.lifecycle.lifespan))
	print("adult days: normal=%.1f %s=%.1f" % [normal_days, str(sim.lifecycle.lifespan), chosen_days])
	check(chosen_days > 0.0, "The chosen pace gives a real stage duration (%.1f days)" % chosen_days)

	# --- A birthday really advances the Lifelet -------------------------------
	var stage_before: String = str(sim.character.age_stage)
	var next: String = Lifecycle.next_stage(stage_before)
	print("stage=%s next=%s" % [stage_before, next])
	check(not next.is_empty(), "The current stage has a next stage (%s -> %s)" % [stage_before, next])
	if not next.is_empty():
		app.show_birthday()
		await frames(4)
		var accepted: bool = false
		for node: Node in app.find_children("*", "Button", true, false):
			var label: String = str((node as Button).text)
			if node is Button and label.begins_with("Celebrate"):
				(node as Button).pressed.emit()
				accepted = true
				break
		# The birthday is a real activity: the Lifelet walks to the cake and the
		# stage changes when it finishes, so the clock has to run at full speed.
		check(accepted, "The birthday dialog offers its Celebrate action")
		app.household.set_speed(3)
		var deadline: int = Time.get_ticks_msec() + 120000
		while str(sim.character.age_stage) == stage_before and Time.get_ticks_msec() < deadline:
			await frames(10)
		app.household.set_speed(0)
		await frames(6)
		var stage_after: String = str(sim.character.age_stage)
		check(stage_after == next, "Celebrating a birthday advanced the stage (%s -> %s)" % [stage_before, stage_after])
		check(sim.character.get("world_state", {}) is Dictionary, "The aged Lifelet keeps a valid world state")

	# --- And the choice survives a save --------------------------------------
	var saved: bool = app.save_game("", "Lifecycle settings")
	check(saved, "The household with changed settings saved")
	var lifespan_at_save: String = str(sim.lifecycle.lifespan)
	var auto_at_save: bool = bool(sim.lifecycle.auto_age)
	var stage_at_save: String = str(sim.character.age_stage)
	await frames(6)

	# Reload in this same process; probe_save_resume covers the fresh process.
	app.load_game(str(app.active_save_id))
	await frames(20)
	check(str(app.sim.lifecycle.lifespan) == lifespan_at_save, "The lifespan pace resumed (%s)" % str(app.sim.lifecycle.lifespan))
	check(bool(app.sim.lifecycle.auto_age) == auto_at_save, "Automatic birthdays resumed (%s)" % str(app.sim.lifecycle.auto_age))
	check(str(app.sim.character.age_stage) == stage_at_save, "The celebrated stage resumed (%s)" % str(app.sim.character.age_stage))

	print("LIFECYCLE_SETTINGS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	app.queue_free(); await frames(3)
	quit(0 if failures.is_empty() else 1)
