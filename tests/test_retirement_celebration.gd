extends SceneTree
## Retiring in the real game. An elder who holds a job is told they can retire and
## chooses it from the Career record (a Retire button and a confirmation); an
## elder who has never been paid for a shift retires by themselves. Either way the
## grand celebration shows "<Name> is now retired" in the middle of the screen with
## streamers and a loud fanfare, and the game keeps running underneath. The Career
## panel then says "Retired", the work buttons are gone, and the pension arrives on
## the seventh day after retiring, once, even across a save and a load.
const DT: float = .05
var app: Node
var checks: int = 0
var failures: Array[String] = []
var heard: Array = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i: int in count: await process_frame

func member(first_name: String) -> LifeSim:
	for entry: Dictionary in app.household.members:
		if str(entry.sim.character.name).begins_with(first_name): return entry.sim
	return null

func member_id(first_name: String) -> String:
	for entry: Dictionary in app.household.members:
		if str(entry.sim.character.name).begins_with(first_name): return str(entry.id)
	return ""

func member_index(first_name: String) -> int:
	for index: int in app.household.members.size():
		if str(app.household.members[index].sim.character.name).begins_with(first_name): return index
	return -1

func boot() -> void:
	LifeSchoolBus.active = null
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	await frames(4)
	app.set_sound(true)
	app.household_profiles = [
		{"name": "Ada Vale", "age_stage": "adult", "traits": []},
		{"name": "Ben Vale", "age_stage": "elder", "traits": []},
		{"name": "Cy Vale", "age_stage": "elder", "traits": []}]
	app.start_household()
	await frames(6)
	app.set_process(false)
	app.household.set_speed(0)
	listen()

var listened: Object = null

## Record the household's milestones, once, whichever household the game now holds.
func listen() -> void:
	if listened == app.household: return
	listened = app.household
	app.household.member_milestone.connect(func(id: String, kind: String, data: Dictionary): heard.append({"id": id, "kind": kind, "data": data}))

func kinds(kind: String) -> Array:
	return heard.filter(func(entry: Dictionary) -> bool: return str(entry.kind) == kind)

## Let the household's calendar run to `target` at the real speed setting, keeping
## everyone fed and rested so nothing but the calendar moves.
func run_to_day(target: int, speed: int = 8) -> void:
	var before: int = app.household.speed
	app.household.set_speed(speed)
	while app.household.day < target:
		for entry: Dictionary in app.household.members:
			for need: String in LifeSim.NEED_NAMES: entry.sim.needs[need] = 100.0
		app.household.tick(60.0)
	app.household.set_speed(before)

func celebrations() -> Array:
	return app.get_children().filter(func(node: Node) -> bool: return node is LifeMilestoneCelebration and not node.is_queued_for_deletion())

func show_now() -> Node:
	app._process(DT)
	await frames(2)
	var shown: Node = app.announcements.current if app.announcements.showing() else null
	if shown != null: shown.set_process(false)
	return shown

func finish_current() -> void:
	var shown: Node = app.announcements.current
	if is_instance_valid(shown): shown.advance(shown.duration + 1.0)
	await frames(2)

func player_in(node: Node) -> AudioStreamPlayer:
	var players: Array = node.find_children("*", "AudioStreamPlayer", true, false)
	return players[0] if not players.is_empty() else null

func button_named(button_name: String) -> Button:
	return app.find_child(button_name, true, false) as Button

func run() -> void:
	await boot()
	var ben: LifeSim = member("Ben")
	var cy: LifeSim = member("Cy")
	var ada: LifeSim = member("Ada")
	# Nobody acts on their own and no wish pays out, so the only money that moves is the pension.
	for entry: Dictionary in app.household.members:
		entry.sim.autonomy = false
		entry.sim.wants.clear()
	# Ben has been paid for a shift: a job to give up. Cy never has.
	ben.career.worked_day = 1
	ben.career.schedule = LifeCareerSchedule.attend(ben.career.schedule, 1, 0.0)
	check(ben.has_job() and not cy.has_job() and not ada.has_job(), "Ben holds a job; Cy and Ada have never been paid for a shift")

	# ---- before the fourteen days: nothing
	run_to_day(14)
	check(kinds("retirement_eligible").is_empty() and kinds("retired").is_empty() and not ben.is_retired() and not cy.is_retired(), "On day 14 nobody has been told anything")
	app.panel_tab = "Career"
	app.select_household_member(member_index("Ben"))
	check(app.bound_member_id == member_id("Ben") and str(app.career_labels.title.text) == str(ben.career.title), "Ben's Career panel shows his job: " + str(app.career_labels.title.text))
	check(button_named("CareerDetails") != null and button_named("CareerDetails").text == "Career details", "The record button is plain until he can retire")

	# ---- day 15: Ben is told, Cy retires on his own
	run_to_day(15)
	check(app.household.day == 15, "Day 15")
	check(kinds("retirement_eligible").size() == 1 and kinds("retirement_eligible")[0].id == member_id("Ben"), "Ben, who has a job, is told he can retire")
	check(kinds("retired").size() == 1 and kinds("retired")[0].id == member_id("Cy") and cy.is_retired() and int(cy.retirement.retired_day) == 15, "Cy, who has no job to give up, retires by himself")
	check(not ben.is_retired() and ben.retirement_error().is_empty(), "Ben is still working, and free to choose")
	check(app.household.speed == 0 and not app.overlay_open and not app.overlay_pauses_sim, "Nothing paused or opened a menu (speed %d)" % app.household.speed)
	var banner: Node = await show_now()
	check(banner != null and banner.title == "Cy Vale is now retired" and banner.style == "grand", "The grand banner names Cy: %s" % (str(banner.title) if banner != null else "none"))
	check(banner != null and banner.subtitle == "No longer required to work · ℒ1,000 pension every 7 days", "...with the line under it: %s" % (str(banner.subtitle) if banner != null else ""))
	check(banner != null and banner.pieces.size() >= 200, "Streamers: %d pieces" % (banner.pieces.size() if banner != null else 0))
	var voice: AudioStreamPlayer = player_in(banner) if banner != null else null
	check(voice != null and voice.playing and voice.stream.get_length() > 2.5, "A fanfare is playing (%.1f s)" % (voice.stream.get_length() if voice != null else 0.0))
	var viewport: Vector2 = app.get_viewport().get_visible_rect().size
	if banner != null:
		var centre: Vector2 = banner.title_label.get_global_rect().get_center()
		check(banner.title_label.is_visible_in_tree() and absf(centre.x - viewport.x * .5) <= 40.0 and absf(centre.y - viewport.y * .5) <= 40.0, "The headline is in the middle of the screen (%s in %s)" % [str(centre), str(viewport)])
	await finish_current()

	# ---- Ben's Career panel now offers retiring
	app.refresh_hud()
	await frames(2)
	check(button_named("CareerDetails") != null and button_named("CareerDetails").text == "Retire…", "Ben's Career panel names Retire once he can")
	check(str(app.age_label.tooltip_text).contains("Can retire now"), "...and his age tooltip says so: " + str(app.age_label.tooltip_text).replace("\n", " | "))
	run_to_day(16)
	var speed_before: int = 3
	app.household.set_speed(speed_before)
	app.show_career_record()
	await frames(2)
	var retire_button: Button = button_named("CareerRetire")
	check(retire_button != null and not retire_button.disabled and retire_button.text == "Retire…", "The record has an enabled Retire button")
	check(app.sim.speed == 0 and app.overlay_pauses_sim, "The game waits while the record is open")
	retire_button.pressed.emit()
	await frames(2)
	var confirm: Button = button_named("ConfirmRetire")
	check(confirm != null and button_named("KeepWorking") != null, "A confirmation card asks first")
	check(not ben.is_retired(), "Asking does not retire him")
	button_named("KeepWorking").pressed.emit()
	await frames(2)
	check(not ben.is_retired() and button_named("CareerRetire") != null, "Keep working goes back to the record")
	button_named("CareerRetire").pressed.emit()
	await frames(2)
	button_named("ConfirmRetire").pressed.emit()
	await frames(2)
	check(ben.is_retired() and int(ben.retirement.retired_day) == 16 and int(ben.retirement.next_pension_day) == 23, "Retire retires him on day 16, first pension day 23")
	check(kinds("retired").size() == 2 and kinds("retired")[1].id == member_id("Ben"), "One 'retired' milestone for Ben")
	check(app.sim.speed == speed_before and not app.overlay_open, "The game runs at the speed it had before the menu (%d)" % app.sim.speed)
	var ben_banner: Node = await show_now()
	check(ben_banner != null and ben_banner.title == "Ben Vale is now retired" and ben_banner.style == "grand" and ben_banner.pieces.size() >= 200, "The same banner for Ben: %s" % (str(ben_banner.title) if ben_banner != null else "none"))
	var ben_voice: AudioStreamPlayer = player_in(ben_banner) if ben_banner != null else null
	check(ben_voice != null and ben_voice.playing and ben_voice.stream.get_length() > 2.5, "...with the fanfare")
	check(celebrations().size() == 1, "Only one celebration is on the screen at a time")
	await finish_current()

	# ---- the panel and the record afterwards
	app.household.set_speed(0)
	app.refresh_hud()
	await frames(2)
	check(app.career_labels.title.text == "Retired" and app.career_labels.work.disabled and app.career_labels.work.text == "Retired", "The Career panel says Retired and the work button is shut")
	check(str(app.career_labels.details.text).contains("ℒ1,000 pension") and str(app.career_labels.details.text).contains("day 23"), "...and gives the pension and its next day: " + str(app.career_labels.details.text))
	check(button_named("CareerDetails") != null and button_named("CareerDetails").text == "Career details", "The record button is plain again")
	check(not bool(app.household.retire_member(member_id("Ben")).ok) and str(app.household.retire_member(member_id("Ben")).error) == "Already retired.", "Pressing Retire again is refused")
	app.show_career_record()
	await frames(2)
	check(button_named("CareerRetire") == null, "The record no longer has a Retire button")
	var summary: Label = app.find_child("RetirementSummary", true, false) as Label
	check(summary != null and summary.text.contains("Retired on day 16") and summary.text.contains("next ℒ1,000 on day 23"), "It says when and what: " + (summary.text if summary != null else "no summary"))
	var find_job: Button = null
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if (node as Button).text == "Find a job": find_job = node
		check((node as Button).text != "Work from home" and (node as Button).text != "Go to the station", "No work button on the retired record: " + (node as Button).text)
	check(find_job != null and find_job.disabled and find_job.tooltip_text.contains("pension"), "Find a job is disabled and says why")
	app.close_overlay()

	# ---- the pension: Cy on day 22, Ben on day 23, one payment each
	run_to_day(21)
	var funds_21: int = app.household.funds
	check(kinds("pension").is_empty(), "Nothing before day 22")
	run_to_day(22)
	check(app.household.funds - funds_21 == 1000 and int(cy.retirement.pension_paid) == 1000 and int(ben.retirement.pension_paid) == 0, "Day 22: the household purse rises by exactly 1,000 (Cy's): %d" % (app.household.funds - funds_21))
	check(kinds("pension").size() == 1 and kinds("pension")[0].id == member_id("Cy") and int(kinds("pension")[0].data.amount) == 1000, "One pension milestone, Cy's")
	await frames(1)
	var pension_notices: Array = [app.notice_text] + Array(app.notice_queue)
	check(pension_notices.any(func(text: String) -> bool: return text.contains("Pension") and text.contains("ℒ1,000")), "A notice announces it: " + str(pension_notices).left(160))
	check(celebrations().is_empty(), "A pension is a notice, not a banner")

	# ---- a save and a load in the middle of the period change nothing
	app.household.set_speed(0)
	check(app.save_game(), "The household saves (%s)" % app.notice_text)
	var slot: String = app.active_save_id
	app.load_game(slot)
	await frames(4)
	app.set_process(false)
	app.household.set_speed(0)
	heard.clear()
	listen()
	var cy_after: LifeSim = member("Cy")
	var ben_after: LifeSim = member("Ben")
	check(cy_after.is_retired() and int(cy_after.retirement.next_pension_day) == 29 and int(cy_after.retirement.pension_paid) == 1000, "After the load Cy is still retired, paid once, next on day 29")
	check(ben_after.is_retired() and int(ben_after.retirement.next_pension_day) == 23 and int(ben_after.retirement.pension_paid) == 0, "...and Ben, next on day 23")
	var funds_loaded: int = app.household.funds
	for entry: Dictionary in app.household.members:
		entry.sim.autonomy = false
		entry.sim.wants.clear()
	run_to_day(23)
	check(app.household.funds - funds_loaded == 1000 and int(ben_after.retirement.pension_paid) == 1000 and int(cy_after.retirement.pension_paid) == 1000, "Day 23: exactly Ben's 1,000 after the reload, and Cy's day-22 pension is not paid again: %d" % (app.household.funds - funds_loaded))
	check(kinds("pension").size() == 1 and kinds("pension")[0].id == member_id("Ben"), "One pension milestone after the load, Ben's")
	run_to_day(29)
	check(int(cy_after.retirement.pension_paid) == 2000 and int(ben_after.retirement.pension_paid) == 1000, "Day 29 is Cy's second payment")
	app.queue_free()
	print("RETIREMENT_CELEBRATION %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
