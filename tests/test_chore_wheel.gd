extends SceneTree
## The player's way into household cleaning: a Household ring with Clean Home on a
## housemate's wheel (and on nobody else's), a Clean Home button on the selected Lifelet's
## own card, the panel and its presets, the HUD button and its percentage, the progress line
## "CLEANING HOME — n OF m", and the reasons a Lifelet cannot be sent.
const DT: float = 1.0 / 30.0
var app: Node
var flow: Node
var checks: int = 0
var failures: Array[String] = []

var capture: bool = false
var shots_dir: String = "/tmp/claude-1001/-home-james-Projects-JustLife/1e705e6b-64f2-44c8-9b30-d76de0e8b1ce/scratchpad/shots/cleaning/"

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()

func shot(name: String) -> void:
	if not capture: return
	await frames(2)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	root.get_texture().get_image().save_png(shots_dir + name + ".png")
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i: int in count: await process_frame

func find(name: String) -> Node:
	return app.overlay.find_child(name, true, false)

func member(index: int) -> LifeSim:
	return app.household.members[index].sim
func member_id(index: int) -> String:
	return str(app.household.members[index].id)

func click_member(index: int) -> void:
	app.on_object_clicked({"id": member_id(index), "kind": "neighbor", "label": str(member(index).character.name)}, Vector2(700, 420))
	await frames()

func calm() -> void:
	for m: Dictionary in app.household.members:
		m.sim.autonomy = false
		m.sim.day = 6; m.sim.minutes = 600.0
		for need: String in LifeSim.NEED_NAMES: m.sim.needs[need] = 90.0
	app.household.day = 6; app.household.minutes = 600.0

func run() -> void:
	app = load("res://scenes/main.tscn").instantiate(); root.add_child(app)
	await frames(4)
	app.set_sound(false)
	app.household_profiles = [{"name": "Ada Vale", "age_stage": "adult", "traits": []}, {"name": "Teo Vale", "age_stage": "teen", "traits": []}, {"name": "Bo Vale", "age_stage": "baby", "traits": []}]
	app.selected_lot = 0; app.start_household()
	await frames(6)
	app.set_process(false); app.household.set_speed(0)
	flow = app.chore_flow
	calm()
	flow.chores().reset(); flow.rebuild_stations(true)
	var selected: String = app.household.selected_id()
	check(selected == member_id(0), "Ada is the selected Lifelet")

	# ---------------------------------------------------- the housemate wheel
	await click_member(1)
	check(find("InteractionWheel") != null, "Clicking a housemate opens the wheel")
	for ring: String in ["social", "fun", "romantic", "household"]:
		check(find("WheelCategory_" + ring) != null, "The %s ring is on the wheel" % ring)
	check(app.wheel_category("clean_home") == "household", "Clean Home belongs to the Household ring")
	var household_ring: Button = find("WheelCategory_household")
	household_ring.pressed.emit(); await frames()
	var clean: Button = find("WheelAction_clean_home")
	check(clean != null and clean.text == "Clean Home", "The Household ring holds Clean Home")
	check(clean != null and clean.disabled, "...which says a spotless home needs nothing (%s)" % [clean.tooltip_text if clean != null else ""])
	await shot("ui_wheel_spotless")
	app.close_overlay()
	# A neighbour is not a housemate: nothing to ask of them.
	app.show_interactions({"id": "maya", "kind": "neighbor", "label": "Maya Chen"}, Vector2(700, 420)); await frames()
	check(find("WheelCategory_household") == null, "A neighbour's wheel has no Household ring")
	app.close_overlay()
	# The baby cannot clean.
	await click_member(2)
	find("WheelCategory_household").pressed.emit(); await frames()
	var baby_clean: Button = find("WheelAction_clean_home")
	check(baby_clean != null and baby_clean.disabled and str(baby_clean.tooltip_text).contains("baby"), "A baby's Clean Home is shut, and says why (%s)" % [baby_clean.tooltip_text if baby_clean != null else ""])
	app.close_overlay()

	# ------------------------------------------------------------- a dirty home
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now() - 5.0 * 1440.0
	flow.chores().toys.clear()
	await click_member(1)
	find("WheelCategory_household").pressed.emit(); await frames()
	clean = find("WheelAction_clean_home")
	check(clean != null and not clean.disabled, "With dirt about, Clean Home opens up")
	check(clean != null and str(clean.tooltip_text).contains("Teo"), "It names who is asked (%s)" % [clean.tooltip_text if clean != null else ""])
	await shot("ui_wheel_household")
	clean.pressed.emit(); await frames()
	check(find("CleanHomePanel") != null, "Choosing it opens the Clean Home panel")
	await shot("ui_panel")
	check(app.bound_member_id == selected, "Control stays with Ada")
	for preset: String in ["quick", "full", "inside", "outside"]:
		var button: Button = find("CleanPreset_" + preset)
		check(button != null and not button.disabled, "The %s preset is open" % preset)
		if button != null: check(button.text.contains("tasks") and (button.text.contains("min") or button.text.contains(" h")), "%s says its tasks and time (%s)" % [preset, button.text.replace("\n", " / ")])
	var checkboxes: Array = app.overlay.find_children("CleanCat_*", "CheckBox", true, false)
	check(checkboxes.size() >= 7, "The panel lists a row for each part of the home (%d)" % checkboxes.size())
	check(find("CleanCat_floors") != null and find("CleanCat_windows") != null and find("CleanCat_entry") != null, "Floors, windows and the entry are among them")
	check(str(find("CleanTally").text).contains("tasks"), "The tally counts the chosen tasks (%s)" % find("CleanTally").text)
	var teen: LifeSim = member(1)
	find("CleanPreset_quick").pressed.emit(); await frames()
	check(find("CleanHomePanel") == null, "Choosing a preset closes the panel")
	var action: Dictionary = teen.get_current_action()
	check(not action.is_empty() and action.has("chore") and str(action.chore.mode) == "quick", "Teo is sent to clean without switching control")
	check(app.bound_member_id == selected and app.household.selected_id() == selected, "Ada is still the Lifelet in control")
	check(app.overlay_open == false, "The game goes back to life")
	app.household.set_speed(1)
	for frame: int in 30: app._process(DT)
	# The HUD follows the chosen Lifelet when they are selected.
	app.select_household_member(1)
	await frames(2)
	app.refresh_hud()
	check(str(app.action_context.text).begins_with("CLEANING HOME — 1 OF"), "The HUD shows the round: %s" % app.action_context.text)
	await shot("ui_hud_progress")
	check(is_instance_valid(app.chore_hud_button) and app.chore_hud_button.text.begins_with("Clean Home"), "The HUD button is there: %s" % app.chore_hud_button.text)
	check(str(app.chore_hud_button.tooltip_text).contains("clean"), "...with the home's state in its tooltip")
	var score_now: int = int(round(flow.home_score()))
	check(app.chore_hud_button.text.contains("%d%%" % score_now), "...and the percentage (%s vs %d%%)" % [app.chore_hud_button.text, score_now])
	var progress_line: String = str(app.action_context.text)
	for frame: int in 1200: app._process(DT)
	app.refresh_hud()
	check(str(app.action_context.text) != progress_line and str(app.action_context.text).begins_with("CLEANING HOME"), "The count moves on as tasks finish: %s" % app.action_context.text)
	# The Cancel action button cancels the whole round.
	app.cancel_current_action()
	check(teen.action_queue.is_empty(), "Cancel action cancels the whole round")
	app.select_household_member(0)
	await frames(2)

	# ----------------------------------------------------- the Lifelet's own card
	app.on_object_clicked({"id": selected, "kind": "neighbor", "label": "Ada Vale"}, Vector2(700, 420)); await frames()
	var card_button: Button = find("CleanHome")
	check(card_button != null and card_button.text == "Clean Home…", "The selected Lifelet's card offers Clean Home…")
	await shot("ui_person_card")
	check(card_button != null and not card_button.disabled, "...enabled while the home needs cleaning")
	check(find("CleanHomePanel") == null, "...and nothing else opens")
	var card_bottom: float = 0.0
	for node: Node in app.overlay.get_children():
		if node is Control and (node as Control).size.y > 500 and (node as Control).size.x < 500: card_bottom = (node as Control).position.y + (node as Control).size.y
	for name: String in ["CleanHome"]:
		var control: Control = find(name)
		check(control != null and control.position.y + control.size.y <= card_bottom + .5, "The button sits inside the card (%.0f of %.0f)" % [control.position.y + control.size.y if control != null else 0.0, card_bottom])
	card_button.pressed.emit(); await frames()
	check(find("CleanHomePanel") != null and app.household.selected_id() == selected, "It opens the panel for Ada")
	# Choosing categories.
	for box: Node in app.overlay.find_children("CleanCat_*", "CheckBox", true, false): (box as CheckBox).button_pressed = false
	await frames()
	check(find("CleanSelected").disabled, "Choosing nothing leaves Start disabled")
	(find("CleanCat_windows") as CheckBox).button_pressed = true
	await frames()
	check(not find("CleanSelected").disabled and str(find("CleanTally").text).contains("tasks"), "Choosing Windows counts its tasks (%s)" % find("CleanTally").text)
	find("CleanSelected").pressed.emit(); await frames()
	var chosen: Dictionary = member(0).get_current_action()
	check(not chosen.is_empty() and str(chosen.id) == "chore_wash_window" and str(chosen.chore.mode) == "custom", "Ada washes windows, and only windows (%s)" % chosen.get("id", ""))
	var only_windows: bool = true
	for entry: Variant in chosen.chore.plan:
		if not str(entry).begins_with("chore_wash_window@"): only_windows = false
	check(only_windows, "Her round holds nothing else")
	member(0).action_queue.clear()

	# ------------------------------------------------------------ the refusals
	member(0).queue_action("snack", "", Vector3.ZERO)
	member(0).action_queue.clear()
	var away_member: LifeSim = member(1)
	check(flow.start_error(away_member).is_empty(), "A Lifelet at home can be sent")
	check(not flow.start_error(member(2)).is_empty(), "A baby cannot (%s)" % flow.start_error(member(2)))
	# Holding food.
	var carried: bool = false
	app.household.meals.portions.append({"id": "plate_probe", "venue": "home", "owner": member_id(1), "storage": "carried", "progress": 0.0, "host": "", "expires": 1e9, "recipe": "garden_skillet", "seat": ""})
	carried = not app.household.meals.carried_by(member_id(1)).is_empty()
	if carried: check(not flow.start_error(member(1)).is_empty(), "A Lifelet holding food is told to put it down (%s)" % flow.start_error(member(1)))
	app.household.meals.portions.pop_back()
	# Nothing dirty.
	for key: Variant in flow.chores().cleaned.keys(): flow.chores().cleaned[key] = flow.now()
	var spotless: Dictionary = flow.start(member_id(0), "quick")
	check(not bool(spotless.ok) and str(spotless.error).contains("Nothing"), "A spotless home has nothing to clean (%s)" % spotless.error)
	await click_member(1)
	find("WheelCategory_household").pressed.emit(); await frames()
	check(find("WheelAction_clean_home").disabled, "...and the wheel says so")
	app.close_overlay()
	var refuse_button: Variant = null
	print("CHORE_WHEEL %d checks, %d failures" % [checks, failures.size()])
	app.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
